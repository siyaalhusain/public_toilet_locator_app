import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'MapSelectionPage.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:photo_view/photo_view.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ExplorePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Explore')),
      body: const Center(child: Text('Explore Page')),
    );
  }
}
