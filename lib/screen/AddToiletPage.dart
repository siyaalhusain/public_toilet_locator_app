import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // Added for Timer

const kGoogleApiKey =
    'AIzaSyC3AXw-RcPsAR5s9Cgr84chOLDYT575ZM4'; // Replace with your actual API key

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
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _imagePicker = ImagePicker();

  LatLng? _selectedLocation;
  bool _isSubmitting = false;
  List<File> _selectedImages = [];
  List<String> _existingImageUrls = [];
  bool _isUploading = false;
  GoogleMapController? _mapController;
  List<PlacePrediction> _placePredictions = [];
  bool _isSearching = false;
  FocusNode _searchFocusNode = FocusNode();
  BitmapDescriptor? _customMarker;
  int _toiletLimit = 0;
  int _currentToiletCount = 0;
  bool _isCheckingLimit = true;
  bool _hasSubscription = false;
  Timer? _debounceTimer;

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
  ];
  Set<String> selectedAmenities = {};

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
    _initCustomMarker();
    _checkToiletLimit();

    if (widget.isEditing && widget.toiletData != null) {
      _populateFormWithExistingData();
    }
  }

  Future<void> _checkToiletLimit() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isCheckingLimit = false;
      });
      return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final role = userData['role'] as String?;

        if (role == 'Owner') {
          final subscription =
              userData['subscription'] as Map<String, dynamic>?;
          if (subscription != null) {
            setState(() {
              _hasSubscription = true;
            });

            final planId = subscription['planId'] as String?;

            if (planId == 'basic') {
              _toiletLimit = 2;
            } else if (planId == 'standard') {
              _toiletLimit = 5;
            } else if (planId == 'premium') {
              _toiletLimit = 9999;
            }

            final toiletsQuery = await _firestore
                .collection('toilets')
                .where('ownerId', isEqualTo: user.uid)
                .get();

            setState(() {
              _currentToiletCount = toiletsQuery.size;
            });
          }
        } else {
          setState(() {
            _toiletLimit = 9999;
            _hasSubscription = true;
          });
        }
      }
    } catch (e) {
      print('Error checking toilet limit: $e');
    } finally {
      setState(() {
        _isCheckingLimit = false;
      });
    }
  }

  Future<void> _initCustomMarker() async {
    _customMarker = await BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueRed,
    );
  }

  void _populateFormWithExistingData() {
    final data = widget.toiletData!;

    if (data['name'] != null) {
      _toiletNameController.text = data['name'];
    }

    if (data['address'] != null) {
      _addressController.text = data['address'];
    }

    if (data['amenities'] != null && data['amenities'] is List) {
      setState(() {
        selectedAmenities = Set<String>.from(data['amenities']);
      });
    }

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

    if (data['imageUrls'] != null && data['imageUrls'] is List) {
      setState(() {
        _existingImageUrls = List<String>.from(data['imageUrls']);
      });
    }

    if (widget.isEditing &&
        widget.toiletId != null &&
        _existingImageUrls.isEmpty) {
      _fetchToiletDataFromFirestore();
    }
  }

  Future<void> _fetchToiletDataFromFirestore() async {
    try {
      final docSnapshot =
          await _firestore.collection('toilets').doc(widget.toiletId).get();

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
    _addressController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _getCurrentUser() {
    if (!widget.isEditing) {
      final user = _auth.currentUser;
      if (user == null) {
        _showSnackBar(
            'You must be logged in to add a toilet', Colors.red, Icons.error);
      }
    }
  }

  void _selectLocation(LatLng position) {
    setState(() {
      _selectedLocation = position;
      _searchController.clear();
      _placePredictions = [];
    });

    _showSnackBar(
      'Location selected: (${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)})',
      Colors.blue,
      Icons.location_on,
    );
  }

  Future<void> _searchPlaces(String input) async {
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (input.isEmpty) {
        setState(() {
          _placePredictions = [];
        });
        return;
      }

      setState(() {
        _isSearching = true;
      });

      try {
        final url = Uri.parse(
            'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$kGoogleApiKey&components=country:lk');

        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'OK') {
            setState(() {
              _placePredictions = (data['predictions'] as List)
                  .map((p) => PlacePrediction.fromJson(p))
                  .toList();
            });
          } else {
            print('Places API error: ${data['status']}');
            setState(() {
              _placePredictions = [];
            });
          }
        } else {
          print('HTTP error: ${response.statusCode}');
          setState(() {
            _placePredictions = [];
          });
        }
      } catch (e) {
        print('Error searching places: $e');
        _showSnackBar('Error searching places: $e', Colors.red, Icons.error);
        setState(() {
          _placePredictions = [];
        });
      } finally {
        setState(() {
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _handleSearch() async {
    if (_searchController.text.isEmpty) return;

    if (_placePredictions.isNotEmpty) {
      final firstPrediction = _placePredictions.first;
      await _getPlaceDetails(firstPrediction.placeId!);
      return;
    }

    await _geocodeAddress(_searchController.text);
  }

  Future<void> _geocodeAddress(String address) async {
    setState(() {
      _isSearching = true;
    });

    try {
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$kGoogleApiKey');

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final result = data['results'][0];
          final geometry = result['geometry'];
          final location = geometry['location'];
          final lat = location['lat'] as double;
          final lng = location['lng'] as double;
          final formattedAddress = result['formatted_address'] as String;

          setState(() {
            _selectedLocation = LatLng(lat, lng);
            _addressController.text = formattedAddress;
            _searchController.text = formattedAddress;
            _placePredictions = [];
          });

          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: _selectedLocation!,
                zoom: 16,
              ),
            ),
          );

          _showSnackBar(
            'Location selected: $formattedAddress',
            Colors.green,
            Icons.check_circle,
          );
        } else {
          _showSnackBar(
            'Location not found',
            Colors.orange,
            Icons.warning,
          );
        }
      } else {
        throw Exception('Failed to geocode address');
      }
    } catch (e) {
      _showSnackBar('Error searching location: $e', Colors.red, Icons.error);
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _getPlaceDetails(String placeId) async {
    setState(() {
      _isSearching = true;
    });

    try {
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$kGoogleApiKey');

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final result = data['result'];
          final geometry = result['geometry'];
          final location = geometry['location'];
          final lat = location['lat'] as double;
          final lng = location['lng'] as double;
          final name = result['name'] as String? ?? 'Selected Location';
          final address = result['formatted_address'] as String? ?? '';

          setState(() {
            _selectedLocation = LatLng(lat, lng);
            _addressController.text = address;
            _placePredictions = [];
            _searchController.text = address;
          });

          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: _selectedLocation!,
                zoom: 16,
              ),
            ),
          );

          _showSnackBar(
            'Location selected: $name',
            Colors.green,
            Icons.check_circle,
          );
        }
      }
    } catch (e) {
      _showSnackBar('Error getting place details: $e', Colors.red, Icons.error);
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
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
        _showSnackBar(
          'Location permissions are permanently denied.',
          Colors.red,
          Icons.error,
        );
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

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_selectedLocation!, 15),
      );

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          String address = [
            place.name,
            place.street,
            place.locality,
            place.administrativeArea
          ].where((part) => part?.isNotEmpty ?? false).join(', ');
          _addressController.text = address;
        }
      } catch (e) {
        print('Error getting address: $e');
      }

      _showSnackBar(
        'Current location selected: (${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)})',
        Colors.green,
        Icons.my_location,
      );
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
        imageQuality: 85,
        maxWidth: 1200,
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
        String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        String fileName =
            'toilet_${widget.toiletId ?? timestamp}_${timestamp}_${uploadedUrls.length}.jpg';

        Reference ref = FirebaseStorage.instance
            .ref()
            .child('toilet_images')
            .child(fileName);

        UploadTask uploadTask = ref.putFile(imageFile);
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
    if (_isCheckingLimit) {
      _showSnackBar('Please wait while we verify your subscription...',
          Colors.orange, Icons.warning);
      return;
    }

    if (!_hasSubscription && !widget.isEditing) {
      _showSnackBar('You need an active subscription to add toilets',
          Colors.red, Icons.error);
      return;
    }

    if (!widget.isEditing && _currentToiletCount >= _toiletLimit) {
      _showSnackBar(
        'You have reached your toilet limit of $_toiletLimit for your subscription plan. Please upgrade to add more toilets.',
        Colors.red,
        Icons.error,
      );
      return;
    }

    if (_formKey.currentState!.validate() &&
        _selectedLocation != null &&
        _addressController.text.isNotEmpty) {
      setState(() {
        _isSubmitting = true;
      });

      final toiletName = _toiletNameController.text;
      final address = _addressController.text;
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
        List<String> uploadedImageUrls = await _uploadImages();
        List<String> allImageUrls = [
          ..._existingImageUrls,
          ...uploadedImageUrls
        ];

        final toiletData = {
          'name': toiletName,
          'address': address,
          'amenities': selectedAmenities.toList(),
          'location': {
            'latitude': _selectedLocation!.latitude,
            'longitude': _selectedLocation!.longitude,
          },
          'imageUrls': allImageUrls,
        };

        if (!widget.isEditing) {
          toiletData.addAll({
            'rating': 0.0,
            'timestamp': FieldValue.serverTimestamp(),
            'ownerId': user!.uid,
            'ownerEmail': user.email ?? '',
          });

          await _firestore.collection('toilets').add(toiletData);

          _showSnackBar(
            'Toilet "$toiletName" added successfully!',
            Colors.green,
            Icons.check_circle,
          );

          _formKey.currentState!.reset();
          setState(() {
            _selectedLocation = null;
            selectedAmenities.clear();
            _selectedImages.clear();
            _existingImageUrls.clear();
            _addressController.clear();
            _searchController.clear();
            _currentToiletCount++;
          });
        } else if (widget.toiletId != null) {
          await _firestore
              .collection('toilets')
              .doc(widget.toiletId)
              .update(toiletData);

          _showSnackBar(
            'Toilet "$toiletName" updated successfully!',
            Colors.green,
            Icons.check_circle,
          );

          Future.delayed(Duration(seconds: 1), () {
            Navigator.pop(context);
          });
        }
      } catch (e) {
        _showSnackBar(
          'Error ${widget.isEditing ? 'updating' : 'adding'} toilet: $e',
          Colors.red,
          Icons.error,
        );
      } finally {
        setState(() {
          _isSubmitting = false;
        });
      }
    } else {
      if (_selectedLocation == null) {
        _showSnackBar(
          'Please select a location on the map.',
          Colors.orange,
          Icons.warning,
        );
      }
      if (_addressController.text.isEmpty) {
        _showSnackBar(
          'Please enter the toilet address.',
          Colors.orange,
          Icons.warning,
        );
      }
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
          if (_isCheckingLimit) LinearProgressIndicator(),
          if (!_isCheckingLimit && !widget.isEditing && _toiletLimit != 9999)
            Container(
              padding: EdgeInsets.all(8),
              color: Colors.blue[50],
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    'Toilet limit: $_currentToiletCount/$_toiletLimit',
                    style: TextStyle(color: Colors.blue[800]),
                  ),
                ],
              ),
            ),
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _selectedLocation ?? LatLng(7.8731, 80.7718),
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
                              snippet: _addressController.text.isNotEmpty
                                  ? _addressController.text
                                  : '${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)}',
                            ),
                            icon: _customMarker ??
                                BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueRed,
                                ),
                          ),
                        }
                      : {},
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    children: [
                      Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                decoration: InputDecoration(
                                  hintText: 'Search for a location...',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                  suffixIcon: _isSearching
                                      ? Padding(
                                          padding: EdgeInsets.all(8),
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                        )
                                      : IconButton(
                                          icon: Icon(Icons.clear),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {
                                              _placePredictions = [];
                                            });
                                          },
                                        ),
                                ),
                                onChanged: (value) {
                                  if (value.length > 2) {
                                    _searchPlaces(value);
                                  } else {
                                    setState(() {
                                      _placePredictions = [];
                                    });
                                  }
                                },
                                onFieldSubmitted: (value) => _handleSearch(),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.search),
                              onPressed: _handleSearch,
                            ),
                          ],
                        ),
                      ),
                      if (_placePredictions.isNotEmpty)
                        Container(
                          margin: EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.3,
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: AlwaysScrollableScrollPhysics(),
                            itemCount: _placePredictions.length,
                            itemBuilder: (context, index) {
                              final prediction = _placePredictions[index];
                              return Material(
                                child: ListTile(
                                  leading: Icon(Icons.location_on),
                                  title: Text(prediction.description ?? ''),
                                  onTap: () {
                                    _getPlaceDetails(prediction.placeId!);
                                    setState(() {
                                      _placePredictions = [];
                                    });
                                    _searchFocusNode.unfocus();
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                if (_selectedLocation != null)
                  Positioned(
                    bottom: 16,
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
                              'Selected: ${_addressController.text.isNotEmpty ? _addressController.text : '(${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)})'}',
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
          Expanded(
            flex: 6,
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
                      TextFormField(
                        controller: _addressController,
                        decoration: InputDecoration(
                          labelText: 'Address',
                          hintText: 'Enter the full address of the toilet',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: Icon(Icons.location_on),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the address';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      _buildImageGrid(),
                      SizedBox(height: 16),
                      Text(
                        'Amenities',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
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

class PlacePrediction {
  final String? description;
  final String? placeId;

  PlacePrediction({this.description, this.placeId});

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    return PlacePrediction(
      description: json['description'],
      placeId: json['place_id'],
    );
  }
}
