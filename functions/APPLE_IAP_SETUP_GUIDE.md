# Apple In-App Purchase setup for Mlivecast

This adds Apple auto-renewable subscriptions to the iOS subscription screen. iOS reads localized prices from the App Store, asks StoreKit to purchase, and sends Apple's signed transaction to Firebase for signature verification. Only the verified backend writes `user_subscriptions/{uid}` and `users/{uid}.subscriptionLevel`. Web and Android keep their existing code paths.

The implementation uses these product identifiers (create them exactly, case-sensitive):

| Mlivecast plan | App Store Connect product ID | Existing plan ID |
|---|---|---|
| Premium Monthly | `com.mlivecast.premium.monthly` | `premium` |
| Premium Yearly | `com.mlivecast.premium.yearly` | `premium_yearly` |

The iOS app's bundle ID in this repository is `com.contestlive.contestLive`.

## A. App Store Connect setup (account owner/admin)

1. Sign in at [App Store Connect](https://appstoreconnect.apple.com/) with an account that can manage the app's agreements and in-app purchases.
2. Open **Business** and complete the Paid Apps Agreement, tax forms, and banking details. Apple will not sell paid IAP products until these are accepted.
3. Open **My Apps → Mlivecast → In-App Purchases** (Apple may label this section **Subscriptions**).
4. Create one subscription group, for example **Mlivecast Premium**.
5. Inside the group create two **Auto-Renewable Subscriptions**:
   - Product ID `com.mlivecast.premium.monthly`, duration one month.
   - Product ID `com.mlivecast.premium.yearly`, duration one year.
6. Set the display name, description, and price for each. The app will show StoreKit's localized price, so edit the displayed dollar values in the app only by changing prices in App Store Connect. Make the annual price and discount text truthful for the actual configured price.
7. Complete Apple's required product localization, review screenshot, and subscription metadata. Both subscriptions must belong to the same group so Apple manages an upgrade/downgrade as one subscription.
8. Ensure the products are available in the intended countries and submit them with the app version when App Store Connect requests it.
9. In **Users and Access → Sandbox**, create a Sandbox tester account (not a real customer's Apple Account) for purchase testing. On a test iPhone/iPad, use the app build installed through TestFlight and sign into the App Store sandbox tester when prompted.
10. In the app's App Store Connect page, open **App Store Server Notifications** and configure **Version 2** for both Production and Sandbox. Use these URLs after the Firebase functions are deployed:

    Production: `https://us-central1-contest-app-94050.cloudfunctions.net/appleSubscriptionNotifications`

    Staging: `https://us-central1-mlivecast-staging.cloudfunctions.net/appleSubscriptionNotifications`

    If App Store Connect provides separate Production and Sandbox URL fields, enter the same matching Firebase URL in both fields. The function checks the signed payload's Apple environment. If staging has a separate App Store Connect app record, configure that app's Sandbox URL to staging too.

11. Copy the app's numeric **Apple ID** from **App Information**. It is a number (not the bundle ID). Put that number in the production and staging Functions environment file as described below.

## B. Firebase/Functions setup (developer)

The server verifies Apple's JWS data using Apple's public root certificate. This does **not** need an App Store Connect `.p8` private key or Stripe credentials. A `.p8` key would only be needed later if we decide to call Apple's App Store Server API directly.

1. Download the current **Apple Root CA - G3** certificate from [Apple PKI](https://www.apple.com/certificateauthority/). Save the binary `.cer` file locally; do not put it in the app bundle.
2. In PowerShell, make a Base64 copy of that public certificate (replace the path with the actual downloaded file):

   ```powershell
   $appleRootBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\path\to\AppleRootCA-G3.cer'))
   Set-Clipboard $appleRootBase64
   ```

3. In the project folder, set the Firebase Secret in staging and production. Each command prompts for the secret value; paste the clipboard contents into the prompt. Do not put the Base64 string in source code or a chat:

   ```powershell
   firebase functions:secrets:set APPLE_ROOT_CA_G3_BASE64 --project mlivecast-staging
   firebase functions:secrets:set APPLE_ROOT_CA_G3_BASE64 --project contest-app-94050
   ```

4. In `functions/.env.mlivecast-staging`, add the numeric Apple ID:

   ```text
   APPLE_APP_ID=6772730781
   ```

   Add the same `APPLE_APP_ID=6772730781` to `functions/.env.contest-app-94050`. This is the numeric app Apple ID shown in App Store Connect → App Information; it is not the bundle ID, subscription group ID, or individual subscription IDs. Keep these files out of public source control if that is your repository's convention; the ID is not a secret.

5. Deploy just the two Apple functions to staging first:

   ```powershell
   firebase deploy --only functions:verifyAppleSubscription,functions:appleSubscriptionNotifications --project mlivecast-staging
   ```

6. After staging tests pass, deploy the same functions to production:

   ```powershell
   firebase deploy --only functions:verifyAppleSubscription,functions:appleSubscriptionNotifications --project contest-app-94050
   ```

7. Once deployment succeeds, paste the matching notification URL from section A into App Store Connect and send Apple's **Test Notification** from that page. The latest attempt should report success. Do not enable the iOS purchase UI in a release until the endpoint returns successful verification and notifications.

## C. iOS build and test steps

1. On a Mac, run `flutter pub get`, open `ios/Runner.xcworkspace` in Xcode, confirm the signing team and bundle ID are `com.contestlive.contestLive`, and keep the app's existing Firebase plist/configuration.
2. In Xcode, confirm the Runner target has **In-App Purchase** capability enabled if Xcode exposes it for this project. StoreKit purchases are configured in App Store Connect; no app secret belongs in Xcode or Flutter source.
3. Create a TestFlight build with the new Dart code. Use the TestFlight install and Sandbox tester for an end-to-end test, because the Firebase verifier accepts Apple's Sandbox and Production signed transactions. Xcode's local StoreKit Configuration is useful for checking the purchase sheet and product UI, but its local transactions are not Apple Sandbox transactions and won't activate a Firebase entitlement through this verifier.
4. Sign into Mlivecast with a Firebase account, open **Upgrade Subscription**, and confirm the two products show the localized App Store prices. If either product is missing, check the product IDs, agreements, product metadata, storefront availability, bundle ID, and build's App Store Connect record.
5. Buy Premium Monthly using the Sandbox tester. Accept the Apple purchase sheet. Confirm the verified Firebase records update `user_subscriptions/{uid}` and `users/{uid}.subscriptionLevel` to `premium`; premium features should unlock from the existing field.
6. Delete/reinstall the app or sign into the same Mlivecast account on another test device and press **Restore Purchases**. The same verified entitlement should be restored. The backend intentionally binds an Apple original transaction to the first Mlivecast account that claims it; contact support rather than trying to attach one Apple subscription to multiple Mlivecast accounts.
7. In iOS Settings / Apple Account subscriptions, cancel the Sandbox subscription. Cancellation should turn off renewal but retain access until the paid period expires. Use Apple's Sandbox renewal timing and server notification history to verify expiration, renewal, refund, and restore behavior.
8. Repeat on a real iPhone/iPad test device and then review device logs and Firebase Functions logs. Do not use a Stripe test card for the Apple subscription flow.

## D. Before App Review

- Add working Privacy Policy and Terms of Use links to the app's subscription screen and App Store metadata. The current repository does not provide the owner's canonical URLs, so use the company's real public legal pages before submitting.
- The subscription screen links to the existing in-app Terms of Use/EULA and shows a Privacy Policy link when `MLIVECAST_PRIVACY_POLICY_URL` is provided. For the iOS release build, pass the owner's real public URL, for example `flutter build ipa --release --dart-define=MLIVECAST_PRIVACY_POLICY_URL=https://YOUR-REAL-DOMAIN/privacy` (replace the example with the real URL; don't submit the placeholder). Also enter the same URL in App Store Connect's app privacy-policy field.
- Make the app's subscription name, duration, localized price, renewal terms, restore action, and Apple account management path visible. The screen now shows Apple's price, renewal disclosure, Restore Purchases, and Manage Subscription.
- In App Review notes, give the reviewer a working account and explain where to open the subscription screen; state that Apple purchase-sheet confirmation is required and provide steps if the reviewer needs a sandbox account.
- Apple review outcome is not guaranteed by code. The account owner must submit the products and build, complete business agreements, and verify that all paid digital features use the correct payment method.

## Scope limitation: sponsorships

This change covers the rejected **Premium subscription** purchase. Mlivecast sponsorships still create user-priced tiers and use Stripe Connect. Apple explicitly includes advertisements displayed in the same app in its IAP policy examples; the owner must decide whether iOS sponsorship purchases will use a catalog of fixed Apple price points or be disabled on iOS. Do not claim the iOS app is fully policy-cleared while Stripe sponsorship checkout remains available in the iOS build. The Stripe sponsorship flow remains unchanged on web and Android.
