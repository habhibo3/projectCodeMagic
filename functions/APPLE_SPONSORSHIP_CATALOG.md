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

From the repository's `functions` directory, run:

```powershell
node .\scripts\seed_apple_sponsorship_catalog.js
```

The script targets `mlivecast-staging` explicitly, merges these six documents,
and requires Google Application Default Credentials with Firestore write access
to that staging project. It does not deploy functions or write to production.

Before using the products, confirm that the six **Product ID** values in App
Store Connect exactly match the IDs above (case-sensitive). The numeric Apple
IDs are not the Product IDs. Then deploy the pending sponsorship functions to
staging and install a new staging iOS TestFlight build. Test with an Apple
Sandbox tester before submitting anything for review.
