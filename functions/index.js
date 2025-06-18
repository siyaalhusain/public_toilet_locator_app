const functions = require('firebase-functions');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const cors = require('cors')({origin: true});
admin.initializeApp();
verifyEmailConfig().catch(console.error);

// Configure email transport
// Replace your current transporter configuration in index.js
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: functions.config().gmail.email,
    pass: functions.config().gmail.password
  },
  pool: true,
  maxConnections: 1,
  rateDelta: 20000, // 20 seconds between emails
  rateLimit: 5 // max 5 emails per rateDelta
});

// Add this helper function to verify your email config
async function verifyEmailConfig() {
  return new Promise((resolve, reject) => {
    transporter.verify((error, success) => {
      if (error) {
        console.error('Email transport verification failed:', error);
        reject(error);
      } else {
        console.log('Email transport is ready');
        resolve(success);
      }
    });
  });
}

// Call this at startup


// Helper function to send emails
async function sendEmail(to, subject, text) {
  const mailOptions = {
    from: `"Clean Restrooms Admin" <${functions.config().gmail.email}>`,
    to: to,
    subject: subject,
    text: text,
    html: `<p>${text.replace(/\n/g, '<br>')}</p>`
  };

  try {
    await transporter.sendMail(mailOptions);
    console.log(`Email sent to ${to}`);
    return true;
  } catch (error) {
    console.error('Error sending email:', error);
    throw error;
  }
}
// Add this to your index.js
exports.sendEmailNotification = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { email, subject, message, type } = data;

  try {
    // First create a notification record
    const notificationRef = admin.firestore().collection('notifications').doc();
    await notificationRef.set({
      userId: context.auth.uid,
      type: type || 'generic_notification',
      email: email,
      subject: subject,
      message: message,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false,
      emailDelivered: false // Initially false until confirmed
    });

    // Try to send the email
    const emailSent = await sendEmail(email, subject, message);

    // Update notification with delivery status
    await notificationRef.update({
      emailDelivered: emailSent,
      deliveredAt: admin.firestore.FieldValue.serverTimestamp()
    });

    return { success: true, notificationId: notificationRef.id };
  } catch (error) {
    console.error('Error sending email notification:', error);
    throw new functions.https.HttpsError('internal', 'Failed to send notification');
  }
});
// Cloud Function to approve payment and send approval email
exports.approvePayment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { userId, planName, price, duration, userEmail } = data;

  try {
    const now = admin.firestore.Timestamp.now();
    let endDate = new Date(now.toDate());

    if (duration.includes('month')) {
      const months = parseInt(duration.split(' ')[0]) || 1;
      endDate.setMonth(endDate.getMonth() + months);
    } else if (duration.includes('year')) {
      const years = parseInt(duration.split(' ')[0]) || 1;
      endDate.setFullYear(endDate.getFullYear() + years);
    }

    const batch = admin.firestore().batch();
    const userRef = admin.firestore().collection('users').doc(userId);

    batch.update(userRef, {
      'subscription.paymentStatus': 'approved',
      'subscription.startDate': now,
      'subscription.endDate': admin.firestore.Timestamp.fromDate(endDate),
      'isAccountActive': true,
    });

    const historyRef = admin.firestore().collection('paymentHistory').doc();
    batch.set(historyRef, {
      userId: userId,
      amount: price,
      planName: planName,
      status: 'approved',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      processedBy: context.auth.uid,
      startDate: now,
      endDate: admin.firestore.Timestamp.fromDate(endDate),
    });

    const notificationRef = admin.firestore().collection('notifications').doc();
    batch.set(notificationRef, {
      userId: userId,
      type: 'payment_approved',
      message: `Your payment for ${planName} plan has been approved. Your subscription is now active.`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });

    await batch.commit();

    // Send approval email
    const emailSubject = 'Your Owner Account Has Been Approved';
    const emailMessage = `Dear Owner,

We are pleased to inform you that your account has been approved by our admin team.

Account Details:
- Plan: ${planName}
- Price: LKR ${price}
- Duration: ${duration}

You can now log in to your account and start managing your restrooms.

Thank you for choosing our service!

Best regards,
Clean Restrooms Team`;

    await sendEmail(userEmail, emailSubject, emailMessage);

    return { success: true, message: 'Payment approved and email sent' };
  } catch (error) {
    console.error('Error approving payment:', error);
    throw new functions.https.HttpsError('internal', 'Failed to approve payment');
  }
});

// Cloud Function to reject payment and send rejection email
exports.rejectPayment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { userId, reason, userEmail } = data;

  try {
    const batch = admin.firestore().batch();
    const userRef = admin.firestore().collection('users').doc(userId);

    batch.update(userRef, {
      'subscription.paymentStatus': 'rejected',
      'subscription.rejectionReason': reason,
      'isAccountActive': false,
    });

    const historyRef = admin.firestore().collection('paymentHistory').doc();
    batch.set(historyRef, {
      userId: userId,
      status: 'rejected',
      reason: reason,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      processedBy: context.auth.uid,
    });

    const notificationRef = admin.firestore().collection('notifications').doc();
    batch.set(notificationRef, {
      userId: userId,
      type: 'payment_rejected',
      message: `Your payment was rejected. Reason: ${reason}`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });

    await batch.commit();

    // Send rejection email
    const emailSubject = 'Your Owner Account Requires Attention';
    const emailMessage = `Dear Owner,

We regret to inform you that your account registration has been rejected.

Reason for rejection: ${reason}

Please review your payment details and resubmit your application, or contact our support team for assistance.

Best regards,
Clean Restrooms Team`;

    await sendEmail(userEmail, emailSubject, emailMessage);

    return { success: true, message: 'Payment rejected and email sent' };
  } catch (error) {
    console.error('Error rejecting payment:', error);
    throw new functions.https.HttpsError('internal', 'Failed to reject payment');
  }
});

// Existing function to check for expired subscriptions
exports.checkExpiredSubscriptions = functions.pubsub
  .schedule('0 0 * * *') // Run daily at midnight
  .timeZone('UTC')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    console.log(`Running expired subscription check at ${now.toDate()}`);

    const snapshot = await admin.firestore()
      .collection('users')
      .where('role', '==', 'Owner')
      .where('isAccountActive', '==', true)
      .get();

    const batch = admin.firestore().batch();
    let expiredCount = 0;

    snapshot.forEach(doc => {
      const userData = doc.data();

      if (userData.subscription && userData.subscription.endDate) {
        if (userData.subscription.endDate.toDate() < now.toDate()) {
          batch.update(doc.ref, {
            'isAccountActive': false,
            'subscription.status': 'expired'
          });

          const historyRef = admin.firestore().collection('paymentHistory').doc();
          batch.set(historyRef, {
            userId: doc.id,
            email: userData.email,
            status: 'expired',
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
            message: 'Subscription expired automatically',
            previousPlan: userData.subscription.planName,
            previousEndDate: userData.subscription.endDate
          });

          const notificationRef = admin.firestore().collection('notifications').doc();
          batch.set(notificationRef, {
            userId: doc.id,
            type: 'subscription_expired',
            message: 'Your subscription has expired. Please renew to continue using the service.',
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false
          });

          expiredCount++;
        }
      }
    });

    if (expiredCount > 0) {
      await batch.commit();
      console.log(`Updated ${expiredCount} expired subscriptions`);
    } else {
      console.log('No expired subscriptions found');
    }

    return null;
  });

// Existing function to send subscription expiration notices
exports.sendSubscriptionExpirationNotices = functions.pubsub
  .schedule('0 9 * * *') // Run daily at 9 AM
  .timeZone('UTC')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    const sevenDaysFromNow = new Date(now.toDate());
    sevenDaysFromNow.setDate(sevenDaysFromNow.getDate() + 7);

    const snapshot = await admin.firestore()
      .collection('users')
      .where('role', '==', 'Owner')
      .where('isAccountActive', '==', true)
      .get();

    let notificationsSent = 0;
    const batch = admin.firestore().batch();

    for (const doc of snapshot.docs) {
      const userData = doc.data();

      if (userData.subscription && userData.subscription.endDate) {
        const endDate = userData.subscription.endDate.toDate();
        const sevenDayTarget = sevenDaysFromNow.toDateString();

        if (endDate.toDateString() === sevenDayTarget) {
          const notifRef = admin.firestore().collection('notifications').doc();
          batch.set(notifRef, {
            userId: doc.id,
            type: 'subscription_expiring_soon',
            message: `Your subscription will expire in 7 days on ${endDate.toLocaleDateString()}.`,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false
          });

          if (userData.email) {
            const emailSubject = 'Your Subscription Will Expire Soon';
            const emailMessage = `Dear ${userData.name || 'User'},

Your subscription will expire in 7 days on ${endDate.toLocaleDateString()}.

To avoid service interruption, please renew your subscription before the expiration date.

Current Plan: ${userData.subscription.planName || 'Unknown Plan'}
Expiration Date: ${endDate.toLocaleDateString()}

Thank you for using our service!

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
      console.log(`Sent ${notificationsSent} expiration notices`);
    }

    return null;
  });

// Existing function to count pending payments
exports.getPendingPaymentsCount = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  try {
    const snapshot = await admin.firestore()
      .collection('users')
      .where('role', '==', 'Owner')
      .where('subscription.paymentStatus', '==', 'pending')
      .get();

    return { count: snapshot.size };
  } catch (error) {
    console.error('Error counting pending payments:', error);
    throw new functions.https.HttpsError('internal', 'Failed to count pending payments');
  }
});

// Existing function to search payments
exports.searchPayments = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { query, status } = data;

  try {
    let usersRef = admin.firestore().collection('users').where('role', '==', 'Owner');

    if (status && status !== 'All') {
      usersRef = usersRef.where('subscription.paymentStatus', '==', status.toLowerCase());
    }

    const snapshot = await usersRef.get();
    const results = [];

    if (query) {
      const lowerQuery = query.toLowerCase();

      for (const doc of snapshot.docs) {
        const userData = doc.data();

        if (userData.subscription) {
          const name = (userData.name || '').toLowerCase();
          const email = (userData.email || '').toLowerCase();
          const planName = (userData.subscription.planName || '').toLowerCase();

          if (name.includes(lowerQuery) || email.includes(lowerQuery) || planName.includes(lowerQuery)) {
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
    console.error('Error searching payments:', error);
    throw new functions.https.HttpsError('internal', 'Failed to search payments');
  }
});

// Existing function to get subscription analytics
exports.getSubscriptionAnalytics = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  try {
    const snapshot = await admin.firestore()
      .collection('users')
      .where('role', '==', 'Owner')
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

    snapshot.forEach(doc => {
      const userData = doc.data();

      if (userData.subscription) {
        const subscription = userData.subscription;

        if (subscription.paymentStatus === 'approved' && userData.isAccountActive) {
          analytics.activeSubscriptions++;
          analytics.totalRevenue += subscription.price || 0;

          switch ((subscription.planId || '').toLowerCase()) {
            case 'basic': analytics.planDistribution.basic++; break;
            case 'standard': analytics.planDistribution.standard++; break;
            case 'premium': analytics.planDistribution.premium++; break;
            default: analytics.planDistribution.other++;
          }
        } else if (subscription.paymentStatus === 'pending') {
          analytics.pendingPayments++;
        } else if (subscription.paymentStatus === 'rejected') {
          analytics.rejectedPayments++;
        }

        if (subscription.status === 'expired' ||
            (subscription.endDate && subscription.endDate.toDate() < new Date())) {
          analytics.expiredSubscriptions++;
        }
      }
    });

    return analytics;
  } catch (error) {
    console.error('Error getting analytics:', error);
    throw new functions.https.HttpsError('internal', 'Failed to get analytics');
  }
});

// Existing function to handle notification updates
exports.updateUnreadNotificationCount = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snapshot, context) => {
    const notificationData = snapshot.data();
    const userId = notificationData.userId;

    if (!userId) return null;

    try {
      const query = await admin.firestore()
        .collection('notifications')
        .where('userId', '==', userId)
        .where('read', '==', false)
        .get();

      const unreadCount = query.size;
      await admin.firestore().collection('users').doc(userId).update({
        'unreadNotifications': unreadCount
      });

      return null;
    } catch (error) {
      console.error('Error updating notification count:', error);
      return null;
    }
  });

// Existing function to delete payment verification
exports.deletePaymentVerification = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const { userId } = data;

  try {
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    const userData = userDoc.data();

    const batch = admin.firestore().batch();
    const userRef = admin.firestore().collection('users').doc(userId);

    batch.update(userRef, {
      'subscription': admin.firestore.FieldValue.delete(),
      'isAccountActive': false,
    });

    const historyRef = admin.firestore().collection('paymentHistory').doc();
    batch.set(historyRef, {
      userId: userId,
      action: 'verification_deleted',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      processedBy: context.auth.uid,
      notes: 'Payment verification deleted by admin'
    });

    const notificationRef = admin.firestore().collection('notifications').doc();
    batch.set(notificationRef, {
      userId: userId,
      type: 'payment_verification_deleted',
      message: 'Your payment verification has been deleted by admin.',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });

    await batch.commit();

    if (userData.email) {
      const emailSubject = 'Payment Verification Deleted';
      const emailMessage = `Dear ${userData.name || 'User'},

Your payment verification has been deleted by an administrator.

Please submit a new payment through your account dashboard if you wish to continue using our services.

Best regards,
Clean Restrooms Team`;

      await sendEmail(userData.email, emailSubject, emailMessage);
    }

    return { success: true };
  } catch (error) {
    console.error('Error deleting verification:', error);
    throw new functions.https.HttpsError('internal', 'Failed to delete verification');
  }
});

// HTTP endpoint for testing email functionality
exports.testEmail = functions.https.onRequest(async (req, res) => {
  cors(req, res, async () => {
    try {
      const { email } = req.query;

      if (!email) {
        return res.status(400).send('Email parameter is required');
      }

      const result = await sendEmail(
        email,
        'Test Email from Clean Restrooms',
        'This is a test email sent from the Clean Restrooms backend.'
      );

      return res.status(200).send(`Test email sent to ${email}: ${result}`);
    } catch (error) {
      console.error('Error sending test email:', error);
      return res.status(500).send('Error sending test email');
    }
  });
});