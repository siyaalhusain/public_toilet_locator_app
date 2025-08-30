import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';

class ContactUsPage extends StatefulWidget {
  @override
  _ContactUsPageState createState() => _ContactUsPageState();
}

class _ContactUsPageState extends State<ContactUsPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Contact information
  final String _adminPhoneNumber = '+94715308550';
  final String _adminEmail = 'husain200426@gmail.com';
  final String _adminAddress = '123 Main Street, Colombo, Sri Lanka';
  final String _adminHours = 'Monday - Friday: 9:00 AM - 5:00 PM';

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
    super.dispose();
  }


  // Helper method to directly make phone calls
  void _makePhoneCall(String phoneNumber) async {
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

  // Helper method to launch email
  void _launchEmail() async {
    final Uri emailUri = Uri(
        scheme: 'mailto',
        path: _adminEmail,
        queryParameters: {'subject': 'Support Request - Locatar App'});

    try {
      await launchUrl(emailUri);
    } catch (e) {
      _showSnackBar(
          'Could not open email client. Please email $_adminEmail manually.');
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
                        "Contact Us",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "We're here to help with any questions or issues",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Contact Cards Container
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
                            // Customer Support section
                            Text(
                              "Customer Support",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Our team is available to assist you with any questions or issues.",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Contact Cards
                            _buildContactCard(
                              title: "Call Us",
                              subtitle: "Speak directly with our support team",
                              icon: Icons.call,
                              buttonText: "Call Now",
                              buttonIcon: Icons.call,
                              value: _adminPhoneNumber,
                              onTap: () => _makePhoneCall(_adminPhoneNumber),
                              color: Colors.green,
                            ),

                            const SizedBox(height: 16),

                            _buildContactCard(
                              title: "Email Us",
                              subtitle: "Send us your questions or feedback",
                              icon: Icons.email,
                              buttonText: "Send Email",
                              buttonIcon: Icons.email,
                              value: _adminEmail,
                              onTap: _launchEmail,
                              color: Color(0xFF2E86DE),
                            ),

                            const SizedBox(height: 24),

                            // Business Hours
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        color: Colors.grey[700],
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        "Business Hours",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _adminHours,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[700],
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String buttonText,
    required IconData buttonIcon,
    required String value,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 1,
                shadowColor: Colors.black.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(buttonIcon, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    buttonText,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
