/* eslint-disable require-jsdoc, max-len */

const admin = require("firebase-admin");

const PROJECT_ID = "mlivecast-staging";

const products = [
  {
    productId: "Diamond_Contest_Sponsor",
    appStoreConnectAppleId: "6822701123",
    priceCents: 100000,
    ownerTypes: ["CONTEST"],
  },
  {
    productId: "Gold_Contest_Sponsor",
    appStoreConnectAppleId: "6822701905",
    priceCents: 50000,
    ownerTypes: ["CONTEST"],
  },
  {
    productId: "Silver_Contest_Sponsor",
    appStoreConnectAppleId: "6822702260",
    priceCents: 20000,
    ownerTypes: ["CONTEST"],
  },
  {
    productId: "Diamond_Station_Sponsor",
    appStoreConnectAppleId: "6822703263",
    priceCents: 100000,
    durationMonths: 1,
    ownerTypes: ["STATION"],
  },
  {
    productId: "Gold_Station_Sponsor",
    appStoreConnectAppleId: "6822703987",
    priceCents: 50000,
    durationMonths: 1,
    ownerTypes: ["STATION"],
  },
  {
    productId: "Silver_Station_Sponsor",
    appStoreConnectAppleId: "6822704289",
    priceCents: 20000,
    durationMonths: 1,
    ownerTypes: ["STATION"],
  },
];

async function seedCatalog() {
  admin.initializeApp({projectId: PROJECT_ID});
  const db = admin.firestore();
  const batch = db.batch();
  for (const product of products) {
    const {productId, ...fields} = product;
    batch.set(db.collection("apple_sponsorship_products").doc(productId), {
      ...fields,
      active: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  await batch.commit();
  console.log(`Seeded ${products.length} sponsorship products in ${PROJECT_ID}.`);
}

seedCatalog().catch((error) => {
  console.error("Could not seed the staging Apple sponsorship catalog:", error);
  process.exitCode = 1;
});
