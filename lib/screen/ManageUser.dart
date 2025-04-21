import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ManageUsersPage extends StatefulWidget {
  @override
  _ManageUsersPageState createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  String _selectedRole = 'User';
  bool _isLoading = false;
  bool _loadingUsers = true;
  bool _hidePassword = true;
  late TabController _tabController;

  // Store real users from Firestore
  List<Map<String, dynamic>> _users = [];

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchUsers();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // Method to fetch users from Firestore - all owners (active and inactive) and admin-added users
  Future<void> _fetchUsers() async {
    setState(() {
      _loadingUsers = true;
    });

    try {
      // Get all owners from Firestore (both active and inactive)
      final QuerySnapshot ownersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'Owner')
          .get();

      // Get all admin-added users from Firestore
      final QuerySnapshot adminAddedSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('addedBy', isNotEqualTo: '')
          .get();

      // Combine results while avoiding duplicates
      Set<String> addedIds = {};
      List<Map<String, dynamic>> fetchedUsers = [];

      // First add all owners (active and inactive)
      for (var doc in ownersSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        fetchedUsers.add({
          'id': doc.id,
          'name': data['name'] ?? 'No Name',
          'email': data['email'] ?? 'No Email',
          'role': data['role'] ?? 'User',
          'status': data['status'] ?? 'Active',
          'addedBy': data['addedBy'] ?? '',
          'isAccountActive': data['isAccountActive'] ?? false,
        });
        addedIds.add(doc.id);
      }

      // Then add admin-added users that aren't already in the list
      for (var doc in adminAddedSnapshot.docs) {
        if (!addedIds.contains(doc.id)) {
          final data = doc.data() as Map<String, dynamic>;
          fetchedUsers.add({
            'id': doc.id,
            'name': data['name'] ?? 'No Name',
            'email': data['email'] ?? 'No Email',
            'role': data['role'] ?? 'User',
            'status': data['status'] ?? 'Active',
            'addedBy': data['addedBy'] ?? '',
            'isAccountActive': data['isAccountActive'] ?? false,
          });
          addedIds.add(doc.id);
        }
      }

      setState(() {
        _users = fetchedUsers;
        _loadingUsers = false;
      });
    } catch (e) {
      print('Error fetching users: $e');
      setState(() {
        _loadingUsers = false;
      });
      _showSnackBar('Error fetching users: ${e.toString()}', Colors.red);
    }
  }

  // Method to handle adding a user
  Future<void> _addUser() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        String email = _emailController.text.trim();
        String password = _passwordController.text.trim();
        String name = _nameController.text.trim();

        // Get current admin user
        User? currentUser = FirebaseAuth.instance.currentUser;
        String adminId = currentUser?.uid ?? '';

        // Create user in Firebase Auth
        UserCredential userCredential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Add user to Firestore with admin info
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
          'name': name,
          'email': email,
          'role': _selectedRole,
          'status': 'Active',
          'addedBy': adminId, // Track that this user was added by an admin
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Reload users list to show the newly added user
        await _fetchUsers();

        // Clear the form
        _emailController.clear();
        _passwordController.clear();
        _nameController.clear();
        setState(() {
          _selectedRole = 'User';
          _isLoading = false;
        });

        // Show success message
        _showSnackBar('User added successfully!', Colors.green);

        // Switch to users list tab
        _tabController.animateTo(0);
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        _showSnackBar('Error adding user: ${e.toString()}', Colors.red);
      }
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(8),
      ),
    );
  }

  // Implemented edit user functionality
  void _editUser(Map<String, dynamic> user) {
    final TextEditingController _editNameController =
        TextEditingController(text: user['name']);
    final TextEditingController _editEmailController =
        TextEditingController(text: user['email']);
    String _editSelectedRole = user['role'];
    String _editSelectedStatus = user['status'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit User'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Name Field
              TextField(
                controller: _editNameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              SizedBox(height: 16),

              // Email Field (display only, not editable)
              TextField(
                controller: _editEmailController,
                enabled: false, // Email cannot be changed
                decoration: InputDecoration(
                  labelText: 'Email (cannot be changed)',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  fillColor: Colors.grey.shade100,
                  filled: true,
                ),
              ),
              SizedBox(height: 16),

              // Role Dropdown
              DropdownButtonFormField<String>(
                value: _editSelectedRole,
                decoration: InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: ['Admin', 'User', 'Owner', 'Maintainer']
                    .map((role) => DropdownMenuItem(
                          value: role,
                          child: Text(role),
                        ))
                    .toList(),
                onChanged: (value) {
                  _editSelectedRole = value!;
                },
              ),
              SizedBox(height: 16),

              // Status Dropdown
              DropdownButtonFormField<String>(
                value: _editSelectedStatus,
                decoration: InputDecoration(
                  labelText: 'Status',
                  prefixIcon: Icon(Icons.toggle_on),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: ['Active', 'Inactive', 'Suspended']
                    .map((status) => DropdownMenuItem(
                          value: status,
                          child: Text(status),
                        ))
                    .toList(),
                onChanged: (value) {
                  _editSelectedStatus = value!;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() {
                _isLoading = true;
              });

              try {
                // Update user in Firestore
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user['id'])
                    .update({
                  'name': _editNameController.text.trim(),
                  'role': _editSelectedRole,
                  'status': _editSelectedStatus,
                  'updatedAt': FieldValue.serverTimestamp(),
                });

                // Reload users list
                await _fetchUsers();

                _showSnackBar('User updated successfully', Colors.green);
              } catch (e) {
                _showSnackBar(
                    'Error updating user: ${e.toString()}', Colors.red);
              } finally {
                setState(() {
                  _isLoading = false;
                });
              }
            },
            child: Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _deleteUser(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete User'),
        content: Text('Are you sure you want to delete ${user['name']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              try {
                // Delete from Firestore
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user['id'])
                    .delete();

                // Note: Deleting the actual Firebase Auth user would require either admin SDK
                // or an admin-authorized Cloud Function

                // Reload the users list
                await _fetchUsers();

                _showSnackBar('User deleted successfully', Colors.green);
              } catch (e) {
                _showSnackBar(
                    'Error deleting user: ${e.toString()}', Colors.red);
              }
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredUsers {
    if (_searchQuery.isEmpty) return _users;

    return _users.where((user) {
      final name = user['name'].toString().toLowerCase();
      final email = user['email'].toString().toLowerCase();
      final role = user['role'].toString().toLowerCase();
      final query = _searchQuery.toLowerCase();

      return name.contains(query) ||
          email.contains(query) ||
          role.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Manage Users'),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Theme.of(context).primaryColor,
          tabs: [
            Tab(text: 'Users'),
            Tab(text: 'Add User'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Users List Tab
          _buildUsersList(),

          // Add User Tab
          _buildAddUserForm(),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search users...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),

        // Users count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_filteredUsers.length} users',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              TextButton.icon(
                onPressed: () => _fetchUsers(),
                icon: Icon(Icons.refresh, size: 18),
                label: Text('Refresh'),
              ),
            ],
          ),
        ),

        Expanded(
          child: _loadingUsers
              ? Center(child: CircularProgressIndicator())
              : _filteredUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No users found',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            Text(
                              'Try a different search term',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                              ),
                            ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.all(16),
                      itemCount: _filteredUsers.length,
                      separatorBuilder: (context, index) => Divider(height: 1),
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];
                        return _buildUserListItem(user);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildUserListItem(Map<String, dynamic> user) {
    Color roleColor;
    switch (user['role']) {
      case 'Admin':
        roleColor = Colors.red;
        break;
      case 'Owner':
        roleColor = Colors.purple;
        break;
      case 'Maintainer':
        roleColor = Colors.blue;
        break;
      default:
        roleColor = Colors.green;
    }

    // Check if user was added by admin
    bool isAdminAdded =
        user['addedBy'] != null && user['addedBy'].toString().isNotEmpty;

    return Card(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        leading: CircleAvatar(
          backgroundColor: roleColor.withOpacity(0.2),
          child: Text(
            user['name'].isNotEmpty
                ? user['name'].substring(0, 1).toUpperCase()
                : '?',
            style: TextStyle(
              color: roleColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Flexible(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  user['name'],
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isAdminAdded)
                Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: Icon(
                    Icons.verified_user,
                    size: 14,
                    color: Colors.blue,
                  ),
                ),
            ],
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text(
              user['email'],
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
            SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: roleColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      user['role'],
                      style: TextStyle(
                        color: roleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: user['status'] == 'Active'
                          ? Colors.green.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      user['status'],
                      style: TextStyle(
                        color: user['status'] == 'Active'
                            ? Colors.green
                            : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isAdminAdded)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Admin Added',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'edit') {
              _editUser(user);
            } else if (value == 'delete') {
              _deleteUser(user);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'edit',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddUserForm() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Form title and description
              Text(
                'Add New User',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Fill in the details to create a new user account',
                style: TextStyle(
                  color: Colors.grey.shade600,
                ),
              ),
              SizedBox(height: 24),

              // Name Field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Email Field
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an email';
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Password Field
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _hidePassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _hidePassword = !_hidePassword;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                obscureText: _hidePassword,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Role Dropdown
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                items: ['Admin', 'User', 'Owner', 'Maintainer']
                    .map((role) => DropdownMenuItem(
                          value: role,
                          child: Text(role),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedRole = value!;
                  });
                },
              ),
              SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _addUser,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 2,
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        )
                      : Text(
                          'Add User',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              SizedBox(height: 16),

              // Cancel Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () {
                    // Clear the form
                    _emailController.clear();
                    _passwordController.clear();
                    _nameController.clear();
                    setState(() {
                      _selectedRole = 'User';
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: BorderSide(color: Theme.of(context).primaryColor),
                  ),
                  child: Text(
                    'Clear Form',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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
