import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchPage extends StatefulWidget {
  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  TextEditingController _searchController = TextEditingController();
  List<QueryDocumentSnapshot> _searchResults = [];
  Position? _currentPosition;
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  final double searchRadius = 5.0;
  LatLng _initialMapPosition = const LatLng(7.8731, 80.7718);
  List<LatLng> polylineCoordinates = [];
  List<Map<String, dynamic>> _searchHistory = [];
  late PolylinePoints polylinePoints;
  bool _showCombinedList = false;

  @override
  void initState() {
    super.initState();
    polylinePoints = PolylinePoints();
    _getCurrentLocation();
    _loadSearchHistory();
  }

  Future<void> _saveSearchHistory(Map<String, dynamic> searchData) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _searchHistory.add(searchData);

    // Convert list of maps to a list of JSON strings
    List<String> encodedList =
        _searchHistory.map((item) => json.encode(item)).toList();

    await prefs.setStringList('search_history', encodedList);
    setState(() {}); // Update UI
  }

  Future<void> _loadSearchHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? storedData = prefs.getStringList('search_history');

    if (storedData != null) {
      setState(() {
        _searchHistory = storedData
            .map((item) => json.decode(item) as Map<String, dynamic>)
            .toList();
      });
    }
  }

  // Get Current User Location and Load All Toilets
  Future<void> _getCurrentLocation() async {
    try {
      PermissionStatus permission = await Permission.location.request();
      if (!permission.isGranted) {
        print("Location permission denied");
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      print(
          "Current Location: Lat:${position.latitude}, Lng:${position.longitude}"); // Debugging log

      setState(() {
        _currentPosition = position;
        _initialMapPosition = LatLng(position.latitude, position.longitude);
        _markers.add(
          Marker(
            markerId: MarkerId("current_location"),
            position: _initialMapPosition,
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(title: "You are here"),
          ),
        );
      });

      _updateMapPosition(_initialMapPosition);
      _fetchAllToilets(); // Load toilets after setting location
    } catch (e) {
      print("Error getting location: $e");
    }
  }

  // Fetch and Display All Toilets (Like Home Page)
  Future<void> _fetchAllToilets() async {
    QuerySnapshot snapshot =
        await FirebaseFirestore.instance.collection('toilets').get();
    Set<Marker> markers = {};

    for (var doc in snapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      if (data.containsKey('location')) {
        double toiletLat = data['location']['latitude'];
        double toiletLng = data['location']['longitude'];

        markers.add(
          Marker(
            markerId: MarkerId(doc.id),
            position: LatLng(toiletLat, toiletLng),
            infoWindow: InfoWindow(
              title: data['name'] ?? 'Unnamed Toilet',
              snippet: "Tap for details",
              onTap: () {
                _showToiletDetails(data);
              },
            ),
          ),
        );
      }
    }

    setState(() {
      _markers = markers;
    });
  }

  // Search Toilets by Name (Updated)
  void _searchToilets(String query) async {
    QuerySnapshot snapshot =
        await FirebaseFirestore.instance.collection('toilets').get();

    Set<Marker> markers = {};
    List<QueryDocumentSnapshot> searchResults = [];

    for (var doc in snapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      if (data.containsKey('name') && data.containsKey('location')) {
        String toiletName = data['name'].toString().toLowerCase();
        if (toiletName.contains(query.toLowerCase())) {
          // ✅ Partial Match Check
          searchResults.add(doc);

          double toiletLat = data['location']['latitude'];
          double toiletLng = data['location']['longitude'];

          markers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(toiletLat, toiletLng),
              infoWindow: InfoWindow(
                title: data['name'] ?? 'Unnamed Toilet',
                snippet: "Tap for details",
                onTap: () {
                  _showToiletDetails(data);
                },
              ),
            ),
          );
          // Save the search to history
          if (!_searchHistory.any((history) => history['id'] == doc.id)) {
            _saveSearchHistory({
              'id': doc.id,
              'name': data['name'],
              'location': data['location']
            });
          }
        }
      }
    }

    setState(() {
      _searchResults = searchResults; // ✅ Update the list view
      _markers =
          markers.isNotEmpty ? markers : _markers; // ✅ Update map markers
    });

    if (searchResults.isEmpty) {
      _fetchAllToilets(); // ✅ Show all toilets if no matches found
    }
  }

  Future<void> _getDirections(LatLng destination) async {
    if (_currentPosition == null) {
      print("Error: Current location is null");
      return;
    }
    // 🔹 Check for invalid destination coordinates
    if (destination.latitude == 0.0 || destination.longitude == 0.0) {
      print("Invalid destination coordinates");
      return;
    }
    LatLng start =
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    LatLng end = destination;

    String googleMapsUrl =
        'https://maps.googleapis.com/maps/api/directions/json?origin=${start.latitude},${start.longitude}&destination=${end.latitude},${end.longitude}&mode=driving&key=AIzaSyC3AXw-RcPsAR5s9Cgr84chOLDYT575ZM4';

    try {
      var response = await http.get(Uri.parse(googleMapsUrl));

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        print("Response Data: $data"); // Debugging

        if (data['status'] != 'OK') {
          print(
              "Google API Error: ${data['status']} - ${data['error_message'] ?? 'No error message'}");
          return;
        }

        var route = data['routes'][0];
        var polyline = route['overview_polyline']['points'];
        List<LatLng> polylineCoordinates = _decodePolyline(polyline);

        print("Polyline Coordinates: $polylineCoordinates"); // Debugging log

        // Ensure polyline data is valid before updating state
        if (polylineCoordinates.isEmpty) {
          print("Error: No polyline coordinates found.");
          return;
        }

        setState(() {
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId("route"),
              points: polylineCoordinates,
              color: Colors.blue,
              width: 5,
            ),
          );
        });
        print("Polylines Added: ${_polylines.length}"); // Debugging log

        _updateMapPosition(end);

        var legs = route['legs'][0];
        var distance = legs['distance']['text'];
        var duration = legs['duration']['text'];

        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text("Route Details"),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Distance: $distance"),
                  Text("Estimated Time: $duration"),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close"),
                ),
                TextButton(
                  onPressed: () {
                    _openGoogleMaps(end.latitude, end.longitude);
                  },
                  child: const Text("Get Directions 🧭"),
                ),
              ],
            );
          },
        );
      } else {
        print("Error: HTTP ${response.statusCode}");
        print("Response Body: ${response.body}");
      }
    } catch (e) {
      print("Error fetching directions: $e");
    }
  }

  List<LatLng> _decodePolyline(String polyline) {
    try {
      List<LatLng> polylineCoordinates = [];
      int index = 0;
      int len = polyline.length;
      int lat = 0;
      int lng = 0;

      while (index < len) {
        int shift = 0;
        int result = 0;

        // Decode latitude
        do {
          int byte = polyline.codeUnitAt(index++) - 63;
          result |= (byte & 0x1f) << shift;
          shift += 5;
        } while (polyline.codeUnitAt(index - 1) >= 0x20);
        lat += (result & 0x01 != 0) ? ~(result >> 1) : (result >> 1);

        shift = 0;
        result = 0;

        // Decode longitude
        do {
          int byte = polyline.codeUnitAt(index++) - 63;
          result |= (byte & 0x1f) << shift;
          shift += 5;
        } while (polyline.codeUnitAt(index - 1) >= 0x20);
        lng += (result & 0x01 != 0) ? ~(result >> 1) : (result >> 1);

        polylineCoordinates.add(LatLng((lat / 1E5), (lng / 1E5)));
      }

      return polylineCoordinates;
    } catch (e) {
      print("Error decoding polyline: $e");
      return [];
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371; // Earth radius in KM
    double dLat = (lat2 - lat1) * (3.141592653589793 / 180);
    double dLon = (lon2 - lon1) * (3.141592653589793 / 180);
    double a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1 * (3.141592653589793 / 180)) *
            cos(lat2 * (3.141592653589793 / 180)) *
            (sin(dLon / 2) * sin(dLon / 2));
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c; // Distance in KM
  }

  void _showToiletDetails(Map<String, dynamic> data) {
    double toiletLat = data['location']['latitude'];
    double toiletLng = data['location']['longitude'];
    double avgRating = data['average_rating'] ?? 0.0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(data['name'] ?? "Toilet Details"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Amenities: ${data['amenities'] ?? 'Not listed'}"),
                Row(
                  children: [
                    const Text("Rating: "),
                    RatingBarIndicator(
                      rating: avgRating,
                      itemBuilder: (context, _) => const Icon(
                        Icons.star,
                        color: Colors.amber,
                      ),
                      itemCount: 5,
                      itemSize: 20.0,
                    ),
                    Text(" ($avgRating)"),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
              TextButton(
                onPressed: () {
                  _openGoogleMaps(toiletLat, toiletLng);
                  _updateMapPosition(LatLng(toiletLat, toiletLng));
                },
                child: const Text("Navigate"),
              ),
            ],
          );
        },
      );
    });
  }

  void _openGoogleMaps(double lat, double lng) async {
    String url = 'https://www.google.com/maps?q=$lat,$lng&z=12&t=m&hl=en';
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not open the map';
    }
  }

  void _updateMapPosition(LatLng position) {
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(position, 14),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
    _searchController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Toilet Locator")),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (query) {
                        _searchToilets(query);
                        setState(() {
                          _showCombinedList = query.isNotEmpty;
                        });
                      },
                      onTap: () {
                        setState(() {
                          _showCombinedList = true;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search Toilets',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                    // Combined dropdown list
                    if (_showCombinedList)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.5),
                              spreadRadius: 2,
                              blurRadius: 5,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        margin: EdgeInsets.symmetric(horizontal: 8),
                        constraints: BoxConstraints(
                          maxHeight: 200, // Adjust as needed
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            // Section header for search results
                            if (_searchResults.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.all(8),
                                child: Text(
                                  'Search Results',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                            // Search results
                            ..._searchResults.map((doc) {
                              var data = doc.data() as Map<String, dynamic>;
                              return ListTile(
                                leading: Icon(Icons.search, color: Colors.blue),
                                title: Text(data['name'] ?? "Unnamed Toilet"),
                                onTap: () {
                                  double lat = data['location']['latitude'];
                                  double lng = data['location']['longitude'];
                                  _updateMapPosition(LatLng(lat, lng));
                                  setState(() {
                                    _showCombinedList = false;
                                    _searchController.text = data['name'] ?? "";
                                  });
                                },
                              );
                            }).toList(),

                            // Section header for search history
                            if (_searchHistory.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.all(8),
                                child: Text(
                                  'Recent Searches',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            // Search history
                            ..._searchHistory.map((history) {
                              return ListTile(
                                leading:
                                    Icon(Icons.history, color: Colors.green),
                                title: Text(history['name']),
                                onTap: () {
                                  setState(() {
                                    _searchController.text = history['name'];
                                    _searchToilets(history['name']);
                                    _showCombinedList = false;
                                  });
                                },
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              // List of Search Results (Only Shows If There Are Results)
              Expanded(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _initialMapPosition,
                    zoom: 14.0,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                ),
              ),
            ],
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: FloatingActionButton(
              onPressed: _getCurrentLocation,
              child: Icon(Icons.location_on),
            ),
          ),
        ],
      ),
    );
  }
}
