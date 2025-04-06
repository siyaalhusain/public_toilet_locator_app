import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ImprovedManageMaintainersPage extends StatefulWidget {
  const ImprovedManageMaintainersPage({Key? key}) : super(key: key);

  @override
  _ImprovedManageMaintainersPageState createState() =>
      _ImprovedManageMaintainersPageState();
}

class _ImprovedManageMaintainersPageState
    extends State<ImprovedManageMaintainersPage> {
  final CollectionReference maintainersCollection =
      FirebaseFirestore.instance.collection('maintainers');

  // Search and filter
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Confirm deletion of maintainer
  Future<void> _confirmDeleteMaintainer(String documentId, String email) async {
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
                _deleteMaintainer(documentId, email);
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Delete a maintainer
  Future<void> _deleteMaintainer(String documentId, String email) async {
    try {
      // First, delete the user from Firebase Authentication
      await _deleteUserFromAuth(email);

      // Then delete the document from Firestore
      await maintainersCollection.doc(documentId).delete();

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

  // Delete user from Firebase Authentication
  Future<void> _deleteUserFromAuth(String email) async {
    try {
      // Note: This requires appropriate admin privileges or backend function
      // In a real-world scenario, you'd typically use Firebase Admin SDK or a cloud function
      // Here's a placeholder implementation
      print('Deleting user with email: $email');
      // Actual deletion would require backend authentication
    } catch (e) {
      print('Error deleting user from Auth: $e');
      throw Exception('Could not remove user from authentication');
    }
  }

  // Build search section
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

  // Build empty state widget
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
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
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
          // Search section
          _buildSearchSection(),

          // Maintainers list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: maintainersCollection
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                // Loading state
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Error state
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red[300],
                          size: 80,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading maintainers',
                          style: TextStyle(color: Colors.red[300]),
                        ),
                        Text('${snapshot.error}'),
                      ],
                    ),
                  );
                }

                // Filter maintainers
                final maintainers = (snapshot.data?.docs ?? []).where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  final fullName =
                      (data['fullName'] ?? '').toString().toLowerCase();
                  return email.contains(_searchQuery) ||
                      fullName.contains(_searchQuery);
                }).toList();

                // Empty state
                if (maintainers.isEmpty) {
                  return _buildEmptyState();
                }

                // Maintainers list
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: maintainers.length,
                  itemBuilder: (context, index) {
                    final doc = maintainers[index];
                    final data = doc.data() as Map<String, dynamic>;

                    return Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue[600],
                          child: Text(
                            (data['fullName'] ?? 'M')
                                .toString()
                                .characters
                                .first
                                .toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          data['fullName'] ?? 'Unnamed Maintainer',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['email'] ?? 'No email',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            if (data['createdAt'] != null)
                              Text(
                                'Added: ${_formatTimestamp(data['createdAt'])}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                          ),
                          onPressed: () => _confirmDeleteMaintainer(
                              doc.id, data['email'] ?? 'Unknown'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to format timestamp
  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';

    final DateTime date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year}';
  }
}
