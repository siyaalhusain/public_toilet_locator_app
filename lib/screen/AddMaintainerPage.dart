import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ImprovedAddMaintainerPage extends StatefulWidget {
  // Different constructor to force refresh
  const ImprovedAddMaintainerPage({Key? key}) : super(key: key);

  @override
  _ImprovedAddMaintainerPageState createState() =>
      _ImprovedAddMaintainerPageState();
}

class _ImprovedAddMaintainerPageState extends State<ImprovedAddMaintainerPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();

  bool _isSubmitting = false;
  bool _isLoading = true; // Added loading state for initial data fetch
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  List<Map<String, dynamic>> _availableToilets = [];
  List<Map<String, dynamic>> _selectedToilets = [];
  String? _currentOwnerId;
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Force a small delay to ensure Firebase is ready
    Future.delayed(Duration(milliseconds: 300), () {
      _fetchCurrentOwnerAndToilets();
    });
  }

  // Override didChangeDependencies to refresh data when returning to this page
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    print("Page dependencies changed - refreshing data");
    if (!_isLoading) {
      setState(() {
        _isLoading = true;
      });
      _fetchCurrentOwnerAndToilets();
    }
  }

  // Override didUpdateWidget to refresh data when widget is updated
  @override
  void didUpdateWidget(covariant ImprovedAddMaintainerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    print("Widget updated - refreshing data");
    _fetchCurrentOwnerAndToilets();
  }

  // Fetch toilets owned by the current user that don't have a maintainer assigned
  Future<void> _fetchCurrentOwnerAndToilets() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get current logged in user
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        // Handle user not logged in case
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User not logged in. Please log in to continue.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Store current user ID
      setState(() {
        _currentOwnerId = currentUser.uid;
      });

      // Debug statement
      print('Current owner ID: $_currentOwnerId');

      // First, check all toilets regardless of owner to see if any exist
      QuerySnapshot allToiletsSnapshot =
          await FirebaseFirestore.instance.collection('toilets').get();

      print('Total toilets in database: ${allToiletsSnapshot.docs.length}');

      // Then check all toilets for this owner without the assignedMaintainer filter
      QuerySnapshot ownerToiletsSnapshot = await FirebaseFirestore.instance
          .collection('toilets')
          .where('ownerId', isEqualTo: _currentOwnerId)
          .get();

      print(
          'Total toilets for this owner: ${ownerToiletsSnapshot.docs.length}');

      // If there are toilets for this owner, print their IDs and names
      if (ownerToiletsSnapshot.docs.isNotEmpty) {
        print('Owner toilet details:');
        ownerToiletsSnapshot.docs.forEach((doc) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          print('Toilet ID: ${doc.id}');
          print('Full toilet data: $data');
          print('Fields present: ${data.keys.toList()}');

          String ownerId =
              data.containsKey('ownerId') ? data['ownerId'] : 'field missing';
          String name =
              data.containsKey('name') ? data['name'] : 'name missing';

          // Check if the ownerId matches exactly (to catch case sensitivity issues)
          bool ownerMatches = ownerId == _currentOwnerId;
          print('Owner matches current user: $ownerMatches');

          // Check the structure of the assignedMaintainer field
          if (data.containsKey('assignedMaintainer')) {
            print('assignedMaintainer value: ${data['assignedMaintainer']}');
            print(
                'assignedMaintainer type: ${data['assignedMaintainer']?.runtimeType}');
          } else {
            print('assignedMaintainer field missing entirely');
          }
        });
      }

      // Query Firestore for ALL toilets owned by current user (regardless of assignment status)
      // Without any filtering on assignedMaintainer field
      QuerySnapshot toiletSnapshot;
      try {
        // Get all toilets for the current owner - NO FILTER on assignedMaintainer
        toiletSnapshot = await FirebaseFirestore.instance
            .collection('toilets')
            .where('ownerId', isEqualTo: _currentOwnerId)
            .get();

        print(
            'Found ${toiletSnapshot.docs.length} total toilets for this owner');

        // Debug: Print each toilet's details
        toiletSnapshot.docs.forEach((doc) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          print(
              'Toilet ID: ${doc.id}, Name: ${data['name'] ?? 'unnamed'}, Owner ID: ${data['ownerId']}');
          if (data.containsKey('assignedMaintainer')) {
            print('  Has maintainer: ${data['assignedMaintainer'] != null}');
            if (data['assignedMaintainer'] != null) {
              print('  Maintainer details: ${data['assignedMaintainer']}');
            }
          } else {
            print('  No assignedMaintainer field exists');
          }
        });
      } catch (e) {
        print('Error fetching toilets: $e');
        // Initialize empty snapshot to avoid null errors
        toiletSnapshot = await FirebaseFirestore.instance
            .collection('toilets')
            .limit(0)
            .get();
      }

      // If we made it here, we're using the results from Approach 1
      print(
          'Using results from query: ${toiletSnapshot.docs.length} unassigned toilets');

      // Map query results to a list of maps, flagging already assigned toilets
      List<Map<String, dynamic>> mappedToilets = [];

      for (var doc in toiletSnapshot.docs) {
        try {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

          // Check if toilet is already assigned to a maintainer
          bool isAssigned = false;
          String assignedTo = "";

          if (data.containsKey('assignedMaintainer') &&
              data['assignedMaintainer'] != null) {
            isAssigned = true;

            // Try to get maintainer name if available
            if (data['assignedMaintainer'] is Map &&
                (data['assignedMaintainer'] as Map).containsKey('name')) {
              assignedTo =
                  (data['assignedMaintainer'] as Map)['name'].toString();
            }
          }

          // Add toilet data with assignment information
          mappedToilets.add({
            'id': doc.id,
            'isAssigned': isAssigned,
            'assignedTo': assignedTo,
            ...data
          });

          print(
              'Mapped toilet: ${doc.id}, Name: ${data['name'] ?? 'Unnamed'}, Assigned: $isAssigned');
        } catch (e) {
          print('Error mapping toilet ${doc.id}: $e');
        }
      }

      setState(() {
        _availableToilets = mappedToilets;
        _isLoading = false;
      });

      print('Final available toilets count: ${_availableToilets.length}');

      // Additional debug to verify toilet data
      if (_availableToilets.isNotEmpty) {
        print('First toilet name: ${_availableToilets[0]['name']}');
      }
    } catch (e) {
      print('Error fetching toilets: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching toilets: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Validate email format
  bool _isValidEmail(String email) {
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email);
  }

  // Validate password
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters long';
    }
    return null;
  }

  // Handle form submission
  Future<void> _submitForm() async {
    // Validate form inputs
    if (_formKey.currentState!.validate()) {
      // Check if passwords match
      if (_passwordController.text != _confirmPasswordController.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Passwords do not match'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Check if at least one toilet is selected
      if (_selectedToilets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one toilet to assign'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Check if there are any already assigned toilets and confirm with user
      List<Map<String, dynamic>> alreadyAssignedToilets = _selectedToilets
          .where((toilet) => toilet['isAssigned'] == true)
          .toList();

      if (alreadyAssignedToilets.isNotEmpty) {
        // Show confirmation dialog
        bool proceed = await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Confirm Reassignment'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${alreadyAssignedToilets.length} of the selected toilets are already assigned to other maintainers:'),
                    SizedBox(height: 8),
                    ...alreadyAssignedToilets
                        .map((toilet) => Padding(
                              padding: EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• ${toilet['name'] ?? 'Unnamed toilet'} (currently assigned to ${toilet['assignedTo']})',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ))
                        .toList(),
                    SizedBox(height: 8),
                    Text('Are you sure you want to reassign these toilets?'),
                  ],
                ),
                actions: [
                  TextButton(
                    child: Text('Cancel'),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  ElevatedButton(
                    child: Text('Proceed'),
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                  ),
                ],
              ),
            ) ??
            false; // Default to false if dialog is dismissed

        if (!proceed) {
          return; // User cancelled the operation
        }
      }

      setState(() {
        _isSubmitting = true;
      });

      try {
        // Create new user account in Firebase Authentication
        UserCredential userCredential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        // Create user document in Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
          'email': _emailController.text.trim(),
          'fullName': _fullNameController.text.trim(),
          'role': 'Maintainer',
          'createdAt': FieldValue.serverTimestamp(),
          'ownerId': _currentOwnerId, // Link maintainer to owner
        });

        // Update each selected toilet with maintainer info
        for (var toilet in _selectedToilets) {
          await FirebaseFirestore.instance
              .collection('toilets')
              .doc(toilet['id'])
              .update({
            'assignedMaintainer': {
              'id': userCredential.user!.uid,
              'name': _fullNameController.text.trim(),
              'email': _emailController.text.trim(),
            },
            'maintenanceStatus': 'Assigned',
            'assignedAt': FieldValue.serverTimestamp(),
          });

          // Create maintenance task for each assigned toilet
          await FirebaseFirestore.instance.collection('maintenanceTasks').add({
            'toiletId': toilet['id'],
            'toiletName': toilet['name'] ?? 'Unnamed Toilet',
            'maintainerId': userCredential.user!.uid,
            'maintainerName': _fullNameController.text.trim(),
            'ownerId': _currentOwnerId,
            'status': 'Pending',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        if (mounted) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Maintainer created and ${_selectedToilets.length} toilets assigned'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );

          // Reset form and state
          _formKey.currentState!.reset();
          _emailController.clear();
          _passwordController.clear();
          _confirmPasswordController.clear();
          _fullNameController.clear();
          setState(() {
            _selectedToilets.clear();
            _isSubmitting = false;
          });

          // Refresh available toilets list after a brief delay
          // This ensures Firestore has time to update
          Future.delayed(Duration(seconds: 1), () {
            _fetchCurrentOwnerAndToilets();
          });
        }
      } on FirebaseAuthException catch (e) {
        // Handle Firebase Auth specific errors
        String errorMessage = _getAuthErrorMessage(e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        // Handle general errors
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating account: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  // Translates Firebase Auth error codes to user-friendly messages
  String _getAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'The email address is already in use';
      case 'invalid-email':
        return 'The email address is invalid';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled';
      case 'weak-password':
        return 'The password is too weak';
      default:
        return 'An error occurred during authentication';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Create Maintainer Account',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          // Add refresh button
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Refreshing toilet list...'),
                  backgroundColor: Colors.blue,
                ),
              );
              setState(() {
                _isLoading = true; // Show loading indicator while refreshing
                _selectedToilets.clear(); // Clear selections when refreshing
              });
              _fetchCurrentOwnerAndToilets();
            },
            tooltip: 'Refresh toilet list',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? _buildLoadingIndicator()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildMaintainerDetailsSection(),
                      const SizedBox(height: 24),
                      _buildToiletAssignmentSection(),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[600],
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSubmitting
                            ? const CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              )
                            : const Text(
                                'Create Maintainer Account',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // Loading indicator widget
  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.green[600]),
          const SizedBox(height: 16),
          Text(
            'Loading available toilets...',
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  // Maintainer personal information form section
  Widget _buildMaintainerDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _fullNameController,
          decoration: InputDecoration(
            labelText: 'Full Name',
            prefixIcon: const Icon(Icons.person),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[100],
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter full name';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _emailController,
          decoration: InputDecoration(
            labelText: 'Email Address',
            prefixIcon: const Icon(Icons.email),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[100],
          ),
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter an email address';
            }
            if (!_isValidEmail(value)) {
              return 'Please enter a valid email address';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[100],
          ),
          obscureText: _obscurePassword,
          validator: _validatePassword,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _confirmPasswordController,
          decoration: InputDecoration(
            labelText: 'Confirm Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
              ),
              onPressed: () {
                setState(() {
                  _obscureConfirmPassword = !_obscureConfirmPassword;
                });
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[100],
          ),
          obscureText: _obscureConfirmPassword,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please confirm your password';
            }
            if (value != _passwordController.text) {
              return 'Passwords do not match';
            }
            return null;
          },
        ),
      ],
    );
  }

  // Toilet selection and assignment section
  Widget _buildToiletAssignmentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Assign Toilets',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.green[800],
          ),
        ),
        const SizedBox(height: 16),
        if (_availableToilets.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 4.0),
                        child: Text(
                          'Found ${_availableToilets.length} toilets for your account',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableToilets.map((toilet) {
                          final isSelected = _selectedToilets
                              .any((t) => t['id'] == toilet['id']);

                          // Get the toilet name, with multiple fallbacks
                          String toiletName = 'Unnamed Toilet';
                          if (toilet.containsKey('name') &&
                              toilet['name'] != null) {
                            toiletName = toilet['name'].toString();
                          } else if (toilet.containsKey('toiletName') &&
                              toilet['toiletName'] != null) {
                            toiletName = toilet['toiletName'].toString();
                          }

                          // Include ID to ensure we can identify it
                          String toiletId = toilet['id'] != null
                              ? toilet['id'].toString()
                              : '';
                          String displayName = toiletName;

                          // Include additional information if available
                          if (toilet.containsKey('location')) {
                            var location = toilet['location'];
                            if (location is Map &&
                                location.containsKey('latitude') &&
                                location.containsKey('longitude')) {
                              displayName +=
                                  ' (${location['latitude'].toStringAsFixed(2)}, ${location['longitude'].toStringAsFixed(2)})';
                            }
                          }

                          // Check if this toilet is already assigned
                          bool isAssigned = toilet['isAssigned'] == true;
                          String assignedTo = toilet['assignedTo'] ?? '';

                          // Create tooltip text
                          String tooltipText = 'ID: $toiletId';
                          if (isAssigned) {
                            tooltipText += '\nAlready assigned to: $assignedTo';
                          }

                          return Tooltip(
                            message: tooltipText,
                            child: FilterChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Show an icon to indicate assignment status
                                  if (isAssigned)
                                    Icon(
                                      Icons.person_outlined,
                                      size: 16,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.orange,
                                    ),
                                  if (isAssigned) SizedBox(width: 4),
                                  Text(
                                    displayName,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : (isAssigned
                                              ? Colors.black54
                                              : Colors.black),
                                      decoration: isAssigned
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                              selected: isSelected,
                              onSelected: (bool selected) {
                                // Show warning if trying to select already assigned toilet
                                if (selected && isAssigned) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'This toilet is already assigned to $assignedTo. Assigning it to a new maintainer will override the existing assignment.'),
                                      backgroundColor: Colors.orange,
                                      action: SnackBarAction(
                                        label: 'OK',
                                        onPressed: () {
                                          // Add to selected toilets anyway
                                          setState(() {
                                            _selectedToilets.add(toilet);
                                          });
                                        },
                                      ),
                                    ),
                                  );
                                  return; // Don't select automatically
                                }

                                setState(() {
                                  if (selected) {
                                    _selectedToilets.add(toilet);
                                  } else {
                                    _selectedToilets.removeWhere(
                                        (t) => t['id'] == toilet['id']);
                                  }
                                });
                              },
                              selectedColor: Colors.green[600],
                              backgroundColor:
                                  isAssigned ? Colors.grey[100] : Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: isAssigned
                                      ? Colors.orange[200]!
                                      : Colors.green[200]!,
                                  width: isAssigned ? 0.5 : 1.0,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.bathroom_rounded,
                  size: 60,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No available toilets to assign',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'You may need to add toilets first or all toilets are already assigned',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        if (_selectedToilets.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected Toilets',
                    style: TextStyle(
                      color: Colors.green[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedToilets.map((toilet) {
                      return Chip(
                        label: Text(toilet['name'] ?? 'Unnamed Toilet'),
                        backgroundColor: Colors.green[100],
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () {
                          setState(() {
                            _selectedToilets
                                .removeWhere((t) => t['id'] == toilet['id']);
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total Toilets Selected: ${_selectedToilets.length}',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
