import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:project_x/screen/ManageUser.dart';
import 'package:project_x/screen/update_maintanance_status.dart';
import 'package:project_x/screen/user_counting_page.dart';
import 'package:project_x/screen/view_counting_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:project_x/screen/admin_notifications_page.dart';

import 'AddCommentPage.dart';
import 'AddMaintainerPage.dart';
import 'AddToiletPage.dart';
import 'ManageMaintainersPage.dart';
import 'ManageToiletsPage.dart';
import 'ReportIssuePage.dart';
import 'ViewReportsPage.dart';
import 'View_assign_task.dart';
import 'contact_us_page.dart';
import 'view_reviews_page.dart';
import 'admin_payment_verification_screen.dart';
// profile page
class ProfilePage extends StatefulWidget {
  final String role;

  const ProfilePage({Key? key, required this.role}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? userName;
  String? userEmail;
  String? userPhotoUrl;
  bool isLoading = true;
  File? _profileImage;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  int _unreadNotificationsCount = 0;
  StreamSubscription<QuerySnapshot>? _notificationsSubscription;

  // Enhanced Role Configuration with Sophisticated Color Palette
  static const Map<String, RoleConfig> _roleConfigs = {
    'Admin': RoleConfig(
      primaryColor: Color(0xFF5E35B1), // Deep Purple
      secondaryColor: Color(0xFFD1C4E9), // Light Purple
      accentColor: Color(0xFF7C4DFF), // Vibrant Purple
      textColor: Color(0xFF4A148C), // Dark Purple
      backgroundColor: Color(0xFFF3E5F5), // Very Light Purple
    ),
    'Owner': RoleConfig(
      primaryColor: Color(0xFF2E7D32), // Forest Green
      secondaryColor: Color(0xFFC8E6C9), // Light Green
      accentColor: Color(0xFF4CAF50), // Vibrant Green
      textColor: Color(0xFF1B5E20), // Dark Green
      backgroundColor: Color(0xFFE8F5E9), // Very Light Green
    ),
    'User': RoleConfig(
      primaryColor: Color(0xFF1976D2), // Bright Blue
      secondaryColor: Color(0xFFBBDEFB), // Light Blue
      accentColor: Color(0xFF2196F3), // Vibrant Blue
      textColor: Color(0xFF0D47A1), // Dark Blue
      backgroundColor: Color(0xFFE3F2FD), // Very Light Blue
    ),
    'Maintainer': RoleConfig(
      primaryColor: Color(0xFFF57C00), // Deep Orange
      secondaryColor: Color(0xFFFFE0B2), // Light Orange
      accentColor: Color(0xFFFF9800), // Vibrant Orange
      textColor: Color(0xFFE65100), // Dark Orange
      backgroundColor: Color(0xFFFFF3E0), // Very Light Orange
    ),
  };

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _setupNotificationsListener();
  }

  @override
  void dispose() {
    _notificationsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _setupNotificationsListener() async {
    if (widget.role != 'Admin') return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    _notificationsSubscription = _firestore
        .collection('notifications')
        .where('userId', isEqualTo: currentUser.uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _unreadNotificationsCount = snapshot.size;
        });
      }
    });
  }

  Future<void> _loadUserData() async {
    setState(() {
      isLoading = true;
    });

    try {
      User? currentUser = _auth.currentUser;

      if (currentUser != null) {
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();

        setState(() {
          if (userDoc.exists) {
            Map<String, dynamic> userData =
                userDoc.data() as Map<String, dynamic>;
            userName = userData['name'] ?? currentUser.displayName ?? 'User';
            userPhotoUrl = userData['photoUrl'] ?? currentUser.photoURL;
          } else {
            userName = currentUser.displayName ?? 'User';
            userPhotoUrl = currentUser.photoURL;
          }

          userEmail = currentUser.email;
          isLoading = false;
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userName', userName ?? 'User');
        await prefs.setString('userEmail', userEmail ?? '');
        if (userPhotoUrl != null) {
          await prefs.setString('userPhotoUrl', userPhotoUrl!);
        }
      } else {
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          userName = prefs.getString('userName') ?? 'User';
          userEmail = prefs.getString('userEmail') ?? '';
          userPhotoUrl = prefs.getString('userPhotoUrl');
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        userName = prefs.getString('userName') ?? 'User';
        userEmail = prefs.getString('userEmail') ?? '';
        userPhotoUrl = prefs.getString('userPhotoUrl');
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load user data: $e')),
      );
    }
  }

  Future<void> _pickProfileImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _profileImage = File(image.path);
      });
      await _uploadProfileImage();
    }
  }

  Future<void> _uploadProfileImage() async {
    if (_profileImage == null) return;

    try {
      setState(() {
        isLoading = true;
      });

      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      final String fileName =
          'profile_images/${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final Reference storageRef = _storage.ref().child(fileName);
      final UploadTask uploadTask = storageRef.putFile(_profileImage!);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      await _firestore.collection('users').doc(currentUser.uid).set({
        'photoUrl': downloadUrl,
        'name': userName,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await currentUser.updatePhotoURL(downloadUrl);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userPhotoUrl', downloadUrl);

      setState(() {
        userPhotoUrl = downloadUrl;
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile picture updated successfully!')),
      );
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload profile picture: $e')),
      );
    }
  }

  Future<void> _deleteProfileImage() async {
    try {
      setState(() {
        isLoading = true;
      });

      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      if (userPhotoUrl != null && userPhotoUrl!.contains('firebase')) {
        String filePath = userPhotoUrl!.split('/o/')[1].split('?')[0];
        filePath = Uri.decodeFull(filePath);
        await _storage.ref().child(filePath).delete();
      }

      await _firestore.collection('users').doc(currentUser.uid).update({
        'photoUrl': FieldValue.delete(),
      });

      await currentUser.updatePhotoURL(null);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('userPhotoUrl');

      setState(() {
        userPhotoUrl = null;
        _profileImage = null;
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile picture deleted successfully!')),
      );
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete profile picture: $e')),
      );
    }
  }

  Future<void> _showEditProfileDialog(BuildContext context) async {
    final roleConfig = _roleConfigs[widget.role] ?? _roleConfigs['User']!;
    final TextEditingController nameController =
        TextEditingController(text: userName);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("Edit Profile",
                  style: TextStyle(color: roleConfig.primaryColor)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _pickProfileImage,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: roleConfig.secondaryColor,
                            backgroundImage: _profileImage != null
                                ? FileImage(_profileImage!)
                                : userPhotoUrl != null
                                    ? NetworkImage(userPhotoUrl!)
                                        as ImageProvider
                                    : null,
                            child: _profileImage == null && userPhotoUrl == null
                                ? Text(
                                    userName != null && userName!.isNotEmpty
                                        ? userName![0].toUpperCase()
                                        : 'U',
                                    style: TextStyle(
                                      fontSize: 40,
                                      fontWeight: FontWeight.bold,
                                      color: roleConfig.primaryColor,
                                    ),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: roleConfig.primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_profileImage != null || userPhotoUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextButton.icon(
                          icon: Icon(Icons.delete, color: Colors.red),
                          label: Text('Remove Photo',
                              style: TextStyle(color: Colors.red)),
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteProfileImage();
                          },
                        ),
                      ),
                    SizedBox(height: 20),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: "Name",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    SizedBox(height: 12),
                    if (userEmail != null && userEmail!.isNotEmpty)
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: roleConfig.backgroundColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.email, color: Colors.grey),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                userEmail!,
                                style: TextStyle(
                                  color: Colors.grey[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: roleConfig.primaryColor,
                  ),
                  onPressed: () async {
                    if (nameController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Please enter your name')),
                      );
                      return;
                    }

                    try {
                      User? currentUser = _auth.currentUser;
                      if (currentUser != null) {
                        await _firestore
                            .collection('users')
                            .doc(currentUser.uid)
                            .set({
                          'name': nameController.text,
                          'lastUpdated': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));

                        await currentUser
                            .updateDisplayName(nameController.text);
                      }

                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('userName', nameController.text);

                      setState(() {
                        userName = nameController.text;
                      });

                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Profile updated successfully!')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update profile: $e')),
                      );
                    }
                  },
                  child: Text("Save", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  IconData _getIconForRole(String role) {
    switch (role) {
      case 'Admin':
        return Icons.admin_panel_settings_rounded;
      case 'Owner':
        return Icons.home_work_rounded;
      case 'User':
        return Icons.person_rounded;
      case 'Maintainer':
        return Icons.build_rounded;
      default:
        return Icons.account_circle_rounded;
    }
  }

  Widget _buildWelcomeSection(RoleConfig roleConfig) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: roleConfig.primaryColor.withOpacity(0.1),
            blurRadius: 15,
            spreadRadius: 2,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickProfileImage,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: roleConfig.secondaryColor,
                    boxShadow: [
                      BoxShadow(
                        color: roleConfig.primaryColor.withOpacity(0.2),
                        blurRadius: 10,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: isLoading
                      ? CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                              roleConfig.primaryColor),
                        )
                      : userPhotoUrl != null
                          ? CircleAvatar(
                              radius: 20,
                              backgroundImage: NetworkImage(userPhotoUrl!),
                            )
                          : Text(
                              userName != null && userName!.isNotEmpty
                                  ? userName![0].toUpperCase()
                                  : 'U',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: roleConfig.primaryColor,
                              ),
                            ),
                ),
                if (userPhotoUrl != null)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _deleteProfileImage,
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.delete_forever,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${userName ?? ''}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: roleConfig.textColor,
                  ),
                ),
                if (userEmail != null && userEmail!.isNotEmpty)
                  Text(
                    userEmail!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  )
                else
                  Text(
                    'Manage your Public Toilet System account',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActionButtons(
      BuildContext context, RoleConfig roleConfig) {
    return _getActionsForRole(widget.role).map((action) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: roleConfig.primaryColor.withOpacity(0.15),
              blurRadius: 15,
              spreadRadius: 1,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              if (action.page != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => action.page!),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Feature coming soon'),
                    backgroundColor: roleConfig.primaryColor,
                  ),
                );
              }
            },
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: roleConfig.secondaryColor,
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        action.icon,
                        color: roleConfig.primaryColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: roleConfig.textColor,
                            ),
                          ),
                          if (action.subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                action.subtitle!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (action.badge != null)
                      Container(
                        margin: EdgeInsets.only(right: 12),
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          action.badge!,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: roleConfig.primaryColor,
                      size: 28,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<RoleAction> _getActionsForRole(String role) {
    switch (role) {
      case 'Admin':
        return [
          RoleAction(
            title: 'Notifications',
            subtitle: 'View pending actions',
            icon: Icons.notifications,
            page: AdminNotificationsPage(),
            badge: _unreadNotificationsCount > 0
                ? _unreadNotificationsCount.toString()
                : null,
          ),
          RoleAction(
            title: 'Verify Payments',
            subtitle: 'Approve or reject payment receipts',
            icon: Icons.payment_rounded,
            page: AdminPaymentVerificationScreen(),
          ),
          RoleAction(
            title: 'Manage Users',
            icon: Icons.people_rounded,
            page: ManageUsersPage(),
          ),
        ];
      case 'Owner':
        return [
          RoleAction(
            title: 'Add Toilets',
            icon: Icons.add_location_rounded,
            page: AddToiletPage(),
          ),
          RoleAction(
            title: 'Manage Toilets',
            icon: Icons.manage_search_rounded,
            page: ManageToiletsPage(),
          ),
          RoleAction(
            title: 'Add Maintainers',
            icon: Icons.person_add_rounded,
            page: ImprovedAddMaintainerPage(),
          ),
          RoleAction(
            title: 'Manage Maintainers',
            icon: Icons.manage_accounts_rounded,
            page: ImprovedManageMaintainersPage(),
          ),
          RoleAction(
            title: 'View Reports',
            icon: Icons.report_rounded,
            page: ViewReportsPage(),
          ),
          RoleAction(
            title: 'Toilet Usage Statistics',
            icon: Icons.bar_chart_rounded,
            page: OwnerCountingPage(),
          ),
          RoleAction(
            title: 'Contact Us',
            icon: Icons.contact_support_rounded,
            page: ContactUsPage(),
          ),
        ];
      case 'User':
        return [
          RoleAction(
            title: 'View Reviews',
            icon: Icons.reviews_rounded,
            page: ViewReviewsPage(toiletId: 'all'),
          ),
          RoleAction(
            title: 'Post Comment & Photo',
            icon: Icons.add_comment_rounded,
            page: AddCommentPage(),
          ),
          RoleAction(
            title: 'Report an Issue',
            icon: Icons.report_problem_rounded,
            page: ReportIssuePage(),
          ),
          RoleAction(
            title: 'Contact Us',
            icon: Icons.contact_support_rounded,
            page: ContactUsPage(),
          ),
        ];
      case 'Maintainer':
        return [
          RoleAction(
            title: 'Toilet User Counting',
            icon: Icons.numbers_rounded,
            page: CounterPage(toiletId: 'TOILET001'),
          ),
          RoleAction(
            title: 'Update Maintenance Status',
            icon: Icons.construction_rounded,
            page: UpdateMaintenanceStatusPage(),
          ),
          RoleAction(
            title: 'View My Tasks',
            icon: Icons.assignment,
            page: const ViewAssignedTasksPage(),
          ),
        ];
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleConfig = _roleConfigs[widget.role] ?? _roleConfigs['User']!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: roleConfig.backgroundColor,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: roleConfig.backgroundColor,
        body: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 220.0,
                floating: false,
                pinned: true,
                backgroundColor: roleConfig.primaryColor,
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: true,
                  title: Text(
                    '${widget.role} Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          blurRadius: 10.0,
                          color: Colors.black38,
                          offset: Offset(1.0, 1.0),
                        ),
                      ],
                    ),
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          roleConfig.primaryColor,
                          roleConfig.accentColor,
                        ],
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _pickProfileImage,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 20,
                                    offset: Offset(0, 10),
                                  )
                                ],
                              ),
                              child: isLoading
                                  ? CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    )
                                  : userPhotoUrl != null
                                      ? CircleAvatar(
                                          radius: 60,
                                          backgroundImage:
                                              NetworkImage(userPhotoUrl!),
                                          backgroundColor: Colors.transparent,
                                        )
                                      : CircleAvatar(
                                          radius: 60,
                                          backgroundColor: Colors.white24,
                                          child: Text(
                                            userName != null &&
                                                    userName!.isNotEmpty
                                                ? userName![0].toUpperCase()
                                                : 'U',
                                            style: TextStyle(
                                              fontSize: 48,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
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
                actions: [
                  if (widget.role == 'Admin')
                    Stack(
                      children: [
                        IconButton(
                          icon: Icon(Icons.notifications, color: Colors.white),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      AdminNotificationsPage()),
                            ).then((_) {
                              _setupNotificationsListener();
                            });
                          },
                        ),
                        if (_unreadNotificationsCount > 0)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Text(
                                _unreadNotificationsCount > 9
                                    ? '9+'
                                    : _unreadNotificationsCount.toString(),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  IconButton(
                    icon: Icon(Icons.edit, color: Colors.white),
                    onPressed: () => _showEditProfileDialog(context),
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16.0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    [
                      _buildWelcomeSection(roleConfig),
                      ..._buildActionButtons(context, roleConfig),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoleConfig {
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final Color textColor;
  final Color backgroundColor;

  const RoleConfig({
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.textColor,
    required this.backgroundColor,
  });
}

class RoleAction {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? page;
  final String? badge;

  const RoleAction({
    required this.title,
    this.subtitle,
    required this.icon,
    this.page,
    this.badge,
  });
}
