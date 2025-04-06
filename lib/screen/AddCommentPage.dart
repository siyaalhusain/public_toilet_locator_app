import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'MapSelectionPage.dart';

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

  @override
  void initState() {
    super.initState();
    _selectedToiletId = widget.toiletId;
    _selectedToiletName = widget.toiletName;
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

  Future<void> _searchToiletByName(BuildContext context) async {
    TextEditingController searchController = TextEditingController();
    List<QueryDocumentSnapshot> searchResults = [];
    bool isSearching = false;

    Future<void> performSearch(String query, Function setDialogState) async {
      if (query.isEmpty) {
        setDialogState(() => searchResults.clear());
        return;
      }

      setDialogState(() => isSearching = true);

      try {
        var querySnapshot = await FirebaseFirestore.instance
            .collection('toilets')
            .where('name', isGreaterThanOrEqualTo: query)
            .where('name', isLessThanOrEqualTo: query + '\uf8ff')
            .limit(10)
            .get();

        setDialogState(() {
          searchResults = querySnapshot.docs;
          isSearching = false;
        });
      } catch (e) {
        setDialogState(() => isSearching = false);
        print("Search error: $e");
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text("Search Toilet"),
              content: Container(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      onChanged: (value) {
                        performSearch(value, setDialogState);
                      },
                      decoration: InputDecoration(
                        hintText: "Enter toilet name",
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    if (isSearching)
                      CircularProgressIndicator()
                    else if (searchResults.isNotEmpty)
                      Container(
                        height: 250,
                        child: ListView.separated(
                          itemCount: searchResults.length,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1),
                          itemBuilder: (context, index) {
                            var toilet = searchResults[index];
                            return ListTile(
                              title: Text(toilet['name']),
                              subtitle: toilet['address'] != null
                                  ? Text(toilet['address'],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)
                                  : null,
                              trailing: Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () {
                                Navigator.pop(context);
                                setState(() {
                                  _selectedToiletId = toilet.id;
                                  _selectedToiletName = toilet['name'];
                                });
                              },
                            );
                          },
                        ),
                      )
                    else if (searchController.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Icon(Icons.search_off,
                                size: 48, color: Colors.grey),
                            SizedBox(height: 16),
                            Text("No toilets found"),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text("Cancel"),
                ),
              ],
            );
          },
        );
      },
    );
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
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
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
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(Icons.wc, color: Colors.blue),
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
                                      icon:
                                          Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () =>
                                          _searchToiletByName(context),
                                    ),
                                  )
                                : Column(
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _searchToiletByName(context),
                                        icon: Icon(Icons.search),
                                        label: Text("Search by Name"),
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          side: BorderSide(color: Colors.blue),
                                        ),
                                      ),
                                      SizedBox(height: 10),
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          final result = await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  MapSelectionPage(
                                                      showToilets: true),
                                            ),
                                          );
                                          if (result != null) {
                                            setState(() {
                                              _selectedToiletId = result['id'];
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
                                          side: BorderSide(color: Colors.green),
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
                                Icon(Icons.star, color: Colors.amber, size: 24),
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
                                hintText: 'Share your experience details...',
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
                                        borderRadius: BorderRadius.circular(10),
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
                                              color:
                                                  Colors.white.withOpacity(0.8),
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
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.grey[300]!,
                                          width: 1,
                                        ),
                                        // Use a BoxDecoration with a custom painter for dashed border if needed
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
                    SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
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
