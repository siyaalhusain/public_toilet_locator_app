import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'AddCommentPage.dart';
import 'view_reviews_page.dart';

class NearbyToiletsPage extends StatefulWidget {
  final gmaps.LatLng? userLocation;

  const NearbyToiletsPage({Key? key, required this.userLocation})
      : super(key: key);

  @override
  _NearbyToiletsPageState createState() => _NearbyToiletsPageState();
}

class _NearbyToiletsPageState extends State<NearbyToiletsPage> {
  final CollectionReference toiletsCollection =
      FirebaseFirestore.instance.collection('toilets');

  String _formatReviewDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showToiletDetailsSheet(
      BuildContext context, Map<String, dynamic> toilet) async {
    // Try to fetch maintenance status
    DocumentSnapshot? maintenanceSnapshot;
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('maintenanceRecords')
          .where('toiletId', isEqualTo: toilet['id'])
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
            .doc(toilet['id'])
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          initialChildSize: maintenanceSnapshot != null ? 0.8 : 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    margin: EdgeInsets.only(top: 10, bottom: 8),
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 16, right: 16, bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wc, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          toilet['name'] ?? "Toilet Details",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Maintenance Status
                            if (maintenanceSnapshot != null &&
                                maintenanceSnapshot.exists)
                              Container(
                                margin: EdgeInsets.only(bottom: 15),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: (maintenanceSnapshot['status'] ==
                                                    'Operational'
                                                ? Colors.green
                                                : Colors.red)
                                            .withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color:
                                              maintenanceSnapshot['status'] ==
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
                                            color:
                                                maintenanceSnapshot['status'] ==
                                                        'Operational'
                                                    ? Colors.green
                                                    : Colors.red,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            maintenanceSnapshot['status'] ??
                                                'Unknown Status',
                                            style: TextStyle(
                                              color: maintenanceSnapshot[
                                                          'status'] ==
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
                                    if (maintenanceSnapshot['lastUpdated'] !=
                                        null)
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.calendar_today,
                                                size: 14,
                                                color: Colors.grey[700]),
                                            SizedBox(width: 4),
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

                            // Operating Hours
                            if (hasOperatingInfo)
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
                                        Icon(Icons.access_time,
                                            color: Colors.blue),
                                        SizedBox(width: 10),
                                        Text(
                                          is24Hours
                                              ? "Open 24 Hours"
                                              : "Open: $openingTime - $closingTime",
                                          style: TextStyle(fontSize: 14),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8),
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

                            // Features
                            if (hasOperatingInfo && features.isNotEmpty)
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
                                        Icon(Icons.list_alt,
                                            color: Colors.blue),
                                        SizedBox(width: 10),
                                        Text(
                                          "Features:",
                                          style: TextStyle(fontSize: 14),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: features.entries
                                          .where((entry) => entry.value == true)
                                          .map((entry) => Chip(
                                                label: Text(entry.key),
                                                backgroundColor: Colors.blue
                                                    .withOpacity(0.2),
                                                labelStyle: TextStyle(
                                                    color: Colors.blue),
                                              ))
                                          .toList(),
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
                                      "Amenities: ${toilet['amenities']?.join(', ') ?? 'Not listed'}",
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 15),
                            if (toilet['photoUrl'] != null) ...[
                              Text(
                                "Photo",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  toilet['photoUrl'],
                                  width: double.infinity,
                                  height: 200,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                    height: 200,
                                    color: Colors.grey[200],
                                    child: Center(
                                      child: Icon(Icons.broken_image,
                                          color: Colors.grey),
                                    ),
                                  ),
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
                                  rating: toilet['average_rating'] ?? 0.0,
                                  itemBuilder: (context, _) =>
                                      Icon(Icons.star, color: Colors.amber),
                                  itemCount: 5,
                                  itemSize: 20.0,
                                ),
                                Text(
                                  " (${toilet['average_rating']?.toStringAsFixed(1) ?? '0.0'})",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: 15),
                            Row(
                              children: [
                                Icon(Icons.location_on, color: Colors.green),
                                SizedBox(width: 10),
                                Text(
                                  "Distance: ${toilet['distance']?.toStringAsFixed(1) ?? '?'} km away",
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            SizedBox(height: 15),
                            Divider(height: 25),
                            Text(
                              "Recent Reviews",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 8),
                            FutureBuilder<QuerySnapshot>(
                              future: FirebaseFirestore.instance
                                  .collection('washroom_reviews')
                                  .where('toilet_id', isEqualTo: toilet['id'])
                                  .orderBy('timestamp', descending: true)
                                  .limit(3)
                                  .get(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return Center(
                                      child: CircularProgressIndicator());
                                }
                                if (!snapshot.hasData ||
                                    snapshot.data!.docs.isEmpty) {
                                  return Text("No reviews yet.");
                                }
                                return Column(
                                  children: snapshot.data!.docs.map((doc) {
                                    var review =
                                        doc.data() as Map<String, dynamic>;
                                    return Container(
                                      margin: EdgeInsets.only(bottom: 16),
                                      padding: EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[50],
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 16,
                                                backgroundColor:
                                                    Colors.blue.shade100,
                                                backgroundImage:
                                                    review['user_photo_url'] !=
                                                            null
                                                        ? NetworkImage(review[
                                                            'user_photo_url'])
                                                        : null,
                                                child:
                                                    review['user_photo_url'] ==
                                                            null
                                                        ? Icon(Icons.person,
                                                            size: 16,
                                                            color: Colors.blue)
                                                        : null,
                                              ),
                                              SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  review['user_name'] ??
                                                      'Anonymous User',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                              RatingBarIndicator(
                                                rating: review['rating'] ?? 0.0,
                                                itemBuilder: (context, _) =>
                                                    Icon(Icons.star,
                                                        color: Colors.amber),
                                                itemCount: 5,
                                                itemSize: 16.0,
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 8),
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
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.network(
                                                  review['image_url'],
                                                  height: 100,
                                                  width: double.infinity,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                          stackTrace) =>
                                                      Container(
                                                    height: 100,
                                                    color: Colors.grey[200],
                                                    child: Center(
                                                      child: Icon(
                                                          Icons.broken_image,
                                                          color: Colors.grey),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          SizedBox(height: 8),
                                          Text(
                                            _formatReviewDate(
                                                review['timestamp']),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                            SizedBox(height: 20),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ViewReviewsPage(
                                      toiletId: toilet['id'],
                                    ),
                                  ),
                                );
                              },
                              child: Text("View all reviews"),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AddCommentPage(
                                    toiletId: toilet['id'],
                                    toiletName: toilet['name'],
                                  ),
                                ),
                              );
                            },
                            icon: Icon(Icons.rate_review),
                            label: Text("Add Review"),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.green,
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              // Add navigation functionality here
                            },
                            icon: Icon(Icons.directions),
                            label: Text("Navigate"),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.blue,
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.star, color: Colors.amber, size: 20),
            SizedBox(width: 8),
            Text(
              "Nearby Toilets",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.blue),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _getNearbyToiletsWithReviews(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wc, size: 40, color: Colors.grey),
                  SizedBox(height: 10),
                  Text(
                    "No nearby toilets found",
                    style: TextStyle(color: Colors.grey[600]),
                  )
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.only(bottom: 20),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              var toilet = snapshot.data![index];
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.all(12),
                    leading: Container(
                      width: 60,
                      height: 60,
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
                                    Icon(Icons.wc, color: Colors.blue),
                              ),
                            )
                          : Icon(Icons.wc, color: Colors.blue),
                    ),
                    title: Text(
                      toilet['name'] ?? 'Unnamed Toilet',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.star, color: Colors.amber, size: 16),
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
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on,
                                color: Colors.green, size: 16),
                            SizedBox(width: 4),
                            Text(
                              "${toilet['distance']?.toStringAsFixed(1) ?? '?'} km away",
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 120),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AddCommentPage(
                                    toiletId: toilet['id'],
                                    toiletName: toilet['name'],
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.green,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              minimumSize: Size(0, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Icon(Icons.add_comment, size: 18),
                          ),
                          SizedBox(width: 4),
                          ElevatedButton(
                            onPressed: () {
                              _showToiletDetailsSheet(context, toilet);
                            },
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.blue,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              minimumSize: Size(0, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child:
                                Text("Details", style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getNearbyToiletsWithReviews() async {
    if (widget.userLocation == null) return [];

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
            double distanceInKm = _calculateDistance(
                widget.userLocation!.latitude,
                widget.userLocation!.longitude,
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
}
