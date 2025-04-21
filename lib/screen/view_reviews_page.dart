import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math' as Math;
import 'AddCommentPage.dart';

class ViewReviewsPage extends StatefulWidget {
  @override
  _ViewReviewsPageState createState() => _ViewReviewsPageState();
}

class _ViewReviewsPageState extends State<ViewReviewsPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Position? _userPosition;
  List<Map<String, dynamic>> _nearbyToilets = [];
  List<Map<String, dynamic>> _recentlySearchedToilets = [];
  List<Map<String, dynamic>> _commentedToilets = [];
  bool _isLoading = true;
  bool _locationError = false;
  String _errorMessage = '';
  TextEditingController _searchHistoryController = TextEditingController();
  List<Map<String, dynamic>> _filteredSearchHistory = [];

  late TabController _tabController;
  final double _nearbyRadius = 10.0; // 10km radius

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _getUserLocation();
    _loadSearchHistory();
    _loadUserCommentedToilets();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchHistoryController.dispose();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = true;
          _errorMessage = 'Location services are disabled.';
          _isLoading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationError = true;
            _errorMessage = 'Location permission denied.';
            _isLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError = true;
          _errorMessage = 'Location permissions are permanently denied.';
          _isLoading = false;
        });
        return;
      }

      _userPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await _fetchNearbyToilets();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _locationError = true;
        _errorMessage = 'Could not get location: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSearchHistory() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String>? storedData = prefs.getStringList('search_history');

      if (storedData == null || storedData.isEmpty) return;

      List<Map<String, dynamic>> searchHistory = storedData
          .map((item) => json.decode(item) as Map<String, dynamic>)
          .toList();

      List<Map<String, dynamic>> toilets = [];

      for (var item in searchHistory) {
        try {
          DocumentSnapshot toiletDoc =
          await _firestore.collection('toilets').doc(item['id']).get();

          if (toiletDoc.exists) {
            var data = toiletDoc.data() as Map<String, dynamic>;
            toilets.add({
              'id': toiletDoc.id,
              'name': data['name'] ?? 'Unknown Toilet',
              'address': data['address'] ?? 'No address',
              'average_rating': data['average_rating'] ?? 0.0,
              'reviewsCount': data['reviewsCount'] ?? 0,
              'searchTimestamp': DateTime.now().millisecondsSinceEpoch,
              'photoUrl': data['photoUrl'],
            });
          }
        } catch (e) {
          print('Error loading toilet details: $e');
        }
      }

      setState(() {
        _recentlySearchedToilets = toilets;
        _filteredSearchHistory = toilets;
      });
    } catch (e) {
      print('Error loading search history: $e');
    }
  }

  Future<void> _loadUserCommentedToilets() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      QuerySnapshot reviewsSnapshot = await _firestore
          .collection('washroom_reviews')
          .where('user_id', isEqualTo: currentUser.uid)
          .orderBy('timestamp', descending: true)
          .get();

      Set<String> seenToiletIds = {};
      List<Map<String, dynamic>> commentedToilets = [];

      for (var doc in reviewsSnapshot.docs) {
        var reviewData = doc.data() as Map<String, dynamic>;
        String toiletId = reviewData['toilet_id'];

        if (seenToiletIds.contains(toiletId)) continue;
        seenToiletIds.add(toiletId);

        try {
          DocumentSnapshot toiletDoc =
          await _firestore.collection('toilets').doc(toiletId).get();

          if (toiletDoc.exists) {
            var toiletData = toiletDoc.data() as Map<String, dynamic>;
            commentedToilets.add({
              'id': toiletId,
              'name': toiletData['name'] ??
                  reviewData['toilet_name'] ??
                  'Unknown Toilet',
              'address': toiletData['address'] ?? 'No address',
              'average_rating':
              toiletData['average_rating'] ?? reviewData['rating'] ?? 0.0,
              'reviewsCount': toiletData['reviewsCount'] ?? 1,
              'lastCommentDate': reviewData['timestamp'] != null
                  ? (reviewData['timestamp'] as Timestamp).toDate()
                  : null,
              'photoUrl': toiletData['photoUrl'],
              'userRating': reviewData['rating'] ?? 0.0,
            });
          }
        } catch (e) {
          print('Error loading commented toilet: $e');
        }
      }

      setState(() {
        _commentedToilets = commentedToilets;
      });
    } catch (e) {
      print('Error loading user commented toilets: $e');
    }
  }

  Future<void> _fetchNearbyToilets() async {
    if (_userPosition == null) return;

    try {
      QuerySnapshot snapshot = await _firestore.collection('toilets').get();
      List<Map<String, dynamic>> toilets = [];

      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('location') && data['location'] != null) {
          double? toiletLat =
          (data['location']['latitude'] as num?)?.toDouble();
          double? toiletLng =
          (data['location']['longitude'] as num?)?.toDouble();

          if (toiletLat != null && toiletLng != null) {
            double distanceInKm = _calculateDistance(_userPosition!.latitude,
                _userPosition!.longitude, toiletLat, toiletLng);

            if (distanceInKm <= _nearbyRadius) {
              toilets.add({
                'id': doc.id,
                'name': data['name'] ?? 'Unnamed Toilet',
                'address': data['address'] ?? 'No address',
                'distance': distanceInKm,
                'average_rating': data['average_rating'] ?? 0.0,
                'reviewsCount': data['reviewsCount'] ?? 0,
                'photoUrl': data['photoUrl'],
              });
            }
          }
        }
      }

      toilets.sort((a, b) => (a['distance']).compareTo(b['distance']));

      setState(() {
        _nearbyToilets = toilets;
      });
    } catch (e) {
      print('Error fetching nearby toilets: $e');
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295;
    double a = 0.5 -
        Math.cos((lat2 - lat1) * p) / 2 +
        Math.cos(lat1 * p) *
            Math.cos(lat2 * p) *
            (1 - Math.cos((lon2 - lon1) * p)) /
            2;
    return 12742 * Math.asin(Math.sqrt(a));
  }

  void _navigateToAddComment(String toiletId, String toiletName) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddCommentPage(
          toiletId: toiletId,
          toiletName: toiletName,
        ),
      ),
    );

    if (result == true) {
      setState(() {
        _isLoading = true;
      });
      await _loadUserCommentedToilets();
      await _fetchNearbyToilets();
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterSearchHistory(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredSearchHistory = _recentlySearchedToilets;
      });
      return;
    }

    setState(() {
      _filteredSearchHistory = _recentlySearchedToilets
          .where((toilet) => toilet['name']
          .toString()
          .toLowerCase()
          .contains(query.toLowerCase()))
          .toList();
    });
  }

  Widget _buildToiletItem(Map<String, dynamic> toilet,
      {bool showDistance = false}) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: toilet['photoUrl'] != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      toilet['photoUrl'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Icon(Icons.wc, size: 40, color: Colors.blue),
                    ),
                  )
                      : Icon(Icons.wc, size: 40, color: Colors.blue),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        toilet['name'],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      if (toilet['address'] != null &&
                          toilet['address'] != 'No address')
                        Text(
                          toilet['address'],
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.star, color: Colors.amber, size: 18),
                          SizedBox(width: 4),
                          Text(
                            "${toilet['average_rating']?.toStringAsFixed(1) ?? '0.0'}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            "(${toilet['reviewsCount'] ?? 0} reviews)",
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      if (showDistance && toilet['distance'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.location_on,
                                  color: Colors.green, size: 18),
                              SizedBox(width: 4),
                              Text(
                                "${toilet['distance'].toStringAsFixed(1)} km away",
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _navigateToAddComment(toilet['id'], toilet['name']),
                icon: Icon(Icons.rate_review, size: 18),
                label: Text(toilet['userRating'] != null
                    ? "Update Review"
                    : "Add Review"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Toilets & Reviews'),
        elevation: 0,
        backgroundColor: Colors.blue,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: [
            Tab(icon: Icon(Icons.location_on), text: "Nearby"),
            Tab(icon: Icon(Icons.history), text: "Searched"),
            Tab(icon: Icon(Icons.rate_review), text: "Reviewed"),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          // Nearby Toilets Tab
          _locationError
              ? Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off,
                      size: 70, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "Location Error",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _errorMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                        _locationError = false;
                      });
                      _getUserLocation();
                    },
                    icon: Icon(Icons.refresh),
                    label: Text("Retry"),
                  ),
                ],
              ),
            ),
          )
              : _nearbyToilets.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off,
                    size: 70, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  "No Toilets Nearby",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "We couldn't find any toilets within ${_nearbyRadius.toInt()} km of your location.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          )
              : ListView.builder(
            itemCount: _nearbyToilets.length,
            itemBuilder: (context, index) {
              return _buildToiletItem(_nearbyToilets[index],
                  showDistance: true);
            },
          ),

          // Recently Searched Toilets Tab with Search
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: _searchHistoryController,
                  onChanged: _filterSearchHistory,
                  decoration: InputDecoration(
                    hintText: "Search your history...",
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                  ),
                ),
              ),
              Expanded(
                child: _filteredSearchHistory.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off,
                          size: 70, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        _searchHistoryController.text.isEmpty
                            ? "No Search History"
                            : "No Results Found",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        _searchHistoryController.text.isEmpty
                            ? "Toilets you search for will appear here."
                            : "No toilets match your search.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
                    : ListView.builder(
                  itemCount: _filteredSearchHistory.length,
                  itemBuilder: (context, index) {
                    return _buildToiletItem(
                        _filteredSearchHistory[index]);
                  },
                ),
              ),
            ],
          ),

          // User's Commented Toilets Tab
          _commentedToilets.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.rate_review,
                    size: 70, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  "No Reviews Yet",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Toilets you've reviewed will appear here.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          )
              : ListView.builder(
            itemCount: _commentedToilets.length,
            itemBuilder: (context, index) {
              var toilet = _commentedToilets[index];
              return _buildToiletItem(toilet);
            },
          ),
        ],
      ),
    );
  }
}
