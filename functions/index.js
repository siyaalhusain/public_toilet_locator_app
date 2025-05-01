// index.js - Updated Firebase Cloud Functions with enhanced notification, payment proof, and email support

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
admin.initializeApp();

/**
 * Cloud Function that runs daily to check for expired subscriptions
 * and automatically deactivate accounts with expired subscriptions
 */
exports.checkExpiredSubscriptions = functions.pubsub
  .schedule('0 0 * * *') // Run daily at midnight
  .timeZone('UTC')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    console.log(`Running expired subscription check at ${now.toDate()}`);

    // Query for all owner accounts with active subscriptions
    const snapshot = await admin.firestore()
      .collection('users')
      .where('role', '==', 'Owner')
      .where('isAccountActive', '==', true)
      .get();

    const batch = admin.firestore().batch();
    let expiredCount = 0;

    snapshot.forEach(doc => {
      const userData = doc.data();

      // Check if user has subscription data
      if (userData.subscription && userData.subscription.endDate) {
        // Check if subscription has ended
        if (userData.subscription.endDate.toDate() < now.toDate()) {
          console.log(`Subscription expired for user: ${userData.email}`);

          // Update user document to deactivate account
          batch.update(doc.ref, {
            'isAccountActive': false,
            'subscription.status': 'expired'
          });

          // Log to payment history
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

          // Create a notification for the user
          const notificationRef = admin.firestore().collection('notifications').doc();
          batch.set(notificationRef, {
            userId: doc.id,
            type: 'subscription_expired',
            message: 'Your subscription has expired. Please renew to continue using the service.',
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false
          });

          // Send email notification for subscription expiration
          _sendEmail(
            userData.email,
            'Your Subscription Has Expired',
            `Dear User,\n\nYour subscription to our service has expired. Please renew your subscription to continue using all features.\n\nPrevious Plan: ${userData.subscription.planName}\nExpired On: ${userData.subscription.endDate.toDate().toLocaleDateString()}\n\nYou can renew your subscription from your account dashboard.\n\nBest regards,\nThe Support Team`
          );

          expiredCount++;
        }
      }
    });

    // If any accounts were updated, commit the batch
    if (expiredCount > 0) {
      await batch.commit();
      console.log(`Updated ${expiredCount} expired subscriptions and sent notifications`);
    } else {
      console.log('No expired subscriptions found');
    }

    return null;
  });

/**
 * Cloud Function to handle payment approval
 * This can be called from the admin dashboard
 */
exports.approvePayment = functions.https.onCall(async (data, context) => {
  // Verify that the caller is an admin
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in to approve payments');
  }

  // You would verify admin role here in production
  // For simplicity, we're just checking authentication

  const { userId, duration = '1 month' } = data;

  if (!userId) {
    throw new functions.https.HttpsError('invalid-argument', 'User ID is required');
  }

  try {
    // Get user document
    const userDoc = await admin.firestore().collection('users').doc(userId).get();

    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'User not found');
    }

    const userData = userDoc.data();

    if (userData.role !== 'Owner') {
      throw new functions.https.HttpsError('invalid-argument', 'User is not an Owner');
    }

    // Calculate subscription dates
    const now = admin.firestore.Timestamp.now();
    let endDate;

    // Parse the duration (e.g., "1 month", "3 months", "1 year")
    if (duration.includes('month')) {
      const months = parseInt(duration.split(' ')[0], 10) || 1;
      const endDateTime = new Date(now.toDate());
      endDateTime.setMonth(endDateTime.getMonth() + months);
      endDate = admin.firestore.Timestamp.fromDate(endDateTime);
    } else if (duration.includes('year')) {
      const years = parseInt(duration.split(' ')[0], 10) || 1;
      const endDateTime = new Date(now.toDate());
      endDateTime.setFullYear(endDateTime.getFullYear() + years);
      endDate = admin.firestore.Timestamp.fromDate(endDateTime);
    } else {
      // Default to 1 month if duration format is not recognized
      const endDateTime = new Date(now.toDate());
      endDateTime.setMonth(endDateTime.getMonth() + 1);
      endDate = admin.firestore.Timestamp.fromDate(endDateTime);
    }

    // Create a batch for atomic operations
    const batch = admin.firestore().batch();

    // Update the user document
    const userRef = admin.firestore().collection('users').doc(userId);
    batch.update(userRef, {
      'subscription.paymentStatus': 'approved',
      'subscription.startDate': now,
      'subscription.endDate': endDate,
      'isAccountActive': true,
    });

    // Add to payment history
    const historyRef = admin.firestore().collection('paymentHistory').doc();
    batch.set(historyRef, {
      userId: userId,
      amount: userData.subscription?.price || 0,
      planName: userData.subscription?.planName || 'Unknown Plan',
      status: 'approved',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      processedBy: context.auth.uid,
      startDate: now,
      endDate: endDate,
    });

    // Create notification document
    const notificationRef = admin.firestore().collection('notifications').doc();
    batch.set(notificationRef, {
      userId: userId,
      type: 'payment_approved',
      message: `Your payment for ${userData.subscription?.planName || 'subscription'} has been approved. Your subscription is now active until ${endDate.toDate().toLocaleDateString()}.`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });

    // Commit all the operations as a single transaction
    await batch.commit();

    // Send email notification
    if (userData.email) {
      const emailSubject = 'Payment Approved - Subscription Activated';
      const emailMessage = `Dear ${userData.name || 'User'},

Your payment for the ${userData.subscription?.planName || 'subscription'} plan has been approved. Your subscription is now active until ${endDate.toDate().toLocaleDateString()}.

Plan Details:
- Plan: ${userData.subscription?.planName || 'Unknown Plan'}
- Amount: $${(userData.subscription?.price || 0).toFixed(2)}
- Duration: ${duration}
- Start Date: ${now.toDate().toLocaleDateString()}
- End Date: ${endDate.toDate().toLocaleDateString()}

Thank you for your payment. You now have full access to all features of your subscription.

If you have any questions or concerns, please contact our support team.

Best regards,
The Support Team`;

      await _sendEmail(userData.email, emailSubject, emailMessage);
    }

    return {
      success: true,
      message: 'Payment approved successfully',
      notificationId: notificationRef.id,
      subscription: {
        startDate: now.toDate(),
        endDate: endDate.toDate(),
        status: 'approved'
      }
    };
  } catch (error) {
    console.error('Error approving payment:', error);
    throw new functions.https.HttpsError('internal', 'Failed to approve payment', error);
  }
});

/**
 * Cloud Function to handle payment rejection
 * This can be called from the admin dashboard
 */
exports.rejectPayment = functions.https.onCall(async (data, context) => {
  // Verify that the caller is an admin
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in to reject payments');
  }

  // You would verify admin role here in production

  const { userId, reason } = data;

  if (!userId) {
    throw new functions.https.HttpsError('invalid-argument', 'User ID is required');
  }

  try {
    // Get the user data for notification details
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    const userData = userDoc.data();

    // Create a batch for atomic operations
    const batch = admin.firestore().batch();

    // Update the user document
    const userRef = admin.firestore().collection('users').doc(userId);
    batch.update(userRef, {
      'subscription.paymentStatus': 'rejected',
      'subscription.rejectionReason': reason || 'No reason provided',
      'isAccountActive': false,
    });

    // Add to payment history
    const historyRef = admin.firestore().collection('paymentHistory').doc();
    batch.set(historyRef, {
      userId: userId,
      email: userData?.email || '',
      status: 'rejected',
      reason: reason || 'No reason provided',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      processedBy: context.auth.uid,
    });

    // Create notification for user
    const notificationRef = admin.firestore().collection('notifications').doc();
    batch.set(notificationRef, {
      userId: userId,
      type: 'payment_rejected',
      message: `Your payment was rejected. Reason: ${reason || 'No reason provided'}`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });

    // Commit all the operations as a single transaction
    await batch.commit();

    // Send email notification
    if (userData?.email) {
      const emailSubject = 'Payment Rejected - Action Required';
      const emailMessage = `Dear ${userData.name || 'User'},

Unfortunately, your payment for the ${userData.subscription?.planName || 'subscription'} plan (${userData.subscription?.price ? '$' + userData.subscription.price.toFixed(2) : ''}) has been rejected.

Reason for rejection: ${reason || 'No reason provided'}

If you believe this is an error or need assistance with your payment, please contact our support team.
You can also submit a new payment through your account dashboard.

Best regards,
The Support Team`;

      await _sendEmail(userData.email, emailSubject, emailMessage);
    }

    return {
      success: true,
      message: 'Payment rejected successfully',
      notificationId: notificationRef.id
    };
  } catch (error) {
    console.error('Error rejecting payment:', error);
    throw new functions.https.HttpsError('internal', 'Failed to reject payment', error);
  }
});

/**
 * Function to count pending payment verifications
 * This can be used to update badges in the admin dashboard
 */
exports.getPendingPaymentsCount = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in');
  }

  try {
    // Query for pending payments
    const snapshot = await admin.firestore()
      .collection('users')
      .where('role', '==', 'Owner')
      .where('subscription.paymentStatus', '==', 'pending')
      .get();

    return {
      count: snapshot.size
    };
  } catch (error) {
    console.error('Error counting pending payments:', error);
    throw new functions.https.HttpsError('internal', 'Failed to count pending payments', error);
  }
});

/**
 * Function to send notification when subscription is about to expire
 * Runs daily and checks for subscriptions ending in 7 days
 */
exports.sendSubscriptionExpirationNotices = functions.pubsub
  .schedule('0 9 * * *') // Run daily at 9 AM
  .timeZone('UTC')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();

    // Calculate the date 7 days from now
    const sevenDaysFromNow = new Date(now.toDate());
    sevenDaysFromNow.setDate(sevenDaysFromNow.getDate() + 7);
    const sevenDaysFutureTimestamp = admin.firestore.Timestamp.fromDate(sevenDaysFromNow);

    // Calculate the date 1 day from now (for last warning)
    const oneDayFromNow = new Date(now.toDate());
    oneDayFromNow.setDate(oneDayFromNow.getDate() + 1);
    const oneDayFutureTimestamp = admin.firestore.Timestamp.fromDate(oneDayFromNow);

    // Query for active subscriptions ending in approximately 7 days
    const sevenDayQuery = await admin.firestore()
      .collection('users')
      .where('role', '==', 'Owner')
      .where('isAccountActive', '==', true)
      .get();

    let notificationsSent = 0;
    const batch = admin.firestore().batch();

    // Process each user
    for (const doc of sevenDayQuery.docs) {
      const userData = doc.data();

      if (userData.subscription && userData.subscription.endDate) {
        const endDate = userData.subscription.endDate.toDate();
        const sevenDayTarget = sevenDaysFromNow.toDateString();
        const oneDayTarget = oneDayFromNow.toDateString();
        const endDateString = endDate.toDateString();

        // Check if subscription ends in about 7 days
        if (endDateString === sevenDayTarget) {
          // Create a notification document
          const notifRef = admin.firestore().collection('notifications').doc();
          batch.set(notifRef, {
            userId: doc.id,
            email: userData.email,
            type: 'subscription_expiring_soon',
            message: `Your subscription will expire in 7 days on ${endDate.toLocaleDateString()}. Please renew to maintain access.`,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false
          });

          // Send email notification
          if (userData.email) {
            const emailSubject = 'Your Subscription Will Expire in 7 Days';
            const emailMessage = `Dear ${userData.name || 'User'},

Your subscription will expire in 7 days on ${endDate.toLocaleDateString()}.

To avoid service interruption, please renew your subscription before the expiration date.

Current Plan: ${userData.subscription.planName || 'Unknown Plan'}
Expiration Date: ${endDate.toLocaleDateString()}

You can renew your subscription from your account dashboard.

Best regards,
The Support Team`;

            await _sendEmail(userData.email, emailSubject, emailMessage);
          }

          notificationsSent++;
        }
        // Check if subscription ends tomorrow (last warning)
        else if (endDateString === oneDayTarget) {
          // Create a notification document
          const notifRef = admin.firestore().collection('notifications').doc();
          batch.set(notifRef, {
            userId: doc.id,
            email: userData.email,
            type: 'subscription_expiring_tomorrow',
            message: `URGENT: Your subscription will expire tomorrow. Please renew immediately to avoid service interruption.`,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false
          });

          // Send email notification
          if (userData.email) {
            const emailSubject = 'URGENT: Your Subscription Expires Tomorrow';
            const emailMessage = `Dear ${userData.name || 'User'},

URGENT: Your subscription will expire TOMORROW on ${endDate.toLocaleDateString()}.

To avoid service interruption, please renew your subscription immediately.

Current Plan: ${userData.subscription.planName || 'Unknown Plan'}
Expiration Date: ${endDate.toLocaleDateString()}

You can renew your subscription from your account dashboard.

Best regards,
The Support Team`;

            await _sendEmail(userData.email, emailSubject, emailMessage);
          }

          notificationsSent++;
        }
      }
    }

    // Commit all notifications
    if (notificationsSent > 0) {
      await batch.commit();
      console.log(`Sent ${notificationsSent} subscription expiration notifications`);
    } else {
      console.log('No subscription notifications needed today');
    }

    return null;
  });

/**
 * Cloud Function to renew an expired subscription
 */
exports.renewSubscription = functions.https.onCall(async (data, context) => {
  // Check authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in to renew subscriptions');
  }

  const userId = context.auth.uid;
  const { planId, duration, paymentProofUrl } = data;

  if (!planId || !duration) {
    throw new functions.https.HttpsError('invalid-argument', 'Plan ID and duration are required');
  }

  try {
    // Get the user document
    const userDoc = await admin.firestore().collection('users').doc(userId).get();

    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'User not found');
    }

    const userData = userDoc.data();

    if (userData.role !== 'Owner') {
      throw new functions.https.HttpsError('permission-denied', 'Only owners can renew subscriptions');
    }

    // Get plan details (in a production app, you would have a plans collection)
    // For this example, we'll use hardcoded plans
    const plans = {
      'basic': { name: 'Basic', price: 9.99 },
      'standard': { name: 'Standard', price: 19.99 },
      'premium': { name: 'Premium', price: 29.99 }
    };

    const plan = plans[planId] || { name: 'Unknown Plan', price: 0 };

    // Create batch for atomic operations
    const batch = admin.firestore().batch();

    // Update subscription status to pending renewal
    const userRef = admin.firestore().collection('users').doc(userId);
    batch.update(userRef, {
      'subscription.planId': planId,
      'subscription.planName': plan.name,
      'subscription.price': plan.price,
      'subscription.duration': duration,
      'subscription.paymentStatus': 'pending',
      'subscription.paymentMethod': 'bankTransfer',
      'subscription.paymentProofUrl': paymentProofUrl || null,
      'subscription.renewalRequestDate': admin.firestore.FieldValue.serverTimestamp(),
    });

    // Add to payment history
    const historyRef = admin.firestore().collection('paymentHistory').doc();
    batch.set(historyRef, {
      userId: userId,
      amount: plan.price,
      planName: plan.name,
      status: 'pending_renewal',
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
      paymentProofUrl: paymentProofUrl || null,
    });

    // Create notification for admin
    const adminNotifRef = admin.firestore().collection('adminNotifications').doc();
    batch.set(adminNotifRef, {
      type: 'renewal_request',
      userId: userId,
      userName: userData.name || 'Unknown User',
      userEmail: userData.email || 'No email',
      planName: plan.name,
      amount: plan.price,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });

    // Create notification for user
    const userNotifRef = admin.firestore().collection('notifications').doc();
    batch.set(userNotifRef, {
      userId: userId,
      type: 'renewal_requested',
      message: `Your subscription renewal request for ${plan.name} plan has been submitted and is pending approval.`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });

    // Commit all operations
    await batch.commit();

    // Send confirmation email to user
    if (userData.email) {
      const emailSubject = 'Subscription Renewal Request Received';
      const emailMessage = `Dear ${userData.name || 'User'},

We have received your subscription renewal request for the ${plan.name} plan.

Plan Details:
- Plan: ${plan.name}
- Price: $${plan.price.toFixed(2)}
- Duration: ${duration}

Your request is pending approval. We will notify you once your payment has been processed.

Thank you for continuing to use our service!

Best regards,
The Support Team`;

      await _sendEmail(userData.email, emailSubject, emailMessage);
    }

    return {
      success: true,
      message: 'Subscription renewal request submitted successfully'
    };
  } catch (error) {
    console.error('Error renewing subscription:', error);
    throw new functions.https.HttpsError('internal', 'Failed to process renewal request', error);
  }
});

/**
 * Cloud Function to update user plan or payment details
 * This can be called from the admin dashboard
 */
exports.updatePaymentDetails = functions.https.onCall(async (data, context) => {
  // Verify that the caller is an admin
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in to update payment details');
  }

  // You would verify admin role here in production

  const { userId, planName, price } = data;

  if (!userId) {
    throw new functions.https.HttpsError('invalid-argument', 'User ID is required');
  }

  try {
    // Get user data for email notification
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    const userData = userDoc.data();

    // Create batch for atomic operations
    const batch = admin.firestore().batch();

    // Update the user document with new plan details
    const userRef = admin.firestore().collection('users').doc(userId);
    batch.update(userRef, {
      'subscription.planName': planName,
      'subscription.price': parseFloat(price),
      'subscription.lastUpdated': admin.firestore.FieldValue.serverTimestamp(),
      'subscription.updatedBy': context.auth.uid,
    });

    // Log the change
    const historyRef = admin.firestore().collection('paymentHistory').doc();
    batch.set(historyRef, {
      userId: userId,
      action: 'details_updated',
      planName: planName,
      price: parseFloat(price),
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      processedBy: context.auth.uid,
      notes: 'Payment details updated by admin'
    });

    // Create notification for user
    const notificationRef = admin.firestore().collection('notifications').doc();
    batch.set(notificationRef, {
      userId: userId,
      type: 'payment_details_updated',
      message: `Your payment details have been updated by an administrator. New plan: ${planName}, price: $${parseFloat(price).toFixed(2)}.`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });

    // Commit all operations
    await batch.commit();

    // Send email notification
    if (userData?.email) {
      const emailSubject = 'Payment Details Updated';
      const emailMessage = `Dear ${userData.name || 'User'},

Your payment details have been updated by our administrative team.

Updated Details:
- Plan: ${planName}
- Price: $${parseFloat(price).toFixed(2)}

If you have any questions about these changes, please contact our support team.

Best regards,
The Support Team`;

      await _sendEmail(userData.email, emailSubject, emailMessage);
    }

    return {
      success: true,
      message: 'Payment details updated successfully',
      notificationId: notificationRef.id
    };
  } catch (error) {
    console.error('Error updating payment details:', error);
    throw new functions.https.HttpsError('internal', 'Failed to update payment details', error);
  }
});

/**
 * Cloud Function to search for payments
 * This can be called from the admin dashboard
 */
exports.searchPayments = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in');
  }

  const { query, status } = data;

  if (!query && !status) {
    throw new functions.https.HttpsError('invalid-argument', 'Search query or status is required');
  }

  try {
    let usersRef = admin.firestore().collection('users').where('role', '==', 'Owner');

    // If status is specified, filter by payment status
    if (status && status !== 'All') {
      usersRef = usersRef.where('subscription.paymentStatus', '==', status.toLowerCase());
    }

    const snapshot = await usersRef.get();

    const results = [];

    // If a search query is provided, filter results manually
    // Firestore doesn't support text search natively
    if (query) {
      const lowerQuery = query.toLowerCase();

      for (const doc of snapshot.docs) {
        const userData = doc.data();

        // Check if user has subscription data
        if (userData.subscription) {
          // Search in name, email, and plan name
          const name = (userData.name || '').toLowerCase();
          const email = (userData.email || '').toLowerCase();
          const planName = (userData.subscription.planName || '').toLowerCase();

          if (name.includes(lowerQuery) || email.includes(lowerQuery) || planName.includes(lowerQuery)) {
            results.push({
              userId: doc.id,
              name: userData.name || 'Unknown',
              email: userData.email || 'No email',
              planName: userData.subscription.planName || 'Unknown Plan',
              planPrice: userData.subscription.price || 0,
              paymentStatus: userData.subscription.paymentStatus || 'pending',
              paymentMethod: userData.subscription.paymentMethod || 'Unknown',
              paymentProofUrl: userData.subscription.paymentProofUrl || '',
              createdAt: userData.createdAt || admin.firestore.Timestamp.now(),
              isAccountActive: userData.isAccountActive || false,
            });
          }
        }
      }
    } else {
      // If no query, just return all results from the status filter
      for (const doc of snapshot.docs) {
        const userData = doc.data();

        if (userData.subscription) {
          results.push({
            userId: doc.id,
            name: userData.name || 'Unknown',
            email: userData.email || 'No email',
            planName: userData.subscription.planName || 'Unknown Plan',
            planPrice: userData.subscription.price || 0,
            paymentStatus: userData.subscription.paymentStatus || 'pending',
            paymentMethod: userData.subscription.paymentMethod || 'Unknown',
            paymentProofUrl: userData.subscription.paymentProofUrl || '',
            createdAt: userData.createdAt || admin.firestore.Timestamp.now(),
            isAccountActive: userData.isAccountActive || false,
          });
        }
      }
    }

    // Sort by creation date, newest first
    results.sort((a, b) => {
      const dateA = a.createdAt?.toDate() || new Date();
      const dateB = b.createdAt?.toDate() || new Date();
      return dateB - dateA;
    });

    return { results };
  } catch (error) {
    console.error('Error searching payments:', error);
    throw new functions.https.HttpsError('internal', 'Failed to search payments', error);
  }
});

/**
 * Cloud Function to get subscription analytics
 * This can be used for the admin dashboard
 */
exports.getSubscriptionAnalytics = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in');
  }

  try {
    // Get all owner accounts
    const snapshot = await admin.firestore()
      .collection('users')
      .where('role', '==', 'Owner')
      .get();

    // Initialize counters
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

    // Process each owner
    snapshot.forEach(doc => {
      const userData = doc.data();

      if (userData.subscription) {
        const subscription = userData.subscription;

        // Count by payment status
        if (subscription.paymentStatus === 'approved' && userData.isAccountActive) {
          analytics.activeSubscriptions++;

          // Add to total revenue (only count active subscriptions)
          if (subscription.price) {
            analytics.totalRevenue += subscription.price;
          }

          // Count by plan
          if (subscription.planId) {
            switch (subscription.planId.toLowerCase()) {
              case 'basic':
                analytics.planDistribution.basic++;
                break;
              case 'standard':
                analytics.planDistribution.standard++;
                break;
              case 'premium':
                analytics.planDistribution.premium++;
                break;
              default:
                analytics.planDistribution.other++;
            }
          } else {
            analytics.planDistribution.other++;
          }
        } else if (subscription.paymentStatus === 'pending') {
          analytics.pendingPayments++;
        } else if (subscription.paymentStatus === 'rejected') {
          analytics.rejectedPayments++;
        }

        // Check if subscription has status 'expired'
        if (subscription.status === 'expired' ||
           (subscription.endDate && subscription.endDate.toDate() < new Date())) {
          analytics.expiredSubscriptions++;
        }
      }
    });

    return analytics;
  } catch (error) {
    console.error('Error getting subscription analytics:', error);
    throw new functions.https.HttpsError('internal', 'Failed to get subscription analytics', error);
  }
});

/**
 * Cloud Function to get notifications for a specific user
 */
exports.getUserNotifications = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in');
  }

  const userId = context.auth.uid;
  const { limit = 20, markAsRead = false } = data;

  try {
    // Query notifications for this user
    const snapshot = await admin.firestore()
      .collection('notifications')
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .get();

    const notifications = [];
    const batch = admin.firestore().batch();
    let updateCount = 0;

    snapshot.forEach(doc => {
      const notification = {
        id: doc.id,
        ...doc.data()
      };

      notifications.push(notification);

      // If requested, mark notifications as read
      if (markAsRead && !notification.read) {
        batch.update(doc.ref, { read: true });
        updateCount++;
      }
    });

    // Commit updates if any
    if (updateCount > 0) {
      await batch.commit();
    }

    return { notifications };
  } catch (error) {
    console.error('Error getting user notifications:', error);
    throw new functions.https.HttpsError('internal', 'Failed to get notifications', error);
  }
});

/**
 * Cloud Function to mark a notification as read
 */
exports.markNotificationRead = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in');
  }

  const userId = context.auth.uid;
  const { notificationId } = data;

  if (!notificationId) {
    throw new functions.https.HttpsError('invalid-argument', 'Notification ID is required');
  }

  try {
    // Get the notification
    const notificationDoc = await admin.firestore().collection('notifications').doc(notificationId).get();

    if (!notificationDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Notification not found');
    }

    const notificationData = notificationDoc.data();

    // Verify this notification belongs to the user
    if (notificationData.userId !== userId) {
      throw new functions.https.HttpsError('permission-denied', 'You do not have permission to access this notification');
    }

    // Update the notification
    await admin.firestore().collection('notifications').doc(notificationId).update({
      read: true,
      readAt: admin.firestore.FieldValue.serverTimestamp()
    });

    return { success: true };
  } catch (error) {
    console.error('Error marking notification as read:', error);
    throw new functions.https.HttpsError('internal', 'Failed to update notification', error);
  }
});

/**
 * Cloud Function to check if payment proof exists
 * This helps troubleshoot issues with viewing payment proofs
 */
exports.checkPaymentProof = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in');
  }

  const { userId, imageUrl } = data;

  if (!userId || !imageUrl) {
    throw new functions.https.HttpsError('invalid-argument', 'User ID and image URL are required');
  }

  try {
    // Attempt to get metadata for the file
    // This assumes the payment proofs are stored in Firebase Storage
    // Extract the path from the URL
    const path = decodeURIComponent(imageUrl.split('/o/')[1].split('?')[0]);

    try {
      // Check if the file exists
      const file = admin.storage().bucket().file(path);
      const [exists] = await file.exists();

      if (!exists) {
        return {
          exists: false,
          message: 'The payment proof file does not exist in storage',
          url: imageUrl,
          path: path
        };
      }

      // Get file metadata
      const [metadata] = await file.getMetadata();

      return {
        exists: true,
        message: 'Payment proof file exists',
        url: imageUrl,
        path: path,
        contentType: metadata.contentType,
        size: metadata.size,
        timeCreated: metadata.timeCreated,
        updated: metadata.updated
      };
    } catch (storageError) {
      console.error('Storage error:', storageError);

      return {
        exists: false,
        message: 'Error checking storage: ' + storageError.message,
        url: imageUrl,
        error: storageError.message
      };
    }
  } catch (error) {
    console.error('Error checking payment proof:', error);
    throw new functions.https.HttpsError('internal', 'Failed to check payment proof', error);
  }
});

/**
 * Cloud Function to check and fix payment proof image URLs
 * This is useful for troubleshooting issues with payment slip display
 */
exports.checkPaymentProofImage = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in');
  }

  const { userId, imageUrl } = data;

  if (!imageUrl) {
    throw new functions.https.HttpsError('invalid-argument', 'Image URL is required');
  }

  try {
    // Parse the URL to check if it's a Firebase Storage URL
    const isFirebaseStorageUrl = imageUrl.includes('firebasestorage.googleapis.com');

    // Check if it's a Firebase Storage URL and extract the path
    let path = '';
    if (isFirebaseStorageUrl) {
      // Extract path from the URL format: https://firebasestorage.googleapis.com/v0/b/[bucket]/o/[path]?[params]
      if (imageUrl.includes('/o/')) {
        path = decodeURIComponent(imageUrl.split('/o/')[1].split('?')[0]);
      }
    }

    // Check if the URL is accessible via HTTP
    let isAccessible = false;
    let accessError = null;

    try {
      // Use axios for HTTP requests
      const axios = require('axios');

      // Set timeout to 5 seconds and only fetch headers
      const response = await axios({
        method: 'HEAD',
        url: imageUrl,
        timeout: 5000,
        validateStatus: status => status < 400, // Consider all non-4xx/5xx as success
      });

      isAccessible = true;
    } catch (error) {
      console.error('Error checking URL accessibility:', error);
      isAccessible = false;
      accessError = error.message;
    }

    // If it's a Firebase Storage URL, check if the file exists in storage
    let fileExists = false;
    let fileMetadata = null;
    let signedUrl = null;

    if (isFirebaseStorageUrl && path) {
      try {
        // Check if the file exists in Firebase Storage
        const file = admin.storage().bucket().file(path);
        [fileExists] = await file.exists();

        if (fileExists) {
          // Get file metadata
          [fileMetadata] = await file.getMetadata();

          // Generate a fresh signed URL that's valid for 15 minutes
          const [url] = await file.getSignedUrl({
            action: 'read',
            expires: Date.now() + 15 * 60 * 1000, // 15 minutes
          });

          signedUrl = url;
        }
      } catch (storageError) {
        console.error('Storage error:', storageError);
      }
    }

    // Update the user's document with the fixed URL if we have a valid signed URL
    if (userId && signedUrl) {
      try {
        await admin.firestore().collection('users').doc(userId).update({
          'subscription.paymentProofUrl': signedUrl,
          'subscription.paymentProofUrlUpdated': admin.firestore.FieldValue.serverTimestamp()
        });
      } catch (updateError) {
        console.error('Error updating user document:', updateError);
      }
    }

    return {
      originalUrl: imageUrl,
      isFirebaseStorageUrl,
      path: path || null,
      isAccessible,
      accessError,
      fileExists,
      fileMetadata: fileMetadata || null,
      signedUrl,
      fixApplied: !!signedUrl
    };
  } catch (error) {
    console.error('Error checking payment proof image:', error);
    throw new functions.https.HttpsError('internal', 'Failed to check payment proof image', error);
  }
});

/**
 * Listener for new notifications to update unread count
 */
exports.updateUnreadNotificationCount = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snapshot, context) => {
    const notificationData = snapshot.data();
    const userId = notificationData.userId;

    if (!userId) {
      console.log('No user ID found in notification');
      return null;
    }

    try {
      // Count unread notifications for this user
      const query = await admin.firestore()
        .collection('notifications')
        .where('userId', '==', userId)
        .where('read', '==', false)
        .get();

      const unreadCount = query.size;

      // Update the user's unread notification count
      await admin.firestore().collection('users').doc(userId).update({
        'unreadNotifications': unreadCount
      });

      console.log(`Updated unread notification count for user ${userId} to ${unreadCount}`);
      return null;
    } catch (error) {
      console.error('Error updating unread notification count:', error);
      return null;
    }
  });

/**
 * Cloud Function to create the notifications collection if it doesn't exist
 * This is useful for setup and troubleshooting
 */
exports.ensureNotificationsCollection = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in');
  }

  try {
    // Create a dummy document in the notifications collection
    const dummyRef = admin.firestore().collection('notifications').doc('setup');
    await dummyRef.set({
      type: 'system',
      message: 'Notifications collection initialization',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: true
    });

    // Delete the dummy document
    await dummyRef.delete();

    return {
      success: true,
      message: 'Notifications collection verified/created successfully'
    };
  } catch (error) {
    console.error('Error ensuring notifications collection:', error);
    throw new functions.https.HttpsError('internal', 'Failed to ensure notifications collection exists', error);
  }
});

/**
 * Cloud Function to send email notifications to users
 * This function can be called from any client application
 */
exports.sendEmailNotification = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in to send email notifications');
  }

  const { email, subject, message } = data;

  if (!email || !subject || !message) {
    throw new functions.https.HttpsError('invalid-argument', 'Email, subject, and message are required');
  }

  try {
    // Call the internal email function
    await _sendEmail(email, subject, message);

    // Log the successful email sending
    await admin.firestore().collection('emailLogs').add({
      to: email,
      subject: subject,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      sentBy: context.auth.uid,
      status: 'sent'
    });

    return {
      success: true,
      message: 'Email notification sent successfully'
    };
  } catch (error) {
    console.error('Error sending email notification:', error);

    // Log the error
    await admin.firestore().collection('emailLogs').add({
      to: email,
      subject: subject,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      sentBy: context.auth.uid,
      status: 'error',
      error: error.message
    });

    throw new functions.https.HttpsError('internal', 'Failed to send email notification', error);
  }
});

/**
 * Internal helper function to send emails
 * This centralizes the email sending logic to be used by other Cloud Functions
 */
async function _sendEmail(email, subject, message) {
  try {
    // Configure nodemailer with your email service
    const transporter = nodemailer.createTransport({
      service: 'gmail',  // Or your preferred email service
      auth: {
        user: functions.config().email.user,
        pass: functions.config().email.password
      }
    });

    // Email options
    const mailOptions = {
      from: functions.config().email.from || '"Your App" <noreply@yourapp.com>',
      to: email,
      subject: subject,
      text: message,
      html: message.replace(/\n/g, '<br>')
    };

    // Send the email
    const info = await transporter.sendMail(mailOptions);
    console.log('Email sent:', info.messageId);
    return info;
  } catch (error) {
    console.error('Error in _sendEmail helper function:', error);
    throw error; // Re-throw to be handled by the calling function
  }
}

/**
 * Cloud Function to delete payment verification
 * This can be called from the admin dashboard
 */
exports.deletePaymentVerification = functions.https.onCall(async (data, context) => {
  // Verify that the caller is an admin
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'You must be logged in to delete payment verifications');
  }

  // You would verify admin role here in production

  const { userId } = data;

  if (!userId) {
    throw new functions.https.HttpsError('invalid-argument', 'User ID is required');
  }

  try {
    // Get user data before deleting
    const userDoc = await admin.firestore().collection('users').doc(userId).get();

    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'User not found');
    }

    const userData = userDoc.data();
    const userEmail = userData.email;
    const userName = userData.name || 'User';
    const planName = userData.subscription?.planName || 'Unknown Plan';

    // Create a batch for atomic operations
    const batch = admin.firestore().batch();

    // Reference to user document
    const userRef = admin.firestore().collection('users').doc(userId);

    // Remove the subscription field from the user document
    batch.update(userRef, {
      'subscription': admin.firestore.FieldValue.delete(),
      'isAccountActive': false,
    });

    // Add to payment history
    const historyRef = admin.firestore().collection('paymentHistory').doc();
    batch.set(historyRef, {
      userId: userId,
      email: userEmail,
      action: 'verification_deleted',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      processedBy: context.auth.uid,
      notes: 'Payment verification deleted by admin'
    });

    // Create notification document
    const notificationRef = admin.firestore().collection('notifications').doc();
    batch.set(notificationRef, {
      userId: userId,
      type: 'payment_verification_deleted',
      message: 'Your payment verification has been deleted by admin.',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false
    });

    // Commit all the operations as a single transaction
    await batch.commit();

    // Send email notification
    if (userEmail) {
      const emailSubject = 'Payment Verification Deleted';
      const emailMessage = `Dear ${userName},

This is to inform you that your payment verification for the ${planName} plan has been deleted by an administrator.

If you wish to continue using our services, please submit a new payment through your account dashboard.

If you have any questions or concerns, please contact our support team.

Best regards,
The Support Team`;

      await _sendEmail(userEmail, emailSubject, emailMessage);
    }

    return {
      success: true,
      message: 'Payment verification deleted successfully',
      notificationId: notificationRef.id
    };
  } catch (error) {
    console.error('Error deleting payment verification:', error);
    throw new functions.https.HttpsError('internal', 'Failed to delete payment verification', error);
  }
});