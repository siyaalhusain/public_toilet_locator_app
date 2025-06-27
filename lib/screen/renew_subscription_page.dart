import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class SubscriptionPlan {
  final String id;
  final String name;
  final String description;
  final double price;
  final String duration;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.duration,
  });
}

class RenewSubscriptionPage extends StatefulWidget {
  @override
  _RenewSubscriptionPageState createState() => _RenewSubscriptionPageState();
}

class _RenewSubscriptionPageState extends State<RenewSubscriptionPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  File? _paymentSlip;
  bool _isLoading = false;
  bool _showPaymentOptions = false;
  SubscriptionPlan? _selectedPlan;

  // Hardcoded subscription plans
  final List<SubscriptionPlan> _subscriptionPlans = [
    SubscriptionPlan(
      id: 'basic',
      name: 'Basic',
      description: 'List up to 2 restrooms',
      price: 1000.0,
      duration: '1 month',
    ),
    SubscriptionPlan(
      id: 'standard',
      name: 'Standard',
      description: 'List up to 5 restrooms',
      price: 2000.0,
      duration: '1 month',
    ),
    SubscriptionPlan(
      id: 'premium',
      name: 'Premium',
      description: 'Unlimited restrooms with analytics',
      price: 3000.0,
      duration: '1 month',
    ),
  ];

  Future<void> _pickPaymentSlip() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _paymentSlip = File(image.path);
      });
    }
  }

  // When a subscription plan is selected
  void _onPlanSelected(SubscriptionPlan plan) {
    setState(() {
      _selectedPlan = plan;
      _showPaymentOptions = true;
    });
  }

  Future<void> _uploadRenewal() async {
    if (_paymentSlip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please upload a payment slip')),
      );
      return;
    }

    if (_selectedPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a subscription plan')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      // Upload payment slip
      final String fileName =
          'renewals/${DateTime.now().millisecondsSinceEpoch}_$userId';
      final Reference storageRef = _storage.ref().child(fileName);
      final UploadTask uploadTask = storageRef.putFile(_paymentSlip!);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      // Update user document
      await _firestore.collection('users').doc(userId).update({
        'subscription': {
          'planId': _selectedPlan?.id,
          'planName': _selectedPlan?.name,
          'price': _selectedPlan?.price,
          'duration': _selectedPlan?.duration,
          'paymentStatus': 'renew_pending',
          'paymentProofUrl': downloadUrl,
          'isRenewal': true,
          'submittedAt': FieldValue.serverTimestamp(),
        },
      });

      // Create notification for admin
      await _firestore.collection('notifications').add({
        'userId': userId,
        'title': 'Subscription Renewal Request',
        'message':
            'New renewal request from ${_auth.currentUser?.email ?? "an owner"} for ${_selectedPlan?.name} plan',
        'type': 'renewal_request',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'isAdminNotification': true,
        'relatedPage': 'payments',
        'userEmail': _auth.currentUser?.email,
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Renewal request submitted for approval')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting renewal: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildSubscriptionPlanCard(SubscriptionPlan plan) {
    final bool isSelected = _selectedPlan?.id == plan.id;

    return GestureDetector(
      onTap: () => _onPlanSelected(plan),
      child: Container(
        margin: EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? Color(0xFF2E86DE).withOpacity(0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Color(0xFF2E86DE) : Colors.grey[300]!,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Color(0xFF2E86DE) : Colors.white,
                border: Border.all(
                  color: isSelected ? Color(0xFF2E86DE) : Colors.grey[400]!,
                ),
              ),
              child: isSelected
                  ? Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    plan.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "LKR ${plan.price.toStringAsFixed(0)}",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E86DE),
                  ),
                ),
                Text(
                  "per ${plan.duration}",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Renew Subscription'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Renew Your Subscription',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              'Select a new subscription plan and upload your payment receipt',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 20),

            // Subscription plans
            Text(
              "Select a Subscription Plan:",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 10),
            ..._subscriptionPlans
                .map((plan) => _buildSubscriptionPlanCard(plan))
                .toList(),
            SizedBox(height: 14),

            // Payment options for selected plan
            if (_showPaymentOptions) ...[
              Text(
                "Payment Method:",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 10),

              // Bank Transfer Info
              Container(
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.account_balance,
                          color: Color(0xFF2E86DE),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Bank Transfer",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Please transfer the subscription amount to our bank account and upload the payment receipt below.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14),

              // Display bank details
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Bank Transfer Details:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      "Bank: Example Bank\nAccount Name: Clean Restrooms Ltd\nAccount Number: 1234567890\nReference: ${_auth.currentUser?.email ?? 'Your Email'}",
                      style: TextStyle(fontSize: 12),
                    ),
                    SizedBox(height: 6),
                    Text(
                      "Amount: LKR ${_selectedPlan?.price.toStringAsFixed(0)}",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E86DE),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14),

              // Upload section
              Text(
                "Upload Payment Receipt:",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 10),

              // Upload button
              InkWell(
                onTap: _pickPaymentSlip,
                child: Container(
                  width: double.infinity,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _paymentSlip != null
                          ? Color(0xFF2E86DE)
                          : Colors.grey[300]!,
                      width: 1.5,
                    ),
                  ),
                  child: _paymentSlip != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _paymentSlip!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.upload_file,
                              size: 28,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Tap to upload payment receipt",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              SizedBox(height: 6),
              Text(
                "Your subscription will be activated after payment verification.",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
              SizedBox(height: 20),
            ],

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _uploadRenewal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF2E86DE),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? CircularProgressIndicator(color: Colors.white)
                    : Text(
                        'Submit Renewal Request',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
