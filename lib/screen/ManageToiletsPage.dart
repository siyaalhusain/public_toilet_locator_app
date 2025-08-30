import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'AddToiletPage.dart';

class ManageToiletsPage extends StatefulWidget {
  @override
  _ManageToiletsPageState createState() => _ManageToiletsPageState();
}
//comments
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
      'imageUrls':
          toiletData['imageUrls'] ?? [], // Include image URLs for editing
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

  // Method to show a carousel of images
  void _showImageCarousel(List<String> imageUrls, String toiletName) {
    if (imageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No images available for this toilet')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  toiletName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                height: MediaQuery.of(context).size.height * 0.4,
                child: PageView.builder(
                  itemCount: imageUrls.length,
                  itemBuilder: (context, index) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          imageUrls[index],
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error, color: Colors.red),
                                  SizedBox(height: 8),
                                  Text('Failed to load image'),
                                ],
                              ),
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes !=
                                        null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                        ),
                        Positioned(
                          bottom: 16,
                          right: 16,
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${index + 1}/${imageUrls.length}',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              ButtonBar(
                alignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text('Close'),
                  ),
                ],
              ),
            ],
          ),
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
              // Show search dialog
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Search Toilets'),
                  content: TextField(
                    decoration: InputDecoration(
                      hintText: 'Enter toilet name',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                      Navigator.pop(context);
                    },
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        // Search is already handled by onChanged
                        Navigator.pop(context);
                      },
                      child: Text('Search'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search query indicator
          if (_searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Chip(
                label: Text('Searching: $_searchQuery'),
                deleteIcon: Icon(Icons.close, size: 18),
                onDeleted: () {
                  setState(() {
                    _searchQuery = '';
                  });
                },
              ),
            ),

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

                          // Get image URLs safely
                          List<String> imageUrls = [];
                          if (data['imageUrls'] != null &&
                              data['imageUrls'] is List) {
                            imageUrls = List<String>.from(data['imageUrls']);
                          }

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
                            child: Column(
                              children: [
                                // Image preview (if available)
                                if (imageUrls.isNotEmpty)
                                  GestureDetector(
                                    onTap: () => _showImageCarousel(imageUrls,
                                        data['name'] ?? 'Unnamed Toilet'),
                                    child: Container(
                                      height: 150,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(12),
                                          topRight: Radius.circular(12),
                                        ),
                                      ),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.only(
                                              topLeft: Radius.circular(12),
                                              topRight: Radius.circular(12),
                                            ),
                                            child: Image.network(
                                              imageUrls.first,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                return Container(
                                                  color: Colors.grey[300],
                                                  child: Center(
                                                    child: Icon(
                                                      Icons.image_not_supported,
                                                      size: 40,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          if (imageUrls.length > 1)
                                            Positioned(
                                              bottom: 8,
                                              right: 8,
                                              child: Container(
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.black54,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  '+${imageUrls.length - 1} more',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),

                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                            child: Icon(Icons.wc,
                                                color: Colors.blue),
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

                                          // Image count badge (if there are images)
                                          if (imageUrls.isNotEmpty)
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.green[100],
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.image,
                                                      size: 16,
                                                      color: Colors.green[800]),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    '${imageUrls.length}',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.green[800],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                          // Options menu
                                          PopupMenuButton(
                                            onSelected: (value) {
                                              if (value == 'delete') {
                                                _deleteToilet(doc.id);
                                              } else if (value == 'edit') {
                                                _editToilet(doc.id, data);
                                              } else if (value ==
                                                  'view_images') {
                                                _showImageCarousel(
                                                    imageUrls,
                                                    data['name'] ??
                                                        'Unnamed Toilet');
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              if (imageUrls.isNotEmpty)
                                                PopupMenuItem(
                                                  value: 'view_images',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.photo_library,
                                                          color: Colors.purple,
                                                          size: 20),
                                                      SizedBox(width: 8),
                                                      Text('View Images'),
                                                    ],
                                                  ),
                                                ),
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

                                // Actions row
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 16, right: 16, bottom: 16),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          _editToilet(doc.id, data);
                                        },
                                        icon: Icon(Icons.edit, size: 18),
                                        label: Text('Edit'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.blue,
                                          side: BorderSide(color: Colors.blue),
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: imageUrls.isNotEmpty
                                            ? () => _showImageCarousel(
                                                imageUrls,
                                                data['name'] ??
                                                    'Unnamed Toilet')
                                            : null,
                                        icon:
                                            Icon(Icons.photo_library, size: 18),
                                        label: Text('Images'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.purple,
                                          side: BorderSide(
                                              color: imageUrls.isNotEmpty
                                                  ? Colors.purple
                                                  : Colors.grey),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => AddToiletPage(isEditing: false)),
          );
        },
        icon: Icon(Icons.add),
        label: Text('Add Toilet'),
        tooltip: 'Add Toilet',
      ),
    );
  }
}
