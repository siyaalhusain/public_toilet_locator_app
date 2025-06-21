// index.js
import { onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import nodemailer from "nodemailer";
import cors from "cors";

// Initialize Firebase services
initializeApp();
const db = getFirestore();
const corsHandler = cors({ origin: true });

// Email configuration
const gmailEmail = process.env.GMAIL_EMAIL;
const gmailPassword = process.env.GMAIL_PASSWORD;
// Email transporter setup
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: gmailEmail,
    pass: gmailPassword
  },
  pool: true,
  maxConnections: 1,
  rateDelta: 20000,
  rateLimit: 5
});

// Helper Functions
// ================

/**
 * Sends email with HTML formatting
 */
async function sendEmail(to, subject, text) {
  const mailOptions = {
    from: `"Clean Restrooms Admin" <${gmailEmail}>`,
    to,
    subject,
    text,
    html: `<div style="font-family: Arial, sans-serif; line-height: 1.6; max-width: 600px; margin: 0 auto;">
      <h2 style="color: #2E86DE;">Clean Restrooms</h2>
      <div style="background: #f9f9f9; padding: 20px; border-radius: 5px;">
        ${text.replace(/\n/g, '<br>')}
      </div>
      <p style="font-size: 12px; color: #777; margin-top: 20px;">
        © ${new Date().getFullYear()} Clean Restrooms
      </p>
    </div>`
  };

  try {
    const info = await transporter.sendMail(mailOptions);
    logger.log(`Email sent to ${to}`, { messageId: info.messageId });

    // Log successful email
    await db.collection("emailLogs").add({
      to,
      subject,
      status: "sent",
      messageId: info.messageId,
      timestamp: FieldValue.serverTimestamp()
    });

    return true;
  } catch (error) {
    logger.error("Failed to send email", error);

    // Log failed email
    await db.collection("emailLogs").add({
      to,
      subject,
      status: "failed",
      error: error.message,
      timestamp: FieldValue.serverTimestamp()
    });

    throw error;
  }
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

export const sendEmailNotification = onCall(async (request) => {
  if (!request.auth) {
    throw new Error("Unauthenticated");
  }

  const { email, subject, message, type } = request.data;

  try {
    const notificationRef = db.collection("notifications").doc();
    await notificationRef.set({
      userId: request.auth.uid,
      type: type || "generic_notification",
      email,
      subject,
      message,
      createdAt: FieldValue.serverTimestamp(),
      read: false,
      emailDelivered: false
    });

    const emailSent = await sendEmail(email, subject, message);
    await notificationRef.update({
      emailDelivered: emailSent,
      deliveredAt: FieldValue.serverTimestamp()
    });

    return {
      success: true,
      notificationId: notificationRef.id
    };
  } catch (error) {
    logger.error("Failed to send notification", error);
    throw new Error("Failed to send notification");
  }
});

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
      read: false
    });

    await batch.commit();

    const emailSubject = "Payment Approved - Account Activated";
    const emailMessage = `Dear Owner,

Your payment for the ${planName} plan (LKR ${price}) has been approved.

Account Details:
- Plan: ${planName}
- Amount: LKR ${price}
- Duration: ${duration}
- Start Date: ${formatDate(now.toDate())}
- End Date: ${formatDate(endDate)}

You can now log in and access all owner features.

Thank you for choosing Clean Restrooms!

Best regards,
The Clean Restrooms Team`;

    await sendEmail(userEmail, emailSubject, emailMessage);

    return {
      success: true,
      message: "Payment approved and notification sent",
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
      read: false
    });

    await batch.commit();

    const emailSubject = "Payment Rejected - Action Required";
    const emailMessage = `Dear Owner,

We regret to inform you that your payment has been rejected.

Reason for rejection: ${reason}

Please review your payment details and resubmit your application, or contact our support team for assistance.

Best regards,
Clean Restrooms Team`;

    await sendEmail(userEmail, emailSubject, emailMessage);

    return {
      success: true,
      message: "Payment rejected and notification sent",
      notificationId: notificationRef.id
    };
  } catch (error) {
    logger.error("Payment rejection failed", error);
    throw new Error("Failed to reject payment");
  }
});

export const checkExpiredSubscriptions = onSchedule({
  schedule: "0 0 * * *",
  timeZone: "UTC"
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
        read: false
      });

      if (userData.email) {
        const emailSubject = "Your Subscription Has Expired";
        const emailMessage = `Dear ${userData.name || "User"},

Your Clean Restrooms subscription has expired on ${formatDate(subscription.endDate.toDate())}.

To continue using our services, please renew your subscription from your account dashboard.

If you have any questions, please contact our support team.

Best regards,
Clean Restrooms Team`;

        await sendEmail(userData.email, emailSubject, emailMessage);
      }

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
  timeZone: "UTC"
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
          read: false
        });

        if (userData.email) {
          const emailSubject = "Your Subscription Will Expire Soon";
          const emailMessage = `Dear ${userData.name || "User"},

Your Clean Restrooms subscription will expire in 7 days on ${formatDate(endDate)}.

To avoid service interruption, please renew your subscription before the expiration date.

Current Plan: ${subscription.planName || "Unknown Plan"}
Expiration Date: ${formatDate(endDate)}

You can renew your subscription from your account dashboard.

Best regards,
Clean Restrooms Team`;

          await sendEmail(userData.email, emailSubject, emailMessage);
        }

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
  schedule: "every 5 minutes"
}, async () => {
  const snapshot = await db.collection("notifications")
    .where("read", "==", false)
    .get();

  const userCounts = {};

  for (const doc of snapshot.docs) {
    const userId = doc.data().userId;
    userCounts[userId] = (userCounts[userId] || 0) + 1;
  }

  const batch = db.batch();
  for (const [userId, count] of Object.entries(userCounts)) {
    const userRef = db.collection("users").doc(userId);
    batch.update(userRef, { unreadNotifications: count });
  }

  await batch.commit();
  logger.log(`Updated unread counts for ${Object.keys(userCounts).length} users`);
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
      read: false
    });

    await batch.commit();

    if (userData.email) {
      const emailSubject = "Payment Verification Deleted";
      const emailMessage = `Dear ${userData.name || "User"},

Your payment verification has been deleted by an administrator.

If you wish to continue using our services, please submit a new payment through your account dashboard.

For any questions, please contact our support team.

Best regards,
Clean Restrooms Team`;

      await sendEmail(userData.email, emailSubject, emailMessage);
    }

    return { success: true };
  } catch (error) {
    logger.error("Failed to delete verification", error);
    throw new Error("Failed to delete verification");
  }
});
// ... (keep all your existing imports and other functions above)

export const testEmail = onRequest(async (req, res) => {
  corsHandler(req, res, async () => {
    try {
      const { email } = req.query;

      if (!email) {
        return res.status(400).send("Email parameter is required");
      }

      await sendEmail(
        email,
        "Test Email from Clean Restrooms",
        "This is a test email from the Clean Restrooms backend system."
      );

      return res.status(200).send(`Test email sent to ${email}`);
    } catch (error) {
      logger.error("Test email failed", error);
      return res.status(500).send("Error sending test email");
    }
  });
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
    await admin.auth().deleteUser(userId);

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