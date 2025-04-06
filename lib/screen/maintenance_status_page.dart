import 'package:flutter/material.dart';

import 'home_page.dart';

class MaintenanceStatusPage extends StatelessWidget {
  final String loggedInUserRole;

  MaintenanceStatusPage({required this.loggedInUserRole});

  // Example data (you can replace this with dynamic data from your database)
  final List<Map<String, String>> maintenanceTasks = [
    {
      'facility': 'Toilet 1',
      'status': 'Pending',
      'scheduledDate': '2025-01-22',
    },
    {
      'facility': 'Toilet 2',
      'status': 'Completed',
      'scheduledDate': '2025-01-18',
    },
    {
      'facility': 'Toilet 3',
      'status': 'In Progress',
      'scheduledDate': '2025-01-20',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Maintenance Status"),
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
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListView.builder(
          itemCount: maintenanceTasks.length,
          itemBuilder: (context, index) {
            final task = maintenanceTasks[index];
            return Card(
              elevation: 4,
              margin: const EdgeInsets.symmetric(vertical: 8.0),
              child: ListTile(
                title: Text(task['facility']!),
                subtitle: Text("Scheduled: ${task['scheduledDate']}"),
                trailing: Text(
                  task['status']!,
                  style: TextStyle(
                    color: task['status'] == 'Completed'
                        ? Colors.green
                        : task['status'] == 'Pending'
                            ? Colors.red
                            : Colors.orange,
                  ),
                ),
                onTap: () {
                  // Implement functionality for when the user taps a task
                  // E.g., show task details or edit options
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Tapped on ${task['facility']}")),
                  );
                },
              ),
            );
          },
        ),
      ),
      floatingActionButton: loggedInUserRole == "maintainer"
          ? FloatingActionButton(
              onPressed: () {
                // Add logic to add a new maintenance task or update the status
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          "Feature to add a new maintenance task coming soon!")),
                );
              },
              child: Icon(Icons.add),
              tooltip: "Add Maintenance Task",
            )
          : null, // Only show the button if the user role is "maintainer"
    );
  }
}
