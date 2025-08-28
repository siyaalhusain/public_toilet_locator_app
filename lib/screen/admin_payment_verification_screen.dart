import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'dart:async';
import 'package:photo_view/photo_view.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
// there is a four tab
class AdminPaymentVerificationScreen extends StatefulWidget {
  @override
  _AdminPaymentVerificationScreenState createState() =>
      _AdminPaymentVerificationScreenState();
}

class _AdminPaymentVerificationScreenState
    extends State<AdminPaymentVerificationScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  late TabController _tabController;

  // Data for each tab
  List<Map<String, dynamic>> _pendingPayments = [];
  List<Map<String, dynamic>> _activePayments = [];
  List<Map<String, dynamic>> _inactivePayments = [];
  List<Map<String, dynamic>> _renewPayments = [];

  // Filtered data for search
  List<Map<String, dynamic>> _filteredPending = [];
  List<Map<String, dynamic>> _filteredActive = [];
  List<Map<String, dynamic>> _filteredInactive = [];
  List<Map<String, dynamic>> _filteredRenew = [];

  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _subscriptionTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllPayments();
    _ensureNotificationsCollectionExists();

    // Check every 5 minutes for expired subscriptions
    _subscriptionTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      _checkAndMoveExpiredSubscriptions();
    });

    // Also check immediately when screen loads
    _checkAndMoveExpiredSubscriptions();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
        _filterAllPayments();
      });
    });

    _tabController.addListener(() {
      setState(() {
        _filterAllPayments();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _subscriptionTimer?.cancel();
    super.dispose();
  }

  // Start timer to check subscription expiry every hour
  void _startSubscriptionTimer() {
    _subscriptionTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      if (mounted) {
        _checkAndMoveExpiredSubscriptions();
      }
    });
  }

  Future<void> _checkAndMoveExpiredSubscriptions() async {
    try {
      final now = DateTime.now();
      final activeQuery = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'Owner')
          .where('subscription.paymentStatus', isEqualTo: 'approved')
          .where('isAccountActive', isEqualTo: true)
          .get();

      WriteBatch batch = _firestore.batch();
      List<String> expiredUserIds = [];

      for (var doc in activeQuery.docs) {
        final data = doc.data();
        final subscription = data['subscription'] as Map<String, dynamic>?;

        if (subscription != null && subscription['endDate'] != null) {
          final endDate = (subscription['endDate'] as Timestamp).toDate();

          if (now.isAfter(endDate)) {
            // Move to inactive
            batch.update(doc.reference, {
              'subscription.paymentStatus': 'expired',
              'isAccountActive': false,
              'subscription.expiredAt': FieldValue.serverTimestamp(),
              'subscription.rejectionReason': 'Subscription period ended',
            });

            expiredUserIds.add(doc.id);

            // Add notification
            final notificationRef =
                _firestore.collection('notifications').doc();
            batch.set(notificationRef, {
              'userId': doc.id,
              'type': 'subscription_expired',
              'message':
                  'Your subscription has expired. Please renew to continue using our services.',
              'createdAt': FieldValue.serverTimestamp(),
              'read': false
            });
          }
        }
      }

      if (expiredUserIds.isNotEmpty) {
        await batch.commit();
        await _disableRelatedData(expiredUserIds);
        await _loadAllPayments(); // Refresh data

        // Show a snackbar to inform admin
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${expiredUserIds.length} subscription(s) moved to inactive'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('Error checking expired subscriptions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking expired subscriptions'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _disableRelatedData(List<String> userIds) async {
    try {
      WriteBatch batch = _firestore.batch();

      for (String userId in userIds) {
        // Disable toilets owned by this user
        final toiletsQuery = await _firestore
            .collection('toilets')
            .where('ownerId', isEqualTo: userId)
            .get();

        for (var toiletDoc in toiletsQuery.docs) {
          batch.update(toiletDoc.reference, {
            'isActive': false,
            'disabledAt': FieldValue.serverTimestamp(),
            'disabledReason': 'Owner subscription expired'
          });
        }

        // Disable maintainers assigned to this owner's toilets
        final maintainersQuery = await _firestore
            .collection('users')
            .where('role', isEqualTo: 'Maintainer')
            .where('assignedOwnerId', isEqualTo: userId)
            .get();

        for (var maintainerDoc in maintainersQuery.docs) {
          batch.update(maintainerDoc.reference, {
            'isAccountActive': false,
            'disabledAt': FieldValue.serverTimestamp(),
            'disabledReason': 'Owner subscription expired'
          });
        }
      }

      await batch.commit();
    } catch (e) {
      print('Error disabling related data: $e');
    }
  }

  Future<void> _enableRelatedData(String userId) async {
    try {
      WriteBatch batch = _firestore.batch();

      // Enable toilets owned by this user
      final toiletsQuery = await _firestore
          .collection('toilets')
          .where('ownerId', isEqualTo: userId)
          .get();

      for (var toiletDoc in toiletsQuery.docs) {
        batch.update(toiletDoc.reference, {
          'isActive': true,
          'enabledAt': FieldValue.serverTimestamp(),
        });
      }

      // Enable maintainers assigned to this owner's toilets
      final maintainersQuery = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'Maintainer')
          .where('assignedOwnerId', isEqualTo: userId)
          .get();

      for (var maintainerDoc in maintainersQuery.docs) {
        batch.update(maintainerDoc.reference, {
          'isAccountActive': true,
          'enabledAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (e) {
      print('Error enabling related data: $e');
    }
  }

  void _filterAllPayments() {
    _filteredPending = _filterPayments(_pendingPayments);
    _filteredActive = _filterPayments(_activePayments);
    _filteredInactive = _filterPayments(_inactivePayments);
    _filteredRenew = _filterPayments(_renewPayments);
  }

  List<Map<String, dynamic>> _filterPayments(
      List<Map<String, dynamic>> payments) {
    if (_searchQuery.isEmpty) return List.from(payments);

    return payments.where((payment) {
      final String searchLower = _searchQuery.toLowerCase();
      final String name = payment['name']?.toString().toLowerCase() ?? '';
      final String email = payment['email']?.toString().toLowerCase() ?? '';
      final String planName =
          payment['planName']?.toString().toLowerCase() ?? '';

      return name.contains(searchLower) ||
          email.contains(searchLower) ||
          planName.contains(searchLower);
    }).toList();
  }

  Future<void> _ensureNotificationsCollectionExists() async {
    try {
      await _firestore.collection('notifications').limit(1).get();
    } catch (e) {
      await _firestore.collection('notifications').doc('dummy').set({
        'type': 'system',
        'message': 'Notifications collection initialization',
        'createdAt': FieldValue.serverTimestamp(),
        'read': true
      });
      await _firestore.collection('notifications').doc('dummy').delete();
    }
  }

// Update the _loadAllPayments method in admin_payment_verification_screen.dart
  Future<void> _loadAllPayments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get all owner users
      QuerySnapshot snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'Owner')
          .get();

      List<Map<String, dynamic>> pending = [];
      List<Map<String, dynamic>> active = [];
      List<Map<String, dynamic>> inactive = [];
      List<Map<String, dynamic>> renew = [];

      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        if (data.containsKey('subscription')) {
          Map<String, dynamic> subscription = data['subscription'];
          String paymentStatus = subscription['paymentStatus'] ?? 'pending';
          bool isRenewal = subscription['isRenewal'] ?? false;

          // Check if subscription has actually expired
          if (paymentStatus == 'approved' && subscription['endDate'] != null) {
            DateTime endDate = (subscription['endDate'] as Timestamp).toDate();
            if (DateTime.now().isAfter(endDate)) {
              paymentStatus = 'expired';
            }
          }

          String formattedDate = 'Unknown date';
          if (data['createdAt'] != null) {
            formattedDate = DateFormat('MMM d, yyyy - h:mm a')
                .format((data['createdAt'] as Timestamp).toDate());
          }

          Map<String, dynamic> paymentData = {
            'userId': doc.id,
            'name': data['name'] ?? 'Unknown',
            'email': data['email'] ?? 'No email',
            'planName': subscription['planName'] ?? 'Unknown Plan',
            'planPrice': subscription['price'] ?? 0.0,
            'paymentStatus': paymentStatus,
            'paymentMethod': subscription['paymentMethod'] ?? 'Unknown',
            'paymentProofUrl': subscription['paymentProofUrl'] ?? '',
            'duration': subscription['duration'] ?? '1 month',
            'createdAt': data['createdAt'],
            'formattedDate': formattedDate,
            'isAccountActive': data['isAccountActive'] ?? false,
            'startDate': subscription['startDate'],
            'endDate': subscription['endDate'],
            'rejectionReason': subscription['rejectionReason'],
            'isRenewal': isRenewal,
          };

          // Categorize payments
          if (paymentStatus == 'renew_pending') {
            renew.add(paymentData);
          } else if (paymentStatus == 'pending' && !isRenewal) {
            pending.add(paymentData);
          } else if (paymentStatus == 'approved' &&
              (data['isAccountActive'] ?? false)) {
            active.add(paymentData);
          } else {
            inactive.add(paymentData);
          }
        }
      }

      // Sort all lists by creation date (newest first)
      pending.sort((a, b) =>
          (b['createdAt'] as Timestamp).compareTo(a['createdAt'] as Timestamp));
      active.sort((a, b) =>
          (b['createdAt'] as Timestamp).compareTo(a['createdAt'] as Timestamp));
      inactive.sort((a, b) =>
          (b['createdAt'] as Timestamp).compareTo(a['createdAt'] as Timestamp));
      renew.sort((a, b) =>
          (b['createdAt'] as Timestamp).compareTo(a['createdAt'] as Timestamp));

      setState(() {
        _pendingPayments = pending;
        _activePayments = active;
        _inactivePayments = inactive;
        _renewPayments = renew;
        _filterAllPayments();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading payments: $e');
      setState(() {
        _isLoading = false;
      });
      _handleError('loading payments', e);
    }
  }

  Future<bool> _checkIfRenewal(String email) async {
    try {
      final inactiveQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .where('role', isEqualTo: 'Owner')
          .where('isAccountActive', isEqualTo: false)
          .limit(1)
          .get();

      return inactiveQuery.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _approvePayment(String userId, double price, String planName,
      String duration, String userEmail, String userName) async {
    try {
      EasyLoading.show(status: 'Approving payment...');

      DateTime now = DateTime.now();
      DateTime endDate = now;

      if (duration.contains('month')) {
        int months = int.tryParse(duration.split(' ')[0]) ?? 1;
        endDate = DateTime(now.year, now.month + months, now.day);
      } else if (duration.contains('year')) {
        int years = int.tryParse(duration.split(' ')[0]) ?? 1;
        endDate = DateTime(now.year + years, now.month, now.day);
      }

      WriteBatch batch = _firestore.batch();
      DocumentReference userRef = _firestore.collection('users').doc(userId);

      batch.update(userRef, {
        'subscription.paymentStatus': 'approved',
        'subscription.startDate': now,
        'subscription.endDate': endDate,
        'isAccountActive': true,
      });

      // Add to payment history
      DocumentReference historyRef =
          _firestore.collection('paymentHistory').doc();
      batch.set(historyRef, {
        'userId': userId,
        'amount': price,
        'planName': planName,
        'status': 'approved',
        'processedAt': FieldValue.serverTimestamp(),
        'processedBy': FirebaseAuth.instance.currentUser?.uid,
        'startDate': now,
        'endDate': endDate,
      });

      // Add notification
      DocumentReference notificationRef =
          _firestore.collection('notifications').doc();
      batch.set(notificationRef, {
        'userId': userId,
        'type': 'payment_approved',
        'message':
            'Your payment for $planName plan has been approved. Your subscription is now active until ${DateFormat('MMM d, yyyy').format(endDate)}.',
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'isAdminNotification': false // This goes to owner's notifications
      });

      await batch.commit();

      // Enable related data (toilets and maintainers)
      await _enableRelatedData(userId);

      // Send email notification

      await _loadAllPayments();
      EasyLoading.dismiss();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment approved successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      EasyLoading.dismiss();
      _handleError('approving payment', e);
    }
  }

  Future<void> _rejectPayment(
      String userId, String reason, String userEmail, String userName) async {
    try {
      EasyLoading.show(status: 'Rejecting payment...');

      WriteBatch batch = _firestore.batch();
      DocumentReference userRef = _firestore.collection('users').doc(userId);

      DocumentSnapshot userDoc = await userRef.get();
      final userData = userDoc.data() as Map<String, dynamic>;
      final planName = userData['subscription']['planName'] ?? 'Unknown Plan';
      final price = userData['subscription']['price'] ?? 0.0;

      batch.update(userRef, {
        'subscription.paymentStatus': 'rejected',
        'subscription.rejectionReason': reason,
        'isAccountActive': false,
      });

      // Add to payment history
      DocumentReference historyRef =
          _firestore.collection('paymentHistory').doc();
      batch.set(historyRef, {
        'userId': userId,
        'status': 'rejected',
        'reason': reason,
        'processedAt': FieldValue.serverTimestamp(),
        'processedBy': FirebaseAuth.instance.currentUser?.uid,
      });

      // Add notification
      DocumentReference notificationRef =
          _firestore.collection('notifications').doc();
      batch.set(notificationRef, {
        'userId': userId,
        'type': 'payment_rejected',
        'message': 'Your payment was rejected. Reason: $reason',
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'isAdminNotification': false // This goes to owner's notifications
      });

      await batch.commit();

      // Disable related data
      await _disableRelatedData([userId]);

      // Send email notification

      await _loadAllPayments();
      EasyLoading.dismiss();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment rejected successfully'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      EasyLoading.dismiss();
      _handleError('rejecting payment', e);
    }
  }

  Future<void> _changeToInactive(
      String userId, String userEmail, String userName, String reason) async {
    try {
      EasyLoading.show(status: 'Moving to inactive...');

      WriteBatch batch = _firestore.batch();
      DocumentReference userRef = _firestore.collection('users').doc(userId);

      batch.update(userRef, {
        'subscription.paymentStatus': 'rejected',
        'subscription.rejectionReason': reason,
        'isAccountActive': false,
        'subscription.changedToInactiveAt': FieldValue.serverTimestamp(),
      });

      // Add notification
      DocumentReference notificationRef =
          _firestore.collection('notifications').doc();
      batch.set(notificationRef, {
        'userId': userId,
        'type': 'account_deactivated',
        'message':
            'Your account has been deactivated by admin. Reason: $reason',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
        'isAdminNotification': false // Add this flag
      });

      await batch.commit();

      // Disable related data
      await _disableRelatedData([userId]);
      await _loadAllPayments();
      EasyLoading.dismiss();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved to inactive successfully'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      EasyLoading.dismiss();
      _handleError('moving to inactive', e);
    }
  }

  Future<void> _changeToActive(String userId, String userEmail, String userName,
      String planName, double price, String duration) async {
    try {
      EasyLoading.show(status: 'Activating account...');

      DateTime now = DateTime.now();
      DateTime endDate = now;

      if (duration.contains('month')) {
        int months = int.tryParse(duration.split(' ')[0]) ?? 1;
        endDate = DateTime(now.year, now.month + months, now.day);
      } else if (duration.contains('year')) {
        int years = int.tryParse(duration.split(' ')[0]) ?? 1;
        endDate = DateTime(now.year + years, now.month, now.day);
      }

      WriteBatch batch = _firestore.batch();
      DocumentReference userRef = _firestore.collection('users').doc(userId);

      batch.update(userRef, {
        'subscription.paymentStatus': 'approved',
        'subscription.startDate': now,
        'subscription.endDate': endDate,
        'isAccountActive': true,
        'subscription.rejectionReason':
            FieldValue.delete(), // Clear rejection reason
      });

      // Add notification
      DocumentReference notificationRef =
          _firestore.collection('notifications').doc();
      batch.set(notificationRef, {
        'userId': userId,
        'type': 'account_activated',
        'message':
            'Your account has been activated. Your subscription is now active until ${DateFormat('MMM d, yyyy').format(endDate)}.',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
        'isAdminNotification': false // Add this flag
      });

      await batch.commit();

      // Enable related data
      await _enableRelatedData(userId);

      // Update local state to remove rejection reason
      setState(() {
        // Update in inactive payments
        _inactivePayments.removeWhere((payment) => payment['userId'] == userId);

        // Add to active payments with cleared rejection reason
        final paymentIndex =
            _inactivePayments.indexWhere((p) => p['userId'] == userId);
        if (paymentIndex != -1) {
          var updatedPayment =
              Map<String, dynamic>.from(_inactivePayments[paymentIndex]);
          updatedPayment['paymentStatus'] = 'approved';
          updatedPayment['isAccountActive'] = true;
          updatedPayment.remove('rejectionReason'); // Remove from local data
          _activePayments.add(updatedPayment);
        }
      });

      // Send email notification
      ;
      await _loadAllPayments(); // Refresh all data
      EasyLoading.dismiss();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Account activated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      EasyLoading.dismiss();
      _handleError('activating account', e);
    }
  }

  Future<void> _deleteVerification(
      String userId, String userEmail, String userName) async {
    try {
      EasyLoading.show(status: 'Deleting account...');

      final callable =
          FirebaseFunctions.instance.httpsCallable('deleteUserAccount');
      final result = await callable.call({'userId': userId});

      if (result.data['success'] == true) {
        // Send email notification

        await _loadAllPayments();
        EasyLoading.dismiss();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account deleted successfully'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        EasyLoading.dismiss();
        _handleError('deleting account', 'Failed to delete account');
      }
    } catch (e) {
      EasyLoading.dismiss();
      _handleError('deleting account', e);
    }
  }

  void _handleError(String operation, dynamic error) {
    _firestore.collection('errors').add({
      'operation': operation,
      'error': error.toString(),
      'timestamp': FieldValue.serverTimestamp(),
      'adminId': FirebaseAuth.instance.currentUser?.uid,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error during $operation'),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'DETAILS',
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Error Details'),
                content: SingleChildScrollView(
                  child: Text(error.toString()),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('OK'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showRejectDialog(String userId, String userEmail, String userName) {
    final TextEditingController reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Reject Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Please provide a reason for rejecting this payment:'),
              SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                  hintText: 'E.g., Unclear payment slip, Wrong amount, etc.',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please provide a reason'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
                _rejectPayment(
                    userId, reasonController.text.trim(), userEmail, userName);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('Reject'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(
      String userId, String userName, String userEmail) async {
    // First get counts of related data
    EasyLoading.show(status: 'Checking related data...');

    final toiletsCount = (await _firestore
            .collection('toilets')
            .where('ownerId', isEqualTo: userId)
            .get())
        .docs
        .length;

    final maintainersCount = (await _firestore
            .collection('users')
            .where('role', isEqualTo: 'Maintainer')
            .where('assignedOwnerId', isEqualTo: userId)
            .get())
        .docs
        .length;

    EasyLoading.dismiss();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Permanent Deletion'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Are you sure you want to permanently delete this account and ALL related data?'),
                SizedBox(height: 16),
                Text('This will delete:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('• The user account ($userName)'),
                Text('• $toiletsCount toilet(s) owned by this user'),
                Text(
                    '• $maintainersCount maintainer(s) assigned to this owner'),
                Text('• All reviews for these toilets'),
                SizedBox(height: 16),
                Text('This action cannot be undone!',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteVerification(userId, userEmail, userName);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('Delete Permanently',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showActivateConfirmationDialog(String userId, String userName,
      String userEmail, String planName, double price, String duration) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Activate Account'),
          content: Text(
              'Are you sure you want to activate $userName\'s account? This will start a new subscription period.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _changeToActive(
                    userId, userEmail, userName, planName, price, duration);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: Text('Activate', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showInactiveConfirmationDialog(
      String userId, String userName, String userEmail) {
    final TextEditingController reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Move to Inactive'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'Please provide a reason for moving this account to inactive:'),
              SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                  hintText: 'E.g., Payment issue, Violation of terms, etc.',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please provide a reason'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
                _changeToInactive(
                    userId, userEmail, userName, reasonController.text.trim());
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: Text('Move to Inactive',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showPaymentProof(String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.8,
            child: Column(
              children: [
                AppBar(
                  title: Text('Payment Proof'),
                  leading: IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    IconButton(
                      icon: Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: imageUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('URL copied to clipboard')),
                        );
                      },
                    ),
                  ],
                ),
                Expanded(
                  child: PhotoView(
                    imageProvider: CachedNetworkImageProvider(imageUrl),
                    backgroundDecoration: BoxDecoration(color: Colors.white),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentCard(Map<String, dynamic> payment, String tabType) {
    return Card(
      margin: EdgeInsets.all(8.0),
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with name and status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    payment['name'] ?? 'Unknown',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(payment['paymentStatus']),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    payment['paymentStatus']?.toUpperCase() ?? 'UNKNOWN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),

            // Email
            Row(
              children: [
                Icon(Icons.email, size: 16, color: Colors.grey[600]),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    payment['email'] ?? 'No email',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),

            // Plan details
            Row(
              children: [
                Icon(Icons.subscriptions, size: 16, color: Colors.grey[600]),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${payment['planName']} - \$${payment['planPrice']?.toStringAsFixed(2) ?? '0.00'} (${payment['duration']})',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),

            // Payment method
            Row(
              children: [
                Icon(Icons.payment, size: 16, color: Colors.grey[600]),
                SizedBox(width: 8),
                Text(
                  'Payment Method: ${payment['paymentMethod'] ?? 'Unknown'}',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
            SizedBox(height: 4),

            // Date
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                SizedBox(width: 8),
                Text(
                  'Created: ${payment['formattedDate']}',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),

            // Show subscription dates for active payments
            if (tabType == 'active' &&
                payment['startDate'] != null &&
                payment['endDate'] != null) ...[
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.date_range, size: 16, color: Colors.green[600]),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Active: ${DateFormat('MMM d, yyyy').format((payment['startDate'] as Timestamp).toDate())} - ${DateFormat('MMM d, yyyy').format((payment['endDate'] as Timestamp).toDate())}',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Show rejection reason for rejected payments
            if (payment['rejectionReason'] != null &&
                payment['rejectionReason'].toString().isNotEmpty &&
                tabType != 'active') ...[
              // Added this condition
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  border: Border.all(color: Colors.red[200]!),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: Colors.red[600]),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Rejection Reason: ${payment['rejectionReason']}',
                        style: TextStyle(
                          color: Colors.red[700],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 12),

            // Payment proof and actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Payment proof button
                if (payment['paymentProofUrl'] != null &&
                    payment['paymentProofUrl'].toString().isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () =>
                        _showPaymentProof(payment['paymentProofUrl']),
                    icon: Icon(Icons.image, size: 16),
                    label: Text('View Proof'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  )
                else
                  Text(
                    'No payment proof',
                    style: TextStyle(
                      color: Colors.red[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),

                // Action buttons based on tab
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: _buildActionButtons(payment, tabType),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActionButtons(
      Map<String, dynamic> payment, String tabType) {
    switch (tabType) {
      case 'pending':
      case 'renew':
        return [
          ElevatedButton(
            onPressed: () => _approvePayment(
              payment['userId'],
              payment['planPrice']?.toDouble() ?? 0.0,
              payment['planName'] ?? '',
              payment['duration'] ?? '1 month',
              payment['email'] ?? '',
              payment['name'] ?? '',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: Text('Approve'),
          ),
          SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _showRejectDialog(
              payment['userId'],
              payment['email'] ?? '',
              payment['name'] ?? '',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: Text('Reject'),
          ),
        ];

      case 'active':
        return [
          ElevatedButton(
            onPressed: () => _showInactiveConfirmationDialog(
              payment['userId'],
              payment['name'] ?? '',
              payment['email'] ?? '',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: Text('Move to Inactive'),
          ),
        ];

      case 'inactive':
        return [
          ElevatedButton(
            onPressed: () => _showActivateConfirmationDialog(
              payment['userId'],
              payment['name'] ?? '',
              payment['email'] ?? '',
              payment['planName'] ?? '',
              payment['planPrice']?.toDouble() ?? 0.0,
              payment['duration'] ?? '1 month',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: Text('Activate'),
          ),
          SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _showDeleteConfirmationDialog(
              payment['userId'],
              payment['name'] ?? '',
              payment['email'] ?? '',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: Text('Delete'),
          ),
        ];

      default:
        return [];
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
      case 'expired':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildTabContent(List<Map<String, dynamic>> payments, String tabType) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox,
              size: 64,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16),
            Text(
              'No ${tabType.toLowerCase()} payments found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            if (_searchQuery.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(
                'Try adjusting your search criteria',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllPayments,
      child: ListView.builder(
        itemCount: payments.length,
        itemBuilder: (context, index) {
          return _buildPaymentCard(payments[index], tabType);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Payment Verification'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadAllPayments,
            icon: Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(60),
          child: Padding(
            padding: EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, email, or plan...',
                prefixIcon: Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                        },
                        icon: Icon(Icons.clear),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Tab headers with counts
          Container(
            color: Colors.blue[700],
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: [
                Tab(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Pending'),
                      if (_filteredPending.isNotEmpty)
                        Container(
                          margin: EdgeInsets.only(top: 2),
                          padding:
                              EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_filteredPending.length}',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                Tab(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Active'),
                      if (_filteredActive.isNotEmpty)
                        Container(
                          margin: EdgeInsets.only(top: 2),
                          padding:
                              EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_filteredActive.length}',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                Tab(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Inactive'),
                      if (_filteredInactive.isNotEmpty)
                        Container(
                          margin: EdgeInsets.only(top: 2),
                          padding:
                              EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_filteredInactive.length}',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                Tab(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Renew'),
                      if (_filteredRenew.isNotEmpty)
                        Container(
                          margin: EdgeInsets.only(top: 2),
                          padding:
                              EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_filteredRenew.length}',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabContent(_filteredPending, 'pending'),
                _buildTabContent(_filteredActive, 'active'),
                _buildTabContent(_filteredInactive, 'inactive'),
                _buildTabContent(_filteredRenew, 'renew'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
