/* eslint-disable max-len, require-jsdoc, new-cap */

const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const {
  AccessToken,
  RoomServiceClient,
  WebhookReceiver,
} = require("livekit-server-sdk");

const db = admin.firestore();
const REGION = "us-central1";
const LIVEKIT_URL = process.env.LIVEKIT_URL || "";
const LIVEKIT_API_KEY = () => process.env.LIVEKIT_API_KEY || "";
const LIVEKIT_API_SECRET = () => process.env.LIVEKIT_API_SECRET || "";
const STREAMS = "streams";
const PARTICIPANTS = "stream_participants";
const LEDGER = "usage_ledger";
const PROCESSED = "processed_webhook_events";

function requiredId(value, label) {
  if (typeof value !== "string" || !value.trim() || value.includes("/")) {
    throw new Error(`Invalid ${label}`);
  }
  return value.trim();
}

function roomService() {
  if (!LIVEKIT_URL || !LIVEKIT_API_KEY() || !LIVEKIT_API_SECRET()) {
    throw new Error("LiveKit server configuration is missing");
  }
  const httpUrl = LIVEKIT_URL.replace(/^wss:/, "https:").replace(/^ws:/, "http:");
  return new RoomServiceClient(httpUrl, LIVEKIT_API_KEY(), LIVEKIT_API_SECRET());
}

function readBearer(req) {
  const header = req.get("Authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : null;
}

function cors(req, res) {
  res.set("Access-Control-Allow-Origin", req.get("Origin") || "*");
  res.set("Vary", "Origin");
  res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
}

function jsonRole(role, userId) {
  return JSON.stringify({role, userId: userId || null});
}

function getSessionRef(kind, contestId, stationId, entryId) {
  if (kind === "station") {
    return db.collection("stations").doc(stationId)
        .collection("live").doc("session");
  }
  if (kind === "organizer") {
    return db.collection("contests").doc(contestId)
        .collection("organizer_live").doc("session");
  }
  return db.collection("contests").doc(contestId)
      .collection("entries").doc(entryId)
      .collection("live").doc("session");
}

async function authorizeTokenRequest(body, uid) {
  const kind = body.roomKind;
  if (!["station", "organizer", "entry"].includes(kind)) {
    throw new Error("Invalid room kind");
  }

  let contestId = null;
  let stationId = null;
  let entryId = null;
  let ownerUserId = null;
  let publisherUserIds = [];

  if (kind === "station") {
    stationId = requiredId(body.stationId || body.contestId, "stationId");
    const station = await db.collection("stations").doc(stationId).get();
    if (!station.exists) throw new Error("Station not found");
    ownerUserId = station.get("creatorId") || null;
    publisherUserIds = [ownerUserId].filter(Boolean);
  } else {
    contestId = requiredId(body.contestId, "contestId");
    const contest = await db.collection("contests").doc(contestId).get();
    if (!contest.exists) throw new Error("Contest not found");
    ownerUserId = contest.get("creatorId") || null;
    publisherUserIds = [ownerUserId].filter(Boolean);

    if (kind === "entry") {
      entryId = requiredId(body.entryId, "entryId");
      const entry = await db.collection("contests").doc(contestId)
          .collection("entries").doc(entryId).get();
      if (!entry.exists) throw new Error("Contest entry not found");
      const entryOwner = entry.get("userId");
      if (entryOwner && !publisherUserIds.includes(entryOwner)) {
        publisherUserIds.push(entryOwner);
      }
    }
  }

  let role = "VIEWER";
  if (body.isHost === true) {
    if (!uid || !publisherUserIds.includes(uid)) {
      throw new Error("You are not authorized to host this room");
    }
    role = "HOST";
  } else if (body.isCoHost === true) {
    if (!uid) throw new Error("Sign in is required to co-host");
    const session = await getSessionRef(kind, contestId, stationId, entryId).get();
    if (!session.exists || session.get("coHostUserId") !== uid) {
      throw new Error("You are not authorized to co-host this room");
    }
    role = "COHOST";
  }

  return {kind, contestId, stationId, entryId, ownerUserId, role};
}

exports.issueLiveKitToken = functions
    .region(REGION)
    .runWith({secrets: ["LIVEKIT_API_KEY", "LIVEKIT_API_SECRET"]})
    .https.onRequest(async (req, res) => {
      cors(req, res);
      if (req.method === "OPTIONS") return res.status(204).send("");
      if (req.method !== "POST") return res.status(405).json({error: "POST required"});

      try {
        if (!LIVEKIT_URL || !LIVEKIT_API_KEY() || !LIVEKIT_API_SECRET()) {
          return res.status(503).json({error: "LiveKit service is not configured"});
        }
        let uid = null;
        const bearer = readBearer(req);
        if (bearer) {
          const decoded = await admin.auth().verifyIdToken(bearer);
          uid = decoded.uid;
        }
        const body = req.body || {};
        const request = await authorizeTokenRequest(body, uid);
        const identityPrefix = request.role.toLowerCase();
        const identitySuffix = uid || `anon_${crypto.randomUUID()}`;
        const identity = `${identityPrefix}_${identitySuffix}`;
        const roomName = request.kind === "station" ?
          `station_${request.stationId}` : request.kind === "entry" ?
            `contest_${request.contestId}_${request.entryId}` :
            `station_${request.contestId}`;

        const token = new AccessToken(LIVEKIT_API_KEY(), LIVEKIT_API_SECRET(), {
          identity,
          ttl: "10m",
        });
        token.metadata = jsonRole(request.role, uid);
        token.addGrant({
          roomJoin: true,
          room: roomName,
          roomCreate: request.role === "HOST" || request.role === "COHOST",
          canPublish: request.role === "HOST" || request.role === "COHOST",
          canPublishData: true,
          canSubscribe: true,
        });

        return res.status(200).json({
          serverUrl: LIVEKIT_URL,
          participantToken: await token.toJwt(),
          canPublish: request.role === "HOST" || request.role === "COHOST",
        });
      } catch (error) {
        console.error("[issueLiveKitToken] Request rejected", error.message);
        const clientError = /Invalid |not found|not authorized|Sign in is required/.test(error.message);
        return res.status(clientError ? 403 : 401).json({error: clientError ? error.message : "Unable to issue LiveKit token"});
      }
    });

function decodeRoom(roomName) {
  if (typeof roomName !== "string") return null;
  if (roomName.startsWith("station_")) {
    return {kind: "station", stationId: roomName.slice("station_".length)};
  }
  if (roomName.startsWith("contest_")) {
    const remainder = roomName.slice("contest_".length);
    // Contest and entry IDs can both contain underscores (for example,
    // contest_123_post_456). Preserve the encoded tail here; resolveRoom
    // finds the correct boundary by checking the candidate Firestore records.
    if (!remainder || remainder.startsWith("_") || remainder.endsWith("_")) return null;
    return {
      kind: "entry",
      encodedIds: remainder,
    };
  }
  return null;
}

async function resolveRoom(room) {
  const parsed = decodeRoom(room.name);
  if (!parsed) throw new Error(`Unsupported LiveKit room name: ${room.name}`);
  let ownerUserId = null;
  let stationId = null;
  let contestId = null;
  let entryId = null;
  let ownerType = null;

  if (parsed.kind === "station") {
    stationId = parsed.stationId;
    const station = await db.collection("stations").doc(stationId).get();
    if (station.exists) {
      ownerUserId = station.get("creatorId") || null;
      ownerType = "STATION";
    } else {
      // StationModel.toContestModel is also used for contest organizer rooms.
      const contest = await db.collection("contests").doc(stationId).get();
      if (contest.exists && contest.get("type") !== "Station") {
        contestId = stationId;
        ownerUserId = contest.get("creatorId") || null;
        ownerType = "CONTEST";
        stationId = null;
      }
    }
  } else {
    // Room names use `contest_${contestId}_${entryId}`, but both IDs may
    // contain underscores. Try each possible boundary and accept a split
    // only when both the contest and entry documents exist.
    const parts = parsed.encodedIds.split("_");
    for (let splitAt = 1; splitAt < parts.length; splitAt++) {
      const candidateContestId = parts.slice(0, splitAt).join("_");
      const candidateEntryId = parts.slice(splitAt).join("_");
      const contestRef = db.collection("contests").doc(candidateContestId);
      const [contest, entry] = await Promise.all([
        contestRef.get(),
        contestRef.collection("entries").doc(candidateEntryId).get(),
      ]);
      if (!contest.exists || !entry.exists) continue;
      contestId = candidateContestId;
      entryId = candidateEntryId;
      ownerUserId = contest.get("creatorId") || null;
      ownerType = "CONTEST";
      break;
    }
  }

  if (!ownerUserId) return null;
  return {ownerUserId, stationId, contestId, entryId, ownerType};
}

function streamDocumentId(roomSid) {
  return crypto.createHash("sha256").update(roomSid).digest("hex");
}

function participantDocumentId(streamId, participantSid) {
  return crypto.createHash("sha256")
      .update(`${streamId}:${participantSid}`).digest("hex");
}

function parseParticipant(participant) {
  let role = "GUEST";
  let userId = null;
  try {
    const metadata = JSON.parse(participant.metadata || "{}");
    if (["HOST", "COHOST", "VIEWER", "GUEST"].includes(metadata.role)) {
      role = metadata.role;
      userId = metadata.userId || null;
      return {role, userId};
    }
  } catch (_) {
    // Older client tokens have no metadata; identity prefixes preserve roles.
  }
  const identity = participant.identity || "";
  const match = identity.match(/^(host|cohost|viewer|guest)_(.*)$/i);
  if (match) {
    role = match[1].toUpperCase();
    const suffix = match[2];
    userId = suffix.startsWith("anon_") ? null : suffix || null;
  }
  return {role, userId};
}

function timestampFromSeconds(value, fallback) {
  const seconds = Number(value);
  return Number.isFinite(seconds) && seconds > 0 ?
    admin.firestore.Timestamp.fromMillis(seconds * 1000) : fallback;
}

async function ensureStream(room, eventTime) {
  const streamId = streamDocumentId(room.sid || room.name);
  const streamRef = db.collection(STREAMS).doc(streamId);
  const snapshot = await streamRef.get();
  if (snapshot.exists) return {streamId, streamRef, stream: snapshot.data()};
  const owner = await resolveRoom(room);
  if (!owner) return null;
  const now = eventTime || admin.firestore.Timestamp.now();
  const data = {
    streamId,
    stationId: owner.stationId,
    contestId: owner.contestId,
    entryId: owner.entryId,
    ownerType: owner.ownerType,
    ownerUserId: owner.ownerUserId,
    livekitRoomName: room.name,
    livekitRoomSid: room.sid || null,
    livekitProjectId: LIVEKIT_URL.replace(/^wss?:\/\//, ""),
    status: "LIVE",
    startedAt: now,
    endedAt: null,
    currentViewers: 0,
    peakViewers: 0,
    viewerSecondsTotal: 0,
    hostSecondsTotal: 0,
    cohostSecondsTotal: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  await streamRef.create(data).catch(async (error) => {
    if (error.code !== 6 && error.code !== "already-exists") throw error;
  });
  const fresh = await streamRef.get();
  return {streamId, streamRef, stream: fresh.data()};
}

async function recordJoin(streamInfo, room, participant, joinedAt, options = {}) {
  if (!participant || !participant.sid) return;
  const {role, userId} = parseParticipant(participant);
  const participantId = participantDocumentId(streamInfo.streamId, participant.sid);
  const participantRef = db.collection(PARTICIPANTS).doc(participantId);
  const streamRef = streamInfo.streamRef;
  const eventRef = options.eventId ? db.collection(PROCESSED).doc(options.eventId) : null;

  await db.runTransaction(async (transaction) => {
    const refs = [participantRef, streamRef];
    if (eventRef) refs.push(eventRef);
    const snapshots = await transaction.getAll(...refs);
    const participantSnap = snapshots[0];
    const streamSnap = snapshots[1];
    const eventSnap = eventRef ? snapshots[2] : null;
    if (eventSnap && eventSnap.exists) return;

    if (!participantSnap.exists) {
      let reconnectCount = 0;
      if (userId) {
        const recentSessions = await transaction.get(db.collection(PARTICIPANTS)
            .where("streamId", "==", streamInfo.streamId)
            .where("userId", "==", userId)
            .orderBy("connectedAt", "desc").limit(2));
        const previous = recentSessions.docs.find((doc) => doc.id !== participantId);
        if (previous && previous.get("disconnectedAt")) {
          const gapMs = joinedAt.toMillis() - previous.get("disconnectedAt").toMillis();
          if (gapMs >= 0 && gapMs <= 30000) {
            reconnectCount = (previous.get("reconnectCount") || 0) + 1;
          }
        }
      }
      const isViewer = role === "VIEWER";
      const participantData = {
        participantId,
        streamId: streamInfo.streamId,
        userId,
        role,
        livekitParticipantSid: participant.sid,
        livekitIdentity: participant.identity || null,
        connectedAt: joinedAt,
        disconnectedAt: null,
        connectionSeconds: null,
        reconnectCount,
        reconciled: Boolean(options.reconciled),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      transaction.create(participantRef, participantData);
      const updates = {updatedAt: admin.firestore.FieldValue.serverTimestamp()};
      if (isViewer) {
        const nextCount = (streamSnap.get("currentViewers") || 0) + 1;
        updates.currentViewers = nextCount;
        updates.peakViewers = Math.max(streamSnap.get("peakViewers") || 0, nextCount);
      }
      transaction.set(streamRef, updates, {merge: true});
    }
    if (eventRef) {
      transaction.create(eventRef, {
        eventId: options.eventId,
        eventType: "participant_joined",
        receivedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });
}

async function closeParticipant(streamInfo, room, participant, disconnectedAt, options = {}) {
  if (!participant || !participant.sid) return;
  const participantId = participantDocumentId(streamInfo.streamId, participant.sid);
  const participantRef = db.collection(PARTICIPANTS).doc(participantId);
  const streamRef = streamInfo.streamRef;
  const eventRef = options.eventId ? db.collection(PROCESSED).doc(options.eventId) : null;

  await db.runTransaction(async (transaction) => {
    const refs = [participantRef, streamRef];
    if (eventRef) refs.push(eventRef);
    const snapshots = await transaction.getAll(...refs);
    const participantSnap = snapshots[0];
    const streamSnap = snapshots[1];
    const eventSnap = eventRef ? snapshots[2] : null;
    if (eventSnap && eventSnap.exists) return;
    if (!participantSnap.exists || participantSnap.get("disconnectedAt")) {
      if (eventRef && !eventSnap.exists) {
        transaction.create(eventRef, {
          eventId: options.eventId,
          eventType: "participant_left",
          receivedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      return;
    }

    const data = participantSnap.data();
    const connectedMillis = data.connectedAt && data.connectedAt.toMillis ?
      data.connectedAt.toMillis() : disconnectedAt.toMillis();
    const seconds = Math.max(0, Math.floor((disconnectedAt.toMillis() - connectedMillis) / 1000));
    const role = data.role || "GUEST";
    transaction.update(participantRef, {
      disconnectedAt,
      connectionSeconds: seconds,
      reconciled: Boolean(options.reconciled) || Boolean(data.reconciled),
    });

    const updates = {updatedAt: admin.firestore.FieldValue.serverTimestamp()};
    if (role === "VIEWER") {
      updates.viewerSecondsTotal = admin.firestore.FieldValue.increment(seconds);
      updates.currentViewers = Math.max(0, (streamSnap.get("currentViewers") || 0) - 1);
      const ledgerRef = db.collection(LEDGER).doc(participantId);
      transaction.create(ledgerRef, {
        // Part 2 charges the station/contest account, not the viewer whose
        // connection generated the usage.
        userId: streamSnap.get("ownerUserId") || null,
        stationId: streamSnap.get("stationId") || null,
        contestId: streamSnap.get("contestId") || null,
        streamId: streamInfo.streamId,
        transactionType: "STREAM_USAGE",
        amount: -seconds,
        unit: "VIEWER_SECONDS",
        balanceAfter: null,
        referenceId: participantId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else if (role === "HOST") {
      updates.hostSecondsTotal = admin.firestore.FieldValue.increment(seconds);
    } else if (role === "COHOST") {
      updates.cohostSecondsTotal = admin.firestore.FieldValue.increment(seconds);
    }
    transaction.set(streamRef, updates, {merge: true});
    if (eventRef) {
      transaction.create(eventRef, {
        eventId: options.eventId,
        eventType: "participant_left",
        receivedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });
}

async function handleRoomFinished(room, eventId, endedAt, knownStreamInfo = null) {
  const streamInfo = knownStreamInfo || await ensureStream(room, endedAt);
  if (!streamInfo) return false;
  const open = await db.collection(PARTICIPANTS)
      .where("streamId", "==", streamInfo.streamId)
      .where("disconnectedAt", "==", null).get();
  for (const participantDoc of open.docs) {
    const row = participantDoc.data();
    await closeParticipant(streamInfo, room, {
      sid: row.livekitParticipantSid,
      identity: row.livekitIdentity,
    }, endedAt, {reconciled: true, eventId: `${eventId}_${participantDoc.id}`});
  }
  await streamInfo.streamRef.set({
    status: "ENDED",
    endedAt,
    currentViewers: 0,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  await db.collection(PROCESSED).doc(eventId).set({
    eventId,
    eventType: "room_finished",
    receivedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return true;
}

exports.livekitWebhook = functions
    .region(REGION)
    .runWith({secrets: ["LIVEKIT_API_KEY", "LIVEKIT_API_SECRET"]})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") return res.status(405).send("POST required");
      try {
        const rawBody = req.rawBody ? req.rawBody.toString("utf8") : "";
        const receiver = new WebhookReceiver(LIVEKIT_API_KEY(), LIVEKIT_API_SECRET());
        const event = await receiver.receive(rawBody, req.get("Authorization"));
        if (!event.id || !event.event || !event.room) {
          return res.status(400).send("Invalid LiveKit event");
        }
        const eventTime = timestampFromSeconds(event.createdAt, admin.firestore.Timestamp.now());
        if (event.event === "room_started") {
          const streamInfo = await ensureStream(event.room, eventTime);
          if (!streamInfo) {
            console.warn(`[livekitWebhook] Ignoring room not found in this Firebase project: ${event.room.name}`);
            return res.status(200).send("Room is not tracked in this Firebase project");
          }
          await streamInfo.streamRef.set({status: "LIVE", updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
        } else if (event.event === "participant_joined") {
          const streamInfo = await ensureStream(event.room, eventTime);
          if (!streamInfo) {
            console.warn(`[livekitWebhook] Ignoring room not found in this Firebase project: ${event.room.name}`);
            return res.status(200).send("Room is not tracked in this Firebase project");
          }
          const joinedAt = timestampFromSeconds(event.participant && event.participant.joinedAt, eventTime);
          await recordJoin(streamInfo, event.room, event.participant, joinedAt, {eventId: event.id});
        } else if (event.event === "participant_left" || event.event === "participant_connection_aborted") {
          const streamInfo = await ensureStream(event.room, eventTime);
          if (!streamInfo) {
            console.warn(`[livekitWebhook] Ignoring room not found in this Firebase project: ${event.room.name}`);
            return res.status(200).send("Room is not tracked in this Firebase project");
          }
          await closeParticipant(streamInfo, event.room, event.participant, eventTime, {eventId: event.id});
        } else if (event.event === "room_finished") {
          const streamInfo = await ensureStream(event.room, eventTime);
          if (!streamInfo) {
            console.warn(`[livekitWebhook] Ignoring room not found in this Firebase project: ${event.room.name}`);
            return res.status(200).send("Room is not tracked in this Firebase project");
          }
          await handleRoomFinished(event.room, event.id, eventTime, streamInfo);
        } else {
          return res.status(200).send("Ignored");
        }
        return res.status(200).send("OK");
      } catch (error) {
        console.error("[livekitWebhook] Processing failed", error);
        return res.status(500).send("Webhook processing failed");
      }
    });

exports.reconcileLiveKitUsage = functions
    .region(REGION)
    .runWith({secrets: ["LIVEKIT_API_KEY", "LIVEKIT_API_SECRET"]})
    .pubsub.schedule("every 5 minutes")
    .timeZone("UTC")
    .onRun(async () => {
      const service = roomService();
      const streamsQuery = db.collection(STREAMS)
          .where("status", "==", "LIVE").orderBy(admin.firestore.FieldPath.documentId());
      let page = await streamsQuery.limit(100).get();
      while (!page.empty) {
        for (const streamDoc of page.docs) {
          const stream = streamDoc.data();
          const room = {
            name: stream.livekitRoomName,
            sid: stream.livekitRoomSid,
          };
          try {
            const activeRooms = await service.listRooms([room.name]);
            if (!activeRooms.some((activeRoom) => activeRoom.name === room.name)) {
              const endedAt = admin.firestore.Timestamp.now();
              await handleRoomFinished(
                  room,
                  `reconciled_room_finished_${streamDoc.id}_${endedAt.seconds}`,
                  endedAt);
              continue;
            }
            const liveParticipants = await service.listParticipants(room.name);
            const liveSids = new Set(liveParticipants.map((p) => p.sid));
            const info = {streamId: streamDoc.id, streamRef: streamDoc.ref, stream};

            for (const participant of liveParticipants) {
              const joinedAt = timestampFromSeconds(
                  participant.joinedAt, admin.firestore.Timestamp.now());
              await recordJoin(info, room, participant, joinedAt, {reconciled: true});
            }

            const openRows = await db.collection(PARTICIPANTS)
                .where("streamId", "==", streamDoc.id)
                .where("disconnectedAt", "==", null).get();
            for (const rowDoc of openRows.docs) {
              const row = rowDoc.data();
              if (!liveSids.has(row.livekitParticipantSid)) {
                await closeParticipant(info, room, {
                  sid: row.livekitParticipantSid,
                  identity: row.livekitIdentity,
                }, admin.firestore.Timestamp.now(), {reconciled: true});
              }
            }
          } catch (error) {
            console.error(`[reconcileLiveKitUsage] Room ${room.name} failed`, error);
          }
        }
        page = await streamsQuery.startAfter(page.docs[page.docs.length - 1])
            .limit(100).get();
      }
      return null;
    });
