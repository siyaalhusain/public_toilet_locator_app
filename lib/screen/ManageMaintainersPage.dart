import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Import the AddMaintainerPage
import 'AddMaintainerPage.dart';
import 'Assign_Task.dart';

class ImprovedManageMaintainersPage extends StatefulWidget {
  const ImprovedManageMaintainersPage({Key? key}) : super(key: key);

  @override
  _ImprovedManageMaintainersPageState createState() =>
      _ImprovedManageMaintainersPageState();
}

class _ImprovedManageMaintainersPageState
    extends State<ImprovedManageMaintainersPage> {
  final CollectionReference usersCollection =
      FirebaseFirestore.instance.collection('users');
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String? _currentOwnerId;

  @override
  void initState() {
    super.initState();
    _getCurrentOwnerId();
  }

  Future<void> _getCurrentOwnerId() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      setState(() {
        _currentOwnerId = currentUser.uid;
      });
    }
  }

  Stream<QuerySnapshot> getMaintainersStream() {
    if (_currentOwnerId == null) {
      return const Stream.empty();
    }

    return usersCollection
        .where('role', isEqualTo: 'Maintainer')
        .where('ownerId', isEqualTo: _currentOwnerId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _confirmDeleteMaintainer(
      String maintainerId, String email) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text(
            'Confirm Deletion',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to remove the maintainer with email $email?',
            style: const TextStyle(color: Colors.black87),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Delete'),
              onPressed: () {
                _deleteMaintainer(maintainerId, email);
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteMaintainer(String maintainerId, String email) async {
    try {
      // Unassign all toilets from this maintainer
      QuerySnapshot toiletSnapshot = await FirebaseFirestore.instance
          .collection('toilets')
          .where('assignedMaintainer.id', isEqualTo: maintainerId)
          .get();

      for (var doc in toiletSnapshot.docs) {
        await doc.reference.update({
          'assignedMaintainer': null,
          'maintenanceStatus': 'Unassigned',
        });
      }

      // Delete maintenance tasks for this maintainer
      QuerySnapshot tasksSnapshot = await FirebaseFirestore.instance
          .collection('maintenanceTasks')
          .where('maintainerId', isEqualTo: maintainerId)
          .get();

      for (var doc in tasksSnapshot.docs) {
        await doc.reference.delete();
      }

      // Delete the maintainer from users collection
      await usersCollection.doc(maintainerId).delete();

      // Try to delete from Firebase Auth (requires backend implementation)
      try {
        // This would typically be done via a Cloud Function
        // For now, we'll just log it
        print('Attempting to delete user from Auth: $email');
      } catch (e) {
        print('Error deleting from Auth: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Maintainer removed successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove maintainer: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Widget _buildSearchSection() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search maintainers...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.grey[200],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase();
          });
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.manage_accounts_rounded,
            size: 100,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No maintainers found matching your search'
                : 'No maintainers available',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              _navigateToAddMaintainer();
            },
            icon: const Icon(Icons.person_add),
            label: const Text('Add Your First Maintainer'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaintainerItem(DocumentSnapshot maintainer) {
    final data = maintainer.data() as Map<String, dynamic>;
    final email = data['email'] ?? 'No email';
    final fullName = data['fullName'] ?? 'Unnamed Maintainer';
    final phone = data['phone'] ?? 'No phone';
    final createdAt = data['createdAt'] as Timestamp?;
    final formattedDate = createdAt != null
        ? '${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year}'
        : 'Unknown date';

    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 6), // Reduced horizontal margin
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10), // Reduced from 12
      ),
      elevation: 1, // Reduced from 2
      child: Padding(
        padding:
            const EdgeInsets.all(8.0), // Further reduced padding from 12 to 8
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, // Added to minimize row width
              children: [
                CircleAvatar(
                  radius: 18, // Further reduced from 22 to 18
                  backgroundColor: Colors.blue.shade100,
                  child: Icon(Icons.person,
                      color: Colors.blue.shade800,
                      size: 20), // Reduced from 26 to 20
                ),
                const SizedBox(width: 8), // Reduced from 10 to 8
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                          fontSize: 15, // Further reduced from 16
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2), // Reduced from 4 to 2
                      Row(
                        children: [
                          Icon(Icons.email,
                              size: 12,
                              color: Colors.grey[600]), // Reduced from 14 to 12
                          const SizedBox(width: 3), // Reduced from 4 to 3
                          Expanded(
                            child: Text(
                              email,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12, // Reduced from 13 to 12
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (phone != 'No phone')
                        Padding(
                          padding: const EdgeInsets.only(
                              top: 1), // Reduced from 2 to 1
                          child: Row(
                            children: [
                              Icon(Icons.phone,
                                  size: 12,
                                  color: Colors
                                      .grey[600]), // Reduced from 14 to 12
                              const SizedBox(width: 3), // Reduced from 4 to 3
                              Expanded(
                                child: Text(
                                  phone,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 12, // Reduced from 13 to 12
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 1), // Reduced from 2 to 1
                      Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 12,
                              color: Colors.grey[600]), // Reduced from 14 to 12
                          const SizedBox(width: 3), // Reduced from 4 to 3
                          Expanded(
                            child: Text(
                              'Added: $formattedDate',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12, // Reduced from 13 to 12
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Changed to a column layout for buttons to save horizontal space
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        icon:
                            Icon(Icons.edit, color: Colors.blue[700], size: 14),
                        padding: EdgeInsets.zero,
                        tooltip: 'Edit',
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () {
                          _showEditMaintainerDialog(maintainer.id, data);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: Colors.red, size: 14),
                        padding: EdgeInsets.zero,
                        tooltip: 'Delete',
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () {
                          _confirmDeleteMaintainer(maintainer.id, email);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        icon: Icon(Icons.assignment,
                            color: Colors.green[700], size: 14),
                        padding: EdgeInsets.zero,
                        tooltip: 'Assign Task',
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AssignTaskPage(
                                maintainerId: maintainer.id,
                                maintainerName: fullName,
                                maintainerEmail: email,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Navigation to add maintainer page with refresh upon return
  void _navigateToAddMaintainer() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ImprovedAddMaintainerPage(),
      ),
    );

    // Refresh the list when coming back
    if (mounted) {
      setState(() {
        // This will trigger a refresh of the StreamBuilder
      });
    }
  }

  // Edit maintainer dialog
  Future<void> _showEditMaintainerDialog(
      String maintainerId, Map<String, dynamic> maintainerData) async {
    // Set initial values
    _fullNameController.text = maintainerData['fullName'] ?? '';
    _phoneController.text = maintainerData['phone'] ?? '';

    // Password controllers
    final TextEditingController _passwordController = TextEditingController();
    final TextEditingController _confirmPasswordController =
        TextEditingController();

    // Track password visibility
    bool _obscurePassword = true;
    bool _obscureConfirmPassword = true;

    // Track assigned toilets
    List<Map<String, dynamic>> _assignedToilets = [];
    bool _isLoadingToilets = true;

    // Fetch assigned toilets for this maintainer
    _fetchAssignedToilets(maintainerId).then((toilets) {
      _assignedToilets = toilets;
      if (mounted) {
        setState(() {
          _isLoadingToilets = false;
        });
      }
    });

    // Handle password update
    bool _updatePassword = false;

    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: Row(
              children: [
                Icon(Icons.edit, color: Colors.blue[700]),
                const SizedBox(width: 8),
                const Text(
                  'Edit Maintainer',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Maintainer Basic Information Section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Maintainer Information',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Email field (read-only)
                        TextField(
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Email (cannot be changed)',
                            prefixIcon: const Icon(Icons.email),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[200],
                          ),
                          controller: TextEditingController(
                              text: maintainerData['email'] ?? ''),
                        ),
                        const SizedBox(height: 12),
                        // Name field
                        TextField(
                          controller: _fullNameController,
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Phone field
                        TextField(
                          controller: _phoneController,
                          decoration: InputDecoration(
                            labelText: 'Phone (optional)',
                            prefixIcon: const Icon(Icons.phone),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Password Change Section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Change Password',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                            Switch(
                              value: _updatePassword,
                              onChanged: (value) {
                                setDialogState(() {
                                  _updatePassword = value;
                                  if (!value) {
                                    _passwordController.clear();
                                    _confirmPasswordController.clear();
                                  }
                                });
                              },
                              activeColor: Colors.blue,
                            ),
                          ],
                        ),
                        if (_updatePassword) ...[
                          const SizedBox(height: 12),
                          // New password field
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'New Password',
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setDialogState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Confirm password field
                          TextField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            decoration: InputDecoration(
                              labelText: 'Confirm New Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setDialogState(() {
                                    _obscureConfirmPassword =
                                        !_obscureConfirmPassword;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Toggle the switch to change the password',
                            style: TextStyle(
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Assigned Toilets Section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Assigned Toilets',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                            if (!_isLoadingToilets)
                              Text(
                                '${_assignedToilets.length} toilets',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_isLoadingToilets)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (_assignedToilets.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12.0),
                            child: Text(
                              'No toilets assigned to this maintainer',
                              style: TextStyle(
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        else
                          Container(
                            constraints: const BoxConstraints(
                              maxHeight: 150, // Limit height of toilet list
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                children: _assignedToilets.map((toilet) {
                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8.0),
                                    leading: Icon(Icons.bathroom_outlined,
                                        color: Colors.blue[300]),
                                    title: Text(
                                      toilet['name'] ?? 'Unnamed Toilet',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                    subtitle: Text(
                                      'ID: ${toilet['id'].toString().substring(0, 8)}...',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600]),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.grey)),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Save Changes'),
                onPressed: () {
                  // Validate password if updating
                  if (_updatePassword) {
                    if (_passwordController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Password cannot be empty'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    if (_passwordController.text.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Password must be at least 6 characters'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    if (_passwordController.text !=
                        _confirmPasswordController.text) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Passwords do not match'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                  }

                  _updateMaintainer(
                    maintainerId,
                    _fullNameController.text.trim(),
                    _phoneController.text.trim(),
                    maintainerData['email'],
                    _updatePassword ? _passwordController.text : null,
                  );
                  Navigator.of(dialogContext).pop();
                },
              ),
            ],
          );
        });
      },
    );
  }

  // Fetch toilets assigned to a maintainer
  Future<List<Map<String, dynamic>>> _fetchAssignedToilets(
      String maintainerId) async {
    try {
      QuerySnapshot toiletSnapshot = await FirebaseFirestore.instance
          .collection('toilets')
          .where('assignedMaintainer.id', isEqualTo: maintainerId)
          .get();

      return toiletSnapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'name': data['name'] ?? 'Unnamed Toilet',
          'location': data['location'],
        };
      }).toList();
    } catch (e) {
      print('Error fetching assigned toilets: $e');
      return [];
    }
  }

  // Update maintainer information
  Future<void> _updateMaintainer(
    String maintainerId,
    String fullName,
    String phone,
    String email,
    String? newPassword,
  ) async {
    try {
      // Update user document in Firestore
      await usersCollection.doc(maintainerId).update({
        'fullName': fullName,
        'phone': phone,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update this maintainer in all assigned toilets to reflect name change
      QuerySnapshot toiletSnapshot = await FirebaseFirestore.instance
          .collection('toilets')
          .where('assignedMaintainer.id', isEqualTo: maintainerId)
          .get();

      for (var doc in toiletSnapshot.docs) {
        await doc.reference.update({
          'assignedMaintainer': {
            'id': maintainerId,
            'name': fullName,
            'email': email,
          },
        });
      }

      // Update maintenance tasks to reflect name change
      QuerySnapshot tasksSnapshot = await FirebaseFirestore.instance
          .collection('maintenanceTasks')
          .where('maintainerId', isEqualTo: maintainerId)
          .get();

      for (var doc in tasksSnapshot.docs) {
        await doc.reference.update({
          'maintainerName': fullName,
        });
      }

      // Update password if requested
      if (newPassword != null && newPassword.isNotEmpty) {
        try {
          // Note: Updating password would normally be done through Firebase Auth Admin SDK
          // This would typically be implemented via a Cloud Function
          // For now, we'll show a message indicating this limitation
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Password update requires server-side implementation (Cloud Functions)'),
              backgroundColor: Colors.orange,
            ),
          );

          // In a real implementation, you would call a Cloud Function here
          // Example pseudocode:
          // await FirebaseFunctions.instance.httpsCallable('updateUserPassword').call({
          //   'uid': maintainerId,
          //   'password': newPassword,
          // });
        } catch (e) {
          print('Error updating password: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update password: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Maintainer updated successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update maintainer: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Manage Maintainers',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          _buildSearchSection(),
          Expanded(
            child: _currentOwnerId == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                            'You must be logged in to manage maintainers'),
                      ],
                    ),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: getMaintainersStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }

                      final maintainers = snapshot.data?.docs ?? [];

                      // Filter maintainers based on search query
                      var filteredMaintainers = maintainers;
                      if (_searchQuery.isNotEmpty) {
                        filteredMaintainers = maintainers.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final email =
                              (data['email'] ?? '').toString().toLowerCase();
                          final fullName =
                              (data['fullName'] ?? '').toString().toLowerCase();
                          final phone =
                              (data['phone'] ?? '').toString().toLowerCase();

                          return email.contains(_searchQuery) ||
                              fullName.contains(_searchQuery) ||
                              phone.contains(_searchQuery);
                        }).toList();
                      }

                      if (filteredMaintainers.isEmpty) {
                        return _buildEmptyState();
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(
                            bottom: 80), // Extra space for FAB
                        itemCount: filteredMaintainers.length,
                        itemBuilder: (context, index) {
                          return _buildMaintainerItem(
                              filteredMaintainers[index]);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddMaintainer,
        label: const Text('Add Maintainer'),
        icon: const Icon(Icons.person_add),
        backgroundColor: Colors.green[600],
      ),
    );
  }
}
