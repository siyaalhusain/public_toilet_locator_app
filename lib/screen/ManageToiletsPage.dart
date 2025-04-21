import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'AddToiletPage.dart';

class ManageToiletsPage extends StatefulWidget {
  @override
  _ManageToiletsPageState createState() => _ManageToiletsPageState();
}

class _ManageToiletsPageState extends State<ManageToiletsPage> {
  final CollectionReference toiletsCollection =
      FirebaseFirestore.instance.collection('toilets');
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String _searchQuery = '';
  bool _isLoading = false;
  String? _currentUserId;
  String? _currentUserEmail;

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
  }

  void _getCurrentUser() {
    final user = _auth.currentUser;
    if (user != null) {
      setState(() {
        _currentUserId = user.uid;
        _currentUserEmail = user.email;
      });
    }
  }

  void _deleteToilet(String documentId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await toiletsCollection.doc(documentId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Toilet deleted successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete toilet: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _editToilet(String documentId, Map<String, dynamic> toiletData) {
    // Create a new map from the Firestore data to avoid any potential issues
    final Map<String, dynamic> editableData = {
      'name': toiletData['name'] ?? '',
      'amenities': toiletData['amenities'] ?? [],
      'location': toiletData['location'] ?? {'latitude': 0.0, 'longitude': 0.0},
    };

    // Navigate to the edit page with the toilet data
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddToiletPage(
          isEditing: true,
          toiletId: documentId,
          toiletData: editableData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Toilets'),
        actions: [
          IconButton(
            icon: Icon(Icons.search),
            onPressed: () {
              // Implement search functionality
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Toilets list
          Expanded(
            child: _currentUserId == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.red),
                        SizedBox(height: 16),
                        Text('You must be logged in to manage toilets'),
                      ],
                    ),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: toiletsCollection
                        .where('ownerId', isEqualTo: _currentUserId)
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting ||
                          _isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }

                      final toilets = snapshot.data?.docs ?? [];

                      // Filter toilets based on search query
                      var filteredToilets = toilets;
                      if (_searchQuery.isNotEmpty) {
                        filteredToilets = toilets.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final name =
                              (data['name'] ?? '').toString().toLowerCase();
                          return name.contains(_searchQuery.toLowerCase());
                        }).toList();
                      }

                      if (filteredToilets.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.wc, size: 48, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No toilets found',
                                style: TextStyle(fontSize: 18),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Add your first toilet using the + button',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: filteredToilets.length,
                        itemBuilder: (context, index) {
                          final doc = filteredToilets[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final location = data['location'] ?? {};

                          // Handle amenities data safely
                          String amenitiesText = 'No amenities';
                          if (data['amenities'] != null) {
                            var amenities = data['amenities'];
                            if (amenities is List) {
                              amenitiesText = amenities.join(', ');
                            } else if (amenities is String) {
                              amenitiesText = amenities;
                            }
                          }

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      // Toilet icon
                                      Container(
                                        padding: EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child:
                                            Icon(Icons.wc, color: Colors.blue),
                                      ),
                                      SizedBox(width: 12),

                                      // Toilet name
                                      Expanded(
                                        child: Text(
                                          data['name'] ?? 'Unnamed Toilet',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),

                                      // Options menu
                                      PopupMenuButton(
                                        onSelected: (value) {
                                          if (value == 'delete') {
                                            _deleteToilet(doc.id);
                                          } else if (value == 'edit') {
                                            _editToilet(doc.id, data);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit,
                                                    color: Colors.blue,
                                                    size: 20),
                                                SizedBox(width: 8),
                                                Text('Edit'),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete,
                                                    color: Colors.red,
                                                    size: 20),
                                                SizedBox(width: 8),
                                                Text('Delete'),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 12),

                                  // Amenities
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.bathroom_outlined,
                                          size: 16, color: Colors.grey),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Amenities: $amenitiesText',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),

                                  // Location
                                  if (location['latitude'] != null &&
                                      location['longitude'] != null)
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.location_on,
                                            size: 16, color: Colors.grey),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Location: (${location['latitude'].toStringAsFixed(4)}, ${location['longitude'].toStringAsFixed(4)})',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[700],
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
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => AddToiletPage(isEditing: false)),
          );
        },
        child: Icon(Icons.add),
        tooltip: 'Add Toilet',
      ),
    );
  }
}
