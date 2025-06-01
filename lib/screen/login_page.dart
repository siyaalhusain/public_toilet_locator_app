import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';
import 'home_page.dart';
import 'sign_up.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginScreen extends StatefulWidget {
  final String? errorMessage;

  const LoginScreen({super.key, this.errorMessage});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _loginError;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

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

    if (widget.errorMessage != null) {
      _loginError = widget.errorMessage;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<bool> _verifyAccountStatus(UserCredential userCredential) async {
    if (userCredential.user != null) {
      String userId = userCredential.user!.uid;

      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(userId).get();

      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

        if (userData['role'] == 'Owner') {
          bool isActive = userData['isAccountActive'] ?? false;
          String paymentStatus = '';

          if (userData.containsKey('subscription') &&
              userData['subscription'] is Map<String, dynamic>) {
            Map<String, dynamic> subscription =
                userData['subscription'] as Map<String, dynamic>;
            paymentStatus = subscription['paymentStatus'] ?? '';
          }

          if (!isActive || paymentStatus == 'rejected') {
            await _auth.signOut();

            setState(() {
              if (paymentStatus == 'rejected') {
                _loginError =
                    "Your payment was rejected. Please contact admin for assistance.";
              } else if (paymentStatus == 'pending') {
                _loginError =
                    "Your account is awaiting payment verification. Please wait for approval.";
              } else {
                _loginError =
                    "Your account is not active. Please contact support.";
              }
            });
            return false;
          }

          if (userData.containsKey('subscription') &&
              userData['subscription'] is Map<String, dynamic>) {
            Map<String, dynamic> subscription =
                userData['subscription'] as Map<String, dynamic>;

            if (subscription.containsKey('endDate') &&
                subscription['endDate'] != null) {
              Timestamp endTimestamp = subscription['endDate'];
              DateTime endDate = endTimestamp.toDate();

              if (DateTime.now().isAfter(endDate)) {
                await _firestore.collection('users').doc(userId).update({
                  'isAccountActive': false,
                  'subscription.status': 'expired'
                });

                await _auth.signOut();

                setState(() {
                  _loginError =
                      "Your subscription has expired. Please renew to continue.";
                });
                return false;
              }
            }
          }
        }

        return true;
      }
    }

    return false;
  }

  Future<void> _resetPassword(String email) async {
    if (email.isEmpty) {
      setState(() {
        _loginError = "Please enter your email address";
      });
      return;
    }

    try {
      EasyLoading.show(status: 'Sending password reset email...');
      await _auth.sendPasswordResetEmail(email: email);
      EasyLoading.dismiss();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Password Reset Email Sent"),
          content: Text(
              "We've sent a password reset link to $email. Please check your inbox."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("OK"),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      EasyLoading.dismiss();
      String message = "An error occurred. Please try again.";
      if (e.code == 'user-not-found') {
        message = "No user found with this email address.";
      }
      setState(() {
        _loginError = message;
      });
    } catch (e) {
      EasyLoading.dismiss();
      setState(() {
        _loginError = "An unexpected error occurred. Please try again.";
      });
    }
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<void> _signInWithGoogle() async {
    try {
      EasyLoading.show(status: 'Signing in with Google...');

      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        EasyLoading.dismiss();
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      final bool isNewUser =
          userCredential.additionalUserInfo?.isNewUser ?? false;
      final String userId = userCredential.user?.uid ?? '';

      if (isNewUser) {
        await _firestore.collection('users').doc(userId).set({
          'email': userCredential.user?.email,
          'name': userCredential.user?.displayName,
          'role': 'user',
          'isAccountActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'authProvider': 'google',
        });
      }

      final userDoc = await _firestore.collection('users').doc(userId).get();
      final String role = userDoc.exists
          ? (userDoc.data()?['role'] as String?) ?? 'user'
          : 'user';
      EasyLoading.dismiss();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(loggedInUserRole: role),
        ),
      );
    } on FirebaseAuthException catch (e) {
      EasyLoading.dismiss();
      setState(() {
        _loginError = "Google sign-in failed: ${e.message}";
      });
    } catch (e) {
      EasyLoading.dismiss();
      setState(() {
        _loginError = "Error signing in with Google";
      });
    }
  }

  void _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _loginError = "Please fill all fields.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loginError = null;
    });

    try {
      EasyLoading.show(status: 'Signing in...');

      final UserCredential userCredential =
          await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      bool isAccountValid = await _verifyAccountStatus(userCredential);

      EasyLoading.dismiss();

      if (isAccountValid) {
        final uid = userCredential.user?.uid;
        if (uid != null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data();
            final role = userData?['role'] ?? 'user';

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => HomePage(loggedInUserRole: role),
              ),
            );
          } else {
            setState(() {
              _isLoading = false;
              _loginError = "User data not found.";
            });
          }
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      EasyLoading.dismiss();
      String message = "An error occurred. Please try again.";
      if (e.code == 'user-not-found') {
        message = "No user found for this email.";
      } else if (e.code == 'wrong-password') {
        message = "Incorrect password.";
      }
      setState(() {
        _isLoading = false;
        _loginError = message;
      });
    } catch (e) {
      EasyLoading.dismiss();
      setState(() {
        _isLoading = false;
        _loginError = "An unexpected error occurred. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
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
          Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    physics: ClampingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.only(
                          left: 24.0, right: 24.0, top: 16.0, bottom: 32.0),
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              height: 80,
                              width: 80,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 12,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.wc,
                                size: 50,
                                color: Color(0xFF2E86DE),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "Toilet Finder",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Find clean restrooms nearby",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                            const SizedBox(height: 40),
                            if (_loginError != null) ...[
                              Container(
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.red.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline,
                                        color: Colors.red),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _loginError!,
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                            Container(
                              padding: EdgeInsets.all(24),
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
                                  Text(
                                    "Welcome Back",
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Sign in to continue",
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  _buildTextField(
                                    controller: _emailController,
                                    label: "Email Address",
                                    prefixIcon: Icons.email_outlined,
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                  const SizedBox(height: 20),
                                  _buildTextField(
                                    controller: _passwordController,
                                    label: "Password",
                                    prefixIcon: Icons.lock_outline,
                                    isPassword: true,
                                    obscureText: _obscurePassword,
                                    togglePasswordVisibility: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) {
                                            final emailController =
                                                TextEditingController(
                                                    text:
                                                        _emailController.text);
                                            return AlertDialog(
                                              title: Text("Reset Password"),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                      "Enter your email to receive a password reset link:"),
                                                  SizedBox(height: 16),
                                                  TextField(
                                                    controller: emailController,
                                                    decoration: InputDecoration(
                                                      labelText: "Email",
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                                    keyboardType: TextInputType
                                                        .emailAddress,
                                                  ),
                                                ],
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: Text("Cancel"),
                                                ),
                                                TextButton(
                                                  onPressed: () {
                                                    Navigator.pop(context);
                                                    _resetPassword(
                                                        emailController.text
                                                            .trim());
                                                  },
                                                  child: Text("Send"),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: Color(0xFF2E86DE),
                                        padding: EdgeInsets.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        "Forgot password?",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _login,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Color(0xFF2E86DE),
                                        foregroundColor: Colors.white,
                                        elevation: 2,
                                        shadowColor:
                                            Colors.black.withOpacity(0.3),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        disabledBackgroundColor:
                                            Color(0xFF2E86DE).withOpacity(0.6),
                                      ),
                                      child: _isLoading
                                          ? SizedBox(
                                              height: 24,
                                              width: 24,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : Text(
                                              "Sign In",
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Column(
                              children: [
                                Text(
                                  "Or sign in with",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: _signInWithGoogle,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black87,
                                      elevation: 2,
                                      shadowColor:
                                          Colors.black.withOpacity(0.3),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.g_mobiledata, size: 28),
                                        SizedBox(width: 12),
                                        Text(
                                          "Sign in with Google",
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Don't have an account?",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => SignUp(),
                                      ),
                                    );
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                  child: Text(
                                    "Sign Up",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
        style: TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.grey[600],
            fontSize: 15,
          ),
          prefixIcon: Icon(
            prefixIcon,
            color: Color(0xFF2E86DE).withOpacity(0.8),
            size: 22,
          ),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscureText! ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey[600],
                    size: 22,
                  ),
                  onPressed: togglePasswordVisibility,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
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
}
