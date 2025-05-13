import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

class AddToiletPage extends StatefulWidget {
  final bool isEditing;
  final String? toiletId;
  final Map<String, dynamic>? toiletData;

  const AddToiletPage({
    Key? key,
    this.isEditing = false,
    this.toiletId,
    this.toiletData,
  }) : super(key: key);

  @override
  _AddToiletPageState createState() => _AddToiletPageState();
}

class _AddToiletPageState extends State<AddToiletPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _toiletNameController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _imagePicker = ImagePicker();

  LatLng? _selectedLocation;
  bool _isSubmitting = false;
  List<File> _selectedImages = [];
  List<String> _existingImageUrls = [];
  bool _isUploading = false;

  final List<Map<String, dynamic>> amenities = [
    {"name": "Accessible", "icon": Icons.accessible, "color": Colors.blue},
    {"name": "Men Only", "icon": Icons.male, "color": Colors.indigo},
    {"name": "Female Only", "icon": Icons.female, "color": Colors.pink},
    {"name": "Two Genders", "icon": Icons.wc, "color": Colors.purple},
    {
      "name": "Baby Station",
      "icon": Icons.baby_changing_station,
      "color": Colors.orange
    },
    {"name": "Bathing", "icon": Icons.shower, "color": Colors.teal},
    {"name": "Private", "icon": Icons.visibility_off, "color": Colors.red},
    {"name": "Open to Public", "icon": Icons.public, "color": Colors.green},
    {"name": "All", "icon": Icons.all_inbox, "color": Colors.amber}
  ];
  Set<String> selectedAmenities = {};

  @override
  void initState() {
    super.initState();
    _getCurrentUser();

    // If editing, populate the form with existing data
    if (widget.isEditing && widget.toiletData != null) {
      _populateFormWithExistingData();
    }
  }

  void _populateFormWithExistingData() {
    final data = widget.toiletData!;

    // Set toilet name
    if (data['name'] != null) {
      _toiletNameController.text = data['name'];
    }

    // Set selected amenities
    if (data['amenities'] != null && data['amenities'] is List) {
      setState(() {
        selectedAmenities = Set<String>.from(data['amenities']);
      });
    }

    // Set selected location
    if (data['location'] != null) {
      final location = data['location'];
      if (location['latitude'] != null && location['longitude'] != null) {
        setState(() {
          _selectedLocation = LatLng(
            location['latitude'],
            location['longitude'],
          );
        });
      }
    }

    // Load existing images
    if (data['imageUrls'] != null && data['imageUrls'] is List) {
      setState(() {
        _existingImageUrls = List<String>.from(data['imageUrls']);
      });
    }

    // If we're editing and there are no image URLs in the data, fetch the document to check again
    if (widget.isEditing &&
        widget.toiletId != null &&
        _existingImageUrls.isEmpty) {
      _fetchToiletDataFromFirestore();
    }
  }

  Future<void> _fetchToiletDataFromFirestore() async {
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('toilets')
          .doc(widget.toiletId)
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        if (data['imageUrls'] != null && data['imageUrls'] is List) {
          setState(() {
            _existingImageUrls = List<String>.from(data['imageUrls']);
          });
        }
      }
    } catch (e) {
      print('Error fetching toilet data: $e');
    }
  }

  @override
  void dispose() {
    _toiletNameController.dispose();
    super.dispose();
  }

  void _getCurrentUser() {
    // No need to set current user for editing, as we already have the data
    // This is just for new toilet creation
    if (!widget.isEditing) {
      final user = _auth.currentUser;
      if (user == null) {
        // Handle not logged in case
      }
    }
  }

  void _selectLocation(LatLng position) {
    setState(() {
      _selectedLocation = position;
    });

    _showSnackBar(
        'Location selected: (${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)})',
        Colors.blue,
        Icons.location_on);
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar(
            'Location services are disabled.', Colors.red, Icons.error);
        setState(() {
          _isSubmitting = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar(
              'Location permissions are denied.', Colors.red, Icons.error);
          setState(() {
            _isSubmitting = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('Location permissions are permanently denied.',
            Colors.red, Icons.error);
        setState(() {
          _isSubmitting = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _selectedLocation = LatLng(position.latitude, position.longitude);
        _isSubmitting = false;
      });

      _showSnackBar(
          'Current location selected: (${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)})',
          Colors.green,
          Icons.my_location);
    } catch (e) {
      _showSnackBar('Error getting location: $e', Colors.red, Icons.error);
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> pickedFiles = await _imagePicker.pickMultiImage(
        imageQuality: 85, // Compress images to reduce storage usage
        maxWidth: 1200, // Limit max width
      );

      if (pickedFiles.isNotEmpty) {
        setState(() {
          for (var pickedFile in pickedFiles) {
            _selectedImages.add(File(pickedFile.path));
          }
        });
      }
    } catch (e) {
      _showSnackBar('Error picking images: $e', Colors.red, Icons.error);
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1200,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImages.add(File(pickedFile.path));
        });
      }
    } catch (e) {
      _showSnackBar('Error taking photo: $e', Colors.red, Icons.error);
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _removeExistingImage(int index) {
    setState(() {
      _existingImageUrls.removeAt(index);
    });
  }

  Future<List<String>> _uploadImages() async {
    List<String> uploadedUrls = [];

    if (_selectedImages.isEmpty) return uploadedUrls;

    setState(() {
      _isUploading = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null && !widget.isEditing) {
        throw Exception('User must be logged in to upload images');
      }

      for (var imageFile in _selectedImages) {
        // Create unique filename with timestamp and random suffix
        String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        String fileName =
            'toilet_${widget.toiletId ?? timestamp}_${timestamp}_${uploadedUrls.length}.jpg';

        // Reference to storage location
        Reference ref = FirebaseStorage.instance
            .ref()
            .child('toilet_images')
            .child(fileName);

        // Upload file
        UploadTask uploadTask = ref.putFile(imageFile);

        // Wait for upload to complete and get download URL
        TaskSnapshot taskSnapshot = await uploadTask;
        String downloadUrl = await taskSnapshot.ref.getDownloadURL();

        uploadedUrls.add(downloadUrl);
      }

      return uploadedUrls;
    } catch (e) {
      _showSnackBar('Error uploading images: $e', Colors.red, Icons.error);
      return [];
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  void _showSnackBar(String message, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: EdgeInsets.all(8),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate() && _selectedLocation != null) {
      setState(() {
        _isSubmitting = true;
      });

      final toiletName = _toiletNameController.text;
      final user = _auth.currentUser;

      if (user == null && !widget.isEditing) {
        _showSnackBar(
            'You must be logged in to add a toilet', Colors.red, Icons.error);
        setState(() {
          _isSubmitting = false;
        });
        return;
      }

      try {
        // Upload images first and get URLs
        List<String> uploadedImageUrls = await _uploadImages();

        // Combine existing images (that weren't removed) with new uploaded images
        List<String> allImageUrls = [
          ..._existingImageUrls,
          ...uploadedImageUrls
        ];

        // Data to save
        final toiletData = {
          'name': toiletName,
          'amenities': selectedAmenities.toList(),
          'location': {
            'latitude': _selectedLocation!.latitude,
            'longitude': _selectedLocation!.longitude,
          },
          'imageUrls': allImageUrls,
        };

        // If creating new toilet (not editing)
        if (!widget.isEditing) {
          // Add additional fields for new toilet
          toiletData.addAll({
            'rating': 0.0,
            'timestamp': FieldValue.serverTimestamp(),
            'ownerId': user!.uid,
            'ownerEmail':
                user.email ?? '', // Add empty string fallback for null
          });

          // Create new document
          await FirebaseFirestore.instance
              .collection('toilets')
              .add(toiletData);

          _showSnackBar('Toilet "$toiletName" added successfully!',
              Colors.green, Icons.check_circle);

          // Clear form after submission
          _formKey.currentState!.reset();
          setState(() {
            _selectedLocation = null;
            selectedAmenities.clear();
            _selectedImages.clear();
            _existingImageUrls.clear();
          });
        }
        // If editing existing toilet
        else if (widget.toiletId != null) {
          // Update existing document
          await FirebaseFirestore.instance
              .collection('toilets')
              .doc(widget.toiletId)
              .update(toiletData);

          _showSnackBar('Toilet "$toiletName" updated successfully!',
              Colors.green, Icons.check_circle);

          // Return to the previous screen after updating
          Future.delayed(Duration(seconds: 1), () {
            Navigator.pop(context);
          });
        }
      } catch (e) {
        _showSnackBar(
            'Error ${widget.isEditing ? 'updating' : 'adding'} toilet: $e',
            Colors.red,
            Icons.error);
      } finally {
        setState(() {
          _isSubmitting = false;
        });
      }
    } else if (_selectedLocation == null) {
      _showSnackBar(
          'Please select a location on the map.', Colors.orange, Icons.warning);
    }
  }

  Widget _buildImageGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photos',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 12),

        // Show existing images (when editing)
        if (_existingImageUrls.isNotEmpty) ...[
          Text(
            'Existing Photos',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: _existingImageUrls.length,
            itemBuilder: (context, index) {
              return Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _existingImageUrls[index],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[200],
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.broken_image,
                                    size: 30,
                                    color: Colors.grey[400],
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Load error',
                                    style: TextStyle(
                                        fontSize: 10, color: Colors.grey[500]),
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeExistingImage(index),
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          SizedBox(height: 16),
        ],

        // Show newly selected images
        if (_selectedImages.isNotEmpty) ...[
          Text(
            'New Photos',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: _selectedImages.length,
            itemBuilder: (context, index) {
              return Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _selectedImages[index],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeImage(index),
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          SizedBox(height: 16),
        ],

        // Photo action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickImages,
                icon: Icon(Icons.photo_library),
                label: Text('Gallery'),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _takePhoto,
                icon: Icon(Icons.camera_alt),
                label: Text('Camera'),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),

        if (_isUploading)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text(
                  'Uploading images...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Toilet' : 'Add Toilet'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Map takes up top half of screen
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _selectedLocation ??
                        LatLng(7.8731, 80.7718), // Default to Sri Lanka
                    zoom: 12,
                  ),
                  onTap: _selectLocation,
                  markers: _selectedLocation != null
                      ? {
                          Marker(
                            markerId: const MarkerId('selected-location'),
                            position: _selectedLocation!,
                            infoWindow: InfoWindow(
                              title: 'Selected Location',
                              snippet:
                                  '${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)}',
                            ),
                          ),
                        }
                      : {},
                  myLocationEnabled: true,
                  zoomControlsEnabled: true,
                ),

                // Location indicator overlay
                if (_selectedLocation != null)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.red),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Selected: (${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)})',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Form takes up bottom half
          Expanded(
            flex: 6, // Increased flex to accommodate photo section
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 6,
                    offset: Offset(0, -3),
                  ),
                ],
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Location button
                      ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _getCurrentLocation,
                        icon: Icon(Icons.my_location),
                        label: Text('Use Current Location'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(double.infinity, 46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),

                      // Toilet name field
                      Text(
                        'Toilet Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: _toiletNameController,
                        decoration: InputDecoration(
                          labelText: 'Toilet Name',
                          hintText: 'e.g., Central Park Public Toilet',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: Icon(Icons.business),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the toilet name';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),

                      // Photo upload section
                      _buildImageGrid(),
                      SizedBox(height: 16),

                      // Amenities section
                      Text(
                        'Amenities',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),

                      // Amenities wrap
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: amenities.map((amenity) {
                          bool isSelected =
                              selectedAmenities.contains(amenity["name"]);

                          return FilterChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  amenity["icon"],
                                  size: 18,
                                  color: isSelected
                                      ? Colors.white
                                      : amenity["color"],
                                ),
                                SizedBox(width: 6),
                                Text(
                                  amenity["name"],
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  selectedAmenities.add(amenity["name"]);
                                } else {
                                  selectedAmenities.remove(amenity["name"]);
                                }
                              });
                            },
                            selectedColor: amenity["color"],
                            checkmarkColor: Colors.white,
                            backgroundColor: Colors.grey[100],
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            elevation: isSelected ? 2 : 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: isSelected
                                    ? Colors.transparent
                                    : amenity["color"]!.withOpacity(0.3),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      SizedBox(height: 24),

                      // Submit button
                      ElevatedButton(
                        onPressed: (_isSubmitting || _isUploading)
                            ? null
                            : _submitForm,
                        child: (_isSubmitting || _isUploading)
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(_isUploading
                                      ? 'Uploading Images...'
                                      : 'Submitting...'),
                                ],
                              )
                            : Text(widget.isEditing ? 'Update' : 'Submit'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(double.infinity, 46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _getCurrentLocation,
        child: Icon(Icons.my_location),
        tooltip: 'Get Current Location',
      ),
    );
  }
}
