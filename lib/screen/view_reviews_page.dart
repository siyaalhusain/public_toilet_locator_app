import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ViewReviewsPage extends StatefulWidget {
  @override
  _ViewReviewsPageState createState() => _ViewReviewsPageState();
}

class _ViewReviewsPageState extends State<ViewReviewsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Map<String, dynamic>>> _fetchNearbyToilets() async {
    QuerySnapshot snapshot = await _firestore.collection('toilets').get();
    return snapshot.docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('View Reviews')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchNearbyToilets(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No toilets found nearby.'));
          }
          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              var toilet = snapshot.data![index];
              return Card(
                margin: EdgeInsets.all(10),
                child: ListTile(
                  leading: toilet['photoUrl'] != null
                      ? Image.network(toilet['photoUrl'],
                          width: 50, height: 50, fit: BoxFit.cover)
                      : Icon(Icons.image, size: 50),
                  title: Text(toilet['name'] ?? 'Unknown Toilet'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Rating: ${toilet['rating'] ?? 'N/A'} ⭐"),
                      Text("${toilet['reviewsCount'] ?? 0} reviews"),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
