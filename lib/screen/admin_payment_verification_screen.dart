import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'dart:async';

import 'package:photo_view/photo_view.dart';

class AdminPaymentVerificationScreen extends StatefulWidget {
  @override
  _AdminPaymentVerificationScreenState createState() =>
      _AdminPaymentVerificationScreenState();
}

class _AdminPaymentVerificationScreenState
    extends State<AdminPaymentVerificationScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
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

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadPendingPayments();
    _ensureNotificationsCollectionExists();

    // Add listener for search
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
        // First apply status filter
        bool matchesStatus = _selectedFilter == 'All' ||
            payment['paymentStatus'].toLowerCase() ==
                _selectedFilter.toLowerCase();

        // Then apply search text filter
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

  // Helper method to verify if notifications collection exists and create it if needed
  Future<void> _ensureNotificationsCollectionExists() async {
    try {
      // Check if the notifications collection exists
      final notificationsCollection =
          await _firestore.collection('notifications').limit(1).get();

      // If no error was thrown, the collection exists (even if empty)
      return;
    } catch (e) {
      // If an error was thrown, the collection might not exist
      // Create a dummy document to ensure the collection exists
      await _firestore.collection('notifications').doc('dummy').set({
        'type': 'system',
        'message': 'Notifications collection initialization',
        'createdAt': FieldValue.serverTimestamp(),
        'read': true
      });

      // Then delete the dummy document
      await _firestore.collection('notifications').doc('dummy').delete();

      print('Notifications collection created successfully');
    }
  }

  // Logging helper function for better debugging
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

  // Error handling helper function
  void _handleError(String operation, dynamic error) {
    // Log error to Firestore
    _firestore.collection('errors').add({
      'operation': operation,
      'error': error.toString(),
      'timestamp': FieldValue.serverTimestamp(),
      'adminId': FirebaseAuth.instance.currentUser?.uid,
    }).catchError((e) {
      // If we can't even log to Firestore, just print to console
      print('Failed to log error to Firestore: $e');
    });

    // Display error to user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error during $operation: ${error.toString()}'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
        action: SnackBarAction(
          label: 'DETAILS',
          onPressed: () {
            // Show detailed error dialog
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
      // Query Firestore for all user accounts with subscription info
      QuerySnapshot snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'Owner')
          .get();

      List<Map<String, dynamic>> payments = [];

      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        // Only include users with subscription data
        if (data.containsKey('subscription')) {
          Map<String, dynamic> subscription = data['subscription'];

          // Add relevant data to our list
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
            'isAccountActive': data['isAccountActive'] ?? false,
          });
        }
      }

      // Sort by creation date, newest first
      payments.sort((a, b) {
        Timestamp timestampA = a['createdAt'] ?? Timestamp.now();
        Timestamp timestampB = b['createdAt'] ?? Timestamp.now();
        return timestampB.compareTo(timestampA);
      });

      setState(() {
        _pendingPayments = payments;
        _filterPayments(); // Apply existing search filter
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

  Future<void> _approvePayment(
      String userId, double price, String planName, String duration) async {
    try {
      EasyLoading.show(status: 'Approving payment...');

      _logAction('approve_payment_start', userId,
          {'planName': planName, 'price': price, 'duration': duration});

      // Calculate subscription dates
      DateTime now = DateTime.now();
      DateTime endDate = now;

      // Add months based on duration (assuming format like "1 month", "3 months", etc.)
      if (duration.contains('month')) {
        int months = int.tryParse(duration.split(' ')[0]) ?? 1;
        endDate = DateTime(now.year, now.month + months, now.day);
      } else if (duration.contains('year')) {
        int years = int.tryParse(duration.split(' ')[0]) ?? 1;
        endDate = DateTime(now.year + years, now.month, now.day);
      }

      // Create a batch for atomic operations
      WriteBatch batch = _firestore.batch();

      // Reference to user document
      DocumentReference userRef = _firestore.collection('users').doc(userId);

      // Update the user document
      batch.update(userRef, {
        'subscription.paymentStatus': 'approved',
        'subscription.startDate': now,
        'subscription.endDate': endDate,
        'isAccountActive': true,
      });

      // Create payment history document
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

      // Create notification document
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

      // Commit all the operations as a single transaction
      await batch.commit();

      _logAction('approve_payment_success', userId, {
        'planName': planName,
        'price': price,
        'notificationId': notificationRef.id
      });

      // Refresh the list
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

  Future<void> _rejectPayment(String userId, String reason) async {
    try {
      EasyLoading.show(status: 'Rejecting payment...');

      _logAction('reject_payment_start', userId, {'reason': reason});

      // Create a batch for atomic operations
      WriteBatch batch = _firestore.batch();

      // Reference to user document
      DocumentReference userRef = _firestore.collection('users').doc(userId);

      // Update the user document
      batch.update(userRef, {
        'subscription.paymentStatus': 'rejected',
        'subscription.rejectionReason': reason,
        'isAccountActive': false,
      });

      // Create payment history document
      DocumentReference historyRef =
          _firestore.collection('paymentHistory').doc();
      batch.set(historyRef, {
        'userId': userId,
        'status': 'rejected',
        'reason': reason,
        'processedAt': FieldValue.serverTimestamp(),
        'processedBy': FirebaseAuth.instance.currentUser?.uid,
      });

      // Create notification document
      DocumentReference notificationRef =
          _firestore.collection('notifications').doc();
      batch.set(notificationRef, {
        'userId': userId,
        'type': 'payment_rejected',
        'message': 'Your payment was rejected. Reason: $reason',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false
      });

      // Commit all the operations as a single transaction
      await batch.commit();

      _logAction('reject_payment_success', userId,
          {'reason': reason, 'notificationId': notificationRef.id});

      // Refresh the list
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

  // New method to delete payment verification
  Future<void> _deletePaymentVerification(String userId) async {
    try {
      EasyLoading.show(status: 'Deleting payment verification...');

      _logAction('delete_payment_verification_start', userId);

      // Create a batch for atomic operations
      WriteBatch batch = _firestore.batch();

      // Reference to user document
      DocumentReference userRef = _firestore.collection('users').doc(userId);

      // Remove the subscription field from the user document
      batch.update(userRef, {
        'subscription': FieldValue.delete(),
        'isAccountActive': false,
      });

      // Create payment history document for deletion
      DocumentReference historyRef =
          _firestore.collection('paymentHistory').doc();
      batch.set(historyRef, {
        'userId': userId,
        'action': 'verification_deleted',
        'processedAt': FieldValue.serverTimestamp(),
        'processedBy': FirebaseAuth.instance.currentUser?.uid,
        'notes': 'Payment verification deleted by admin'
      });

      // Create notification document
      DocumentReference notificationRef =
          _firestore.collection('notifications').doc();
      batch.set(notificationRef, {
        'userId': userId,
        'type': 'payment_verification_deleted',
        'message': 'Your payment verification has been deleted by admin.',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false
      });

      // Commit all the operations as a single transaction
      await batch.commit();

      _logAction('delete_payment_verification_success', userId,
          {'notificationId': notificationRef.id});

      // Refresh the list
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

  void _showRejectDialog(String userId) {
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
                _rejectPayment(userId, reasonController.text.trim());
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

  // Show delete confirmation dialog
  void _showDeleteConfirmationDialog(String userId, String userName) {
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
                _deletePaymentVerification(userId);
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

  // Improved _showPaymentProof method for better image handling
  void _showPaymentProof(
      String imageUrl, String userName, String planName, double price) {
    // First, check if the URL is valid
    if (imageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No payment slip attached'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    print('Attempting to load image from URL: $imageUrl');

    // Add loading indicator before showing the dialog
    EasyLoading.show(status: 'Loading payment slip...');

    // First try to download the image to check if it exists and is accessible
    CachedNetworkImageProvider(imageUrl)
        .resolve(ImageConfiguration())
        .addListener(
          ImageStreamListener(
            (info, _) {
              // Image loaded successfully, show the dialog
              EasyLoading.dismiss();
              _showPaymentProofDialog(imageUrl, userName, planName, price);
            },
            onError: (exception, stackTrace) {
              // Handle error case
              EasyLoading.dismiss();
              _handleError('loading payment slip', exception);
            },
          ),
        );
  }

  // Extracted dialog to separate method
  void _showPaymentProofDialog(
      String imageUrl, String userName, String planName, double price) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
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
                    Row(
                      children: [
                        // Edit button
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.blue),
                          tooltip: 'Edit receipt details',
                          onPressed: () {
                            Navigator.pop(context);
                            _showEditPaymentDialog(userName, planName, price);
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
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
                          // Add more configuration parameters for caching
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
              ],
            ),
          ),
        );
      },
    );
  }

  // New method to change payment status (Approved → Rejected or Rejected → Approved)
  Future<void> _changePaymentStatus(String userId, String currentStatus,
      String planName, double price, String duration) async {
    if (currentStatus == 'approved') {
      // If currently approved, show reject dialog
      _showRejectDialog(userId);
    } else if (currentStatus == 'rejected') {
      // If currently rejected, approve it
      _approvePayment(userId, price, planName, duration);
    }
  }

  Future<void> _saveEditedPaymentDetails(
      String userId, String planName, double price) async {
    try {
      EasyLoading.show(status: 'Updating payment details...');

      _logAction('edit_payment_details_start', userId,
          {'planName': planName, 'price': price});

      // Create a batch for atomic operations
      WriteBatch batch = _firestore.batch();

      // Reference to user document
      DocumentReference userRef = _firestore.collection('users').doc(userId);

      // Update the user document with new plan details
      batch.update(userRef, {
        'subscription.planName': planName,
        'subscription.price': price,
        'subscription.lastUpdated': FieldValue.serverTimestamp(),
        'subscription.updatedBy': FirebaseAuth.instance.currentUser?.uid,
      });

      // Create payment history document
      DocumentReference historyRef =
          _firestore.collection('paymentHistory').doc();
      batch.set(historyRef, {
        'userId': userId,
        'action': 'details_updated',
        'planName': planName,
        'price': price,
        'processedAt': FieldValue.serverTimestamp(),
        'processedBy': FirebaseAuth.instance.currentUser?.uid,
        'notes': 'Payment details updated by admin'
      });

      // Create notification document
      DocumentReference notificationRef =
          _firestore.collection('notifications').doc();
      batch.set(notificationRef, {
        'userId': userId,
        'type': 'payment_details_updated',
        'message':
            'Your payment details have been updated. New plan: $planName, price: ${NumberFormat.currency(symbol: '\$').format(price)}.',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false
      });

      // Commit all the operations as a single transaction
      await batch.commit();

      _logAction('edit_payment_details_success', userId, {
        'planName': planName,
        'price': price,
        'notificationId': notificationRef.id
      });

      // Refresh the list
      await _loadPendingPayments();

      EasyLoading.dismiss();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment details updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      EasyLoading.dismiss();
      _logAction('edit_payment_details_error', userId,
          {'error': e.toString(), 'planName': planName, 'price': price});
      _handleError('updating payment details', e);
    }
  }

  void _showEditPaymentDialog(String userName, String planName, double price) {
    final TextEditingController planController =
        TextEditingController(text: planName);
    final TextEditingController priceController =
        TextEditingController(text: price.toString());

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Edit Payment Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('User: $userName',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              TextField(
                controller: planController,
                decoration: InputDecoration(
                  labelText: 'Plan Name',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Price',
                  border: OutlineInputBorder(),
                  prefixText: '\$',
                ),
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
                // Implement saving the edited details
                final String newPlan = planController.text.trim();
                final double newPrice =
                    double.tryParse(priceController.text) ?? price;

                if (newPlan.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Plan name cannot be empty')),
                  );
                  return;
                }

                Navigator.pop(context);

                // Find the userId for this user
                final matchingPayments = _pendingPayments
                    .where((payment) =>
                        payment['name'] == userName &&
                        payment['planName'] == planName &&
                        payment['planPrice'] == price)
                    .toList();

                if (matchingPayments.isNotEmpty) {
                  _saveEditedPaymentDetails(
                      matchingPayments.first['userId'], newPlan, newPrice);
                } else {
                  _handleError('finding user payment record',
                      'Could not find user payment record for $userName with plan $planName');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: Text('Save Changes'),
            ),
          ],
        );
      },
    );
  }

  // Method to show status change dialog
  void _showStatusChangeDialog(Map<String, dynamic> payment) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Change Payment Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('User: ${payment['name']}'),
              SizedBox(height: 8),
              Text('Current Status: ${payment['paymentStatus'].toUpperCase()}'),
              SizedBox(height: 16),
              Text('Are you sure you want to change the payment status?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _changePaymentStatus(
                  payment['userId'],
                  payment['paymentStatus'],
                  payment['planName'],
                  payment['planPrice'],
                  payment['duration'],
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: payment['paymentStatus'] == 'approved'
                    ? Colors.red
                    : Colors.green,
              ),
              child: Text(payment['paymentStatus'] == 'approved'
                  ? 'Change to Rejected'
                  : 'Change to Approved'),
            ),
          ],
        );
      },
    );
  }

  // Method to check notification status
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

      // Show recent notifications in a dialog
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Payment Verification'),
        backgroundColor: Color(0xFF2E86DE),
        elevation: 0,
        actions: [
          // Add notification check button
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
          // Search & Filter Container
          Container(
            padding: EdgeInsets.all(16),
            color: Color(0xFF2E86DE).withOpacity(0.1),
            child: Column(
              children: [
                // Search bar
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

                // Filter dropdown
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

          // Stats summary
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

          // Payment list
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

    // Format timestamp
    String dateString = 'Unknown date';
    if (payment['createdAt'] != null) {
      Timestamp timestamp = payment['createdAt'];
      DateTime dateTime = timestamp.toDate();
      dateString = DateFormat('MMM d, yyyy • h:mm a').format(dateTime);
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
                  'Submitted: $dateString',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            trailing: GestureDetector(
              onTap: () {
                // Only allow changing approved or rejected statuses
                if (payment['paymentStatus'] != 'pending') {
                  _showStatusChangeDialog(payment);
                }
              },
              child: Row(
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
                  // Add edit icon for non-pending payments
                  if (payment['paymentStatus'] != 'pending')
                    Icon(
                      Icons.edit,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1),
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

                // Show payment proof button if URL exists
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

                // Action buttons for pending payments
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
                            onPressed: () =>
                                _showRejectDialog(payment['userId']),
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

                // Action buttons for non-pending payments
                if (payment['paymentStatus'] != 'pending')
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _showStatusChangeDialog(payment),
                                icon: payment['paymentStatus'] == 'approved'
                                    ? Icon(Icons.cancel)
                                    : Icon(Icons.check_circle),
                                label: Text(
                                    payment['paymentStatus'] == 'approved'
                                        ? 'Change to Rejected'
                                        : 'Change to Approved'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      payment['paymentStatus'] == 'approved'
                                          ? Colors.red.withOpacity(0.8)
                                          : Colors.green,
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _showDeleteConfirmationDialog(
                              payment['userId'], payment['name']),
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
}
