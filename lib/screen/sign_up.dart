import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:ui';
import 'home_page.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

// Create a new class for subscription plans
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

class SignUp extends StatefulWidget {
  @override
  _SignUpState createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String? _selectedRole;
  SubscriptionPlan? _selectedPlan;
  bool _isLoading = false;
  bool _agreedToTerms = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // For payment verification
  File? _paymentSlip;
  bool _showPaymentOptions = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Hardcoded subscription plans
// Hardcoded subscription plans with LKR currency and updated prices
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

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1000),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(0.0, 0.8, curve: Curves.easeOut),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Method to pick payment slip image
  Future<void> _pickPaymentSlip() async {
    final ImagePicker _picker = ImagePicker();
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        _paymentSlip = File(image.path);
      });
    }
  }

  // Method to upload payment slip to Firebase Storage
  Future<String?> _uploadPaymentSlip() async {
    if (_paymentSlip == null) return null;

    try {
      final String fileName =
          'payment_slips/${DateTime.now().millisecondsSinceEpoch}_${_emailController.text}';
      final Reference storageRef = _storage.ref().child(fileName);
      final UploadTask uploadTask = storageRef.putFile(_paymentSlip!);

      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('Error uploading payment slip: $e');
      return null;
    }
  }

  // Helper method to directly make phone calls
  void _makePhoneCall(String phoneNumber) async {
    // Using both URI approaches for maximum compatibility
    try {
      // First try the newer approach
      final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
      await launchUrl(phoneUri);
    } catch (e) {
      // If that fails, try the older approach as fallback
      final String url = 'tel:$phoneNumber';
      if (await canLaunch(url)) {
        await launch(url);
      } else {
        // Show error message if both methods fail
        _showSnackBar(
            'Could not launch phone dialer. Please call $phoneNumber manually.');
      }
    }
  }

// Add this method to _SignUpState class in sign_up.dart
  Future<void> _sendAdminNotification(String userName, String userEmail) async {
    try {
      // Get all admin users
      final admins = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'Admin')
          .get();

      // Create a notification for each admin
      for (var admin in admins.docs) {
        await _firestore.collection('notifications').add({
          'userId': admin.id,
          'title': 'New Owner Registration',
          'message':
              '$userName ($userEmail) has registered as an Owner and needs payment verification.',
          'type': 'new_owner',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
          'relatedUserId': _auth.currentUser?.uid,
        });
      }
    } catch (e) {
      print('Error sending admin notification: $e');
    }
  }

  // Show waiting dialog after successful owner signup
  void _showWaitingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final screenWidth = MediaQuery.of(context).size.width;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: screenWidth * 0.85,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF2E86DE).withOpacity(0.1),
                  ),
                  child: Icon(
                    Icons.check_circle,
                    size: 60,
                    color: Color(0xFF2E86DE),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "Account Created!",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 15),
                Text(
                  "Your account has been created successfully. An administrator will review your payment and activate your account soon.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: Colors.orange,
                    ),
                    SizedBox(width: 8),
                    Text(
                      "Typical approval time: 1-2 business days",
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 25),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    InkWell(
                      onTap: () {
                        // Close dialog first
                        Navigator.pop(context);
                        // Then directly launch phone call
                        _makePhoneCall('+94715308550');
                      },
                      child: Container(
                        width: double.infinity,
                        height: 45,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.call, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              "Contact Admin",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pop(context); // Return to login screen
                      },
                      child: Container(
                        width: double.infinity,
                        height: 45,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Color(0xFF2E86DE)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            "Back to Login",
                            style: TextStyle(
                              color: Color(0xFF2E86DE),
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
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

  // New method to show waiting options dialog
  void _showWaitingOptionsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final screenWidth = MediaQuery.of(context).size.width;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: screenWidth * 0.85,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.orange.withOpacity(0.1),
                  ),
                  child: Icon(
                    Icons.hourglass_top,
                    size: 60,
                    color: Colors.orange,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "What would you like to do while waiting?",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 15),
                Text(
                  "Your account is pending approval. Here are some options while you wait:",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: 20),
                InkWell(
                  onTap: () {
                    // Browse app features as a guest
                    Navigator.pop(context);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HomePage(loggedInUserRole: "Guest"),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    height: 45,
                    decoration: BoxDecoration(
                      color: Color(0xFF2E86DE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.explore, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          "Browse as Guest",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 10),
                InkWell(
                  onTap: () {
                    // Direct phone call without closing dialog
                    _makePhoneCall('+94715308550');
                  },
                  child: Container(
                    width: double.infinity,
                    height: 45,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.call, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          "Contact Admin",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 10),
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pop(context); // Return to login screen
                  },
                  child: Container(
                    width: double.infinity,
                    height: 45,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Color(0xFF2E86DE)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        "Back to Login",
                        style: TextStyle(
                          color: Color(0xFF2E86DE),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
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

  void _signUp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // Basic validations
    if (email.isEmpty ||
        password.isEmpty ||
        name.isEmpty ||
        _selectedRole == null) {
      _showSnackBar("Please fill all fields.");
      return;
    }

    if (password != confirmPassword) {
      _showSnackBar("Passwords do not match.");
      return;
    }

    if (!_agreedToTerms) {
      _showSnackBar("You must agree to the terms and conditions.");
      return;
    }

    // Check if owner has selected a plan
    if (_selectedRole == "Owner" && _selectedPlan == null) {
      _showSnackBar("Please select a subscription plan.");
      return;
    }

    // If role is Owner, check for payment slip
    if (_selectedRole == "Owner" &&
        _showPaymentOptions &&
        _paymentSlip == null) {
      _showSnackBar("Please upload your payment receipt.");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create user with Firebase Authentication
      final UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);

      final userId = userCredential.user?.uid;

      if (userId != null) {
        // For Owner role with subscription
        if (_selectedRole == "Owner") {
          String? paymentProofUrl;

          // Upload payment slip
          if (_showPaymentOptions) {
            paymentProofUrl = await _uploadPaymentSlip();
          }

          // Save user details with subscription info to Firestore
          await _firestore.collection('users').doc(userId).set({
            'name': name,
            'email': email,
            'role': _selectedRole,
            'createdAt': FieldValue.serverTimestamp(),
            'subscription': {
              'planId': _selectedPlan?.id,
              'planName': _selectedPlan?.name,
              'price': _selectedPlan?.price,
              'duration': _selectedPlan?.duration,
              'paymentStatus': 'pending',
              'paymentMethod': 'bankTransfer',
              'paymentProofUrl': paymentProofUrl,
              'startDate': null, // Will be set when payment is verified
              'endDate': null, // Will be set when payment is verified
            },
            'isAccountActive': false, // Needs payment verification
          });
          await _sendAdminNotification(name, email);

          setState(() {
            _isLoading = false;
          });

          // Only show one dialog to fix the issue with multiple dialogs
          _showWaitingOptionsDialog();
        } else {
          // For regular User role
          await _firestore.collection('users').doc(userId).set({
            'name': name,
            'email': email,
            'role': _selectedRole,
            'createdAt': FieldValue.serverTimestamp(),
            'isAccountActive': true,
          });

          setState(() {
            _isLoading = false;
          });

          _showSnackBar("Account created successfully!");
          // Navigate to HomePage
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => HomePage(loggedInUserRole: _selectedRole!),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar("Error: ${e.toString()}");
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Color(0xFF2E86DE),
      ),
    );
  }

  // Show subscription plans when Owner role is selected
  void _onRoleSelected(String role) {
    setState(() {
      _selectedRole = role;
      // Reset selected plan when switching roles
      _selectedPlan = null;
      _showPaymentOptions = false;
    });
  }

  // When a subscription plan is selected
  void _onPlanSelected(SubscriptionPlan plan) {
    setState(() {
      _selectedPlan = plan;
      _showPaymentOptions = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background image with blur effect
          Positioned.fill(
            child: ShaderMask(
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Colors.transparent],
                  stops: [0.6, 1.0],
                ).createShader(rect);
              },
              blendMode: BlendMode.dstIn,
              child: Stack(
                children: [
                  Image.asset(
                    'assets/map_background.jpg',
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                      child: Container(
                        color: Colors.black.withOpacity(0.2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Color(0xFF2E86DE).withOpacity(0.5),
                  Color(0xFF2E86DE).withOpacity(0.9),
                ],
                stops: [0.2, 0.6, 1.0],
              ),
            ),
          ),

          // Content
          SafeArea(
            child: SingleChildScrollView(
              physics: ClampingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 16.0),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Back button
                      Container(
                        margin: EdgeInsets.only(top: 8, bottom: 8),
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_back_ios,
                                    color: Colors.white, size: 18),
                                Text(
                                  "Back",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Header
                      Text(
                        "Create Account",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Sign up to find clean restrooms anywhere",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Form Container
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Role selection
                            Text(
                              "I am a:",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Role buttons
                            Row(
                              children: [
                                Expanded(
                                  child: _buildRoleButton(
                                    role: "User",
                                    icon: Icons.person,
                                    isSelected: _selectedRole == "User",
                                    onTap: () => _onRoleSelected("User"),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildRoleButton(
                                    role: "Owner",
                                    icon: Icons.business,
                                    isSelected: _selectedRole == "Owner",
                                    onTap: () => _onRoleSelected("Owner"),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Subscription plans for Owner role
                            if (_selectedRole == "Owner") ...[
                              Text(
                                "Select a Subscription Plan:",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ..._subscriptionPlans
                                  .map((plan) =>
                                      _buildSubscriptionPlanCard(plan))
                                  .toList(),
                              const SizedBox(height: 14),
                            ],

                            // Payment options for selected plan
                            if (_selectedRole == "Owner" &&
                                _showPaymentOptions) ...[
                              Text(
                                "Payment Method:",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 10),

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
                              const SizedBox(height: 14),

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
                                      "Bank: Example Bank\nAccount Name: Clean Restrooms Ltd\nAccount Number: 1234567890\nReference: ${_emailController.text.isEmpty ? 'Your Email' : _emailController.text}",
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
                              const SizedBox(height: 14),

                              // Upload section
                              Text(
                                "Upload Payment Receipt:",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 10),

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
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Image.file(
                                            _paymentSlip!,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
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
                              const SizedBox(height: 14),
                            ],

                            // Name field
                            _buildTextField(
                              controller: _nameController,
                              label: "Full Name",
                              prefixIcon: Icons.person_outline,
                            ),
                            const SizedBox(height: 14),

                            // Email field
                            _buildTextField(
                              controller: _emailController,
                              label: "Email Address",
                              prefixIcon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 14),

                            // Password field
                            _buildTextField(
                              controller: _passwordController,
                              label: "Create Password",
                              prefixIcon: Icons.lock_outline,
                              isPassword: true,
                              obscureText: _obscurePassword,
                              togglePasswordVisibility: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            const SizedBox(height: 14),

                            // Confirm password field
                            _buildTextField(
                              controller: _confirmPasswordController,
                              label: "Confirm Password",
                              prefixIcon: Icons.lock_outline,
                              isPassword: true,
                              obscureText: _obscureConfirmPassword,
                              togglePasswordVisibility: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                });
                              },
                            ),
                            const SizedBox(height: 16),

                            // Terms and conditions
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Transform.scale(
                                  scale: 0.9,
                                  child: Checkbox(
                                    value: _agreedToTerms,
                                    onChanged: (value) {
                                      setState(() {
                                        _agreedToTerms = value!;
                                      });
                                    },
                                    activeColor: Color(0xFF2E86DE),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Text(
                                    "I've read and agree with the Terms and Conditions and the Privacy Policy.",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black87,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Sign up button
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _signUp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF2E86DE),
                                  foregroundColor: Colors.white,
                                  elevation: 2,
                                  shadowColor: Colors.black.withOpacity(0.3),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  disabledBackgroundColor:
                                      Color(0xFF2E86DE).withOpacity(0.6),
                                ),
                                child: _isLoading
                                    ? SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        "Create Account",
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Already have an account link
                      Padding(
                        padding: EdgeInsets.only(top: 16, bottom: 20),
                        child: Center(
                          child: InkWell(
                            onTap: () => Navigator.pop(context),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                  vertical: 6, horizontal: 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "Already have an account?",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    "Sign In",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    bool? obscureText,
    VoidCallback? togglePasswordVisibility,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText ?? false,
        keyboardType: keyboardType,
        style: TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.grey[600],
            fontSize: 13,
          ),
          prefixIcon: Icon(
            prefixIcon,
            color: Color(0xFF2E86DE).withOpacity(0.8),
            size: 18,
          ),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscureText! ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey[600],
                    size: 18,
                  ),
                  onPressed: togglePasswordVisibility,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          filled: true,
          fillColor: Colors.grey[100],
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Color(0xFF2E86DE), width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleButton({
    required String role,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 6),
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
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Color(0xFF2E86DE) : Colors.grey[600],
              size: 26,
            ),
            const SizedBox(height: 6),
            Text(
              role,
              style: TextStyle(
                color: isSelected ? Color(0xFF2E86DE) : Colors.grey[800],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
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
}
