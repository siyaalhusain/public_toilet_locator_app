import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';

class MapSelectionPage extends StatefulWidget {
  final bool showToilets;
  const MapSelectionPage({super.key, this.showToilets = false});

  @override
  _MapSelectionPageState createState() => _MapSelectionPageState();
}

class _MapSelectionPageState extends State<MapSelectionPage> {
  late GoogleMapController mapController;
  Set<Marker> _markers = {};
  LatLng? _selectedLocation;
  LatLng? _currentLocation;
  bool _isLocationFetched = false;
  final Location _location = Location(); // Location instance
  final Completer<GoogleMapController> _controller = Completer();

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    if (widget.showToilets) {
      _loadToilets();
    }
  }

  // Fetch user's current location
  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await _location.serviceEnabled();
      PermissionStatus permissionGranted = await _location.hasPermission();

      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) return;
      }

      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) return;
      }

      LocationData locationData = await _location.getLocation();
      setState(() {
        _currentLocation =
            LatLng(locationData.latitude!, locationData.longitude!);
        _isLocationFetched = true;
      });

      _addCurrentLocationMarker();
      _moveCameraToCurrentLocation();
    } catch (e) {
      debugPrint("Error fetching location: $e");
    }
  }

  // Add marker for user's location
  void _addCurrentLocationMarker() {
    if (_currentLocation != null) {
      setState(() {
        _markers.add(
          Marker(
            markerId: const MarkerId('current_location'),
            position: _currentLocation!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure), // Blue marker for user location
            infoWindow: const InfoWindow(title: 'You are here'),
          ),
        );
      });
    }
  }

  // Move camera to user's location
  void _moveCameraToCurrentLocation() async {
    if (_currentLocation != null) {
      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(_currentLocation!, 15),
      );
    }
  }

  // Load toilets from Firestore
  Future<void> _loadToilets() async {
    try {
      debugPrint("📡 Fetching toilets from Firestore...");

      QuerySnapshot querySnapshot =
          await FirebaseFirestore.instance.collection('toilets').get();

      debugPrint("🔥 Toilets Found: ${querySnapshot.docs.length}");

      if (querySnapshot.docs.isEmpty) {
        debugPrint("⚠️ No toilets found in Firestore.");
      }

      Set<Marker> newMarkers = {}; // Temporary set for markers

      // Add the current location marker if available
      if (_currentLocation != null) {
        newMarkers.add(
          Marker(
            markerId: const MarkerId('current_location'),
            position: _currentLocation!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure),
            infoWindow: const InfoWindow(title: 'You are here'),
          ),
        );
      }

      // Loop through Firestore documents and add markers
      for (var doc in querySnapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;

        // Validate lat/lng values
        if (data.containsKey('location')) {
          double toiletLat = data['location']['latitude'];
          double toiletLng = data['location']['longitude'];
          LatLng toiletLocation = LatLng(toiletLat, toiletLng);

          debugPrint("🚻 Toilet: ${data['name']} at $toiletLat, $toiletLng");

          newMarkers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: toiletLocation,
              infoWindow: InfoWindow(
                title: data['name'],
                onTap: () {
                  _onToiletSelected(doc.id, data['name']);
                },
              ),
            ),
          );
        } else {
          debugPrint(
              "⚠️ Skipping toilet: ${doc.id} - Missing latitude/longitude");
        }
      }

      // Update the state with the new markers
      setState(() {
        _markers = newMarkers;
      });

      debugPrint("✅ Markers updated: ${_markers.length}");
    } catch (e) {
      debugPrint("🔥 Firestore Error: $e");
    }
  }

  // Handle toilet selection
  void _onToiletSelected(String toiletId, String toiletName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Selected Toilet'),
          content: Text('Toilet Name: $toiletName'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context, {
                  'id': toiletId,
                  'name': toiletName,
                }); // Return selected toilet data
              },
              child: const Text('Select'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Toilet on Map')),
      body: Stack(
        children: [
          _isLocationFetched
              ? GoogleMap(
                  onMapCreated: (controller) {
                    mapController = controller;
                  },
                  initialCameraPosition: CameraPosition(
                    target: _currentLocation ?? LatLng(6.927079, 79.861244),
                    zoom: 12,
                  ),
                  markers: _markers,
                  onTap: (location) {
                    setState(() {
                      _selectedLocation = location;
                    });
                  },
                )
              : const Center(child: CircularProgressIndicator()),
          Positioned(
            bottom: 20,
            left: 20,
            child: FloatingActionButton(
              onPressed: _moveCameraToCurrentLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}
