import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';

class GoogleMapPage extends StatefulWidget {
  @override
  _GoogleMapPageState createState() => _GoogleMapPageState();
}

class _GoogleMapPageState extends State<GoogleMapPage> {
  final Set<Marker> _markers = {};
  late GoogleMapController _mapController;

  @override
  void initState() {
    super.initState();
    _fetchToiletLocations();
  }

  // Fetch toilet locations from Firestore
  void _fetchToiletLocations() async {
    final toilets =
        await FirebaseFirestore.instance.collection('toilets').get();
    setState(() {
      for (var toilet in toilets.docs) {
        GeoPoint location = toilet['location'];
        String name = toilet['name'];

        _markers.add(
          Marker(
            markerId: MarkerId(toilet.id),
            position: LatLng(location.latitude, location.longitude),
            infoWindow: InfoWindow(
              title: name,
              snippet: toilet['description'], // Additional info
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Toilets'),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(37.7749, -122.4194), // Default to San Francisco
          zoom: 12,
        ),
        markers: _markers,
        onMapCreated: (controller) {
          _mapController = controller;
        },
      ),
    );
  }
}
