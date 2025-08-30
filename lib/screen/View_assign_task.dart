import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
//VIEWTASK
class ViewAssignedTasksPage extends StatefulWidget {
  const ViewAssignedTasksPage({Key? key}) : super(key: key);

  @override
  _ViewAssignedTasksPageState createState() => _ViewAssignedTasksPageState();
}

class _ViewAssignedTasksPageState extends State<ViewAssignedTasksPage> {
  final CollectionReference tasksCollection =
      FirebaseFirestore.instance.collection('maintenanceTasks');
  String? _currentMaintainerId;
  String _filterStatus = 'All';
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  String _indexErrorUrl = '';

  @override
  void initState() {
    super.initState();
    _getCurrentMaintainerId();
  }

  Future<void> _getCurrentMaintainerId() async {
    setState(() {
      _isLoading = true;
    });

    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        setState(() {
          _currentMaintainerId = currentUser.uid;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'User not authenticated';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Authentication error: $e';
      });
    }
  }

  // Use a safer query approach that requires fewer indexes
  Stream<QuerySnapshot> getTasksStream() {
    if (_currentMaintainerId == null) {
      return const Stream.empty();
    }

    try {
      // Default query - just show by maintainer ID
      var query = tasksCollection.where('maintainerId',
          isEqualTo: _currentMaintainerId);

      // Only add additional filter if not "All"
      if (_filterStatus != 'All') {
        query = query.where('status', isEqualTo: _filterStatus);
      }

      // We'll handle the sorting in-memory instead of in the query
      // This avoids the need for composite indexes
      return query.snapshots();
    } catch (e) {
      print('Error creating query: $e');
      return const Stream.empty();
    }
  }

  // Sort the tasks in-memory instead of in Firestore
  List<DocumentSnapshot> sortTasksByDueDate(List<DocumentSnapshot> tasks) {
    return List.from(tasks)
      ..sort((a, b) {
        final dataA = a.data() as Map<String, dynamic>;
        final dataB = b.data() as Map<String, dynamic>;

        final dueDateA = dataA['dueDate'] as Timestamp?;
        final dueDateB = dataB['dueDate'] as Timestamp?;

        if (dueDateA == null && dueDateB == null) return 0;
        if (dueDateA == null) return 1;
        if (dueDateB == null) return -1;

        return dueDateA.compareTo(dueDateB);
      });
  }

  Future<void> _updateTaskStatus(String taskId, String newStatus) async {
    try {
      await tasksCollection.doc(taskId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task marked as $newStatus'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update task: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleIndexError(String errorMessage) async {
    final urlMatch =
        RegExp(r'https://console\.firebase\.google\.com/.*?(?=\s|$)')
            .firstMatch(errorMessage);

    if (urlMatch != null) {
      final indexUrl = urlMatch.group(0) ?? '';

      try {
        final Uri url = Uri.parse(indexUrl);
        final canLaunch = await canLaunchUrl(url);

        if (canLaunch) {
          await launchUrl(url, mode: LaunchMode.externalApplication);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Opening Firebase Console. Create the index and then restart the app.'),
              duration: Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please visit Firebase Console: $indexUrl'),
              duration: Duration(seconds: 10),
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Cannot open browser: $e. Please visit Firebase Console manually.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Widget _buildTaskItem(DocumentSnapshot task) {
    final data = task.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'No Title';
    final description = data['description'] ?? 'No Description';
    final status = data['status'] ?? 'Unknown';
    final priority = data['priority'] ?? 'Medium';
    final dueDate = data['dueDate'] as Timestamp?;
    final toiletName = data['toiletName'] ?? 'Unknown Toilet';

    Color statusColor;
    switch (status) {
      case 'Completed':
        statusColor = Colors.green;
        break;
      case 'In Progress':
        statusColor = Colors.blue;
        break;
      case 'Overdue':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.orange;
    }

    Color priorityColor;
    switch (priority) {
      case 'High':
        priorityColor = Colors.red;
        break;
      case 'Urgent':
        priorityColor = Colors.deepOrange;
        break;
      case 'Medium':
        priorityColor = Colors.orange;
        break;
      default:
        priorityColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.bathroom, size: 16, color: Colors.blue),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    toiletName,
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.priority_high, size: 16, color: priorityColor),
                const SizedBox(width: 4),
                Text(
                  'Priority: $priority',
                  style: TextStyle(
                    fontSize: 14,
                    color: priorityColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.purple),
                const SizedBox(width: 4),
                Text(
                  dueDate == null
                      ? 'No due date'
                      : 'Due: ${DateFormat('dd/MM/yyyy').format(dueDate.toDate())}',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (status != 'Completed')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Update Task Status'),
                        content: const Text(
                            'Are you sure you want to mark this task as completed?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              _updateTaskStatus(task.id, 'Completed');
                              Navigator.pop(context);
                            },
                            child: const Text('Complete'),
                          ),
                        ],
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: const Text('Mark as Completed'),
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
        title: const Text('My Assigned Tasks'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _filterStatus = value;
                _hasError = false; // Reset error state when filter changes
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'All',
                child: Text('All Tasks'),
              ),
              const PopupMenuItem(
                value: 'Assigned',
                child: Text('Assigned'),
              ),
              const PopupMenuItem(
                value: 'In Progress',
                child: Text('In Progress'),
              ),
              const PopupMenuItem(
                value: 'Completed',
                child: Text('Completed'),
              ),
              const PopupMenuItem(
                value: 'Overdue',
                child: Text('Overdue'),
              ),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: getTasksStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  // If it's a Firestore index error, provide a way to fix it
                  final errorMessage = snapshot.error.toString();
                  if (errorMessage.contains('firebase/failed-precondition') &&
                      errorMessage.contains('requires an index')) {
                    // Don't show the error, just create a fallback query
                    // Silently try to handle the index error
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _handleIndexError(errorMessage);
                    });

                    // Show a loading indicator instead of the error
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Loading tasks...'),
                        ],
                      ),
                    );
                  }

                  // For other errors, show error message
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final tasks = snapshot.data?.docs ?? [];

                // Sort tasks by due date (in-memory)
                final sortedTasks = sortTasksByDueDate(tasks);

                if (sortedTasks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assignment_turned_in,
                          size: 60,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _filterStatus == 'All'
                              ? 'No tasks assigned yet'
                              : 'No $_filterStatus tasks',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: sortedTasks.length,
                  itemBuilder: (context, index) {
                    return _buildTaskItem(sortedTasks[index]);
                  },
                );
              },
            ),
    );
  }
}
