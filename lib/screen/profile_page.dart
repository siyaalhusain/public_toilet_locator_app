import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:project_x/screen/ManageUser.dart';

import 'AddCommentPage.dart';
import 'AddMaintainerPage.dart';
import 'AddToiletPage.dart';
import 'ManageMaintainersPage.dart';
import 'ManageToiletsPage.dart';
import 'ReportIssuePage.dart';
import 'ViewReportsPage.dart';
import 'view_reviews_page.dart';

class ProfilePage extends StatelessWidget {
  final String role;

  const ProfilePage({Key? key, required this.role}) : super(key: key);

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
  Widget build(BuildContext context) {
    // Get role configuration
    final roleConfig = _roleConfigs[role] ?? _roleConfigs['User']!;

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
              // Animated App Bar
              SliverAppBar(
                expandedHeight: 220.0,
                floating: false,
                pinned: true,
                backgroundColor: roleConfig.primaryColor,
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: true,
                  title: Text(
                    '$role Profile',
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
                          Container(
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
                            child: CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.white24,
                              child: Icon(
                                _getIconForRole(role),
                                size: 80,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Main Content
              SliverPadding(
                padding: const EdgeInsets.all(16.0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    [
                      // Welcome Message
                      _buildWelcomeSection(roleConfig),

                      // Action Buttons
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

  // Get appropriate icon based on role
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

  // Welcome Section
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
            child: Icon(
              _getIconForRole(role),
              size: 40,
              color: roleConfig.primaryColor,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, $role!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: roleConfig.textColor,
                  ),
                ),
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

  // Build Action Buttons
  List<Widget> _buildActionButtons(
      BuildContext context, RoleConfig roleConfig) {
    return _getActionsForRole(role).map((action) {
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
                      child: Text(
                        action.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: roleConfig.textColor,
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

  // Get actions based on role
  List<RoleAction> _getActionsForRole(String role) {
    switch (role) {
      case 'Admin':
        return [
          RoleAction(
            title: 'Manage Users',
            icon: Icons.people_rounded,
            page: ManageUsersPage(),
          ),
          RoleAction(
            title: 'View Reports',
            icon: Icons.report_rounded,
            page: ViewReportsPage(),
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
            page: ImprovedAddMaintainerPage(), // Updated class name
          ),
          RoleAction(
            title: 'Manage Maintainers',
            icon: Icons.manage_accounts_rounded,
            page: ImprovedManageMaintainersPage(), // Updated class name
          ),
        ];
      case 'User':
        return [
          RoleAction(
            title: 'View Reviews',
            icon: Icons.reviews_rounded,
            page: ViewReviewsPage(),
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
        ];
      case 'Maintainer':
        return [
          RoleAction(
            title: 'View Assigned Tasks',
            icon: Icons.task_rounded,
            page: null,
          ),
          RoleAction(
            title: 'Update Maintenance Status',
            icon: Icons.construction_rounded,
            page: null,
          ),
        ];
      default:
        return [];
    }
  }
}

// Role Configuration Class
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

// Role Action Class
class RoleAction {
  final String title;
  final IconData icon;
  final Widget? page;

  const RoleAction({
    required this.title,
    required this.icon,
    this.page,
  });
}
