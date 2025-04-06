import 'package:flutter/material.dart';

import 'home_page.dart';

class MyFacilitiesPage extends StatelessWidget {
  final String loggedInUserRole;

  MyFacilitiesPage({required this.loggedInUserRole});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("My Facilities"),
        actions: [
          IconButton(
            icon: Icon(Icons.home),
            onPressed: () {
              // Navigate to the HomePage
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => HomePage(loggedInUserRole: loggedInUserRole),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Text(
          "Welcome to My Facilities. Your role is $loggedInUserRole.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      ),
      floatingActionButton: loggedInUserRole == "owner"
          ? FloatingActionButton(
              onPressed: () {
                // Add logic to add a new facility
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text("Feature to add a new facility coming soon!")),
                );
              },
              child: Icon(Icons.add),
              tooltip: "Add Facility",
            )
          : null, // Only show the button if the user role is "owner"
    );
  }
}
