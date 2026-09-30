/* eslint-disable max-len, require-jsdoc, new-cap, quote-props */

const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

const db = admin.firestore();
const REGION = "us-central1";
const PLATFORM_ACCOUNT = "MLIVECAST_PLATFORM_ACCOUNT";
const SPONSORSHIPS = "sponsorships";
const TIERS = "sponsor_tiers";
const LEDGER = "usage_ledger";
const EVENTS = "stripe_webhook_events";
const STRIPE_API = "https://api.stripe.com/v1";

function stripeSecret() {
  return process.env.STRIPE_SECRET_KEY || "";
}

function config() {
  return {
    currency: (process.env.STRIPE_CURRENCY || "usd").toLowerCase(),
    country: (process.env.STRIPE_CONNECT_COUNTRY || "").toUpperCase(),
    baseUrl: (process.env.PUBLIC_BASE_URL || "").replace(/\/$/, ""),
  };
}

function id(value, field) {
  if (typeof value !== "string" || !value.trim() || value.includes("/")) {
    throw new Error(`Invalid ${field}`);
  }
  return value.trim();
}

function responseCors(req, res) {
  res.set("Access-Control-Allow-Origin", req.get("Origin") || "*");
  res.set("Vary", "Origin");
  res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
}

async function requireUser(req) {
  const match = (req.get("Authorization") || "").match(/^Bearer\s+(.+)$/i);
  if (!match) throw new Error("Sign in is required");
  return admin.auth().verifyIdToken(match[1]);
}

async function isAdmin(uid) {
  const user = await db.collection("users").doc(uid).get();
  return user.exists && user.get("role") === "admin";
}

async function getOwner(ownerType, ownerId) {
  if (ownerType === "STATION") {
    const snap = await db.collection("stations").doc(ownerId).get();
    if (!snap.exists) throw new Error("Station not found");
    return {snapshot: snap, creatorId: snap.get("creatorId"), title: snap.get("title") || "Station"};
  }
  if (ownerType === "CONTEST") {
    const snap = await db.collection("contests").doc(ownerId).get();
    if (!snap.exists) throw new Error("Contest not found");
    return {snapshot: snap, creatorId: snap.get("creatorId"), title: snap.get("title") || "Contest"};
  }
  throw new Error("Invalid owner type");
}

async function requireOwner(uid, ownerType, ownerId) {
  const owner = await getOwner(ownerType, ownerId);
  if (owner.creatorId !== uid) throw new Error("Only the owner can manage sponsorships");
  return owner;
}

function dateFromContest(ownerSnapshot) {
  const raw = ownerSnapshot.get("endDate");
  const date = raw && typeof raw.toDate === "function" ? raw.toDate() : new Date(raw);
  if (!raw || !Number.isFinite(date.getTime())) throw new Error("Contest end date is required for sponsorships");
  return admin.firestore.Timestamp.fromDate(date);
}

function addCalendarMonths(date, months) {
  const result = new Date(date.getTime());
  const day = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + months);
  const lastDay = new Date(Date.UTC(result.getUTCFullYear(), result.getUTCMonth() + 1, 0)).getUTCDate();
  result.setUTCDate(Math.min(day, lastDay));
  return result;
}

async function stripeRequest(path, form, idempotencyKey) {
  if (!stripeSecret()) throw new Error("Stripe is not configured");
  const headers = {
    Authorization: `Bearer ${stripeSecret()}`,
    "Content-Type": "application/x-www-form-urlencoded",
  };
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
  const response = await fetch(`${STRIPE_API}${path}`, {
    method: form ? "POST" : "GET",
    headers,
    body: form ? new URLSearchParams(form).toString() : undefined,
  });
  const json = await response.json();
  if (!response.ok) {
    console.error("[sponsorship] Stripe API error", response.status, json.error && json.error.type);
    throw new Error("Stripe could not complete this request");
  }
  return json;
}

async function stripeDelete(path) {
  if (!stripeSecret()) throw new Error("Stripe is not configured");
  const response = await fetch(`${STRIPE_API}${path}`, {
    method: "DELETE",
    headers: {Authorization: `Bearer ${stripeSecret()}`},
  });
  const json = await response.json();
  if (!response.ok) throw new Error("Stripe could not cancel the subscription");
  return json;
}

async function createCheckout(uid, body) {
  const tierId = id(body.tierId, "tierId");
  const tierRef = db.collection(TIERS).doc(tierId);
  const tierSnap = await tierRef.get();
  if (!tierSnap.exists || tierSnap.get("active") !== true) throw new Error("This sponsor tier is not available");
  const tier = tierSnap.data();
  const owner = await getOwner(tier.ownerType, tier.ownerId);
  if (!owner.creatorId) throw new Error("Sponsorship owner is not configured");
  const settings = config();
  if (!settings.baseUrl || !settings.country || !stripeSecret()) {
    throw new Error("Sponsorship payments are not configured yet");
  }
  if (settings.currency !== "usd") {
    throw new Error("Sponsorship ledger and checkout UI are configured for USD");
  }
  if (tier.ownerType === "CONTEST" && tier.billingPeriod !== "ONE_TIME") {
    throw new Error("Contest sponsorship tiers must be one-time purchases");
  }
  const durationMonths = tier.ownerType === "STATION" ?
    Math.max(1, Math.min(24, Number(body.durationMonths) || 1)) : null;
  const connectedAccountId = (await db.collection("users").doc(owner.creatorId).get()).get("stripeConnectAccountId");
  if (!connectedAccountId) throw new Error("The owner must finish payout setup before this tier can be purchased");
  const account = await stripeRequest(`/accounts/${connectedAccountId}`);
  if (!account.metadata || account.metadata.firebaseUid !== owner.creatorId) {
    throw new Error("The payout account must be onboarded by this owner through Mlivecast");
  }
  if (!account.payouts_enabled || !account.capabilities || account.capabilities.transfers !== "active") {
    throw new Error("The owner's payout account is still being verified");
  }

  const sponsorshipRef = db.collection(SPONSORSHIPS).doc();
  const sponsorUser = await db.collection("users").doc(uid).get();
  const sponsorName = sponsorUser.get("displayName") || sponsorUser.get("name") || "Mlivecast sponsor";
  const contestEndsAt = tier.ownerType === "CONTEST" ? dateFromContest(owner.snapshot) : null;
  if (contestEndsAt && contestEndsAt.toMillis() <= Date.now()) {
    throw new Error("This contest has ended and cannot accept sponsorships");
  }
  const durationEndsAt = durationMonths ?
    admin.firestore.Timestamp.fromDate(addCalendarMonths(new Date(), durationMonths)) : null;
  const endsAt = contestEndsAt || durationEndsAt;

  await db.runTransaction(async (transaction) => {
    const currentTier = await transaction.get(tierRef);
    if (!currentTier.exists || currentTier.get("active") !== true) throw new Error("This sponsor tier is not available");
    const filled = currentTier.get("quantityFilled") || 0;
    const available = currentTier.get("quantityAvailable") || 0;
    if (filled >= available) throw new Error("This sponsor tier is sold out");
    transaction.update(tierRef, {quantityFilled: filled + 1, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
    transaction.create(sponsorshipRef, {
      tierId,
      ownerType: tier.ownerType,
      ownerId: tier.ownerId,
      ownerUserId: owner.creatorId,
      ownerTitle: owner.title,
      sponsorUserId: uid,
      sponsorName,
      bannerSize: tier.bannerSize || "MEDIUM",
      artworkUrl: null,
      artworkPath: null,
      artworkStatus: "NOT_SUBMITTED",
      startedAt: null,
      endsAt,
      durationMonths,
      status: "PENDING_PAYMENT",
      billingPeriod: tier.billingPeriod || "ONE_TIME",
      amountPaid: 0,
      currency: settings.currency,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  const base = settings.baseUrl;
  const form = {
    mode: tier.billingPeriod === "MONTHLY" ? "subscription" : "payment",
    success_url: `${base}/?sponsorship=complete`,
    cancel_url: `${base}/?sponsorship=cancelled`,
    "client_reference_id": sponsorshipRef.id,
    "line_items[0][price_data][currency]": settings.currency,
    "line_items[0][price_data][unit_amount]": String(tier.price),
    "line_items[0][price_data][product_data][name]": `${tier.name} sponsorship — ${owner.title}`,
    "line_items[0][quantity]": "1",
    "metadata[sponsorshipId]": sponsorshipRef.id,
    "metadata[tierId]": tierId,
    "metadata[sponsorUserId]": uid,
    "metadata[ownerType]": tier.ownerType,
    "metadata[ownerId]": tier.ownerId,
  };
  if (tier.billingPeriod === "MONTHLY") {
    form["line_items[0][price_data][recurring][interval]"] = "month";
    form["subscription_data[application_fee_percent]"] = "15";
    form["subscription_data[transfer_data][destination]"] = connectedAccountId;
    form["subscription_data[metadata][sponsorshipId]"] = sponsorshipRef.id;
    form["subscription_data[metadata][durationMonths]"] = String(durationMonths);
  } else {
    const platformFee = Math.round(Number(tier.price) * 0.15);
    form["payment_intent_data[application_fee_amount]"] = String(platformFee);
    form["payment_intent_data[transfer_data][destination]"] = connectedAccountId;
    form["payment_intent_data[metadata][sponsorshipId]"] = sponsorshipRef.id;
  }

  try {
    const checkout = await stripeRequest("/checkout/sessions", form, `sponsor_${sponsorshipRef.id}`);
    await sponsorshipRef.update({
      stripeCheckoutSessionId: checkout.id,
      stripeConnectedAccountId: connectedAccountId,
      stripeSubscriptionId: checkout.subscription || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {checkoutUrl: checkout.url, sponsorshipId: sponsorshipRef.id};
  } catch (error) {
    await releaseReservation(sponsorshipRef.id, "PAYMENT_SETUP_FAILED");
    throw error;
  }
}

async function releaseReservation(sponsorshipId, finalStatus) {
  const sponsorshipRef = db.collection(SPONSORSHIPS).doc(sponsorshipId);
  await db.runTransaction(async (transaction) => {
    const sponsorship = await transaction.get(sponsorshipRef);
    if (!sponsorship.exists || sponsorship.get("status") !== "PENDING_PAYMENT") return;
    const tierRef = db.collection(TIERS).doc(sponsorship.get("tierId"));
    const tier = await transaction.get(tierRef);
    if (tier.exists) {
      transaction.update(tierRef, {
        quantityFilled: Math.max(0, (tier.get("quantityFilled") || 0) - 1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    transaction.update(sponsorshipRef, {
      status: finalStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

function ledgerAmount(total) {
  const platform = Math.round(total * 0.15);
  return {owner: total - platform, platform};
}

function ledgerId(sponsorshipId, paymentReference, side) {
  return crypto.createHash("sha256")
      .update(`${sponsorshipId}:${paymentReference}:${side}`).digest("hex");
}

async function recordRevenue(transaction, sponsorship, sponsorshipId, total, paymentReference) {
  const shares = ledgerAmount(total);
  const ownerEntry = db.collection(LEDGER).doc(ledgerId(sponsorshipId, paymentReference, "owner"));
  const platformEntry = db.collection(LEDGER).doc(ledgerId(sponsorshipId, paymentReference, "platform"));
  transaction.create(ownerEntry, {
    userId: sponsorship.ownerUserId,
    stationId: sponsorship.ownerType === "STATION" ? sponsorship.ownerId : null,
    contestId: sponsorship.ownerType === "CONTEST" ? sponsorship.ownerId : null,
    sponsorshipId,
    transactionType: "SPONSORSHIP_CREDIT",
    amount: shares.owner,
    unit: "USD_CENTS",
    balanceAfter: null,
    referenceId: sponsorshipId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  transaction.create(platformEntry, {
    userId: PLATFORM_ACCOUNT,
    stationId: sponsorship.ownerType === "STATION" ? sponsorship.ownerId : null,
    contestId: sponsorship.ownerType === "CONTEST" ? sponsorship.ownerId : null,
    sponsorshipId,
    transactionType: "SPONSORSHIP_CREDIT",
    amount: shares.platform,
    unit: "USD_CENTS",
    balanceAfter: null,
    referenceId: sponsorshipId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function activatePaidSponsorship(sponsorshipId, paidTotal, paymentReference, stripeSubscriptionId) {
  const sponsorshipRef = db.collection(SPONSORSHIPS).doc(sponsorshipId);
  await db.runTransaction(async (transaction) => {
    const sponsorshipSnap = await transaction.get(sponsorshipRef);
    if (!sponsorshipSnap.exists) throw new Error(`Unknown sponsorship ${sponsorshipId}`);
    const sponsorship = sponsorshipSnap.data();
    const eventPaymentRef = db.collection("sponsorship_payments").doc(
        crypto.createHash("sha256").update(`${sponsorshipId}:${paymentReference}`).digest("hex"));
    const paymentSnap = await transaction.get(eventPaymentRef);
    if (paymentSnap.exists) return;
    if (sponsorship.status === "PENDING_PAYMENT") {
      const owner = await getOwner(sponsorship.ownerType, sponsorship.ownerId);
      let endsAt = sponsorship.endsAt || null;
      if (sponsorship.ownerType === "CONTEST") endsAt = dateFromContest(owner.snapshot);
      transaction.update(sponsorshipRef, {
        status: "ACTIVE",
        artworkStatus: "NOT_SUBMITTED",
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
        endsAt,
        amountPaid: paidTotal,
        stripeSubscriptionId: stripeSubscriptionId || sponsorship.stripeSubscriptionId || null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else if (sponsorship.status === "ACTIVE") {
      transaction.update(sponsorshipRef, {
        amountPaid: admin.firestore.FieldValue.increment(paidTotal),
        stripeSubscriptionId: stripeSubscriptionId || sponsorship.stripeSubscriptionId || null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else if (sponsorship.status === "EXPIRED" || sponsorship.status === "CANCELLED") {
      // The provider can deliver a final paid-invoice event after the expiry
      // job. Record collected revenue without reopening the sponsorship slot.
      transaction.update(sponsorshipRef, {
        amountPaid: admin.firestore.FieldValue.increment(paidTotal),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      throw new Error("Sponsorship is not payable");
    }
    recordRevenue(transaction, sponsorship, sponsorshipId, paidTotal, paymentReference);
    transaction.create(eventPaymentRef, {
      sponsorshipId,
      stripePaymentReference: paymentReference,
      amount: paidTotal,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

async function scheduleSubscriptionEnd(sponsorshipId, subscriptionId) {
  const sponsorship = await db.collection(SPONSORSHIPS).doc(sponsorshipId).get();
  if (!sponsorship.exists || sponsorship.get("ownerType") !== "STATION" ||
      sponsorship.get("billingPeriod") !== "MONTHLY") return;
  const endsAt = sponsorship.get("endsAt");
  if (!endsAt || typeof endsAt.toMillis !== "function") return;
  await stripeRequest(`/subscriptions/${subscriptionId}`, {
    cancel_at: String(Math.floor(endsAt.toMillis() / 1000)),
    proration_behavior: "none",
  }, `sponsor_cancel_${sponsorshipId}`);
}

function parseStripeSignature(header) {
  const parts = (header || "").split(",");
  const timestamp = parts.find((part) => part.startsWith("t="));
  const signatures = parts.filter((part) => part.startsWith("v1="));
  return {timestamp: timestamp && timestamp.slice(2), signatures: signatures.map((part) => part.slice(3))};
}

function verifyStripeEvent(rawBody, header) {
  const signingSecret = process.env.STRIPE_WEBHOOK_SECRET || "";
  if (!signingSecret) throw new Error("Stripe webhook secret is not configured");
  const parsed = parseStripeSignature(header);
  const timestamp = Number(parsed.timestamp);
  if (!timestamp || Math.abs(Date.now() / 1000 - timestamp) > 300) throw new Error("Stale Stripe event");
  const expected = crypto.createHmac("sha256", signingSecret)
      .update(`${parsed.timestamp}.${rawBody}`).digest();
  const valid = parsed.signatures.some((signature) => {
    try {
      const supplied = Buffer.from(signature, "hex");
      return supplied.length === expected.length && crypto.timingSafeEqual(supplied, expected);
    } catch (_) {
      return false;
    }
  });
  if (!valid) throw new Error("Invalid Stripe signature");
  return JSON.parse(rawBody);
}

async function handleStripeEvent(event) {
  const eventRef = db.collection(EVENTS).doc(event.id);
  await db.runTransaction(async (transaction) => {
    const eventSnap = await transaction.get(eventRef);
    if (eventSnap.exists) return;
    transaction.create(eventRef, {
      eventId: event.id,
      eventType: event.type,
      status: "RECEIVED",
      receivedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  const object = event.data.object;
  if (event.type === "checkout.session.completed" || event.type === "checkout.session.async_payment_succeeded") {
    const sponsorshipId = object.metadata && object.metadata.sponsorshipId;
    if (sponsorshipId && object.mode === "subscription") {
      const ref = db.collection(SPONSORSHIPS).doc(sponsorshipId);
      await ref.set({
        stripeSubscriptionId: object.subscription || null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    } else if (sponsorshipId && object.payment_status === "paid") {
      await activatePaidSponsorship(
          sponsorshipId,
          Number(object.amount_total || 0),
          object.payment_intent || object.id,
          null);
    }
  } else if (event.type === "invoice.paid") {
    const subscriptionId = typeof object.subscription === "string" ?
      object.subscription : object.parent && object.parent.subscription_details && object.parent.subscription_details.subscription;
    if (subscriptionId) {
      const query = await db.collection(SPONSORSHIPS)
          .where("stripeSubscriptionId", "==", subscriptionId).limit(1).get();
      let sponsorshipId = query.empty ? null : query.docs[0].id;
      if (!sponsorshipId) {
        const subscription = await stripeRequest(`/subscriptions/${subscriptionId}`);
        sponsorshipId = subscription.metadata && subscription.metadata.sponsorshipId;
        if (sponsorshipId) {
          await db.collection(SPONSORSHIPS).doc(sponsorshipId).set({
            stripeSubscriptionId: subscriptionId,
          }, {merge: true});
        }
      }
      if (sponsorshipId) {
        await scheduleSubscriptionEnd(sponsorshipId, subscriptionId);
        await activatePaidSponsorship(
            sponsorshipId,
            Number(object.amount_paid || 0),
            object.payment_intent || object.id,
            subscriptionId);
      }
    }
  } else if (event.type === "checkout.session.expired" ||
      event.type === "checkout.session.async_payment_failed") {
    const sponsorshipId = object.metadata && object.metadata.sponsorshipId;
    if (sponsorshipId) await releaseReservation(sponsorshipId, "EXPIRED");
  } else if (event.type === "customer.subscription.deleted") {
    const subscriptionId = object.id;
    const query = await db.collection(SPONSORSHIPS)
        .where("stripeSubscriptionId", "==", subscriptionId).limit(1).get();
    if (!query.empty) {
      const sponsorship = query.docs[0];
      if (sponsorship.get("status") === "PENDING_PAYMENT") {
        await releaseReservation(sponsorship.id, "EXPIRED");
      } else {
        await expireSponsorship(sponsorship.ref);
      }
    }
  }

  await eventRef.set({status: "PROCESSED", processedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
}

async function expireSponsorship(sponsorshipRef) {
  await db.runTransaction(async (transaction) => {
    const sponsorship = await transaction.get(sponsorshipRef);
    if (!sponsorship.exists || sponsorship.get("status") !== "ACTIVE") return;
    const tierRef = db.collection(TIERS).doc(sponsorship.get("tierId"));
    const tier = await transaction.get(tierRef);
    if (tier.exists) {
      transaction.update(tierRef, {
        quantityFilled: Math.max(0, (tier.get("quantityFilled") || 0) - 1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    transaction.update(sponsorshipRef, {
      status: "EXPIRED",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

async function createConnectLink(uid) {
  const settings = config();
  if (!settings.country || !settings.baseUrl) throw new Error("Stripe Connect country and public URL are not configured");
  const userRef = db.collection("users").doc(uid);
  const user = await userRef.get();
  let accountId = user.get("stripeConnectAccountId");
  if (!accountId) {
    const account = await stripeRequest("/accounts", {
      type: "express",
      country: settings.country,
      "capabilities[transfers][requested]": "true",
      "metadata[firebaseUid]": uid,
    }, `connect_${uid}`);
    accountId = account.id;
    await userRef.set({stripeConnectAccountId: accountId}, {merge: true});
  }
  const link = await stripeRequest("/account_links", {
    account: accountId,
    refresh_url: `${settings.baseUrl}/?connect=refresh`,
    return_url: `${settings.baseUrl}/?connect=return`,
    type: "account_onboarding",
  });
  return {url: link.url};
}

async function createTier(uid, body) {
  const ownerType = body.ownerType;
  const ownerId = id(body.ownerId, "ownerId");
  await requireOwner(uid, ownerType, ownerId);
  const name = typeof body.name === "string" ? body.name.trim().slice(0, 40) : "";
  const price = Number(body.price);
  const quantityAvailable = Number(body.quantityAvailable);
  const billingPeriod = body.billingPeriod === "MONTHLY" ? "MONTHLY" : "ONE_TIME";
  const bannerSize = ["LARGE", "MEDIUM", "SMALL"].includes(body.bannerSize) ? body.bannerSize : "MEDIUM";
  if (!name || !Number.isInteger(price) || price < 100 || price > 100000000) throw new Error("Tier needs a name and price of at least 100 cents");
  if (!Number.isInteger(quantityAvailable) || quantityAvailable < 1 || quantityAvailable > 1000) throw new Error("Quantity must be between 1 and 1000");
  if (ownerType === "CONTEST" && billingPeriod === "MONTHLY") throw new Error("Contest sponsorships are one-time payments");
  const ref = db.collection(TIERS).doc();
  await ref.set({
    tierId: ref.id,
    ownerType,
    ownerId,
    createdByUserId: uid,
    name,
    price,
    billingPeriod,
    quantityAvailable,
    quantityFilled: 0,
    bannerSize,
    active: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return {tierId: ref.id};
}

async function updateTier(uid, body) {
  const tierId = id(body.tierId, "tierId");
  const ref = db.collection(TIERS).doc(tierId);
  const snap = await ref.get();
  if (!snap.exists) throw new Error("Tier not found");
  await requireOwner(uid, snap.get("ownerType"), snap.get("ownerId"));
  const updates = {updatedAt: admin.firestore.FieldValue.serverTimestamp()};
  if (typeof body.name === "string" && body.name.trim()) updates.name = body.name.trim().slice(0, 40);
  if (Number.isInteger(Number(body.price)) && Number(body.price) >= 100) updates.price = Number(body.price);
  if (updates.price > 100000000) throw new Error("Tier price is too high");
  if (Number.isInteger(Number(body.quantityAvailable)) && Number(body.quantityAvailable) >= snap.get("quantityFilled")) {
    updates.quantityAvailable = Number(body.quantityAvailable);
  } else if (body.quantityAvailable !== undefined) {
    throw new Error("Available quantity cannot be lower than current active sponsorships");
  }
  if (["LARGE", "MEDIUM", "SMALL"].includes(body.bannerSize)) updates.bannerSize = body.bannerSize;
  if (["ONE_TIME", "MONTHLY"].includes(body.billingPeriod)) {
    if (snap.get("ownerType") === "CONTEST" && body.billingPeriod === "MONTHLY") {
      throw new Error("Contest sponsorship tiers are one-time payments");
    }
    updates.billingPeriod = body.billingPeriod;
  }
  if (typeof body.active === "boolean") updates.active = body.active;
  await ref.update(updates);
  if (updates.bannerSize) {
    const activeSponsors = await db.collection(SPONSORSHIPS)
        .where("tierId", "==", tierId)
        .where("status", "==", "ACTIVE").get();
    for (let i = 0; i < activeSponsors.docs.length; i += 400) {
      const batch = db.batch();
      for (const sponsor of activeSponsors.docs.slice(i, i + 400)) {
        batch.update(sponsor.ref, {bannerSize: updates.bannerSize});
      }
      await batch.commit();
    }
  }
  return {success: true};
}

async function submitArtwork(uid, body) {
  const sponsorshipId = id(body.sponsorshipId, "sponsorshipId");
  const path = id(body.storagePath, "storagePath");
  const prefix = `sponsor_artwork/${uid}/${sponsorshipId}/`;
  if (!path.startsWith(prefix)) throw new Error("Artwork must be uploaded to your sponsorship folder");
  const file = admin.storage().bucket().file(path);
  const [exists] = await file.exists();
  if (!exists) throw new Error("Artwork upload was not found");
  const [metadata] = await file.getMetadata();
  const contentType = metadata.contentType || "";
  if (!/^(image\/(jpeg|png|webp)|video\/(mp4|webm))$/.test(contentType)) {
    throw new Error("Artwork must be a JPG, PNG, WebP, MP4, or WebM file");
  }
  const size = Number(metadata.size || 0);
  if (size > 25 * 1024 * 1024) throw new Error("Artwork must be smaller than 25 MB");
  let downloadToken = metadata.metadata && metadata.metadata.firebaseStorageDownloadTokens;
  if (!downloadToken) {
    downloadToken = crypto.randomUUID();
    await file.setMetadata({metadata: {firebaseStorageDownloadTokens: downloadToken}});
  }
  const bucketName = admin.storage().bucket().name;
  const url = `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(path)}?alt=media&token=${downloadToken}`;
  const ref = db.collection(SPONSORSHIPS).doc(sponsorshipId);
  const snap = await ref.get();
  if (!snap.exists || snap.get("sponsorUserId") !== uid || snap.get("status") !== "ACTIVE") {
    throw new Error("You can submit artwork after payment is confirmed");
  }
  await ref.update({
    artworkPath: path,
    artworkUrl: url,
    artworkContentType: contentType,
    artworkStatus: "PENDING_REVIEW",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return {success: true};
}

async function moderateArtwork(uid, body, approve) {
  if (!(await isAdmin(uid))) throw new Error("Admin access is required");
  const sponsorshipId = id(body.sponsorshipId, "sponsorshipId");
  const ref = db.collection(SPONSORSHIPS).doc(sponsorshipId);
  const snap = await ref.get();
  if (!snap.exists || !snap.get("artworkUrl")) throw new Error("Sponsorship artwork not found");
  if (snap.get("status") !== "ACTIVE") throw new Error("Only active sponsorship artwork can be reviewed");
  await ref.update({
    artworkStatus: approve ? "APPROVED" : "REJECTED",
    artworkReviewedBy: uid,
    artworkReviewedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return {success: true};
}

exports.sponsorshipApi = functions
    .region(REGION)
    .runWith({secrets: ["STRIPE_SECRET_KEY"]})
    .https.onRequest(async (req, res) => {
      responseCors(req, res);
      if (req.method === "OPTIONS") return res.status(204).send("");
      if (req.method !== "POST") return res.status(405).json({error: "POST required"});
      try {
        const user = await requireUser(req);
        const body = req.body || {};
        let result;
        switch (body.action) {
          case "create_tier": result = await createTier(user.uid, body); break;
          case "update_tier": result = await updateTier(user.uid, body); break;
          case "create_checkout": result = await createCheckout(user.uid, body); break;
          case "connect_onboarding": result = await createConnectLink(user.uid); break;
          case "submit_artwork": result = await submitArtwork(user.uid, body); break;
          case "approve_artwork": result = await moderateArtwork(user.uid, body, true); break;
          case "reject_artwork": result = await moderateArtwork(user.uid, body, false); break;
          default: throw new Error("Unknown sponsorship action");
        }
        return res.status(200).json(result);
      } catch (error) {
        console.error("[sponsorshipApi] Request failed", error.message);
        const denied = /Sign in|owner can|Admin access|not authorized/.test(error.message);
        return res.status(denied ? 403 : 400).json({error: error.message});
      }
    });

exports.stripeSponsorshipWebhook = functions
    .region(REGION)
    .runWith({secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"]})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") return res.status(405).send("POST required");
      let event;
      try {
        const rawBody = req.rawBody ? req.rawBody.toString("utf8") : "";
        event = verifyStripeEvent(rawBody, req.get("Stripe-Signature"));
      } catch (error) {
        console.error("[stripeSponsorshipWebhook] Signature validation failed", error.message);
        return res.status(400).send("Invalid webhook signature");
      }
      try {
        await handleStripeEvent(event);
        return res.status(200).send("OK");
      } catch (error) {
        console.error("[stripeSponsorshipWebhook] Failed", error.message);
        return res.status(500).send("Webhook processing failed");
      }
    });

exports.expireSponsorships = functions
    .region(REGION)
    .runWith({secrets: ["STRIPE_SECRET_KEY"]})
    .pubsub.schedule("every 24 hours")
    .timeZone("UTC")
    .onRun(async () => {
      const now = admin.firestore.Timestamp.now();
      let page = await db.collection(SPONSORSHIPS)
          .where("status", "==", "ACTIVE")
          .where("endsAt", "<=", now)
          .limit(100).get();
      while (!page.empty) {
        for (const doc of page.docs) {
          await expireSponsorship(doc.ref);
          const subscriptionId = doc.get("stripeSubscriptionId");
          if (subscriptionId && stripeSecret()) {
            try {
              await stripeDelete(`/subscriptions/${subscriptionId}`);
            } catch (error) {
              console.error("[expireSponsorships] Subscription cancel failed", error.message);
            }
          }
        }
        page = await db.collection(SPONSORSHIPS)
            .where("status", "==", "ACTIVE")
            .where("endsAt", "<=", now)
            .startAfter(page.docs[page.docs.length - 1]).limit(100).get();
      }

      // Stripe Checkout sessions expire after 24 hours by default. Recheck
      // their provider status before freeing old reservations: subscriptions
      // and asynchronous payment methods may still be completing.
      const pendingBefore = admin.firestore.Timestamp.fromMillis(
          now.toMillis() - 48 * 60 * 60 * 1000);
      let pending = await db.collection(SPONSORSHIPS)
          .where("status", "==", "PENDING_PAYMENT")
          .where("createdAt", "<=", pendingBefore)
          .orderBy("createdAt")
          .limit(100).get();
      while (!pending.empty) {
        for (const doc of pending.docs) {
          const checkoutSessionId = doc.get("stripeCheckoutSessionId");
          if (checkoutSessionId) {
            try {
              const session = await stripeRequest(`/checkout/sessions/${checkoutSessionId}`);
              if (session.status === "open" && session.expires_at <= Math.floor(now.toMillis() / 1000)) {
                await stripeRequest(`/checkout/sessions/${checkoutSessionId}/expire`, {});
                await releaseReservation(doc.id, "EXPIRED");
              } else if (session.status === "expired") {
                await releaseReservation(doc.id, "EXPIRED");
              }
            } catch (error) {
              console.error(`[expireSponsorships] Checkout ${checkoutSessionId} status check failed`, error.message);
            }
          } else {
            await releaseReservation(doc.id, "EXPIRED");
          }
        }
        pending = await db.collection(SPONSORSHIPS)
            .where("status", "==", "PENDING_PAYMENT")
            .where("createdAt", "<=", pendingBefore)
            .orderBy("createdAt")
            .startAfter(pending.docs[pending.docs.length - 1])
            .limit(100).get();
      }
      return null;
    });

exports.onContestSponsorshipEndDateChanged = functions
    .region(REGION)
    .firestore.document("contests/{contestId}")
    .onUpdate(async (change, context) => {
      const before = change.before.get("endDate");
      const after = change.after.get("endDate");
      const beforeDate = before && typeof before.toDate === "function" ?
        before.toDate() : before ? new Date(before) : null;
      const raw = after;
      const end = raw && typeof raw.toDate === "function" ? raw.toDate() : new Date(raw);
      if (!raw || !Number.isFinite(end.getTime())) return null;
      if (beforeDate && beforeDate.getTime() === end.getTime()) return null;
      const active = await db.collection(SPONSORSHIPS)
          .where("ownerType", "==", "CONTEST")
          .where("ownerId", "==", context.params.contestId)
          .where("status", "==", "ACTIVE").get();
      for (let i = 0; i < active.docs.length; i += 400) {
        const batch = db.batch();
        for (const doc of active.docs.slice(i, i + 400)) {
          batch.update(doc.ref, {
            endsAt: admin.firestore.Timestamp.fromDate(end),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      return null;
    });
