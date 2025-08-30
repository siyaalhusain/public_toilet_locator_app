import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:math' as Math;
import 'AddCommentPage.dart';
//COMMENTS
class _ToiletDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> toiletData;
//view page
  const _ToiletDetailsDialog({required this.toiletData});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot?>(
      future: _fetchMaintenanceStatus(toiletData['id']),
      builder: (context, snapshot) {
        bool hasMaintenance = snapshot.hasData && snapshot.data!.exists;
        Map<String, dynamic>? maintenanceData = hasMaintenance
            ? snapshot.data!.data() as Map<String, dynamic>
            : null;

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Row(
            children: [
              Icon(Icons.wc, color: Colors.blue),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  toiletData['name'] ?? "Toilet Details",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Maintenance Status
                  if (hasMaintenance)
                    Container(
                      margin: EdgeInsets.only(bottom: 15),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color:
                                    (maintenanceData!['status'] == 'Operational'
                                            ? Colors.green
                                            : Colors.red)
                                        .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color:
                                      maintenanceData['status'] == 'Operational'
                                          ? Colors.green
                                          : Colors.red,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    maintenanceData['status'] == 'Operational'
                                        ? Icons.check_circle
                                        : Icons.error,
                                    size: 16,
                                    color: maintenanceData['status'] ==
                                            'Operational'
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    maintenanceData['status'] ??
                                        'Unknown Status',
                                    style: TextStyle(
                                      color: maintenanceData['status'] ==
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
                            SizedBox(width: 8),
                            if (maintenanceData['lastUpdated'] != null)
                              Container(
                                padding: EdgeInsets.symmetric(
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
                                    SizedBox(width: 4),
                                    Text(
                                      'Last: ${DateFormat('MMM d, yyyy').format((maintenanceData['lastUpdated'] as Timestamp).toDate())}',
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
                    ),

                  // Operating Hours (if available)
                  if (toiletData['is24Hours'] != null ||
                      toiletData['openingTime'] != null)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12),
                      margin: EdgeInsets.only(bottom: 15),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.access_time, color: Colors.blue),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  toiletData['is24Hours'] == true
                                      ? "Open 24 Hours"
                                      : "Open: ${toiletData['openingTime'] ?? '06:00'} - ${toiletData['closingTime'] ?? '22:00'}",
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                          if (toiletData['operatingDays'] != null) ...[
                            SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Wrap(
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
                                  bool isOpen = toiletData['operatingDays']
                                          [index] ??
                                      true;
                                  return Chip(
                                    label: Text(days[index]),
                                    backgroundColor: isOpen
                                        ? Colors.green.withOpacity(0.2)
                                        : Colors.grey.withOpacity(0.2),
                                    labelStyle: TextStyle(
                                      color:
                                          isOpen ? Colors.green : Colors.grey,
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                  // Features (if available)
                  if (toiletData['features'] != null &&
                      toiletData['features'].isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12),
                      margin: EdgeInsets.only(bottom: 15),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.list_alt, color: Colors.blue),
                              SizedBox(width: 10),
                              Text(
                                "Features:",
                                style: TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: (toiletData['features']
                                      as Map<String, dynamic>)
                                  .entries
                                  .where((entry) => entry.value == true)
                                  .map((entry) => Chip(
                                        label: Text(entry.key),
                                        backgroundColor:
                                            Colors.blue.withOpacity(0.2),
                                        labelStyle:
                                            TextStyle(color: Colors.blue),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Original content
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
                            "Amenities: ${toiletData['amenities']?.join(', ') ?? 'Not listed'}",
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 15),

                  // Photos section
                  if (toiletData['imageUrls'] != null &&
                      (toiletData['imageUrls'] as List).isNotEmpty) ...[
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
                        itemCount: toiletData['imageUrls'].length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                toiletData['imageUrls'][index],
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

                  // Rating section
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
                        rating: toiletData['average_rating'] ?? 0.0,
                        itemBuilder: (context, _) =>
                            Icon(Icons.star, color: Colors.amber),
                        itemCount: 5,
                        itemSize: 20.0,
                      ),
                      SizedBox(width: 5),
                      Text(
                        "(${toiletData['average_rating']?.toStringAsFixed(1) ?? '0.0'})",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Divider(height: 25),

                  // Reviews section
                  FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('washroom_reviews')
                        .where('toilet_id', isEqualTo: toiletData['id'])
                        .orderBy('timestamp', descending: true)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Text("No reviews yet.");
                      }
                      return Column(
                        children: snapshot.data!.docs.map((doc) {
                          var review = doc.data() as Map<String, dynamic>;
                          return Padding(
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
                                    Expanded(
                                      child: Text(
                                        review['user_name'] ?? 'Anonymous',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    RatingBarIndicator(
                                      rating: review['rating'] ?? 0.0,
                                      itemBuilder: (context, _) =>
                                          Icon(Icons.star, color: Colors.amber),
                                      itemCount: 5,
                                      itemSize: 16.0,
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                if (review['comment'] != null &&
                                    review['comment'].toString().isNotEmpty)
                                  Text(review['comment'],
                                      style: TextStyle(fontSize: 14)),
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
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AddCommentPage(
                      toiletId: toiletData['id'],
                      toiletName: toiletData['name'],
                    ),
                  ),
                );
              },
              child: Text("Add Review"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<DocumentSnapshot?> _fetchMaintenanceStatus(
      String toiletId) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('maintenanceRecords')
          .where('toiletId', isEqualTo: toiletId)
          .limit(1)
          .get();
      return querySnapshot.docs.isNotEmpty ? querySnapshot.docs.first : null;
    } catch (e) {
      debugPrint('Error fetching maintenance status: $e');
      return null;
    }
  }
}

// Rest of the file remains the same...
// [Keep all the existing code from _ViewReviewsPageState class onwards]
class ViewReviewsPage extends StatefulWidget {
  final String toiletId;

  const ViewReviewsPage({Key? key, required this.toiletId}) : super(key: key);

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
  final double _nearbyRadius = 10.0;

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
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String>? storedData =
          prefs.getStringList('search_history_${currentUser.uid}');

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
              'searchTimestamp': item['searchTimestamp'] ??
                  DateTime.now().millisecondsSinceEpoch,
              'photoUrl':
                  data['imageUrls'] != null && data['imageUrls'].isNotEmpty
                      ? data['imageUrls'][0]
                      : null,
              'amenities': data['amenities'] ?? [],
            });
          }
        } catch (e) {
          print('Error loading toilet details: $e');
        }
      }

      toilets.sort((a, b) =>
          (b['searchTimestamp'] as int).compareTo(a['searchTimestamp'] as int));

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
              'average_rating': toiletData['average_rating'] ?? 0.0,
              'reviewsCount': toiletData['reviewsCount'] ?? 1,
              'lastCommentDate': reviewData['timestamp'] != null
                  ? (reviewData['timestamp'] as Timestamp).toDate()
                  : null,
              'photoUrl': toiletData['imageUrls'] != null &&
                      toiletData['imageUrls'].isNotEmpty
                  ? toiletData['imageUrls'][0]
                  : null,
              'userRating': reviewData['rating'] ?? 0.0,
              'comment': reviewData['comment'] ?? '',
              'review_id': doc.id,
              'category_ratings': reviewData['category_ratings'] ?? {},
              'image_url': reviewData['image_url'],
              'amenities': toiletData['amenities'] ?? [],
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
                'photoUrl':
                    data['imageUrls'] != null && data['imageUrls'].isNotEmpty
                        ? data['imageUrls'][0]
                        : null,
                'amenities': data['amenities'] ?? [],
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

  Future<void> _addToSearchHistory(String toiletId, String toiletName) async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> storedData =
          prefs.getStringList('search_history_${currentUser.uid}') ?? [];

      Map<String, dynamic> searchItem = {
        'id': toiletId,
        'name': toiletName,
        'searchTimestamp': DateTime.now().millisecondsSinceEpoch,
      };

      List<Map<String, dynamic>> existingHistory = storedData
          .map((item) => json.decode(item) as Map<String, dynamic>)
          .toList();

      existingHistory.removeWhere((item) => item['id'] == toiletId);
      existingHistory.add(searchItem);

      List<String> updatedData =
          existingHistory.map((item) => json.encode(item)).toList();

      await prefs.setStringList(
          'search_history_${currentUser.uid}', updatedData);
      await _loadSearchHistory();
    } catch (e) {
      print('Error adding to search history: $e');
    }
  }

  void _navigateToAddComment(String toiletId, String toiletName) async {
    await _addToSearchHistory(toiletId, toiletName);

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
      await _loadSearchHistory();
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showToiletDetails(Map<String, dynamic> toilet) async {
    await _addToSearchHistory(toilet['id'], toilet['name']);

    try {
      DocumentSnapshot toiletDoc =
          await _firestore.collection('toilets').doc(toilet['id']).get();

      if (toiletDoc.exists) {
        var fullToiletData = {
          ...toiletDoc.data() as Map<String, dynamic>,
          'id': toilet['id'],
        };

        showDialog(
          context: context,
          builder: (context) => _ToiletDetailsDialog(
            toiletData: fullToiletData,
          ),
        );
      }
    } catch (e) {
      print('Error loading toilet details: $e');
      showDialog(
        context: context,
        builder: (context) => _ToiletDetailsDialog(
          toiletData: toilet,
        ),
      );
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
      {bool showDistance = false, bool showUserReview = false}) {
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
                      if (toilet['lastCommentDate'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today,
                                  color: Colors.orange, size: 16),
                              SizedBox(width: 4),
                              Text(
                                "Reviewed on ${_formatDate(toilet['lastCommentDate'])}",
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (toilet['searchTimestamp'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.history,
                                  color: Colors.purple, size: 16),
                              SizedBox(width: 4),
                              Text(
                                "Searched on ${_formatTimeFromTimestamp(toilet['searchTimestamp'])}",
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
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
            if (showUserReview && toilet['userRating'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          "Your Rating:",
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(width: 8),
                        Row(
                          children: List.generate(5, (index) {
                            return Icon(
                              index < toilet['userRating'].floor()
                                  ? Icons.star
                                  : index < toilet['userRating']
                                      ? Icons.star_half
                                      : Icons.star_border,
                              color: Colors.amber,
                              size: 18,
                            );
                          }),
                        ),
                        SizedBox(width: 4),
                        Text(
                          "(${toilet['userRating'].toStringAsFixed(1)})",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (toilet['comment'] != null &&
                        toilet['comment'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          toilet['comment'],
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[800],
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showToiletDetails(toilet),
                    icon: Icon(Icons.info_outline, size: 18),
                    label: Text("Details"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        _navigateToAddComment(toilet['id'], toilet['name']),
                    icon: Icon(Icons.rate_review, size: 18),
                    label: Text(
                        toilet['userRating'] != null ? "Update" : "Review"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
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
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year}";
  }

  String _formatTimeFromTimestamp(int timestamp) {
    DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return "${date.day}/${date.month}/${date.year}";
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
                        : RefreshIndicator(
                            onRefresh: () async {
                              setState(() {
                                _isLoading = true;
                              });
                              await _getUserLocation();
                            },
                            child: ListView.builder(
                              itemCount: _nearbyToilets.length,
                              itemBuilder: (context, index) {
                                return _buildToiletItem(_nearbyToilets[index],
                                    showDistance: true);
                              },
                            ),
                          ),
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
                          : RefreshIndicator(
                              onRefresh: () async {
                                await _loadSearchHistory();
                              },
                              child: ListView.builder(
                                itemCount: _filteredSearchHistory.length,
                                itemBuilder: (context, index) {
                                  return _buildToiletItem(
                                      _filteredSearchHistory[index]);
                                },
                              ),
                            ),
                    ),
                  ],
                ),
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
                    : RefreshIndicator(
                        onRefresh: () async {
                          await _loadUserCommentedToilets();
                        },
                        child: ListView.builder(
                          itemCount: _commentedToilets.length,
                          itemBuilder: (context, index) {
                            var toilet = _commentedToilets[index];
                            return _buildToiletItem(toilet,
                                showUserReview: true);
                          },
                        ),
                      ),
              ],
            ),
    );
  }
}
