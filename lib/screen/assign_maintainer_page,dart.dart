import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AssignMaintainerPage extends StatefulWidget {
  @override
  _AssignMaintainerPageState createState() => _AssignMaintainerPageState();
}

class _AssignMaintainerPageState extends State<AssignMaintainerPage> {
  final TextEditingController _maintainerEmailController =
      TextEditingController();
  final TextEditingController _maintainerPasswordController =
      TextEditingController();
  final TextEditingController _toiletIdController = TextEditingController();

  void _assignMaintainer() async {
    final email = _maintainerEmailController.text.trim();
    final password = _maintainerPasswordController.text.trim();
    final toiletId = _toiletIdController.text.trim();

    if (email.isEmpty || password.isEmpty || toiletId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("All fields are required.")),
      );
      return;
    }

    try {
      // Save maintainer credentials and the assigned toilet in Firestore
      await FirebaseFirestore.instance.collection('maintainers').add({
        'email': email,
        'password': password,
        'toiletId': toiletId,
        'assignedBy':
            FirebaseAuth.instance.currentUser?.email ?? "Unknown Owner",
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Maintainer assigned successfully!")),
      );

      // Clear the fields after assigning
      _maintainerEmailController.clear();
      _maintainerPasswordController.clear();
      _toiletIdController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error assigning maintainer: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Assign Maintainer')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _maintainerEmailController,
              decoration: InputDecoration(labelText: "Maintainer Email"),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _maintainerPasswordController,
              obscureText: true,
              decoration: InputDecoration(labelText: "Password"),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _toiletIdController,
              decoration: InputDecoration(labelText: "Toilet ID"),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _assignMaintainer,
              child: Text('Assign Maintainer'),
            ),
          ],
        ),
      ),
    );
  }
}
