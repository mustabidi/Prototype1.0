const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

// ─── HELPER: Clamp trust score to [0, 10] ───────────────────
async function adjustTrustScore(userId, delta) {
  const userRef = admin.firestore().collection('users').doc(userId);
  return admin.firestore().runTransaction(async (t) => {
    const userDoc = await t.get(userRef);
    if (!userDoc.exists) return;
    const current = userDoc.data().trustScore || 1;
    const raw = current + delta;
    const clamped = Math.max(0, Math.min(10, raw));
    t.update(userRef, { trustScore: clamped });
  });
}

/**
 * Triggered when a user reports a post.
 * - Ignores reporters < 24h old
 * - Increments reportCount on the post
 * - Auto-hides post at >= 5 unique reports
 * - Penalizes author trust (-2, clamped)
 */
exports.onReportCreated = functions.firestore
  .document('reports/{reportId}')
  .onCreate(async (snapshot, context) => {
    const reportData = snapshot.data();
    const postId = reportData.postId;
    const reportedBy = reportData.reportedBy;

    // Check reporter account age (ignore < 24h)
    const reporterDoc = await admin.firestore().collection('users').doc(reportedBy).get();
    if (reporterDoc.exists) {
      const createdAt = reporterDoc.data().createdAt;
      if (createdAt) {
        const ageMs = Date.now() - createdAt.toDate().getTime();
        if (ageMs < 24 * 60 * 60 * 1000) {
          console.log(`Report ignored: User ${reportedBy} is less than 24h old.`);
          return null;
        }
      }
    }

    const postRef = admin.firestore().collection('posts').doc(postId);

    await admin.firestore().runTransaction(async (t) => {
      const postDoc = await t.get(postRef);
      if (!postDoc.exists) return;

      const newReportCount = (postDoc.data().reportCount || 0) + 1;
      const updates = { reportCount: newReportCount };

      // Auto-moderate: >= 5 unique reports -> disable
      if (newReportCount >= 5 && postDoc.data().isActive === true) {
        updates.isActive = false;
        
        // Penalize author trust score (clamped) in transaction
        const authorId = postDoc.data().userId;
        const authorRef = admin.firestore().collection('users').doc(authorId);
        const authorDoc = await t.get(authorRef);
        if (authorDoc.exists) {
          const currentTrust = authorDoc.data().trustScore || 1;
          const clamped = Math.max(0, Math.min(10, currentTrust - 2));
          t.update(authorRef, { trustScore: clamped });
        }
      }

      t.update(postRef, updates);
    });

    return null;
  });

/**
 * Triggered when a vote is created.
 * - Checks voter eligibility (trust >= 1, age > 24h)
 * - Boosts author trust by +0.2 (clamped to 10)
 */
exports.onVoteCreated = functions.firestore
  .document('post_votes/{voteId}')
  .onCreate(async (snapshot, context) => {
    const voteData = snapshot.data();
    const postId = voteData.postId;
    const voterId = voteData.userId;

    // Check voter eligibility
    const voterDoc = await admin.firestore().collection('users').doc(voterId).get();
    if (!voterDoc.exists) return null;
    const voterData = voterDoc.data();

    // Trust gate
    if ((voterData.trustScore || 0) < 1) {
      console.log(`Vote ignored: Voter ${voterId} has trust < 1`);
      return null;
    }

    // Age gate
    if (voterData.createdAt) {
      const ageMs = Date.now() - voterData.createdAt.toDate().getTime();
      if (ageMs < 24 * 60 * 60 * 1000) {
        console.log(`Vote ignored: Voter ${voterId} is less than 24h old.`);
        return null;
      }
    }

    const postDoc = await admin.firestore().collection('posts').doc(postId).get();
    if (!postDoc.exists) return null;

    const authorId = postDoc.data().userId;

    // Boost author trust by +0.2 (clamped)
    await adjustTrustScore(authorId, 0.2);
    return null;
  });

/**
 * Triggered on post write.
 * Updates distributed counters for active posts per city.
 * Handles all 4 cases: create, delete, soft-delete (isActive flip), expiry.
 */
exports.maintainCityStats = functions.firestore
  .document('posts/{postId}')
  .onWrite(async (change, context) => {
    const beforeData = change.before.exists ? change.before.data() : null;
    const afterData = change.after.exists ? change.after.data() : null;

    const wasActive = beforeData ? beforeData.isActive === true : false;
    const isNowActive = afterData ? afterData.isActive === true : false;

    if (wasActive === isNowActive) return null;

    const city = (afterData && afterData.city) || (beforeData && beforeData.city);
    if (!city) return null;

    const sanitizedCity = city.toLowerCase().replace(/[^a-z0-9]/g, '_');
    const statsRef = admin.firestore().collection('stats').doc(sanitizedCity);

    const incrementVal = (isNowActive && !wasActive) ? 1 : -1;

    return statsRef.set({
      activePosts: admin.firestore.FieldValue.increment(incrementVal),
      lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      cityName: city
    }, { merge: true });
  });

/**
 * Scheduled: Runs every hour.
 * Marks expired posts as isActive: false.
 * This triggers maintainCityStats which decrements the counter.
 */
exports.expireOldPosts = functions.pubsub
  .schedule('every 60 minutes')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    const expiredQuery = admin.firestore().collection('posts')
      .where('isActive', '==', true)
      .where('expiresAt', '<=', now)
      .limit(500); // batch limit to avoid timeout

    const snapshot = await expiredQuery.get();
    if (snapshot.empty) {
      console.log('No expired posts found.');
      return null;
    }

    const batch = admin.firestore().batch();
    snapshot.docs.forEach((doc) => {
      batch.update(doc.ref, { isActive: false });
    });

    await batch.commit();
    console.log(`Expired ${snapshot.size} posts.`);
    return null;
  });

/**
 * Triggered on new post creation.
 * If post.type == "help" and urgency is high enough, publishes to Topic Pub/Sub.
 */
exports.notifyNeighborsOfHelp = functions.firestore
  .document('posts/{postId}')
  .onCreate(async (snapshot, context) => {
    const postData = snapshot.data();

    // 1. Only process "help" requests
    if (postData.type !== 'help') return null;

    // 2. Priority Filter: Do not notify for low urgency
    if (postData.urgencyLevel < 2) {
      console.log('Skipping notification: Urgency too low.', postData.urgencyLevel);
      return null;
    }

    const urgency = postData.urgencyLevel === 3 ? 'URGENT ' : '';
    const conditions = [];

    // 3. Extract targeting topics
    if (postData.city) {
      const sanitizedCity = postData.city.toLowerCase().replace(/[^a-z0-9]/g, '_');
      conditions.push(`'city_${sanitizedCity}' in topics`);
    }

    if (postData.location && postData.location.geohash) {
      const hash5 = postData.location.geohash.substring(0, 5);
      conditions.push(`'geo_${hash5}' in topics`);
    }

    if (conditions.length === 0) {
      console.log('Post lacks city and location. Cannot route notification.');
      return null;
    }

    // Combine conditions with OR
    const conditionString = conditions.join(' || ');

    // 4. Construct Payload with collapse_key for deduplication
    const message = {
      notification: {
        title: `${urgency}Neighbor Needs Help!`,
        body: postData.content.substring(0, 100),
      },
      data: {
        postId: context.params.postId,
        type: 'help_request',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        authorId: postData.userId || '',
      },
      android: {
        collapseKey: context.params.postId, // Dedup: same postId collapses
      },
      apns: {
        headers: {
          'apns-collapse-id': context.params.postId, // iOS dedup
        },
      },
      condition: conditionString,
    };

    try {
      const response = await admin.messaging().send(message);
      console.log(`Sent topic notification successfully. Message ID:`, response);
      return null;
    } catch (error) {
      console.error('Error sending topic notification:', error);
      return null;
    }
  });
