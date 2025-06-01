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

class AdminPaymentVerificationScreen extends StatefulWidget {
  @override
  _AdminPaymentVerificationScreenState createState() =>
      _AdminPaymentVerificationScreenState();
}

class _AdminPaymentVerificationScreenState
    extends State<AdminPaymentVerificationScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  List<Map<String, dynamic>> _pendingPayments = [];
  List<Map<String, dynamic>> _filteredPayments = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';
  final List<String> _filterOptions = [
    'All',
    'Pending',
    'Approved',
    'Rejected'
  ];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadPendingPayments();
    _ensureNotificationsCollectionExists();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
        _filterPayments();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterPayments() {
    if (_selectedFilter == 'All' && _searchQuery.isEmpty) {
      _filteredPayments = List.from(_pendingPayments);
    } else {
      _filteredPayments = _pendingPayments.where((payment) {
        bool matchesStatus = _selectedFilter == 'All' ||
            payment['paymentStatus'].toLowerCase() ==
                _selectedFilter.toLowerCase();

        if (!matchesStatus) return false;

        if (_searchQuery.isEmpty) return true;

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
  }

  // Add this with other state variables
  final Map<String, bool> _emailDeliveryStatus = {};

// Add these new methods
  Future<bool> _verifyEmailDelivery(
      String userId, String notificationId) async {
    try {
      // Check delivery status every 2 seconds for up to 10 seconds
      for (int i = 0; i < 5; i++) {
        await Future.delayed(Duration(seconds: 2));

        final doc = await _firestore
            .collection('notifications')
            .doc(notificationId)
            .get();
        if (doc.exists && doc.data()?['emailDelivered'] == true) {
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error verifying email delivery: $e');
      return false;
    }
  }

  void _showEmailDeliveryStatus(String userId, bool success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Email notification sent successfully'
            : 'Email notification failed to send (queued for retry)'),
        backgroundColor: success ? Colors.green : Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
    setState(() {
      _emailDeliveryStatus[userId] = success;
    });
  }

  Future<void> _ensureNotificationsCollectionExists() async {
    try {
      await _firestore.collection('notifications').limit(1).get();
      return;
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

  void _logAction(String action, String userId,
      [Map<String, dynamic>? extraData]) {
    final Map<String, dynamic> logData = {
      'action': action,
      'timestamp': FieldValue.serverTimestamp(),
      'adminId': FirebaseAuth.instance.currentUser?.uid,
      'userId': userId,
      ...?extraData,
    };

    _firestore.collection('activityLogs').add(logData).catchError((error) {
      print('Error writing log: $error');
    });
  }

  Future<void> _sendEmailNotification(
      String userEmail, String subject, String message) async {
    try {
      final HttpsCallable callable =
      _functions.httpsCallable('sendEmailNotification');
      await callable.call({
        'email': userEmail,
        'subject': subject,
        'message': message,
        'type': 'payment_verification'
      });
    } on PlatformException catch (e) {
      print('Platform error sending email: ${e.message}');
      await _queueEmailNotification(userEmail, subject, message);
    } catch (e) {
      print('Error sending email notification: $e');
      await _queueEmailNotification(userEmail, subject, message);
    }
  }

  Future<void> _queueEmailNotification(
      String userEmail, String subject, String message) async {
    try {
      await _firestore.collection('email_queue').add({
        'email': userEmail,
        'subject': subject,
        'message': message,
        'type': 'payment_verification',
        'createdAt': FieldValue.serverTimestamp(),
        'attempts': 0,
        'status': 'pending'
      });
    } catch (e) {
      print('Failed to queue email: $e');
      _handleError('queueing email notification', e);
    }
  }

  void _handleError(String operation, dynamic error) {
    _firestore.collection('errors').add({
      'operation': operation,
      'error': error.toString(),
      'timestamp': FieldValue.serverTimestamp(),
      'adminId': FirebaseAuth.instance.currentUser?.uid,
    }).catchError((e) {
      print('Failed to log error to Firestore: $e');
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error during $operation: ${error.toString()}'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
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

  Future<void> _loadPendingPayments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      QuerySnapshot snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'Owner')
          .get();

      List<Map<String, dynamic>> payments = [];

      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        if (data.containsKey('subscription')) {
          Map<String, dynamic> subscription = data['subscription'];

          String formattedDate = 'Unknown date';
          if (data['createdAt'] != null) {
            formattedDate = DateFormat('MMM d, yyyy - h:mm a')
                .format((data['createdAt'] as Timestamp).toDate());
          }

          payments.add({
            'userId': doc.id,
            'name': data['name'] ?? 'Unknown',
            'email': data['email'] ?? 'No email',
            'planName': subscription['planName'] ?? 'Unknown Plan',
            'planPrice': subscription['price'] ?? 0.0,
            'paymentStatus': subscription['paymentStatus'] ?? 'pending',
            'paymentMethod': subscription['paymentMethod'] ?? 'Unknown',
            'paymentProofUrl': subscription['paymentProofUrl'] ?? '',
            'duration': subscription['duration'] ?? '1 month',
            'createdAt': data['createdAt'],
            'formattedDate': formattedDate,
            'isAccountActive': data['isAccountActive'] ?? false,
          });
        }
      }

      payments.sort((a, b) {
        Timestamp timestampA = a['createdAt'] ?? Timestamp.now();
        Timestamp timestampB = b['createdAt'] ?? Timestamp.now();
        return timestampB.compareTo(timestampA);
      });

      setState(() {
        _pendingPayments = payments;
        _filterPayments();
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

  Future<void> _approvePayment(String userId, double price, String planName,
      String duration, String userEmail) async {
    try {
      EasyLoading.show(status: 'Approving payment...');
      _logAction('approve_payment_start', userId,
          {'planName': planName, 'price': price, 'duration': duration});

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

      DocumentReference notificationRef =
      _firestore.collection('notifications').doc();
      batch.set(notificationRef, {
        'userId': userId,
        'type': 'payment_approved',
        'message':
        'Your payment for $planName plan has been approved. Your subscription is now active until ${DateFormat('MMM d, yyyy').format(endDate)}.',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false
      });

      await batch.commit();

      _logAction('approve_payment_success', userId, {
        'planName': planName,
        'price': price,
        'notificationId': notificationRef.id
      });

      String emailSubject = 'Payment Approved - Subscription Activated';
      String emailMessage = '''
Dear Valued Customer,

We are pleased to inform you that your payment for the $planName plan has been successfully approved.

Payment Details:
- Plan: $planName
- Amount: \$${price.toStringAsFixed(2)}
- Duration: $duration
- Start Date: ${DateFormat('MMM d, yyyy').format(now)}
- End Date: ${DateFormat('MMM d, yyyy').format(endDate)}

Your account has now been fully activated, and you can access all the features of your subscription. 

If you have any questions or need assistance, please don't hesitate to contact our support team.

Thank you for choosing our service!

Best regards,
The Support Team
''';

      await _sendEmailNotification(userEmail, emailSubject, emailMessage);
      await _loadPendingPayments();
      EasyLoading.dismiss();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment approved and notification sent'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      EasyLoading.dismiss();
      _logAction('approve_payment_error', userId,
          {'error': e.toString(), 'planName': planName, 'price': price});
      _handleError('approving payment', e);
    }
  }

  Future<void> _rejectPayment(
      String userId, String reason, String userEmail) async {
    try {
      EasyLoading.show(status: 'Rejecting payment...');
      _logAction('reject_payment_start', userId, {'reason': reason});

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

      DocumentReference historyRef =
      _firestore.collection('paymentHistory').doc();
      batch.set(historyRef, {
        'userId': userId,
        'status': 'rejected',
        'reason': reason,
        'processedAt': FieldValue.serverTimestamp(),
        'processedBy': FirebaseAuth.instance.currentUser?.uid,
      });

      DocumentReference notificationRef =
      _firestore.collection('notifications').doc();
      batch.set(notificationRef, {
        'userId': userId,
        'type': 'payment_rejected',
        'message': 'Your payment was rejected. Reason: $reason',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false
      });

      await batch.commit();
      _logAction('reject_payment_success', userId,
          {'reason': reason, 'notificationId': notificationRef.id});

      String emailSubject = 'Payment Rejected - Action Required';
      String emailMessage = '''
Dear Customer,

We regret to inform you that your payment for the $planName plan (\$${price.toStringAsFixed(2)}) has been rejected.

Reason for rejection: 
$reason

Next Steps:
1. Please review the reason for rejection above.
2. Ensure your payment meets all requirements.
3. You may submit a new payment through your account dashboard.

If you believe this is an error or need assistance with your payment, please contact our support team immediately.

We apologize for any inconvenience and appreciate your understanding.

Best regards,
The Support Team
''';

      await _sendEmailNotification(userEmail, emailSubject, emailMessage);
      await _loadPendingPayments();
      EasyLoading.dismiss();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment rejected and notification sent'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      EasyLoading.dismiss();
      _logAction('reject_payment_error', userId,
          {'error': e.toString(), 'reason': reason});
      _handleError('rejecting payment', e);
    }
  }

  Future<void> _deletePaymentVerification(
      String userId, String userEmail, String userName) async {
    try {
      EasyLoading.show(status: 'Deleting payment verification...');
      _logAction('delete_payment_verification_start', userId);

      WriteBatch batch = _firestore.batch();
      DocumentReference userRef = _firestore.collection('users').doc(userId);

      DocumentSnapshot userDoc = await userRef.get();
      final userData = userDoc.data() as Map<String, dynamic>;
      final planName = userData['subscription']['planName'] ?? 'Unknown Plan';

      batch.update(userRef, {
        'subscription': FieldValue.delete(),
        'isAccountActive': false,
      });

      DocumentReference historyRef =
      _firestore.collection('paymentHistory').doc();
      batch.set(historyRef, {
        'userId': userId,
        'action': 'verification_deleted',
        'processedAt': FieldValue.serverTimestamp(),
        'processedBy': FirebaseAuth.instance.currentUser?.uid,
        'notes': 'Payment verification deleted by admin'
      });

      DocumentReference notificationRef =
      _firestore.collection('notifications').doc();
      batch.set(notificationRef, {
        'userId': userId,
        'type': 'payment_verification_deleted',
        'message': 'Your payment verification has been deleted by admin.',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false
      });

      await batch.commit();
      _logAction('delete_payment_verification_success', userId,
          {'notificationId': notificationRef.id});

      String emailSubject = 'Payment Verification Deleted';
      String emailMessage = '''Dear $userName,

This is to inform you that your payment verification for the $planName plan has been deleted by an administrator.

Action Required:
- If you wish to continue using our services, please submit a new payment through your account dashboard.
- Ensure all payment details are correct before submission.

For any questions or concerns regarding this action, please contact our support team.

We appreciate your understanding.

Best regards,
The Support Team
''';

      await _sendEmailNotification(userEmail, emailSubject, emailMessage);
      await _loadPendingPayments();
      EasyLoading.dismiss();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment verification deleted and notification sent'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      EasyLoading.dismiss();
      _logAction(
          'delete_payment_verification_error', userId, {'error': e.toString()});
      _handleError('deleting payment verification', e);
    }
  }

  void _showRejectDialog(String userId, String userEmail) {
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
                _rejectPayment(userId, reasonController.text.trim(), userEmail);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: Text('Reject'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(
      String userId, String userName, String userEmail) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Delete Payment Verification'),
          content: Text(
              'Are you sure you want to delete the payment verification for $userName? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _deletePaymentVerification(userId, userEmail, userName);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showPaymentProof(
      String imageUrl, String userName, String planName, double price) {
    if (imageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No payment slip attached'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    EasyLoading.show(status: 'Loading payment slip...');

    CachedNetworkImageProvider(imageUrl)
        .resolve(ImageConfiguration())
        .addListener(
      ImageStreamListener(
            (info, _) {
          EasyLoading.dismiss();
          _showPaymentProofDialog(imageUrl, userName, planName, price);
        },
        onError: (exception, stackTrace) {
          EasyLoading.dismiss();
          _handleError('loading payment slip', exception);
        },
      ),
    );
  }

  void _showPaymentProofDialog(
      String imageUrl, String userName, String planName, double price) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Payment Receipt',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Divider(),
                SizedBox(height: 8),
                Text(
                  'User: $userName',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Plan: $planName (${NumberFormat.currency(symbol: '\$').format(price)})',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 16),
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: PhotoView(
                        imageProvider: CachedNetworkImageProvider(
                          imageUrl,
                          maxHeight: 1000,
                          maxWidth: 1000,
                        ),
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.covered * 2,
                        backgroundDecoration: BoxDecoration(
                          color: Colors.transparent,
                        ),
                        loadingBuilder: (context, event) => Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              if (event != null &&
                                  event.expectedTotalBytes != null)
                                Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Loading payment slip: ${(event.cumulativeBytesLoaded / event.expectedTotalBytes! * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error, color: Colors.red, size: 48),
                              SizedBox(height: 8),
                              Text('Failed to load payment slip',
                                  style: TextStyle(color: Colors.red)),
                              SizedBox(height: 4),
                              Container(
                                padding: EdgeInsets.all(8),
                                margin: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  error.toString(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              SizedBox(height: 8),
                              ElevatedButton.icon(
                                icon: Icon(Icons.refresh),
                                label: Text('Try Again'),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showPaymentProof(
                                      imageUrl, userName, planName, price);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Center(
                  child: Text(
                    '* Pinch to zoom, drag to pan *',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      icon: Icon(Icons.check, size: 18),
                      label: Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        final payment = _pendingPayments.firstWhere(
                              (p) =>
                          p['name'] == userName &&
                              p['planName'] == planName,
                          orElse: () => {},
                        );
                        if (payment.isNotEmpty) {
                          _approvePayment(
                            payment['userId'],
                            payment['planPrice'],
                            payment['planName'],
                            payment['duration'],
                            payment['email'],
                          );
                        }
                      },
                    ),
                    ElevatedButton.icon(
                      icon: Icon(Icons.close, size: 18),
                      label: Text('Reject'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        final payment = _pendingPayments.firstWhere(
                              (p) =>
                          p['name'] == userName &&
                              p['planName'] == planName,
                          orElse: () => {},
                        );
                        if (payment.isNotEmpty) {
                          _showRejectDialog(
                              payment['userId'], payment['email']);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Payment Verification'),
        backgroundColor: Color(0xFF2E86DE),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.notifications),
            tooltip: 'Check notifications',
            onPressed: _checkNotificationStatus,
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            tooltip: 'Refresh payments',
            onPressed: _loadPendingPayments,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            color: Color(0xFF2E86DE).withOpacity(0.1),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name, email or plan',
                    prefixIcon: Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Filter: ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedFilter,
                            isExpanded: true,
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedFilter = newValue;
                                  _filterPayments();
                                });
                              }
                            },
                            items: _filterOptions
                                .map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            color: Colors.grey[100],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatCard(
                  'Pending',
                  _pendingPayments
                      .where((p) => p['paymentStatus'] == 'pending')
                      .length
                      .toString(),
                  Colors.orange,
                ),
                _buildStatCard(
                  'Approved',
                  _pendingPayments
                      .where((p) => p['paymentStatus'] == 'approved')
                      .length
                      .toString(),
                  Colors.green,
                ),
                _buildStatCard(
                  'Rejected',
                  _pendingPayments
                      .where((p) => p['paymentStatus'] == 'rejected')
                      .length
                      .toString(),
                  Colors.red,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _filteredPayments.isEmpty
                ? Center(
              child: Text(
                'No payment records found',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            )
                : RefreshIndicator(
              onRefresh: _loadPendingPayments,
              child: ListView.builder(
                itemCount: _filteredPayments.length,
                itemBuilder: (context, index) {
                  final payment = _filteredPayments[index];
                  return _buildPaymentCard(payment);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String count, Color color) {
    return Column(
      children: [
        Text(
          count,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentCard(Map<String, dynamic> payment) {
    Color statusColor;
    IconData statusIcon;

    switch (payment['paymentStatus']) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
    }

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: payment['paymentStatus'] == 'pending'
              ? Colors.orange.withOpacity(0.5)
              : Colors.grey.withOpacity(0.2),
          width: payment['paymentStatus'] == 'pending' ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: Color(0xFF2E86DE).withOpacity(0.1),
              child: Icon(
                Icons.person,
                color: Color(0xFF2E86DE),
              ),
            ),
            title: Text(
              payment['name'],
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 4),
                Text(payment['email']),
                SizedBox(height: 4),
                Text(
                  'Submitted: ${payment['formattedDate']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  statusIcon,
                  color: statusColor,
                ),
                SizedBox(width: 8),
                Text(
                  payment['paymentStatus'].toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1),
          if (payment['paymentProofUrl'] != null &&
              payment['paymentProofUrl'].isNotEmpty)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment Slip:',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(color: Colors.grey[200]),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: CachedNetworkImage(
                            imageUrl: payment['paymentProofUrl'],
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF2E86DE)),
                              ),
                            ),
                            errorWidget: (context, url, error) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.broken_image,
                                        color: Colors.red, size: 32),
                                    SizedBox(height: 8),
                                    Padding(
                                      padding:
                                      EdgeInsets.symmetric(horizontal: 8),
                                      child: Text(
                                        'Could not load payment slip',
                                        textAlign: TextAlign.center,
                                        style:
                                        TextStyle(color: Colors.red[700]),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(7),
                            onTap: () => _showPaymentProof(
                              payment['paymentProofUrl'],
                              payment['name'],
                              payment['planName'],
                              payment['planPrice'],
                            ),
                            child: Center(
                              child: Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.zoom_in,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Plan: ${payment['planName']}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      NumberFormat.currency(symbol: '\$')
                          .format(payment['planPrice']),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Color(0xFF2E86DE),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text('Payment Method: ${payment['paymentMethod']}'),
                SizedBox(height: 16),
                if (payment['paymentProofUrl'] != null &&
                    payment['paymentProofUrl'].isNotEmpty)
                  Container(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showPaymentProof(
                        payment['paymentProofUrl'],
                        payment['name'],
                        payment['planName'],
                        payment['planPrice'],
                      ),
                      icon: Icon(Icons.receipt_long),
                      label: Text('View Payment Slip'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF2E86DE),
                        padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                if (payment['paymentStatus'] == 'pending')
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _approvePayment(
                              payment['userId'],
                              payment['planPrice'],
                              payment['planName'],
                              payment['duration'],
                              payment['email'],
                            ),
                            icon: Icon(Icons.check),
                            label: Text('Approve'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showRejectDialog(
                                payment['userId'], payment['email']),
                            icon: Icon(Icons.close, color: Colors.red),
                            label: Text(
                              'Reject',
                              style: TextStyle(color: Colors.red),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.red),
                              padding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (payment['paymentStatus'] != 'pending')
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (payment['paymentStatus'] == 'approved') {
                                    _showRejectDialog(
                                        payment['userId'], payment['email']);
                                  } else {
                                    await _approvePayment(
                                      payment['userId'],
                                      payment['planPrice'],
                                      payment['planName'],
                                      payment['duration'],
                                      payment['email'],
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  payment['paymentStatus'] == 'approved'
                                      ? Colors.red.withOpacity(0.8)
                                      : Colors.green,
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: Text(
                                    payment['paymentStatus'] == 'approved'
                                        ? 'Change to Rejected'
                                        : 'Change to Approved'),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _showDeleteConfirmationDialog(
                              payment['userId'],
                              payment['name'],
                              payment['email']),
                          icon: Icon(Icons.delete, color: Colors.red),
                          label: Text(
                            'Delete Verification',
                            style: TextStyle(color: Colors.red),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.red),
                            padding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkNotificationStatus() async {
    try {
      EasyLoading.show(status: 'Checking notifications...');
      QuerySnapshot snapshot = await _firestore
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      List<Map<String, dynamic>> recentNotifications = snapshot.docs
          .map((doc) => {
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      })
          .toList();

      EasyLoading.dismiss();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Recent Notifications'),
          content: Container(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: recentNotifications.length,
              itemBuilder: (context, index) {
                final notification = recentNotifications[index];
                final DateTime? createdAt = notification['createdAt'] != null
                    ? (notification['createdAt'] as Timestamp).toDate()
                    : null;
                return ListTile(
                  title: Text(notification['message'] ?? 'No message'),
                  subtitle: Text(
                      'User ID: ${notification['userId'] ?? 'Unknown'}\n'
                          'Type: ${notification['type'] ?? 'Unknown'}\n'
                          'Date: ${createdAt != null ? DateFormat('MMM d, yyyy • h:mm a').format(createdAt) : 'Unknown'}'),
                  trailing: notification['read'] == true
                      ? Icon(Icons.check_circle, color: Colors.green)
                      : Icon(Icons.circle, color: Colors.red),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CLOSE'),
            ),
          ],
        ),
      );
    } catch (e) {
      EasyLoading.dismiss();
      _handleError('checking notifications', e);
    }
  }
}