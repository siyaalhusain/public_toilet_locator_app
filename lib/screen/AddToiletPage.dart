import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  LatLng? _selectedLocation;
  bool _isSubmitting = false;

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
        // Data to save
        final toiletData = {
          'name': toiletName,
          'amenities': selectedAmenities.toList(),
          'location': {
            'latitude': _selectedLocation!.latitude,
            'longitude': _selectedLocation!.longitude,
          },
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
            flex: 5,
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
                        onPressed: _isSubmitting ? null : _submitForm,
                        child: _isSubmitting
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
                                  Text('Submitting...'),
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
