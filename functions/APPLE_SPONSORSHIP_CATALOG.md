# Staging Apple sponsorship products

The iOS sponsorship flow reads active products from the staging Firestore
collection `apple_sponsorship_products`. The document ID is the App Store
**Product ID** string, not the numeric Apple ID shown by App Store Connect.

| Product | Product ID / Firestore document | Apple ID | USD price | Type | Term |
|---|---|---:|---:|---|---|
| Diamond Contest Sponsor | `Diamond_Contest_Sponsor` | 6822701123 | $1,000 | CONTEST | Until contest ends |
| Gold Contest Sponsor | `Gold_Contest_Sponsor` | 6822701905 | $500 | CONTEST | Until contest ends |
| Silver Contest Sponsor | `Silver_Contest_Sponsor` | 6822702260 | $200 | CONTEST | Until contest ends |
| Diamond Station Sponsor | `Diamond_Station_Sponsor` | 6822703263 | $1,000 | STATION | 1 month |
| Gold Station Sponsor | `Gold_Station_Sponsor` | 6822703987 | $500 | STATION | 1 month |
| Silver Station Sponsor | `Silver_Station_Sponsor` | 6822704289 | $200 | STATION | 1 month |

Amounts in Firestore are integer cents (`100000`, `50000`, `20000`). Each
document has `active: true`, `priceCents`, `ownerTypes`, and the station
documents have `durationMonths: 1`. The numeric Apple IDs are stored as
`appStoreConnectAppleId` for reference; StoreKit transactions are matched using
the Product ID strings.

## Seed the staging catalog

The easiest option is to create the six documents in the Firebase Console:

1. Open Firebase Console and select **mlivecast-staging**.
2. Open **Firestore Database → Data**.
3. Create a collection named `apple_sponsorship_products`.
4. Create each document using the **Product ID / Firestore document** value
   from the table above as its document ID.
5. Add `appStoreConnectAppleId` as a **number**, `priceCents` as a **number**,
   `ownerTypes` as an **array of strings**, and `active` as a **boolean** set
   to `true`. For the three station products, also add `durationMonths` as a
   **number** set to `1`. Contest products do not need `durationMonths`.

For example, `Diamond_Contest_Sponsor` has `appStoreConnectAppleId: 6822701123`,
`priceCents: 100000`, `ownerTypes: ["CONTEST"]`, and `active: true`.

If you prefer the seed script, run it from the repository's `functions`
directory:

```powershell
node .\scripts\seed_apple_sponsorship_catalog.js
```

The script targets `mlivecast-staging` explicitly, merges these six documents,
and requires Google Application Default Credentials with Firestore write access
to that staging project. It does not deploy functions or write to production.

Before using the products, confirm that the six **Product ID** values in App
Store Connect exactly match the IDs above (case-sensitive). The numeric Apple
IDs are not the Product IDs. Deploy the updated backend to staging from the
repository root:

```powershell
firebase deploy --only functions:sponsorshipApi,functions:verifyAppleSponsorship --project mlivecast-staging
```

Then install a new staging iOS TestFlight build and test with an Apple Sandbox
tester before submitting anything for review. Do not deploy production until
staging passes.
