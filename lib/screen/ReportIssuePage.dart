import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ReportIssuePage extends StatefulWidget {
  @override
  _ReportIssuePageState createState() => _ReportIssuePageState();
}

class _ReportIssuePageState extends State<ReportIssuePage> {
  final TextEditingController _issueController = TextEditingController();

  Future<void> _submitReport() async {
    String issueText = _issueController.text.trim();
    if (issueText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please describe the issue")));
      return;
    }

    await FirebaseFirestore.instance.collection('washroom_reports').add({
      'issue': issueText,
      'timestamp': FieldValue.serverTimestamp(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Issue reported successfully!")));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report an Issue')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _issueController,
              decoration:
                  const InputDecoration(labelText: 'Describe the issue'),
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _submitReport,
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}
