// index.js
import { onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import cors from "cors";

// Initialize Firebase services
initializeApp();
const db = getFirestore();
const auth = getAuth();
const corsHandler = cors({ origin: true });

// Helper Functions
// ================

/**
 * Creates an admin notification
 */
// In index.js, update the createAdminNotification function
async function createAdminNotification(message, type, relatedUserId = null, userEmail = null) {
  const notificationRef = db.collection("notifications").doc();
  await notificationRef.set({
    type,
    message,
    createdAt: FieldValue.serverTimestamp(),
    isRead: false,
    isAdminNotification: true,  // Flag for admin notifications
    relatedUserId,
    userEmail
  });
  logger.log(`Admin notification created: ${type}`);
}

// Add a new function for owner notifications
async function createOwnerNotification(userId, message, type) {
  const notificationRef = db.collection("notifications").doc();
  await notificationRef.set({
    userId,
    type,
    message,
    createdAt: FieldValue.serverTimestamp(),
    isRead: false,
    isAdminNotification: false  // Flag for owner notifications
  });
  logger.log(`Owner notification created for ${userId}: ${type}`);
}
/**
 * Calculates subscription end date based on duration
 */
function calculateEndDate(startDate, duration) {
  const date = new Date(startDate);
  if (duration.includes("month")) {
    const months = parseInt(duration.split(" ")[0]) || 1;
    date.setMonth(date.getMonth() + months);
  } else if (duration.includes("year")) {
    const years = parseInt(duration.split(" ")[0]) || 1;
    date.setFullYear(date.getFullYear() + years);
  }
  return date;
}

/**
 * Formats date for display
 */
function formatDate(date) {
  return date.toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric"
  });
}

// Core Functions
// ==============

export const approvePayment = onCall(async (request) => {
  if (!request.auth) {
    throw new Error("Unauthenticated");
  }

  const { userId, planName, price, duration, userEmail } = request.data;

  try {
    const now = Timestamp.now();
    const endDate = calculateEndDate(now.toDate(), duration);

    const batch = db.batch();
    const userRef = db.collection("users").doc(userId);

    batch.update(userRef, {
      "subscription.paymentStatus": "approved",
      "subscription.startDate": now,
      "subscription.endDate": Timestamp.fromDate(endDate),
      "isAccountActive": true
    });

    const historyRef = db.collection("paymentHistory").doc();
    batch.set(historyRef, {
      userId,
      amount: price,
      planName,
      status: "approved",
      processedAt: FieldValue.serverTimestamp(),
      processedBy: request.auth.uid,
      startDate: now,
      endDate: Timestamp.fromDate(endDate)
    });

    const notificationRef = db.collection("notifications").doc();
    batch.set(notificationRef, {
      userId,
      type: "payment_approved",
      message: `Your ${planName} plan payment was approved. Subscription active until ${formatDate(endDate)}.`,
      createdAt: FieldValue.serverTimestamp(),
      read: false,
      isAdminNotification: false
    });

    await batch.commit();

    // Add admin notification
    await createAdminNotification(
      `Payment approved for ${planName} (${duration}) by ${request.auth.token.email}`,
      "payment_approved_admin",
      userId,
      userEmail
    );

    return {
      success: true,
      message: "Payment approved",
      notificationId: notificationRef.id
    };
  } catch (error) {
    logger.error("Payment approval failed", error);
    throw new Error("Failed to approve payment");
  }
});

export const rejectPayment = onCall(async (request) => {
  if (!request.auth) {
    throw new Error("Unauthenticated");
  }

  const { userId, reason, userEmail } = request.data;

  try {
    const batch = db.batch();
    const userRef = db.collection("users").doc(userId);

    batch.update(userRef, {
      "subscription.paymentStatus": "rejected",
      "subscription.rejectionReason": reason,
      "isAccountActive": false
    });

    const historyRef = db.collection("paymentHistory").doc();
    batch.set(historyRef, {
      userId,
      status: "rejected",
      reason,
      processedAt: FieldValue.serverTimestamp(),
      processedBy: request.auth.uid
    });

    const notificationRef = db.collection("notifications").doc();
    batch.set(notificationRef, {
      userId,
      type: "payment_rejected",
      message: `Your payment was rejected. Reason: ${reason}`,
      createdAt: FieldValue.serverTimestamp(),
      read: false,
      isAdminNotification: false
    });

    await batch.commit();

    // Add admin notification
    await createAdminNotification(
      `Payment rejected for ${userEmail}. Reason: ${reason}`,
      "payment_rejected_admin",
      userId,
      userEmail
    );

    return {
      success: true,
      message: "Payment rejected",
      notificationId: notificationRef.id
    };
  } catch (error) {
    logger.error("Payment rejection failed", error);
    throw new Error("Failed to reject payment");
  }
});

export const onRenewalRequest = onDocumentUpdated({
  document: "users/{userId}",
  region: "us-central1"
}, async (event) => {
  const userData = event.data?.after.data();
  const previousData = event.data?.before.data();

  // Check if this is a renewal request (status changed to renew_pending)
  if (userData?.subscription?.paymentStatus === "renew_pending" &&
      userData?.subscription?.isRenewal === true &&
      previousData?.subscription?.paymentStatus !== "renew_pending") {

    try {
      await createAdminNotification(
        `New renewal request from ${userData.email || 'an owner'}`,
        "renewal_request",
        event.params.userId,
        userData.email
      );

      logger.log(`Created admin notification for renewal from ${userData.email}`);
    } catch (error) {
      logger.error("Failed to create renewal notification", error);
    }
  }
});

export const checkExpiredSubscriptions = onSchedule({
  schedule: "0 0 * * *",
  timeZone: "UTC",
  region: "us-central1"
}, async () => {
  const now = Timestamp.now();
  logger.log(`Running expired subscription check at ${now.toDate()}`);

  const snapshot = await db.collection("users")
    .where("role", "==", "Owner")
    .where("isAccountActive", "==", true)
    .get();

  const batch = db.batch();
  let expiredCount = 0;

  for (const doc of snapshot.docs) {
    const userData = doc.data();
    const subscription = userData.subscription;

    if (subscription?.endDate?.toDate() < now.toDate()) {
      batch.update(doc.ref, {
        "isAccountActive": false,
        "subscription.status": "expired"
      });

      const historyRef = db.collection("paymentHistory").doc();
      batch.set(historyRef, {
        userId: doc.id,
        email: userData.email,
        status: "expired",
        processedAt: FieldValue.serverTimestamp(),
        message: "Subscription expired automatically",
        previousPlan: subscription.planName,
        previousEndDate: subscription.endDate
      });

      const notificationRef = db.collection("notifications").doc();
      batch.set(notificationRef, {
        userId: doc.id,
        type: "subscription_expired",
        message: "Your subscription has expired. Please renew to continue using the service.",
        createdAt: FieldValue.serverTimestamp(),
        read: false,
        isAdminNotification: false
      });

      // Add admin notification
      await createAdminNotification(
        `Subscription expired for ${userData.email} (${subscription.planName})`,
        "subscription_expired_admin",
        doc.id,
        userData.email
      );

      expiredCount++;
    }
  }

  if (expiredCount > 0) {
    await batch.commit();
    logger.log(`Updated ${expiredCount} expired subscriptions`);
  } else {
    logger.log("No expired subscriptions found");
  }
});

export const sendSubscriptionExpirationNotices = onSchedule({
  schedule: "0 9 * * *",
  timeZone: "UTC",
  region: "us-central1"
}, async () => {
  const now = Timestamp.now();
  const sevenDaysFromNow = new Date(now.toDate());
  sevenDaysFromNow.setDate(sevenDaysFromNow.getDate() + 7);

  const snapshot = await db.collection("users")
    .where("role", "==", "Owner")
    .where("isAccountActive", "==", true)
    .get();

  let notificationsSent = 0;
  const batch = db.batch();

  for (const doc of snapshot.docs) {
    const userData = doc.data();
    const subscription = userData.subscription;

    if (subscription?.endDate) {
      const endDate = subscription.endDate.toDate();
      const sevenDayTarget = sevenDaysFromNow.toDateString();

      if (endDate.toDateString() === sevenDayTarget) {
        const notifRef = db.collection("notifications").doc();
        batch.set(notifRef, {
          userId: doc.id,
          type: "subscription_expiring_soon",
          message: `Your subscription will expire in 7 days on ${formatDate(endDate)}.`,
          createdAt: FieldValue.serverTimestamp(),
          read: false,
          isAdminNotification: false
        });

        notificationsSent++;
      }
    }
  }

  if (notificationsSent > 0) {
    await batch.commit();
    logger.log(`Sent ${notificationsSent} expiration notices`);
  }
});

export const getPendingPaymentsCount = onCall(async (request) => {
  if (!request.auth) {
    throw new Error("Unauthenticated");
  }

  try {
    const snapshot = await db.collection("users")
      .where("role", "==", "Owner")
      .where("subscription.paymentStatus", "==", "pending")
      .get();

    return { count: snapshot.size };
  } catch (error) {
    logger.error("Failed to count pending payments", error);
    throw new Error("Failed to count pending payments");
  }
});

export const searchPayments = onCall(async (request) => {
  if (!request.auth) {
    throw new Error("Unauthenticated");
  }

  const { query, status } = request.data;

  try {
    let usersRef = db.collection("users").where("role", "==", "Owner");

    if (status && status !== "All") {
      usersRef = usersRef.where("subscription.paymentStatus", "==", status.toLowerCase());
    }

    const snapshot = await usersRef.get();
    const results = [];

    if (query) {
      const lowerQuery = query.toLowerCase();

      for (const doc of snapshot.docs) {
        const userData = doc.data();
        const subscription = userData.subscription;

        if (subscription) {
          const name = (userData.name || "").toLowerCase();
          const email = (userData.email || "").toLowerCase();
          const planName = (subscription.planName || "").toLowerCase();

          if (name.includes(lowerQuery) || email.includes(lowerQuery) || planName.includes(lowerQuery)) {
            results.push({
              userId: doc.id,
              name: userData.name,
              email: userData.email,
              planName: subscription.planName,
              paymentStatus: subscription.paymentStatus,
              paymentProofUrl: subscription.paymentProofUrl,
              createdAt: userData.createdAt
            });
          }
        }
      }
    } else {
      for (const doc of snapshot.docs) {
        const userData = doc.data();
        if (userData.subscription) {
          results.push({
            userId: doc.id,
            name: userData.name,
            email: userData.email,
            planName: userData.subscription.planName,
            paymentStatus: userData.subscription.paymentStatus,
            paymentProofUrl: userData.subscription.paymentProofUrl,
            createdAt: userData.createdAt
          });
        }
      }
    }

    results.sort((a, b) => b.createdAt - a.createdAt);
    return { results };
  } catch (error) {
    logger.error("Failed to search payments", error);
    throw new Error("Failed to search payments");
  }
});

export const getSubscriptionAnalytics = onCall(async (request) => {
  if (!request.auth) {
    throw new Error("Unauthenticated");
  }

  try {
    const snapshot = await db.collection("users")
      .where("role", "==", "Owner")
      .get();

    const analytics = {
      totalOwners: snapshot.size,
      activeSubscriptions: 0,
      pendingPayments: 0,
      rejectedPayments: 0,
      expiredSubscriptions: 0,
      totalRevenue: 0,
      planDistribution: {
        basic: 0,
        standard: 0,
        premium: 0,
        other: 0
      }
    };

    for (const doc of snapshot.docs) {
      const userData = doc.data();
      const subscription = userData.subscription;

      if (subscription) {
        if (subscription.paymentStatus === "approved" && userData.isAccountActive) {
          analytics.activeSubscriptions++;
          analytics.totalRevenue += subscription.price || 0;

          switch ((subscription.planId || "").toLowerCase()) {
            case "basic": analytics.planDistribution.basic++; break;
            case "standard": analytics.planDistribution.standard++; break;
            case "premium": analytics.planDistribution.premium++; break;
            default: analytics.planDistribution.other++;
          }
        } else if (subscription.paymentStatus === "pending") {
          analytics.pendingPayments++;
        } else if (subscription.paymentStatus === "rejected") {
          analytics.rejectedPayments++;
        }

        if (subscription.status === "expired" ||
            (subscription.endDate && subscription.endDate.toDate() < new Date())) {
          analytics.expiredSubscriptions++;
        }
      }
    }

    return analytics;
  } catch (error) {
    logger.error("Failed to get analytics", error);
    throw new Error("Failed to get analytics");
  }
});

export const updateUnreadNotificationCount = onSchedule({
  schedule: "every 5 minutes",
  region: "us-central1"
}, async () => {
  const snapshot = await db.collection("notifications")
    .where("read", "==", false)
    .get();

  const userCounts = {};

  for (const doc of snapshot.docs) {
    const userId = doc.data().userId;
    if (userId) {
      userCounts[userId] = (userCounts[userId] || 0) + 1;
    }
  }

  const batch = db.batch();
  for (const [userId, count] of Object.entries(userCounts)) {
    const userRef = db.collection("users").doc(userId);
    batch.update(userRef, { unreadNotifications: count });
  }

  if (Object.keys(userCounts).length > 0) {
    await batch.commit();
    logger.log(`Updated unread counts for ${Object.keys(userCounts).length} users`);
  }
});

export const deletePaymentVerification = onCall(async (request) => {
  if (!request.auth) {
    throw new Error("Unauthenticated");
  }

  const { userId } = request.data;

  try {
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();

    const batch = db.batch();
    const userRef = db.collection("users").doc(userId);

    batch.update(userRef, {
      "subscription": FieldValue.delete(),
      "isAccountActive": false
    });

    const historyRef = db.collection("paymentHistory").doc();
    batch.set(historyRef, {
      userId,
      action: "verification_deleted",
      processedAt: FieldValue.serverTimestamp(),
      processedBy: request.auth.uid,
      notes: "Payment verification deleted by admin"
    });

    const notificationRef = db.collection("notifications").doc();
    batch.set(notificationRef, {
      userId,
      type: "payment_verification_deleted",
      message: "Your payment verification has been deleted by admin.",
      createdAt: FieldValue.serverTimestamp(),
      read: false,
      isAdminNotification: false
    });

    await batch.commit();

    return { success: true };
  } catch (error) {
    logger.error("Failed to delete verification", error);
    throw new Error("Failed to delete verification");
  }
});

export const deleteUserAccount = onCall(async (request) => {
  // Verify admin privileges
  if (!request.auth) {
    throw new Error("Unauthenticated");
  }

  // Check admin document
  const adminDoc = await db.collection("admins").doc(request.auth.uid).get();
  if (!adminDoc.exists) {
    throw new Error("Unauthorized - Admin access required");
  }

  const { userId } = request.data;
  if (!userId) {
    throw new Error("User ID is required");
  }

  try {
    // Delete from Firebase Authentication
    await auth.deleteUser(userId);

    // Delete from Firestore
    const batch = db.batch();
    const userRef = db.collection("users").doc(userId);

    // Get all related toilets
    const toiletsQuery = await db.collection("toilets")
      .where("ownerId", "==", userId)
      .get();

    // Get all related maintainers
    const maintainersQuery = await db.collection("users")
      .where("role", "==", "Maintainer")
      .where("assignedOwnerId", "==", userId)
      .get();

    // Delete user
    batch.delete(userRef);

    // Delete related toilets
    for (const toiletDoc of toiletsQuery.docs) {
      batch.delete(toiletDoc.ref);
    }

    // Delete related maintainers
    for (const maintainerDoc of maintainersQuery.docs) {
      batch.delete(maintainerDoc.ref);
    }

    // Add to deletion log
    const logRef = db.collection("deletionLogs").doc();
    batch.set(logRef, {
      userId,
      deletedAt: FieldValue.serverTimestamp(),
      deletedBy: request.auth.uid,
      relatedToilets: toiletsQuery.docs.length,
      relatedMaintainers: maintainersQuery.docs.length,
    });

    await batch.commit();

    return { success: true };
  } catch (error) {
    logger.error("Failed to delete user account", error);
    throw new Error("Failed to delete user account");
  }
});