import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
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
  final bool isAccountActive; // Add this new parameter
  final String? paymentStatus; // Add this

  const HomePage({
    Key? key,
    required this.loggedInUserRole,
    this.isAccountActive = true,
    this.paymentStatus, // Add this
  }) : super(key: key);

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
  final TextEditingController _searchController = TextEditingController();
  List<QueryDocumentSnapshot> _searchResults = [];
  List<Map<String, dynamic>> _searchHistory = [];
  bool _showCombinedList = false;
  final CollectionReference toiletsCollection =
      FirebaseFirestore.instance.collection('toilets');
  final Completer<GoogleMapController> _controller = Completer();
  String? _currentUserId;
  bool _isSearching = false;
  List<PlacePrediction> _placePredictions = [];
  final FocusNode _searchFocusNode = FocusNode();
  LatLng? _searchLocation;
  static const String _googleApiKey = 'AIzaSyC3AXw-RcPsAR5s9Cgr84chOLDYT575ZM4';

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _loadMarkers();
    _getUserLocation();
    _loadSearchHistory();
    _searchFocusNode.addListener(_onSearchFocusChange);
  }

  void _onSearchFocusChange() {
    if (!_searchFocusNode.hasFocus && _searchController.text.isEmpty) {
      setState(() {
        _showCombinedList = false;
      });
    }
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? storedData =
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
    final prefs = await SharedPreferences.getInstance();
    searchData['userId'] = _currentUserId;
    _searchHistory.add(searchData);
    _searchHistory = _searchHistory
        .where((item) => item['userId'] == _currentUserId)
        .toList();
    final List<String> encodedList =
        _searchHistory.map((item) => json.encode(item)).toList();
    await prefs.setStringList('search_history_$_currentUserId', encodedList);
    setState(() {});
  }

  Future<void> _getUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled.')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Location permissions are permanently denied.')),
      );
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
        _markers.add(
          Marker(
            markerId: const MarkerId("current_location"),
            position: _userLocation!,
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: const InfoWindow(title: "You are here"),
          ),
        );
      });

      if (_mapController != null) {
        _mapController.animateCamera(
          CameraUpdate.newLatLngZoom(_userLocation!, 14),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
    }
  }

  Future<void> _loadMarkers() async {
    try {
      final querySnapshot = await toiletsCollection.get();
      final Set<Marker> newMarkers = {};
      final List<Map<String, dynamic>> toiletsList = [];

      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('location') && data['location'] != null) {
          final double? latitude =
              (data['location']['latitude'] as num?)?.toDouble();
          final double? longitude =
              (data['location']['longitude'] as num?)?.toDouble();
          final String name = data['name'] ?? 'Unnamed Toilet';

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
              'address': data['address'] ?? 'No address',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading markers: $e')),
      );
    }
  }

  Future<void> _searchPlaces(String input) async {
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
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$_googleApiKey&components=country:lk&types=establishment');

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
          debugPrint('Places API error: ${data['status']}');
        }
      } else {
        debugPrint('HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error searching places: $e');
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
          'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_googleApiKey');

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final result = data['result'];
          final geometry = result['geometry'];
          final location = geometry['location'];
          final lat = location['lat'];
          final lng = location['lng'];
          final address = result['formatted_address'] ?? 'Selected Location';

          setState(() {
            _searchLocation = LatLng(lat, lng);
            _searchController.text = address;
            _placePredictions = [];
          });

          _searchToiletsNearLocation(_searchLocation!);

          _mapController.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: _searchLocation!,
                zoom: 14,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error getting place details: $e');
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _searchToiletsNearLocation(LatLng location) async {
    setState(() {
      _isSearching = true;
    });

    try {
      final snapshot = await toiletsCollection.get();
      final Set<Marker> markers = {};
      final List<QueryDocumentSnapshot> searchResults = [];

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('location') && data['location'] != null) {
          final double toiletLat = data['location']['latitude'];
          final double toiletLng = data['location']['longitude'];

          final double distance = _calculateDistance(
              location.latitude, location.longitude, toiletLat, toiletLng);

          if (distance <= 5) {
            // 5km radius
            searchResults.add(doc);

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
                history['id'] == doc.id &&
                history['userId'] == _currentUserId)) {
              await _saveSearchHistory({
                'id': doc.id,
                'name': data['name'],
                'address': data['address'] ?? 'No address',
                'location': data['location'],
                'userId': _currentUserId,
              });
            }
          }
        }
      }

      setState(() {
        _searchResults = searchResults;
        _markers.clear();
        if (_userLocation != null) {
          _markers.add(
            Marker(
              markerId: const MarkerId("current_location"),
              position: _userLocation!,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueBlue),
              infoWindow: const InfoWindow(title: "You are here"),
            ),
          );
        }
        _markers.addAll(markers);
        _showCombinedList = false;
      });
    } catch (e) {
      debugPrint("Error searching toilets: $e");
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _searchToilets(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showCombinedList = false;
        _placePredictions = [];
      });
      return;
    }

    try {
      setState(() {
        _isSearching = true;
      });

      // Search by name
      final nameSnapshot = await toiletsCollection
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThan: query + 'z')
          .get();

      // Search by address
      final addressSnapshot = await toiletsCollection
          .where('address', isGreaterThanOrEqualTo: query)
          .where('address', isLessThan: query + 'z')
          .get();

      final Set<QueryDocumentSnapshot> combinedResults = {};
      combinedResults.addAll(nameSnapshot.docs);
      combinedResults.addAll(addressSnapshot.docs);

      final Set<Marker> markers = {};
      final List<QueryDocumentSnapshot> searchResults =
          combinedResults.toList();

      for (var doc in searchResults) {
        final data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('location') && data['location'] != null) {
          final double toiletLat = data['location']['latitude'];
          final double toiletLng = data['location']['longitude'];

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
            await _saveSearchHistory({
              'id': doc.id,
              'name': data['name'],
              'address': data['address'] ?? 'No address',
              'location': data['location'],
              'userId': _currentUserId,
            });
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
                markerId: const MarkerId("current_location"),
                position: _userLocation!,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueBlue),
                infoWindow: const InfoWindow(title: "You are here"),
              ),
            );
          }
          _markers.addAll(markers);
        }
        _showCombinedList = query.isNotEmpty;
      });

      if (searchResults.isNotEmpty && _mapController != null) {
        final firstResult = searchResults.first.data() as Map<String, dynamic>;
        final double lat = firstResult['location']['latitude'];
        final double lng = firstResult['location']['longitude'];

        _mapController.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(lat, lng),
            15.0,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error searching toilets: $e");
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295;
    final double a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  void _showToiletDetails(Map<String, dynamic> data) async {
    final double toiletLat = data['location']['latitude'];
    final double toiletLng = data['location']['longitude'];
    final double avgRating = data['average_rating'] ?? 0.0;
    final String toiletId = data['id'];

    // Try to fetch maintenance status
    DocumentSnapshot? maintenanceSnapshot;
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('maintenanceRecords')
          .where('toiletId', isEqualTo: toiletId)
          .limit(1)
          .get();
      maintenanceSnapshot =
          querySnapshot.docs.isNotEmpty ? querySnapshot.docs.first : null;
    } catch (e) {
      debugPrint('Error fetching maintenance status: $e');
    }

    // Fetch complete toilet details from Firestore if maintenance exists
    DocumentSnapshot? toiletDoc;
    bool hasOperatingInfo = false;
    bool is24Hours = false;
    String openingTime = '06:00';
    String closingTime = '22:00';
    List<bool> operatingDays = List.filled(7, true);
    Map<String, bool> features = {};

    if (maintenanceSnapshot != null && maintenanceSnapshot.exists) {
      try {
        toiletDoc = await FirebaseFirestore.instance
            .collection('toilets')
            .doc(toiletId)
            .get();

        if (toiletDoc.exists) {
          hasOperatingInfo = true;
          is24Hours = toiletDoc['is24Hours'] ?? false;
          openingTime = toiletDoc['openingTime'] ?? '06:00';
          closingTime = toiletDoc['closingTime'] ?? '22:00';
          operatingDays = List<bool>.from(
              toiletDoc['operatingDays'] ?? List.filled(7, true));
          features = Map<String, bool>.from(toiletDoc['features'] ?? {});
        }
      } catch (e) {
        debugPrint('Error fetching toilet details: $e');
      }
    }

    final QuerySnapshot reviewsSnapshot = await FirebaseFirestore.instance
        .collection('washroom_reviews')
        .where('toilet_id', isEqualTo: toiletId)
        .orderBy('timestamp', descending: true)
        .limit(3)
        .get();

    final List<Map<String, dynamic>> reviews = reviewsSnapshot.docs.map((doc) {
      final reviewData = doc.data() as Map<String, dynamic>;
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
        if (maintenanceSnapshot != null && maintenanceSnapshot.exists) {
          // Show dialog with maintenance details (your enhanced version)
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width - 40,
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with title
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.wc, color: Colors.blue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            data['name'] ?? "Toilet Details",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Divider
                  const Divider(height: 1, thickness: 1),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Maintenance Status
                          Container(
                            margin: const EdgeInsets.only(bottom: 15),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: (maintenanceSnapshot['status'] ==
                                                'Operational'
                                            ? Colors.green
                                            : Colors.red)
                                        .withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: maintenanceSnapshot['status'] ==
                                              'Operational'
                                          ? Colors.green
                                          : Colors.red,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        maintenanceSnapshot['status'] ==
                                                'Operational'
                                            ? Icons.check_circle
                                            : Icons.error,
                                        size: 16,
                                        color: maintenanceSnapshot['status'] ==
                                                'Operational'
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        maintenanceSnapshot['status'] ??
                                            'Unknown Status',
                                        style: TextStyle(
                                          color:
                                              maintenanceSnapshot['status'] ==
                                                      'Operational'
                                                  ? Colors.green
                                                  : Colors.red,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (maintenanceSnapshot['lastUpdated'] != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.calendar_today,
                                            size: 14, color: Colors.grey[700]),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Last: ${DateFormat('MMM d, yyyy').format((maintenanceSnapshot['lastUpdated'] as Timestamp).toDate())}',
                                          style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Operating Hours (only if hasOperatingInfo)
                          if (hasOperatingInfo)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 15),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time,
                                          color: Colors.blue),
                                      const SizedBox(width: 10),
                                      Text(
                                        is24Hours
                                            ? "Open 24 Hours"
                                            : "Open: $openingTime - $closingTime",
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 4,
                                    children: List.generate(7, (index) {
                                      final days = [
                                        'Mon',
                                        'Tue',
                                        'Wed',
                                        'Thu',
                                        'Fri',
                                        'Sat',
                                        'Sun'
                                      ];
                                      return Chip(
                                        label: Text(days[index]),
                                        backgroundColor: operatingDays[index]
                                            ? Colors.green.withOpacity(0.2)
                                            : Colors.grey.withOpacity(0.2),
                                        labelStyle: TextStyle(
                                          color: operatingDays[index]
                                              ? Colors.green
                                              : Colors.grey,
                                        ),
                                      );
                                    }),
                                  ),
                                ],
                              ),
                            ),

                          // Features (only if hasOperatingInfo)
                          if (hasOperatingInfo && features.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 15),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.list_alt, color: Colors.blue),
                                      SizedBox(width: 10),
                                      Text(
                                        "Features:",
                                        style: TextStyle(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: features.entries
                                        .where((entry) => entry.value == true)
                                        .map((entry) => Chip(
                                              label: Text(entry.key),
                                              backgroundColor:
                                                  Colors.blue.withOpacity(0.2),
                                              labelStyle: const TextStyle(
                                                  color: Colors.blue),
                                            ))
                                        .toList(),
                                  ),
                                ],
                              ),
                            ),

                          // Rest of your content (amenities, photos, ratings, reviews)
                          // ... [Include all the other content sections from your original code here]
                          // Amenities
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 15),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.list_alt, color: Colors.blue),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "Amenities: ${data['amenities']?.join(', ') ?? 'Not listed'}",
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Photos
                          if (data['imageUrls'] != null &&
                              (data['imageUrls'] as List).isNotEmpty) ...[
                            const Text(
                              "Photos",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 100,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: data['imageUrls'].length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        data['imageUrls'][index],
                                        width: 150,
                                        height: 100,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
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
                            const SizedBox(height: 15),
                          ],

                          // Rating
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber),
                              const SizedBox(width: 10),
                              const Text(
                                "Rating:",
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 5),
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
                                " (${avgRating.toStringAsFixed(1)})",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),

                          // Reviews
                          if (reviews.isNotEmpty) ...[
                            const Divider(height: 25),
                            const Text(
                              "Recent Reviews",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...reviews
                                .map((review) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                backgroundColor:
                                                    Colors.blue.shade100,
                                                child: const Icon(Icons.person,
                                                    color: Colors.blue),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                review['user_name'] ??
                                                    'Anonymous',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w500),
                                              ),
                                              const Spacer(),
                                              RatingBarIndicator(
                                                rating: review['rating'] ?? 0.0,
                                                itemBuilder: (context, _) =>
                                                    const Icon(
                                                  Icons.star,
                                                  color: Colors.amber,
                                                ),
                                                itemCount: 5,
                                                itemSize: 16.0,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          if (review['comment'] != null &&
                                              review['comment'].isNotEmpty)
                                            Text(
                                              review['comment'],
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                          if (review['image_url'] != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 8),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
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
                              child: const Text("View all reviews"),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Close",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.directions, size: 18),
                              label: const Text("Navigate"),
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.blue,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                _getDirections(LatLng(toiletLat, toiletLng));
                              },
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.rate_review, size: 18),
                              label: const Text("Review"),
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
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
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          // Show your original dialog without maintenance details
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: Row(
              children: [
                const Icon(Icons.wc, color: Colors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    data['name'] ?? "Toilet Details",
                    style: const TextStyle(fontWeight: FontWeight.bold),
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.list_alt, color: Colors.blue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Amenities: ${data['amenities']?.join(', ') ?? 'Not listed'}",
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  if (data['imageUrls'] != null &&
                      (data['imageUrls'] as List).isNotEmpty) ...[
                    const Text(
                      "Photos",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: data['imageUrls'].length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
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
                    const SizedBox(height: 15),
                  ],
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber),
                      const SizedBox(width: 10),
                      const Text(
                        "Rating:",
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 5),
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
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (reviews.isNotEmpty) ...[
                    const Divider(height: 25),
                    const Text(
                      "Recent Reviews",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...reviews
                        .map((review) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Colors.blue.shade100,
                                        child: const Icon(Icons.person,
                                            color: Colors.blue),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        review['user_name'] ?? 'Anonymous',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500),
                                      ),
                                      const Spacer(),
                                      RatingBarIndicator(
                                        rating: review['rating'] ?? 0.0,
                                        itemBuilder: (context, _) => const Icon(
                                          Icons.star,
                                          color: Colors.amber,
                                        ),
                                        itemCount: 5,
                                        itemSize: 16.0,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  if (review['comment'] != null &&
                                      review['comment'].isNotEmpty)
                                    Text(
                                      review['comment'],
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  if (review['image_url'] != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
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
                      child: const Text("View all reviews"),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Close",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.directions),
                label: const Text("Navigate"),
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
                icon: const Icon(Icons.rate_review),
                label: const Text("Review"),
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
        }
      },
    );
  }

  Future<void> _getDirections(LatLng destination) async {
    if (_userLocation == null) {
      return;
    }

    final String url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=${_userLocation!.latitude},${_userLocation!.longitude}&destination=${destination.latitude},${destination.longitude}&key=$_googleApiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData['status'] == 'OK') {
          final route = jsonData['routes'][0]['legs'][0];
          final steps = route['steps'];

          final List<LatLng> polylinePoints = [];
          for (var step in steps) {
            polylinePoints.add(LatLng(
                step['end_location']['lat'], step['end_location']['lng']));
          }

          setState(() {
            _polylines.clear();
            _polylines.add(Polyline(
              polylineId: const PolylineId('route'),
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
                  children: const [
                    Icon(Icons.directions, color: Colors.blue),
                    SizedBox(width: 10),
                    Text("Route Details"),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.straighten, color: Colors.blue),
                              const SizedBox(width: 10),
                              Text(
                                "Distance: ${route['distance']['text']}",
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.access_time, color: Colors.blue),
                              const SizedBox(width: 10),
                              Text(
                                "Estimated Time: ${route['duration']['text']}",
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
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
                    child: const Text(
                      "Close",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.map),
                    label: const Text("Open in Google Maps"),
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
      debugPrint("Error getting directions: $e");
    }
  }

  void _openGoogleMaps(double lat, double lng) async {
    final String url = 'https://www.google.com/maps?q=$lat,$lng&z=14';
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
      final QuerySnapshot snapshot = await toiletsCollection.get();
      final List<Map<String, dynamic>> nearbyToilets = [];

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('location') && data['location'] != null) {
          final double? toiletLat =
              (data['location']['latitude'] as num?)?.toDouble();
          final double? toiletLng =
              (data['location']['longitude'] as num?)?.toDouble();

          if (toiletLat != null && toiletLng != null) {
            final double distanceInKm = _calculateDistance(
                _userLocation!.latitude,
                _userLocation!.longitude,
                toiletLat,
                toiletLng);

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
      debugPrint("Error fetching nearby toilets with reviews: $e");
      return [];
    }
  }

  void _fetchFilteredToilets() {
    setState(() {
      _markers.clear();
      for (var toilet in allToilets) {
        final String toiletRating = toilet['rating'].toString();
        final List<String> toiletAmenities =
            List<String>.from(toilet['amenities']);

        final bool ratingMatches = (_selectedRating == "Any" ||
            double.parse(toiletRating) >= double.parse(_selectedRating[0]));
        final bool amenitiesMatch = _selectedAmenities
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
          _selectedIndex = 0;
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
        _selectedIndex = 0;
      });
    } else if (index == 3) {
      // Simplified profile navigation that works for all roles
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        // Get the current user's account status from Firestore
        bool isAccountActive = true; // default to true
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();

          if (userDoc.exists) {
            isAccountActive = userDoc['isAccountActive'] ?? true;
          }
        } catch (e) {
          debugPrint('Error fetching user status: $e');
        }

// In the _onItemTapped method for profile navigation
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfilePage(
              role: widget.loggedInUserRole,
              isAccountActive: isAccountActive,
              paymentStatus: widget.paymentStatus, // Pass payment status
            ),
          ),
        );
        setState(() {
          _selectedIndex = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text(
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
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: Stack(
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
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(30),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: (value) {
                      if (value.isNotEmpty) {
                        _searchPlaces(value);
                        _searchToilets(value);
                        setState(() {
                          _showCombinedList = true;
                        });
                      } else {
                        setState(() {
                          _placePredictions = [];
                          _searchResults = [];
                          _showCombinedList = false;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Search by name or location',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 15, horizontal: 16),
                      prefixIcon: const Icon(Icons.search, color: Colors.blue),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchResults = [];
                                  _placePredictions = [];
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
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 5,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        // Toilet Results Section
                        if (_searchResults.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Text(
                              'TOILETS',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ..._searchResults.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return ListTile(
                            leading: const Icon(Icons.wc, color: Colors.blue),
                            title: Text(data['name'] ?? 'Unnamed Toilet'),
                            subtitle: data['address'] != null
                                ? Text(data['address'])
                                : null,
                            onTap: () {
                              final lat = data['location']['latitude'];
                              final lng = data['location']['longitude'];
                              _mapController.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                    LatLng(lat, lng), 15),
                              );
                              setState(() {
                                _showCombinedList = false;
                                _searchController.text = data['name'] ?? '';
                              });
                            },
                          );
                        }).toList(),

                        // Location Results Section
                        if (_placePredictions.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Text(
                              'LOCATIONS',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ..._placePredictions.map((prediction) {
                          return ListTile(
                            leading: const Icon(Icons.location_on,
                                color: Colors.green),
                            title: Text(prediction.description ?? ''),
                            onTap: () {
                              _getPlaceDetails(prediction.placeId!);
                              setState(() {
                                _showCombinedList = false;
                              });
                            },
                          );
                        }).toList(),

                        // Recent Searches Section
                        if (_searchHistory.isNotEmpty &&
                            _searchResults.isEmpty &&
                            _placePredictions.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Text(
                              'RECENT SEARCHES',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ..._searchHistory
                            .where((history) =>
                                history['userId'] == _currentUserId)
                            .map((history) {
                          return ListTile(
                            leading:
                                const Icon(Icons.history, color: Colors.orange),
                            title: Text(history['name']),
                            subtitle: history['address'] != null
                                ? Text(history['address'])
                                : null,
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
              child: const Icon(Icons.my_location, color: Colors.blue),
              elevation: 4,
            ),
          ),
          if (_isSearching)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
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
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(25.0),
            topRight: Radius.circular(25.0),
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            selectedItemColor: Colors.blue,
            unselectedItemColor: Colors.grey,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            elevation: 8,
            items: const [
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
