# Phase 1 Part 1 setup and deployment guide

This implementation adds server-authoritative LiveKit usage tracking and paid sponsorships (tiers, artwork review, display and revenue ledger) to the existing app. It leaves the existing broadcast/session UI model and Agora fallback in place; LiveKit token signing now runs on Cloud Functions.

## 1. Rotate the exposed LiveKit credentials

The old API secret was embedded in a distributed Flutter client, so assume it is compromised.

1. In LiveKit Cloud, create an **additional API key and secret** for the existing LiveKit project. Do not edit or revoke the exposed key yet. Keep the existing project URL. LiveKit lets you choose an API key for the webhook's signing key, so the server and webhook can move to the new pair while legacy apps continue using the old pair ([webhook configuration](https://docs.livekit.io/intro/basics/rooms-participants-tracks/webhooks-events/)).
2. Set the new credentials as Firebase Secrets for each Firebase project:

   ```powershell
   firebase functions:secrets:set LIVEKIT_API_KEY --project contest-app-94050
   firebase functions:secrets:set LIVEKIT_API_SECRET --project contest-app-94050
   ```

   Repeat with `--project mlivecast-staging` for staging. The CLI prompts for each secret value; enter it there and do not put it in source code, `.env` files, or chat. Deploy the Functions so token issuance and signature verification use the new key.

3. In LiveKit Cloud → **Settings → Webhooks**, edit the existing usage webhook and set **Signing API key** to the new key. Do not create a second copy of the same webhook unless you intentionally want duplicate delivery. The Cloud Function verifies the signature using the Firebase-stored key pair.

4. Release the updated app builds. Old installed builds still mint tokens with the old embedded pair; those builds continue to connect while the old key remains active. New builds request short-lived tokens from Cloud Functions and no longer contain a LiveKit signing secret. Confirm a new build and an old installed build can both join and reconnect before retiring the old key.

5. Once users have moved off builds containing the exposed key, revoke/delete the old API key in LiveKit Cloud. Users who have not updated will no longer be able to obtain new tokens from that build. If the exposure requires immediate containment, revoke the old key immediately and accept that those legacy builds will stop being able to join/reconnect; there is no way to revoke a client-held signing secret while continuing to trust tokens signed with that same secret.

## 2. Configure Stripe Connect for sponsorship payments

The app's existing payment service was a simulation. Sponsorship checkout now uses Stripe-hosted Checkout plus Stripe Connect destination charges, with the 15% application fee and the owner's 85% transfer. Sponsorship tier prices and ledger entries are USD cents.

1. Create/enable a Stripe platform account and Connect Express in the Stripe Dashboard. Complete the platform business verification and payout setup.
2. Check that Stripe supports the country where the platform business is registered and the countries where owner payout accounts will be opened. Stripe Connect transfer support depends on the platform/connected-account country pair ([Stripe Connect country guidance](https://docs.stripe.com/connect/cross-border-payouts)). As currently implemented, each connected account is created in the one `STRIPE_CONNECT_COUNTRY` configured for the platform; there is no separate owner-country selector. Owners must therefore be eligible to onboard in that country. Supporting other payout countries needs an explicit country-selection and allowed-transfer implementation. If the platform or owners cannot use this Connect setup, choose a supported marketplace payment provider before going live and replace this Stripe adapter.
3. Create separate Stripe test-mode and live-mode API keys. Set the mode you want in Firebase Secrets:

   ```powershell
   firebase functions:secrets:set STRIPE_SECRET_KEY --project contest-app-94050
   ```

   Repeat for staging. Enter the secret key at the prompt. Never use a publishable key for this server secret.
4. In Stripe Dashboard → Developers → Webhooks, create an endpoint for:

   ```text
   https://us-central1-contest-app-94050.cloudfunctions.net/stripeSponsorshipWebhook
   ```

   For staging, replace the project ID. Subscribe to `checkout.session.completed`, `checkout.session.expired`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `invoice.paid`, and `customer.subscription.deleted`. Copy the endpoint's signing secret and store it in Firebase Secrets:

   ```powershell
   firebase functions:secrets:set STRIPE_WEBHOOK_SECRET --project contest-app-94050
   ```

   Repeat separately for staging. Stripe retries failed deliveries; keep the webhook signing secret private.

The Mlivecast payment account's country code and public return URL are environment settings, not source constants. In each project's `functions/.env.<projectId>` file, add:

```text
STRIPE_CURRENCY=usd
STRIPE_CONNECT_COUNTRY=US
PUBLIC_BASE_URL=https://contest-app-94050.web.app
```

Replace `US` with the Stripe-supported two-letter country of the platform business, and use your actual Firebase Hosting or verified custom-domain origin for `PUBLIC_BASE_URL`. Configure the corresponding values separately for staging. Currency is currently USD-only because the UI labels prices in dollars and the shared ledger uses `USD_CENTS`.

5. Owners must open Sponsor Settings and complete Stripe's hosted Express onboarding before a tier can be purchased. Stripe must report transfers and payouts enabled for that connected account. Stripe holds and routes the 85/15 destination-charge split; Mlivecast still owns its processor fees, refund, and dispute obligations.

### Mobile-store payment policy check

Sponsorship checkout currently opens Stripe's hosted Checkout on web, Android, and iOS. Before releasing paid sponsorship buttons in store-distributed apps, have the app owner confirm the storefront rules for this exact flow. Apple's advertising-management exception is limited to apps whose sole purpose is campaign management and excludes buying ads shown in that same app; Google Play generally requires Play Billing for digital services unless a listed exception/program applies. If either store requires its billing system for these sponsorships, that is additional payment code and product setup, not a Firebase secret. See [Apple App Review Guideline 3.1.1 and 3.1.3(g)](https://developer.apple.com/app-store/review/guidelines/) and [Google Play Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en).

## 3. Configure each Firebase project's LiveKit URL

Cloud Functions reads `LIVEKIT_URL` from the Firebase Functions environment. Production already has `functions/.env.contest-app-94050`; verify that it contains the correct LiveKit Cloud URL. For staging, create `functions/.env.mlivecast-staging` with the staging LiveKit URL (one line: `LIVEKIT_URL=wss://...`). These files contain only the public server URL, never the API secret.

The Flutter client selects the Functions hostname from the initialized Firebase project ID, so production and staging clients call the matching project. This implementation expects the Functions region to remain `us-central1`.

## 4. Deploy Functions

From the project root, deploy the production Functions after both secrets are set:

```powershell
firebase deploy --only functions --project contest-app-94050
```

Deploy staging separately with `--project mlivecast-staging`. Firebase may ask to enable Cloud Scheduler / Cloud Build APIs for scheduled reconciliation and expiry functions; enable them for the project when prompted. The new exports are `issueLiveKitToken`, `livekitWebhook`, `reconcileLiveKitUsage`, `sponsorshipApi`, `stripeSponsorshipWebhook`, `expireSponsorships`, and `onContestSponsorshipEndDateChanged`. Existing account-cleanup exports remain in place.

## 5. Register the LiveKit webhook

After Functions deploy, ensure the production usage webhook in LiveKit Cloud → **Settings → Webhooks** uses the **new API key as its Signing API key** and has this URL:

```text
https://us-central1-contest-app-94050.cloudfunctions.net/livekitWebhook
```

Subscribe to `room_started`, `room_finished`, `participant_joined`, `participant_left`, and `participant_connection_aborted`. LiveKit signs the callbacks; the function verifies each signature with the new API key and secret. Keep the webhook URL private and do not disable signature verification.

If staging uses a **separate LiveKit project**, create/configure a second webhook there with the staging Functions URL and the matching key. If staging and production share one LiveKit project, as they currently do, change the existing production webhook's Signing API key once; do **not** add a staging webhook to that shared project by default. Each webhook URL receives the shared project's events, and the staging database may not contain the production station/contest records those events refer to. Avoid running staging broadcasts against the shared production LiveKit project; use a separate LiveKit project for isolated staging tests.

## 6. Verify Firestore and Storage access

Cloud Functions uses the Admin SDK and writes top-level collections `streams`, `stream_participants`, `usage_ledger`, `processed_webhook_events`, `sponsor_tiers`, `sponsorships`, `sponsorship_payments`, and `stripe_webhook_events`. Confirm Firestore is enabled in each target project. The first live query can prompt you to create indexes. Expect composite indexes for:

- `stream_participants`: `streamId` ascending + `disconnectedAt` ascending; and `streamId` ascending + `userId` ascending + `connectedAt` descending.
- `sponsor_tiers`: `ownerType` ascending + `ownerId` ascending.
- `sponsorships`: `ownerType` ascending + `ownerId` ascending + `status` ascending + `artworkStatus` ascending; `status` ascending + `artworkStatus` ascending; `sponsorUserId` ascending + `ownerType` ascending + `ownerId` ascending; `tierId` ascending + `status` ascending; `status` ascending + `endsAt` ascending; `status` ascending + `createdAt` ascending; and `ownerType` ascending + `ownerId` ascending + `status` ascending.

If a query reports a missing index, use the Firebase-provided index link and create that exact index in the matching project; wait for it to finish building before testing the query again.

Client Firestore rules must allow public reads of tiers and only active/approved artwork, plus owners and sponsors reading their own sponsorship records. Do not allow client writes to any of these billing collections; all creates, payments, tier edits, reviews, and ledger entries go through authenticated Cloud Functions. The Admin SDK bypasses client rules. The current repository does not contain the deployed Firestore rules, so merge equivalent conditions into the existing Firebase Console rules rather than replacing the rules protecting the rest of the app.

The rules below illustrate the required access behavior. They are not a replacement rules file; merge them into the existing rules and keep the current protections around all existing collections:

```text
function signedIn() { return request.auth != null; }
function isAdmin() {
  return signedIn() &&
    get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
}
match /sponsor_tiers/{tierId} {
  allow read: if true;
  allow write: if false;
}
match /sponsorships/{sponsorshipId} {
  allow read: if isAdmin() ||
    (resource.data.status == 'ACTIVE' && resource.data.artworkStatus == 'APPROVED') ||
    (signedIn() && resource.data.sponsorUserId == request.auth.uid) ||
    (signedIn() && resource.data.ownerUserId == request.auth.uid);
  allow write: if false;
}
match /streams/{id} { allow read: if isAdmin(); allow write: if false; }
match /stream_participants/{id} { allow read: if isAdmin(); allow write: if false; }
match /usage_ledger/{id} { allow read: if isAdmin(); allow write: if false; }
match /processed_webhook_events/{id} { allow read, write: if false; }
match /stripe_webhook_events/{id} { allow read, write: if false; }
match /sponsorship_payments/{id} { allow read, write: if false; }
```

Adapt the syntax to the existing `rules_version = '2'` file and retain all existing app rules. Test both authorized queries and denied client writes in the Firebase Emulator or Rules Playground before deploying.

The Flutter upload writes artwork beneath `sponsor_artwork/{uid}/{sponsorshipId}/`. Add a rule to the existing Firebase Storage rules that permits an authenticated user to upload only into their own path, limits files to 25 MB, and allows only JPEG/PNG/WebP/MP4/WebM. The sponsorship API independently verifies file owner path, MIME type, file size, and paid sponsorship status before submission. Public display uses the file's Firebase download token after admin approval. Admin checks use the same `users/{uid}.role == 'admin'` field as the current app.

The matching Storage rule behavior is:

```text
match /sponsor_artwork/{uid}/{sponsorshipId}/{fileName} {
  allow read: if true;
  allow write: if request.auth != null && request.auth.uid == uid &&
    request.resource.size < 25 * 1024 * 1024 &&
    request.resource.contentType.matches('image/(jpeg|png|webp)|video/(mp4|webm)');
}
```

Review Firestore security rules so clients cannot create, edit, or delete usage records, webhook deduplication records, or server-owned stream totals. Admin SDK writes bypass client rules. Existing UI session documents are separate and remain under their current access rules.

## 7. Roll out Android, iOS, and web clients

Build and deploy the Flutter app containing the server-issued token change. All three platforms use the same HTTPS endpoint and Firebase Auth ID token; the endpoint returns a short-lived LiveKit token. Test a signed-in host, a co-host who is present in the live-session document, a signed-in viewer, and an anonymous viewer if the app supports one. Hosting an entry requires the account to own that entry or the contest; station hosting requires the station creator account.

During rollout, legacy app builds still contain the old token signing key. Revoke the old LiveKit key once the new client rollout is complete. Any previous published build or repository history containing that key should be treated as exposed.

Build and deploy the app from the repository root after the backend and rules are configured:

```powershell
flutter build apk --release
flutter build appbundle --release
flutter build web --release
firebase deploy --only hosting --project contest-app-94050
```

For iOS, run `flutter build ios --release` on a Mac with the Apple signing team and provisioning profile configured in Xcode, then archive and submit through App Store Connect. Android releases need the existing upload key/Play Console listing. The source already has Firebase platform options for Android, iOS, and web; retain those existing app registrations and signing setup.

## 8. Check records with controlled transactions

Inspect `streams/{streamId}`, `stream_participants/{participantId}`, and `usage_ledger/{participantId}` after a controlled test stream. Each viewer connection should produce one participant row and, on close, one `STREAM_USAGE` ledger row with a negative `VIEWER_SECONDS` amount. Host and co-host seconds are accumulated separately. Duplicate webhook delivery must not create another ledger row. A scheduled reconciliation runs every five minutes and flags repaired rows with `reconciled: true`.

Reconciliation can recover a participant who is still connected when a poll runs, and can close a previously recorded participant no longer in the room. It cannot reconstruct a participant who joined and left entirely between polls if both relevant webhook deliveries were permanently lost; the ledger remains based on the provider's available event history.

## 9. End-to-end sponsorship walkthrough

1. In Stripe test mode, an owner opens a station or contest, opens **Sponsorships and support**, completes Connect onboarding, then creates tiers with a price, quantity, and display size. Contest tiers are one-time; station tiers may be one-time or monthly with a selected term of 1–24 months.
2. A different signed-in account chooses a tier and completes Stripe Checkout with a Stripe test payment method. Wait for the Stripe webhook; a return from Checkout by itself does not mark a payment complete.
3. The sponsor uploads an image/video. Its status becomes `PENDING_REVIEW`.
4. An admin opens Admin Panel → Sponsor Review, approves the artwork, and confirms it appears on the owner's station/contest Details page in tier-size order.
5. Confirm the `sponsorships` record has `ACTIVE`, the exact `endsAt`, amount and Stripe references; confirm the two `SPONSORSHIP_CREDIT` rows sum to the payment and hold 85%/15% in USD cents. For monthly subscriptions, verify each paid invoice creates one pair of rows.
6. Extend a contest's end date and confirm all active contest sponsorships update. Expire a station sponsorship and confirm its tier slot is freed and its monthly Stripe subscription is cancelled. Abandon Checkout for more than 48 hours and confirm the daily job checks Stripe's Checkout status and releases only expired sessions.

Before production money is accepted, decide and document tax treatment, refund and chargeback handling, owner payout support, acceptable artwork/moderation policy, and whether monthly sponsorship renewals are appropriate. The implementation records successful payments and the requested split; it does not yet automate refunds, chargeback reversals, tax calculation, or an owner earnings/payout statement UI.

## 10. Pre-launch account/configuration checklist

1. Confirm the legal country of the Mlivecast Stripe platform and where owners are eligible to receive payouts. Stripe Connect transfer support is country-pair dependent; configure `STRIPE_CONNECT_COUNTRY` only after confirming the actual platform country and payout model with Stripe. The current code creates every connected account in that one country. If the platform or owners cannot use this Connect setup, do not enable paid tiers until a supported provider or a country-aware implementation is selected.
2. Finish Stripe platform verification and configure owner onboarding, payment method settings, branding and payout terms in Stripe Dashboard. Test with Stripe test-mode platform and connected accounts first.
3. Configure Firestore composite indexes and merge the shown collection rules into the existing deployed Firestore rules. Merge the artwork rule into the existing Storage rules. This repository has no Firestore/Storage rules file, so copying a replacement ruleset into the app would risk breaking its existing data access.
4. Deploy Cloud Functions, register both Stripe and LiveKit webhooks, then run the controlled stream and sponsorship walkthroughs above in staging. Deploy production only after test-mode callbacks and the three client builds work.
5. Decide the Apple App Store and Google Play payment-policy treatment for buying sponsorship placements that are displayed inside the app. The current implementation launches hosted Stripe Checkout on every platform; store policy acceptance is not a Firebase configuration setting. If either store requires its own in-app purchase route for this product, that route needs an additional platform purchase/receipt-verification implementation before store release.
6. Confirm cancellation, refund, dispute, moderation, tax and payout support procedures with the payment-account owner before turning on live payments.
