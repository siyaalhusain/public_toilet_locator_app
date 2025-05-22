import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:project_x/screen/view_reviews_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'AddCommentPage.dart' show AddCommentPage;
import 'nearbytoiletspage.dart';
import 'profile_page.dart';
import 'notifications_page.dart';
import 'login_page.dart';
import 'filter_page.dart';

class HomePage extends StatefulWidget {
  final String loggedInUserRole;

  HomePage({required this.loggedInUserRole});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  late GoogleMapController _mapController;
  String _selectedRating = "Any";
  List<String> _selectedAmenities = [];
  List<Map<String, dynamic>> allToilets = [];
  LatLng? _userLocation;
  TextEditingController _searchController = TextEditingController();
  List<QueryDocumentSnapshot> _searchResults = [];
  List<Map<String, dynamic>> _searchHistory = [];
  bool _showCombinedList = false;
  final CollectionReference toiletsCollection =
      FirebaseFirestore.instance.collection('toilets');
  Completer<GoogleMapController> _controller = Completer();
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _loadMarkers();
    _getUserLocation();
    _loadSearchHistory();
  }

  Future<void> _loadSearchHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? storedData =
        prefs.getStringList('search_history_$_currentUserId');

    if (storedData != null) {
      setState(() {
        _searchHistory = storedData
            .map((item) => json.decode(item) as Map<String, dynamic>)
            .toList();
      });
    }
  }

  Future<void> _saveSearchHistory(Map<String, dynamic> searchData) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    searchData['userId'] = _currentUserId;
    _searchHistory.add(searchData);
    _searchHistory = _searchHistory
        .where((item) => item['userId'] == _currentUserId)
        .toList();
    List<String> encodedList =
        _searchHistory.map((item) => json.encode(item)).toList();
    await prefs.setStringList('search_history_$_currentUserId', encodedList);
    setState(() {});
  }

  void _getUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    setState(() {
      _userLocation = LatLng(position.latitude, position.longitude);
      _markers.add(
        Marker(
          markerId: MarkerId("current_location"),
          position: _userLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(title: "You are here"),
        ),
      );
    });

    if (_mapController != null) {
      _mapController.animateCamera(
        CameraUpdate.newLatLngZoom(_userLocation!, 14),
      );
    }
  }

  void _loadMarkers() async {
    try {
      QuerySnapshot querySnapshot = await toiletsCollection.get();
      Set<Marker> newMarkers = {};
      List<Map<String, dynamic>> toiletsList = [];

      for (var doc in querySnapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
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
                infoWindow: InfoWindow(
                  title: name,
                  onTap: () {
                    _showToiletDetails({
                      ...data,
                      'id': doc.id,
                    });
                  },
                ),
              ),
            );
            toiletsList.add({
              'id': doc.id,
              'name': name,
              'location': data['location'],
              'rating': data['rating'] ?? 0.0,
              'amenities': data['amenities'] ?? [],
              'photoUrl':
                  data['imageUrls'] != null && data['imageUrls'].isNotEmpty
                      ? data['imageUrls'][0]
                      : null,
            });
          }
        }
      }

      setState(() {
        _markers.clear();
        _markers.addAll(newMarkers);
        allToilets = toiletsList;
      });
    } catch (e) {
      print("Error loading markers: $e");
    }
  }

  void _searchToilets(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showCombinedList = false;
      });
      return;
    }

    QuerySnapshot snapshot = await toiletsCollection.get();
    Set<Marker> markers = {};
    List<QueryDocumentSnapshot> searchResults = [];

    for (var doc in snapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      if (data.containsKey('name') && data.containsKey('location')) {
        String toiletName = data['name'].toString().toLowerCase();
        if (toiletName.contains(query.toLowerCase())) {
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
                  _showToiletDetails({
                    ...data,
                    'id': doc.id,
                  });
                },
              ),
            ),
          );

          if (!_searchHistory.any((history) =>
              history['id'] == doc.id && history['userId'] == _currentUserId)) {
            _saveSearchHistory({
              'id': doc.id,
              'name': data['name'],
              'location': data['location'],
              'userId': _currentUserId,
            });
          }
        }
      }
    }

    setState(() {
      _searchResults = searchResults;
      if (markers.isNotEmpty) {
        _markers.clear();
        if (_userLocation != null) {
          _markers.add(
            Marker(
              markerId: MarkerId("current_location"),
              position: _userLocation!,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueBlue),
              infoWindow: InfoWindow(title: "You are here"),
            ),
          );
        }
        _markers.addAll(markers);
      }
      _showCombinedList = query.isNotEmpty;
    });

    if (searchResults.isNotEmpty && _mapController != null) {
      var firstResult = searchResults.first.data() as Map<String, dynamic>;
      double lat = firstResult['location']['latitude'];
      double lng = firstResult['location']['longitude'];

      _mapController.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(lat, lng),
          15.0,
        ),
      );
    }
  }

  void _showToiletDetails(Map<String, dynamic> data) async {
    double toiletLat = data['location']['latitude'];
    double toiletLng = data['location']['longitude'];
    double avgRating = data['average_rating'] ?? 0.0;
    String toiletId = data['id'];

    QuerySnapshot reviewsSnapshot = await FirebaseFirestore.instance
        .collection('washroom_reviews')
        .where('toilet_id', isEqualTo: toiletId)
        .orderBy('timestamp', descending: true)
        .limit(3)
        .get();

    List<Map<String, dynamic>> reviews = reviewsSnapshot.docs.map((doc) {
      var reviewData = doc.data() as Map<String, dynamic>;
      return {
        'user_name': reviewData['user_name'],
        'rating': reviewData['rating'],
        'comment': reviewData['comment'],
        'timestamp': reviewData['timestamp'],
        'image_url': reviewData['image_url'],
      };
    }).toList();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Row(
            children: [
              Icon(Icons.wc, color: Colors.blue),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  data['name'] ?? "Toilet Details",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.list_alt, color: Colors.blue),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Amenities: ${data['amenities']?.join(', ') ?? 'Not listed'}",
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 15),
                if (data['imageUrls'] != null &&
                    (data['imageUrls'] as List).isNotEmpty) ...[
                  Text(
                    "Photos",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: data['imageUrls'].length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              data['imageUrls'][index],
                              width: 150,
                              height: 100,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                width: 150,
                                height: 100,
                                color: Colors.grey[200],
                                child: Center(
                                  child: Icon(Icons.broken_image,
                                      color: Colors.grey),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(height: 15),
                ],
                Row(
                  children: [
                    Icon(Icons.star, color: Colors.amber),
                    SizedBox(width: 10),
                    Text(
                      "Rating:",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    SizedBox(width: 5),
                    RatingBarIndicator(
                      rating: avgRating,
                      itemBuilder: (context, _) => const Icon(
                        Icons.star,
                        color: Colors.amber,
                      ),
                      itemCount: 5,
                      itemSize: 20.0,
                    ),
                    Text(
                      " ($avgRating)",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (reviews.isNotEmpty) ...[
                  Divider(height: 25),
                  Text(
                    "Recent Reviews",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  ...reviews
                      .map((review) => Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: Colors.blue.shade100,
                                      child: Icon(Icons.person,
                                          color: Colors.blue),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      review['user_name'] ?? 'Anonymous',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                    Spacer(),
                                    RatingBarIndicator(
                                      rating: review['rating'] ?? 0.0,
                                      itemBuilder: (context, _) => Icon(
                                        Icons.star,
                                        color: Colors.amber,
                                      ),
                                      itemCount: 5,
                                      itemSize: 16.0,
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                if (review['comment'] != null &&
                                    review['comment'].isNotEmpty)
                                  Text(
                                    review['comment'],
                                    style: TextStyle(fontSize: 14),
                                  ),
                                if (review['image_url'] != null)
                                  Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        review['image_url'],
                                        height: 100,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ))
                      .toList(),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ViewReviewsPage(
                            toiletId: data['id'],
                          ),
                        ),
                      );
                    },
                    child: Text("View all reviews"),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "Close",
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.directions),
              label: Text("Navigate"),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                _getDirections(LatLng(toiletLat, toiletLng));
              },
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.rate_review),
              label: Text("Review"),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AddCommentPage(
                      toiletId: toiletId,
                      toiletName: data['name'],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _getDirections(LatLng destination) async {
    if (_userLocation == null) {
      return;
    }

    String googleAPIKey = 'AIzaSyC3AXw-RcPsAR5s9Cgr84chOLDYT575ZM4';
    String url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=${_userLocation!.latitude},${_userLocation!.longitude}&destination=${destination.latitude},${destination.longitude}&key=$googleAPIKey';

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

          setState(() {
            _polylines.clear();
            _polylines.add(Polyline(
              polylineId: PolylineId('route'),
              points: polylinePoints,
              color: Colors.blue,
              width: 5,
            ));
          });

          _mapController.animateCamera(
            CameraUpdate.newLatLngZoom(destination, 14),
          );

          showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                title: Row(
                  children: [
                    Icon(Icons.directions, color: Colors.blue),
                    SizedBox(width: 10),
                    Text("Route Details"),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.straighten, color: Colors.blue),
                              SizedBox(width: 10),
                              Text(
                                "Distance: ${route['distance']['text']}",
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.access_time, color: Colors.blue),
                              SizedBox(width: 10),
                              Text(
                                "Estimated Time: ${route['duration']['text']}",
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      "Close",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: Icon(Icons.map),
                    label: Text("Open in Google Maps"),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () {
                      _openGoogleMaps(
                          destination.latitude, destination.longitude);
                      Navigator.pop(context);
                    },
                  ),
                ],
              );
            },
          );
        }
      }
    } catch (e) {
      print("Error getting directions: $e");
    }
  }

  void _openGoogleMaps(double lat, double lng) async {
    String url = 'https://www.google.com/maps?q=$lat,$lng&z=14';
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not open the map';
    }
  }

  void _openFilterPage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FilterPage(
          onApplyFilter: (selectedRating, selectedAmenities) {
            Navigator.pop(context, {
              'rating': selectedRating,
              'amenities': selectedAmenities,
            });
          },
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _selectedRating = result['rating'];
        _selectedAmenities = List<String>.from(result['amenities']);
      });
      _applyFilters();
    }
  }

  void _applyFilters() {
    if (_selectedRating == "Any" && _selectedAmenities.isEmpty) {
      _loadMarkers();
    } else {
      _fetchFilteredToilets();
    }
  }

  Future<List<Map<String, dynamic>>> _getNearbyToiletsWithReviews() async {
    if (_userLocation == null) return [];

    try {
      QuerySnapshot snapshot = await toiletsCollection.get();
      List<Map<String, dynamic>> nearbyToilets = [];

      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('location') && data['location'] != null) {
          double? toiletLat =
              (data['location']['latitude'] as num?)?.toDouble();
          double? toiletLng =
              (data['location']['longitude'] as num?)?.toDouble();

          if (toiletLat != null && toiletLng != null) {
            double distanceInKm = _calculateDistance(_userLocation!.latitude,
                _userLocation!.longitude, toiletLat, toiletLng);

            if (distanceInKm <= 10) {
              nearbyToilets.add({
                'id': doc.id,
                'name': data['name'] ?? 'Unnamed Toilet',
                'address': data['address'] ?? 'No address',
                'distance': distanceInKm,
                'average_rating': data['average_rating'] ?? 0.0,
                'reviewsCount': data['reviewsCount'] ?? 0,
                'photoUrl':
                    data['imageUrls'] != null && data['imageUrls'].isNotEmpty
                        ? data['imageUrls'][0]
                        : null,
                'location': data['location'],
                'amenities': data['amenities'] ?? [],
              });
            }
          }
        }
      }

      nearbyToilets.sort((a, b) =>
          (a['distance'] as double).compareTo(b['distance'] as double));

      return nearbyToilets;
    } catch (e) {
      print("Error fetching nearby toilets with reviews: $e");
      return [];
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295;
    double a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  void _fetchFilteredToilets() {
    setState(() {
      _markers.clear();
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
              infoWindow: InfoWindow(
                title: toilet['name'],
                onTap: () {
                  _showToiletDetails(toilet);
                },
              ),
            ),
          );
        }
      }
    });
  }

  void _onItemTapped(int index) async {
    if (index == 0) {
      // Already on home, just set index
      setState(() {
        _selectedIndex = 0;
      });
    } else if (index == 1) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FilterPage(
            onApplyFilter: (selectedRating, selectedAmenities) {
              Navigator.pop(context, {
                'rating': selectedRating,
                'amenities': selectedAmenities,
              });
            },
          ),
        ),
      );

      if (result != null) {
        setState(() {
          _selectedRating = result['rating'];
          _selectedAmenities = List<String>.from(result['amenities']);
          _selectedIndex = 0; // ✅ Return to Home with Home icon active
        });
        _applyFilters();
      }
    } else if (index == 2) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NearbyToiletsPage(userLocation: _userLocation),
        ),
      );
      setState(() {
        _selectedIndex = 0; // ✅ Return to Home with Home icon active
      });
    } else if (index == 3) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProfilePage(role: widget.loggedInUserRole),
        ),
      );
      setState(() {
        _selectedIndex = 0; // ✅ Return to Home with Home icon active
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text(
          'Toilet Finder',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
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
      body: Builder(
        builder: (BuildContext context) {
          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _userLocation ?? const LatLng(37.7749, -122.4194),
                  zoom: 14.0,
                ),
                markers: _markers,
                polylines: _polylines,
                onMapCreated: (GoogleMapController controller) {
                  _mapController = controller;
                  _controller.complete(controller);
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
              ),
              Positioned(
                top: 10,
                left: 20,
                right: 20,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            spreadRadius: 2,
                            blurRadius: 5,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _searchToilets,
                        onTap: () {
                          setState(() {
                            _showCombinedList = true;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search Toilets',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              vertical: 15, horizontal: 16),
                          prefixIcon: Icon(Icons.search, color: Colors.blue),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear, color: Colors.grey),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                      _searchResults.clear();
                                      _showCombinedList = false;
                                      _loadMarkers();
                                    });
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                    if (_showCombinedList)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.5),
                              spreadRadius: 2,
                              blurRadius: 5,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        margin: EdgeInsets.only(top: 5),
                        constraints: BoxConstraints(maxHeight: 200),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
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
                            ..._searchResults.map((doc) {
                              var data = doc.data() as Map<String, dynamic>;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue.withOpacity(0.2),
                                  child: Icon(Icons.search, color: Colors.blue),
                                ),
                                title: Text(data['name'] ?? "Unnamed Toilet"),
                                onTap: () {
                                  double lat = data['location']['latitude'];
                                  double lng = data['location']['longitude'];
                                  _mapController.animateCamera(
                                    CameraUpdate.newLatLng(LatLng(lat, lng)),
                                  );
                                  setState(() {
                                    _showCombinedList = false;
                                    _searchController.text = data['name'] ?? "";
                                  });
                                },
                              );
                            }).toList(),
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
                            ..._searchHistory
                                .where((history) =>
                                    history['userId'] == _currentUserId)
                                .map((history) {
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      Colors.green.withOpacity(0.2),
                                  child:
                                      Icon(Icons.history, color: Colors.green),
                                ),
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
              Positioned(
                right: 20,
                bottom: 120,
                child: FloatingActionButton(
                  heroTag: "locationBtn",
                  backgroundColor: Colors.white,
                  onPressed: _getUserLocation,
                  child: Icon(Icons.my_location, color: Colors.blue),
                  elevation: 4,
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(25),
            topLeft: Radius.circular(25),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              spreadRadius: 0,
              blurRadius: 10,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(25.0),
            topRight: Radius.circular(25.0),
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            selectedItemColor: Colors.blue,
            unselectedItemColor: Colors.grey,
            selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            elevation: 8,
            items: [
              BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.filter_alt),
                label: 'Filter',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.list),
                label: 'Nearby',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
