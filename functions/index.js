const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const auth = admin.auth();

/**
 * Helper function to completely purge all user data from Firestore collections.
 * @param {string} userId - The user ID to delete.
 */
async function purgeUserFirestoreData(userId) {
  if (!userId) return;

  // 1. Delete user's posts
  const postsSnap = await db
      .collection("posts")
      .where("userId", "==", userId)
      .get();
  const postDeletions = postsSnap.docs.map((d) => d.reference.delete());
  await Promise.all(postDeletions);

  // 2. Delete user's stations & any recorded_lives subcollections
  const stationsSnap = await db
      .collection("stations")
      .where("creatorId", "==", userId)
      .get();
  for (const stDoc of stationsSnap.docs) {
    const livesSnap = await stDoc.reference.collection("recorded_lives").get();
    const liveDeletions = livesSnap.docs.map((l) => l.reference.delete());
    await Promise.all(liveDeletions);
    await stDoc.reference.delete();
  }

  // 3. Delete user's contests & entries
  const userContestsSnap = await db
      .collection("contests")
      .where("creatorId", "==", userId)
      .get();
  for (const cDoc of userContestsSnap.docs) {
    const entriesSnap = await cDoc.reference.collection("entries").get();
    const entryDeletions = entriesSnap.docs.map((e) => e.reference.delete());
    await Promise.all(entryDeletions);
    await cDoc.reference.delete();
  }

  // 4. Delete entries submitted by user in other contests
  const allContestsSnap = await db.collection("contests").get();
  for (const cDoc of allContestsSnap.docs) {
    const userEntriesSnap = await cDoc.reference
        .collection("entries")
        .where("userId", "==", userId)
        .get();
    const entryDeletions = userEntriesSnap.docs
        .map((e) => e.reference.delete());
    await Promise.all(entryDeletions);
  }

  // 5. Delete user document if still present
  const userDocRef = db.collection("users").doc(userId);
  const userDoc = await userDocRef.get();
  if (userDoc.exists) {
    await userDocRef.delete();
  }
}

/**
 * Firestore Trigger: Fires whenever a user document is deleted.
 * Automatically deletes the user from Firebase Auth so email is released.
 */
exports.onUserDeleted = functions
    .region("us-central1")
    .firestore.document("users/{userId}")
    .onDelete(async (snap, context) => {
      const userId = context.params.userId;
      console.log(`[onUserDeleted] Triggered for userId: ${userId}`);

      // 1. Delete from Firebase Authentication
      try {
        await auth.deleteUser(userId);
        console.log(`[onUserDeleted] Deleted Auth for UID: ${userId}`);
      } catch (err) {
        if (err.code === "auth/user-not-found") {
          console.log(`[onUserDeleted] User ${userId} not in Auth.`);
        } else {
          console.error(`[onUserDeleted] Error deleting Auth:`, err);
        }
      }

      // 2. Cascade delete remaining Firestore assets
      try {
        await purgeUserFirestoreData(userId);
        console.log(`[onUserDeleted] Cleanup done for userId: ${userId}`);
      } catch (err) {
        console.error(`[onUserDeleted] Error cleaning Firestore:`, err);
      }
    });

/**
 * Firestore Trigger: Handles requests to clean up orphaned Auth accounts.
 * Triggered by creating a doc in user_cleanup_requests/{requestId}.
 */
exports.onCleanupRequest = functions
    .region("us-central1")
    .firestore.document("user_cleanup_requests/{requestId}")
    .onCreate(async (snap, context) => {
      const data = snap.data() || {};
      const {email, userId} = data;

      try {
        let authUser = null;
        if (userId) {
          try {
            authUser = await auth.getUser(userId);
          } catch (e) {
            // Not in Auth
          }
        } else if (email) {
          try {
            authUser = await auth.getUserByEmail(email.trim());
          } catch (e) {
            // Not in Auth
          }
        }

        if (authUser) {
          // Check if user has an active doc in Firestore
          const userDoc = await db.collection("users").doc(authUser.uid).get();
          if (!userDoc.exists) {
            await auth.deleteUser(authUser.uid);
            console.log(`[onCleanupRequest] Deleted orphan: ${authUser.uid}`);
            await snap.ref.set(
                {status: "completed", deleted: true},
                {merge: true},
            );
            return;
          }
        }
        await snap.ref.set({status: "skipped", deleted: false}, {merge: true});
      } catch (error) {
        console.error(`[onCleanupRequest] Error:`, error);
        await snap.ref.set(
            {status: "error", error: error.message},
            {merge: true},
        );
      }
    });
