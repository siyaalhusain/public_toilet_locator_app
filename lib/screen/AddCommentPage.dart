import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as Math;
import 'MapSelectionPage.dart';

class LatLng {
  final double latitude;
  final double longitude;

  LatLng(this.latitude, this.longitude);
}

class AddCommentPage extends StatefulWidget {
  final String? toiletId;
  final String? toiletName;

  const AddCommentPage({super.key, this.toiletId, this.toiletName});

  @override
  _AddCommentPageState createState() => _AddCommentPageState();
}

class _AddCommentPageState extends State<AddCommentPage> {
  final TextEditingController _commentController = TextEditingController();
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  String? _selectedToiletId;
  String? _selectedToiletName;
  double _rating = 3.0;
  final Map<String, double> _categoryRatings = {
    'Cleanliness': 3.0,
    'Accessibility': 3.0,
    'Facilities': 3.0,
  };
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _nearbyToilets = [];
  List<Map<String, dynamic>> _recentToilets = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _showToiletsList = false;
  final TextEditingController _searchController = TextEditingController();
  LatLng? _userLocation;
  bool _isSearching = false;
  String _searchError = '';

  @override
  void initState() {
    super.initState();
    _selectedToiletId = widget.toiletId;
    _selectedToiletName = widget.toiletName;
    _getUserLocation();
    _loadRecentToilets();
  }

  // Get user's current location
  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar("Location services are disabled", Colors.red);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar("Location permission denied", Colors.red);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar(
            "Location permissions are permanently denied", Colors.red);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });

      // Load nearby toilets once we have user's location
      _fetchNearbyToilets();
    } catch (e) {
      print("Error getting location: $e");
      _showSnackBar("Could not get your location", Colors.red);
    }
  }

  // Load toilets the user has recently commented on
  Future<void> _loadRecentToilets() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      QuerySnapshot reviewsSnapshot = await FirebaseFirestore.instance
          .collection('washroom_reviews')
          .where('user_id', isEqualTo: currentUser.uid)
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();

      Set<String> seenToiletIds = {};
      List<Map<String, dynamic>> recentToilets = [];

      for (var doc in reviewsSnapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        String toiletId = data['toilet_id'];

        // Skip duplicate toilets
        if (seenToiletIds.contains(toiletId)) continue;
        seenToiletIds.add(toiletId);

        recentToilets.add({
          'id': toiletId,
          'name': data['toilet_name'],
          'isRecent': true,
        });
      }

      setState(() {
        _recentToilets = recentToilets;
      });
    } catch (e) {
      print("Error loading recent toilets: $e");
    }
  }

  // Fetch toilets near user's current location
  Future<void> _fetchNearbyToilets() async {
    if (_userLocation == null) return;

    try {
      QuerySnapshot snapshot =
          await FirebaseFirestore.instance.collection('toilets').get();

      List<Map<String, dynamic>> nearbyToilets = [];

      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('location') && data['location'] != null) {
          double? toiletLat =
              (data['location']['latitude'] as num?)?.toDouble();
          double? toiletLng =
              (data['location']['longitude'] as num?)?.toDouble();

          if (toiletLat != null && toiletLng != null) {
            // Calculate distance between user and toilet
            double distanceInKm = _calculateDistance(_userLocation!.latitude,
                _userLocation!.longitude, toiletLat, toiletLng);

            // Include only toilets within 10km radius
            if (distanceInKm <= 10) {
              nearbyToilets.add({
                'id': doc.id,
                'name': data['name'] ?? 'Unnamed Toilet',
                'distance': distanceInKm,
                'location': data['location'],
                'isNearby': true,
              });
            }
          }
        }
      }

      // Sort by distance
      nearbyToilets.sort((a, b) => (a['distance']).compareTo(b['distance']));

      setState(() {
        _nearbyToilets = nearbyToilets;
      });
    } catch (e) {
      print("Error fetching nearby toilets: $e");
    }
  }

  // Helper function to calculate distance between two coordinates
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295; // Math.PI / 180
    double a = 0.5 -
        Math.cos((lat2 - lat1) * p) / 2 +
        Math.cos(lat1 * p) *
            Math.cos(lat2 * p) *
            (1 - Math.cos((lon2 - lon1) * p)) /
            2;
    return 12742 * Math.asin(Math.sqrt(a)); // 2 * R; R = 6371 km
  }

  Future<String?> _uploadImage(File image) async {
    try {
      String fileName = DateTime.now().millisecondsSinceEpoch.toString();
      Reference ref =
          FirebaseStorage.instance.ref().child('toilet_photos/$fileName.jpg');
      UploadTask uploadTask = ref.putFile(image);
      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print("Image upload error: $e");
      return null;
    }
  }

  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Wrap(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.camera_alt, color: Colors.blue),
                ),
                title: Text("Take a Photo"),
                subtitle: Text("Use your camera to take a picture"),
                onTap: () async {
                  Navigator.pop(context);
                  final pickedFile =
                      await _picker.pickImage(source: ImageSource.camera);
                  if (pickedFile != null) {
                    setState(() {
                      _selectedImage = File(pickedFile.path);
                    });
                  }
                },
              ),
              Divider(height: 0.5, indent: 70),
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.photo_library, color: Colors.green),
                ),
                title: Text("Choose from Gallery"),
                subtitle: Text("Select an existing photo"),
                onTap: () async {
                  Navigator.pop(context);
                  final pickedFile =
                      await _picker.pickImage(source: ImageSource.gallery);
                  if (pickedFile != null) {
                    setState(() {
                      _selectedImage = File(pickedFile.path);
                    });
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateToiletRating() async {
    try {
      var reviewsSnapshot = await FirebaseFirestore.instance
          .collection('washroom_reviews')
          .where('toilet_id', isEqualTo: _selectedToiletId)
          .get();

      if (reviewsSnapshot.docs.isNotEmpty) {
        double totalRating = 0;
        for (var doc in reviewsSnapshot.docs) {
          totalRating += (doc['rating'] as num).toDouble();
        }
        double avgRating = totalRating / reviewsSnapshot.docs.length;

        await FirebaseFirestore.instance
            .collection('toilets')
            .doc(_selectedToiletId)
            .update({'average_rating': avgRating});
      }
    } catch (e) {
      print("Error updating toilet rating: $e");
    }
  }

  Future<void> _submitComment() async {
    if (_selectedToiletId == null) {
      _showSnackBar("Please select a toilet.", Colors.red);
      return;
    }

    String commentText = _commentController.text.trim();
    if (commentText.isEmpty && _selectedImage == null) {
      _showSnackBar("Please add a comment or image", Colors.red);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await _uploadImage(_selectedImage!);
      }

      User? user = FirebaseAuth.instance.currentUser;
      String userId = user?.uid ?? "anonymous";
      String userName = user?.displayName ?? "Unknown User";

      // Calculate overall rating as average of category ratings
      double calculatedRating =
          (_categoryRatings.values.reduce((a, b) => a + b) /
              _categoryRatings.length);
      // Round to nearest 0.5
      _rating = (calculatedRating * 2).round() / 2;

      await FirebaseFirestore.instance.collection('washroom_reviews').add({
        'toilet_id': _selectedToiletId,
        'toilet_name': _selectedToiletName,
        'user_id': userId,
        'user_name': userName,
        'comment': commentText,
        'image_url': imageUrl,
        'rating': _rating,
        'category_ratings': _categoryRatings,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await _updateToiletRating();

      _showSnackBar("Review added successfully!", Colors.green);
      Navigator.pop(context, true); // Return true to indicate success
    } catch (e) {
      _showSnackBar("Error submitting review: $e", Colors.red);
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _searchFirestoreToilets(
      String query) async {
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('toilets')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThan: query + 'z')
          .limit(5)
          .get();

      return snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'name': doc['name'] ?? 'Unnamed Toilet',
          'isFromFirestore': true,
        };
      }).toList();
    } catch (e) {
      print("Firestore search error: $e");
      return [];
    }
  }

  // Enhanced toilet search function
  void _searchToilets(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showToiletsList = true;
      });
      return;
    }

    // Local search in nearby and recent toilets
    List<Map<String, dynamic>> localResults = [];

    // Search nearby
    localResults.addAll(_nearbyToilets.where((toilet) =>
        toilet['name'].toString().toLowerCase().contains(query.toLowerCase())));

    // Search recent (avoid duplicates)
    Set<String> seenIds =
        Set<String>.from(localResults.map((t) => t['id'].toString()));

    for (var toilet in _recentToilets) {
      if (toilet['name']
              .toString()
              .toLowerCase()
              .contains(query.toLowerCase()) &&
          !seenIds.contains(toilet['id'])) {
        localResults.add(toilet);
        seenIds.add(toilet['id'].toString());
      }
    }

    // If local results found, use them
    if (localResults.isNotEmpty) {
      setState(() {
        _searchResults = localResults;
        _showToiletsList = true;
      });
      return;
    }

    // Only search Firestore if no local results
    setState(() {
      _isSearching = true;
    });

    try {
      // Search in Firestore
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('toilets')
          .orderBy('name')
          .startAt([query]).endAt(
              [query + '\uf8ff']) // Unicode trick for prefix search
          .get();

      List<Map<String, dynamic>> firestoreResults = [];

      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;

        // Calculate distance if user location is available
        double? distance;
        if (_userLocation != null &&
            data.containsKey('location') &&
            data['location'] != null) {
          double? lat = (data['location']['latitude'] as num?)?.toDouble();
          double? lng = (data['location']['longitude'] as num?)?.toDouble();

          if (lat != null && lng != null) {
            distance = _calculateDistance(
                _userLocation!.latitude, _userLocation!.longitude, lat, lng);
          }
        }

        firestoreResults.add({
          'id': doc.id,
          'name': data['name'] ?? 'Unnamed Toilet',
          'distance': distance,
          'location': data['location'],
          'isGlobal': true,
        });
      }

      setState(() {
        _searchResults = firestoreResults;
        _isSearching = false;
        _showToiletsList = true;
      });
    } catch (e) {
      print("Error searching toilets: $e");
      setState(() {
        _isSearching = false;
        _searchError = 'Error searching. Please try again.';
      });
    }
  }

  Widget _buildCategoryRating(String category) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              category,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: RatingBar.builder(
              initialRating: _categoryRatings[category]!,
              minRating: 1,
              direction: Axis.horizontal,
              allowHalfRating: true,
              itemCount: 5,
              itemSize: 28,
              itemBuilder: (context, _) => Icon(
                Icons.star,
                color: Colors.amber,
              ),
              onRatingUpdate: (rating) {
                setState(() {
                  _categoryRatings[category] = rating;
                });
              },
            ),
          ),
          SizedBox(width: 8),
          Text(
            _categoryRatings[category]!.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Write a Review'),
        elevation: 0,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() {
            _showToiletsList = false;
          });
        },
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Review & Rate",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Share your experience with others",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Toilet Selection Section
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Select Toilet",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 16),
                                _selectedToiletName != null
                                    ? ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Container(
                                          padding: EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Icon(Icons.wc,
                                              color: Colors.blue),
                                        ),
                                        title: Text(
                                          _selectedToiletName!,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        subtitle:
                                            Text("Selected toilet for review"),
                                        trailing: IconButton(
                                          icon: Icon(Icons.edit,
                                              color: Colors.blue),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {
                                              _selectedToiletName = null;
                                              _selectedToiletId = null;
                                              _showToiletsList = true;
                                            });
                                          },
                                        ),
                                      )
                                    : Column(
                                        children: [
                                          TextField(
                                            controller: _searchController,
                                            onChanged: _searchToilets,
                                            onTap: () {
                                              setState(() {
                                                _showToiletsList = true;
                                              });
                                            },
                                            decoration: InputDecoration(
                                              hintText: "Search by toilet name",
                                              prefixIcon: Icon(Icons.search),
                                              suffixIcon: _searchController
                                                      .text.isNotEmpty
                                                  ? IconButton(
                                                      icon: Icon(Icons.clear,
                                                          color: Colors.grey),
                                                      onPressed: () {
                                                        setState(() {
                                                          _searchController
                                                              .clear();
                                                          _searchResults
                                                              .clear();
                                                          _showToiletsList =
                                                              true;
                                                        });
                                                      },
                                                    )
                                                  : null,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                          SizedBox(height: 16),
                                          Text(
                                            "Or",
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          SizedBox(height: 16),
                                          OutlinedButton.icon(
                                            onPressed: () async {
                                              final result =
                                                  await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      MapSelectionPage(
                                                          showToilets: true),
                                                ),
                                              );
                                              if (result != null) {
                                                setState(() {
                                                  _selectedToiletId =
                                                      result['id'];
                                                  _selectedToiletName =
                                                      result['name'];
                                                });
                                              }
                                            },
                                            icon: Icon(Icons.map),
                                            label: Text("Find on Map"),
                                            style: OutlinedButton.styleFrom(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 24,
                                                vertical: 12,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              side: BorderSide(
                                                  color: Colors.green),
                                            ),
                                          ),
                                        ],
                                      ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 16),

                        // Rating Section
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Rate Your Experience",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 16),

                                // Category ratings
                                ..._categoryRatings.keys
                                    .map((category) =>
                                        _buildCategoryRating(category))
                                    .toList(),

                                SizedBox(height: 8),
                                Divider(),
                                SizedBox(height: 8),

                                Row(
                                  children: [
                                    Text(
                                      "Overall Rating:",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Spacer(),
                                    Text(
                                      _rating.toStringAsFixed(1),
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Icon(Icons.star,
                                        color: Colors.amber, size: 24),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 16),

                        // Comment Section
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Write Your Review",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 16),
                                TextField(
                                  controller: _commentController,
                                  decoration: InputDecoration(
                                    hintText:
                                        'Share your experience details...',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                  ),
                                  maxLines: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 16),

                        // Photo Section
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Add Photo",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 16),
                                _selectedImage != null
                                    ? Stack(
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: Image.file(
                                              _selectedImage!,
                                              height: 200,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          Positioned(
                                            top: 10,
                                            right: 10,
                                            child: InkWell(
                                              onTap: () {
                                                setState(() {
                                                  _selectedImage = null;
                                                });
                                              },
                                              child: Container(
                                                padding: EdgeInsets.all(5),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withOpacity(0.8),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons.close,
                                                  color: Colors.red,
                                                  size: 20,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : GestureDetector(
                                        onTap: _pickImage,
                                        child: Container(
                                          height: 150,
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: Colors.grey[300]!,
                                              width: 1,
                                            ),
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.add_a_photo,
                                                size: 48,
                                                color: Colors.blue,
                                              ),
                                              SizedBox(height: 8),
                                              Text("Tap to add a photo"),
                                            ],
                                          ),
                                        ),
                                      ),
                                SizedBox(height: 10),
                                if (_selectedImage == null)
                                  OutlinedButton.icon(
                                    onPressed: _pickImage,
                                    icon: Icon(Icons.camera_alt),
                                    label: Text("Upload Photo"),
                                    style: OutlinedButton.styleFrom(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 100), // Extra space for bottom button
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Toilet search results overlay
// ... (previous code remains the same until the Stack widget)

            if (_showToiletsList && _selectedToiletName == null)
              Positioned(
                top: 150, // Position below the search field
                left: 16,
                right: 16,
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Container(
                    constraints: BoxConstraints(maxHeight: 300),
                    padding: EdgeInsets.all(8), // Added missing padding
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        // Search results
                        if (_searchResults.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              "Search Results",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                          ..._searchResults
                              .map((toilet) => ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          toilet['isNearby'] == true
                                              ? Colors.blue.withOpacity(0.2)
                                              : Colors.green.withOpacity(0.2),
                                      child: Icon(
                                        Icons.wc,
                                        color: toilet['isNearby'] == true
                                            ? Colors.blue
                                            : Colors.green,
                                      ),
                                    ),
                                    title: Text(toilet['name']),
                                    subtitle: toilet['distance'] != null
                                        ? Text(
                                            "${toilet['distance'].toStringAsFixed(1)} km away")
                                        : toilet['isRecent'] == true
                                            ? Text("Recently reviewed")
                                            : null,
                                    onTap: () {
                                      setState(() {
                                        _selectedToiletId = toilet['id'];
                                        _selectedToiletName = toilet['name'];
                                        _showToiletsList = false;
                                      });
                                    },
                                  ))
                              .toList(),
                        ] else if (_searchController.text.isEmpty) ...[
                          // Nearby toilets section
                          if (_nearbyToilets.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                "Nearby Toilets",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                            ..._nearbyToilets
                                .take(5)
                                .map((toilet) => ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor:
                                            Colors.blue.withOpacity(0.2),
                                        child:
                                            Icon(Icons.wc, color: Colors.blue),
                                      ),
                                      title: Text(toilet['name']),
                                      subtitle: Text(
                                          "${toilet['distance'].toStringAsFixed(1)} km away"),
                                      onTap: () {
                                        setState(() {
                                          _selectedToiletId = toilet['id'];
                                          _selectedToiletName = toilet['name'];
                                          _showToiletsList = false;
                                        });
                                      },
                                    ))
                                .toList(),
                          ],

                          // Recent toilets section
                          if (_recentToilets.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                "Recently Reviewed",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                            ..._recentToilets
                                .map((toilet) => ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor:
                                            Colors.green.withOpacity(0.2),
                                        child: Icon(Icons.history,
                                            color: Colors.green),
                                      ),
                                      title: Text(toilet['name']),
                                      subtitle: Text("Previously reviewed"),
                                      onTap: () {
                                        setState(() {
                                          _selectedToiletId = toilet['id'];
                                          _selectedToiletName = toilet['name'];
                                          _showToiletsList = false;
                                        });
                                      },
                                    ))
                                .toList(),
                          ],

                          // If both empty, show a message
                          if (_nearbyToilets.isEmpty && _recentToilets.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.search_off,
                                        size: 48, color: Colors.grey),
                                    SizedBox(height: 8),
                                    Text(
                                      "No toilets found nearby. Try searching by name or using the map.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ] else ...[
                          // No results for search
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.search_off,
                                      size: 48, color: Colors.grey),
                                  SizedBox(height: 8),
                                  Text(
                                    "No toilets found matching '${_searchController.text}'",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

// ... (rest of the code remains the same)
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitComment,
            child: _isSubmitting
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 2,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text('Submitting...'),
                    ],
                  )
                : Text('Submit Review'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              minimumSize: Size(double.infinity, 0),
            ),
          ),
        ),
      ),
    );
  }
}
