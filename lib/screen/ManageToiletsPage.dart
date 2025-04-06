import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class ManageToiletsPage extends StatefulWidget {
  @override
  _ManageToiletsPageState createState() => _ManageToiletsPageState();
}

class _ManageToiletsPageState extends State<ManageToiletsPage> {
  final CollectionReference toiletsCollection =
      FirebaseFirestore.instance.collection('toilets');
  String _searchQuery = '';
  bool _isLoading = false;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Toilets'),
        actions: [
          IconButton(
            icon: Icon(Icons.search),
            onPressed: () {
              // You can implement search functionality here
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search toilets...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 0),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
            ),
          ),

          // Toilets list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: toiletsCollection
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
                    final name = (data['name'] ?? '').toString().toLowerCase();
                    return name.contains(_searchQuery.toLowerCase());
                  }).toList();
                }

                if (filteredToilets.isEmpty) {
                  return const Center(child: Text('No toilets available.'));
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
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.wc, color: Colors.blue),
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

                                // Delete menu
                                PopupMenuButton(
                                  onSelected: (value) {
                                    if (value == 'delete') {
                                      _deleteToilet(doc.id);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete,
                                              color: Colors.red, size: 20),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
          // Navigate to add toilet page
        },
        child: Icon(Icons.add),
        tooltip: 'Add Toilet',
      ),
    );
  }
}
