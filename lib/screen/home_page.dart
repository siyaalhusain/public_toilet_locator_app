import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart'; // Import the location package
import 'package:project_x/screen/profile_page.dart';
import 'notifications_page.dart';
import 'search_page.dart';
import 'login_page.dart';
import 'package:http/http.dart' as http;
import 'Filter_page.dart'; // Ensure this import is correct

class HomePage extends StatefulWidget {
  final String loggedInUserRole;

  HomePage({required this.loggedInUserRole});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {}; // Set to store the polylines
  late GoogleMapController _mapController;
  String _selectedRating = "Any"; // Default value
  List<String> _selectedAmenities = [];
  List<Map<String, dynamic>> allToilets = []; // Store all toilet data

  // Firestore reference to the toilets collection
  final CollectionReference toiletsCollection =
      FirebaseFirestore.instance.collection('toilets');

  // User's current location
  LatLng? _userLocation;

  @override
  void initState() {
    super.initState();
    _loadMarkers();
    _getUserLocation(); // Get user location on init
  }

  void _openFilterPage() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FilterPage(
          onApplyFilter: (selectedRating, selectedAmenities) {
            setState(() {
              _selectedRating = selectedRating;
              _selectedAmenities = selectedAmenities;
            });
            _applyFilters(); // Apply filtering logic
          },
        ),
      ),
    );
  }

  void _applyFilters() {
    print(
        "Filtering toilets with rating: $_selectedRating and amenities: $_selectedAmenities");

    if (_selectedRating == "Any" && _selectedAmenities.isEmpty) {
      _loadMarkers(); // Load all toilets when filters are cleared
    } else {
      _fetchFilteredToilets(); // Apply the filters
    }
  }

  void _fetchFilteredToilets() {
    setState(() {
      _markers.clear(); // Clear markers before filtering

      for (var toilet in allToilets) {
        String toiletRating = toilet['rating'].toString();
        List<String> toiletAmenities = List<String>.from(toilet['amenities']);

        bool ratingMatches = (_selectedRating == "Any" ||
            double.parse(toiletRating) >= double.parse(_selectedRating[0]));
        bool amenitiesMatch = _selectedAmenities
            .every((amenity) => toiletAmenities.contains(amenity));

        if (ratingMatches && amenitiesMatch) {
          _markers.add(
            Marker(
              markerId: MarkerId(toilet['id']),
              position: LatLng(toilet['location']['latitude'],
                  toilet['location']['longitude']),
              infoWindow: InfoWindow(title: toilet['name']),
            ),
          );
        }
      }
    });
  }

  // Get the current location of the user
  void _getUserLocation() async {
    Location location = Location();

    bool _serviceEnabled = await location.serviceEnabled();
    PermissionStatus _permissionGranted = await location.hasPermission();

    if (!_serviceEnabled) {
      await location.requestService();
    }

    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await location.requestPermission();
    }

    if (_permissionGranted == PermissionStatus.granted) {
      var currentLocation = await location.getLocation();
      setState(() {
        _userLocation =
            LatLng(currentLocation.latitude!, currentLocation.longitude!);
      });

      // Move the camera to the user's location
      if (_mapController != null && _userLocation != null) {
        _mapController.animateCamera(
          CameraUpdate.newLatLng(_userLocation!),
        );
      }
    }
  }

  // Fetch and load markers from Firestore
  void _loadMarkers() async {
    try {
      QuerySnapshot querySnapshot =
          await FirebaseFirestore.instance.collection('toilets').get();
      print("Fetched ${querySnapshot.docs.length} documents from Firestore.");

      Set<Marker> newMarkers = {}; // Temporary set to store markers
      List<Map<String, dynamic>> toiletsList = []; // Temporary list for toilets
      for (var doc in querySnapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        print("Document Data: $data"); // Debugging print

        if (data.containsKey('location') && data['location'] != null) {
          double? latitude = (data['location']['latitude'] as num?)?.toDouble();
          double? longitude =
              (data['location']['longitude'] as num?)?.toDouble();
          String name = data['name'] ?? 'Unnamed Toilet';

          if (latitude != null && longitude != null) {
            newMarkers.add(
              Marker(
                markerId: MarkerId(doc.id),
                position: LatLng(latitude, longitude),
                infoWindow: InfoWindow(title: name),
              ),
            );
          } else {
            print("⚠ Invalid coordinates in document ${doc.id}");
          }
        } else {
          print("⚠ Missing location data in document ${doc.id}");
        }
      }

      setState(() {
        _markers.clear(); // Clear existing markers
        _markers.addAll(newMarkers); // Add new markers
      });

      print("✅ Markers loaded successfully");
    } catch (e) {
      print("❌ Error loading markers: $e");
    }
  }

  // Method to calculate the shortest path using the Google Maps Directions API
  Future<String> _getDirections(LatLng origin, LatLng destination) async {
    String googleAPIKey = 'AIzaSyC3AXw-RcPsAR5s9Cgr84chOLDYT575ZM4';
    String url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&key=$googleAPIKey';

    try {
      var response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        var jsonData = json.decode(response.body);
        if (jsonData['status'] == 'OK') {
          var route = jsonData['routes'][0]['legs'][0];
          var steps = route['steps'];

          List<LatLng> polylinePoints = [];
          for (var step in steps) {
            polylinePoints.add(LatLng(
                step['end_location']['lat'], step['end_location']['lng']));
          }

          // Create a polyline and add it to the map
          setState(() {
            _polylines.clear(); // Clear previous routes
            _polylines.add(Polyline(
              polylineId: PolylineId('route'),
              points: polylinePoints,
              color: Colors.blue,
              width: 5,
            ));
          });

          return route['duration']['text']; // Return the duration of the route
        } else {
          return 'Error calculating route: ${jsonData['status']}';
        }
      } else {
        return 'HTTP Error: ${response.statusCode}';
      }
    } catch (e) {
      return 'Error calculating route';
    }
  }

  // Show the route dialog with the duration
  void _showRouteDialog(String toiletName, String duration) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Route to $toiletName'),
          content: Text('Estimated time: $duration'),
          actions: <Widget>[
            TextButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _onItemTapped(int index) {
    if (index == 1) {
      // Example toilet data (replace with actual data from Firestore)
      Map<String, dynamic> exampleToiletData = {
        'name': 'Example Toilet',
        'location': {'latitude': 37.7749, 'longitude': -122.4194},
        'average_rating': 4.5,
        'amenities': ['male', 'female', 'accessible'],
      };

      // Navigate to DetailsPage with toiletId and toiletData
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FilterPage(
            onApplyFilter: (selectedRating, selectedAmenities) {
              setState(() {
                _selectedRating = selectedRating;
                _selectedAmenities = selectedAmenities;
              });
              _applyFilters();
            },
          ),
        ),
      );
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => NotificationPage()),
      );
    } else if (index == 3) {
      _navigateToProfilePage();
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  void _navigateToProfilePage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfilePage(role: widget.loggedInUserRole),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // ✅ Google Map as the Background
          GoogleMap(
            initialCameraPosition: _userLocation != null
                ? CameraPosition(
                    target: _userLocation!, // User's location
                    zoom: 12,
                  )
                : CameraPosition(
                    target:
                        LatLng(37.7749, -122.4194), // Default (San Francisco)
                    zoom: 12,
                  ),
            markers: _markers,
            polylines: _polylines, // Display polylines
            onMapCreated: (controller) {
              _mapController = controller;
            },
            myLocationEnabled: true, // Show user location
          ),
          // ✅ View Reviews Section (Draggable Bottom Sheet)
          DraggableScrollableSheet(
            initialChildSize: 0.1, // Minimized state (10% of screen height)
            minChildSize: 0.1, // Minimum size
            maxChildSize: 0.5, // Expandable up to 50% of screen height
            builder: (context, scrollController) {
              return Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // 🔽 Drag Handle
                    Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    SizedBox(height: 10),

                    // 📢 Title: Reviews Section
                    Text(
                      "Reviews Near Toilets",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Divider(),

                    // 📝 Reviews List
                    Expanded(
                      child: FutureBuilder<QuerySnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('reviews')
                            .get(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Center(child: CircularProgressIndicator());
                          }
                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return Center(child: Text("No reviews available."));
                          }

                          return ListView(
                            controller: scrollController,
                            children: snapshot.data!.docs.map((doc) {
                              var review = doc.data() as Map<String, dynamic>;
                              return ListTile(
                                leading: Icon(Icons.star, color: Colors.orange),
                                title: Text(
                                    review['toilet_name'] ?? "Unknown Toilet"),
                                subtitle:
                                    Text(review['comment'] ?? "No Comment"),
                                trailing: Text(
                                  "${review['rating']} ⭐",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // ✅ Positioned Search Button (One-Third Down)
          Positioned(
            top: MediaQuery.of(context).size.height / 6, // 1/6 of screen height
            left: 20,
            right: 20,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.lightBlue, // Solid light blue background color
                borderRadius: BorderRadius.circular(20), // Rounded corners
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: const Offset(0, 3), // Shadow effect
                  ),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  backgroundColor: Colors
                      .transparent, // Remove default background color to show light blue
                  shadowColor:
                      Colors.transparent, // Remove shadow from button itself
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SearchPage()),
                  );
                },
                child: Row(
                  children: [
                    // Search Icon on the Left, with small distance from left
                    const SizedBox(
                        width: 10), // Small gap between left and icon
                    const Icon(Icons.search,
                        color: Colors.white), // White icon color

                    // Spacer to center the text
                    const SizedBox(
                        width: 10), // Space between the icon and the text

                    // Centered Text, also white color
                    Expanded(
                      child: Text(
                        'Search Toilets',
                        textAlign: TextAlign
                            .center, // Center the text in the remaining space
                        style: const TextStyle(
                            fontSize: 18, color: Colors.white), // White text
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.filter), label: 'Filter'), // Updated here
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications), label: 'Notifications'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class ToiletProvider extends ChangeNotifier {
  List<Map<String, dynamic>> toilets = [];

  Future<void> fetchToilets() async {
    QuerySnapshot snapshot =
        await FirebaseFirestore.instance.collection('toilets').get();

    toilets = snapshot.docs.map((doc) {
      return {
        'id': doc.id,
        'name': doc['name'],
        'latitude': doc['latitude'],
        'longitude': doc['longitude'],
      };
    }).toList();

    notifyListeners();
  }
}
