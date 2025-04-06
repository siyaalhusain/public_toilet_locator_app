import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ViewReportsPage extends StatefulWidget {
  @override
  _ViewReportsPageState createState() => _ViewReportsPageState();
}

class _ViewReportsPageState extends State<ViewReportsPage> {
  final CollectionReference reportsCollection =
      FirebaseFirestore.instance.collection('reports');
  bool _isDeleteLoading = false;
  String _selectedFilter = 'All Reports';
  final List<String> _filterOptions = [
    'All Reports',
    'Recent',
    'Maintenance',
    'Cleanliness',
    'Safety'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Reports',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _selectedFilter = value;
              });
            },
            itemBuilder: (context) => _filterOptions
                .map((option) => PopupMenuItem<String>(
                      value: option,
                      child: Row(
                        children: [
                          Icon(
                            option == _selectedFilter
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: option == _selectedFilter
                                ? Colors.blue
                                : Colors.grey,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Text(option),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 16),
              children: _filterOptions.map((filter) {
                bool isSelected = _selectedFilter == filter;
                return Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filter),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                    },
                    backgroundColor: Colors.grey[200],
                    selectedColor: Colors.blue[100],
                    checkmarkColor: Colors.blue,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.blue[800] : Colors.black87,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          Divider(height: 1),

          // Reports list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: reportsCollection
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.report_problem_outlined,
                          size: 70,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No reports available',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'All reported issues will appear here',
                          style: TextStyle(
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Filter reports if needed
                var filteredDocs = snapshot.data!.docs;
                if (_selectedFilter != 'All Reports') {
                  if (_selectedFilter == 'Recent') {
                    // Get reports from the last 7 days
                    final DateTime sevenDaysAgo =
                        DateTime.now().subtract(Duration(days: 7));
                    filteredDocs = filteredDocs.where((doc) {
                      final timestamp = doc['timestamp'] as Timestamp;
                      return timestamp.toDate().isAfter(sevenDaysAgo);
                    }).toList();
                  } else {
                    // Filter by category (assuming 'category' field exists in reports)
                    filteredDocs = filteredDocs.where((doc) {
                      return doc['category'] == _selectedFilter;
                    }).toList();
                  }
                }

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.filter_list_off,
                          size: 70,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No reports match the filter',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Try changing your filter selection',
                          style: TextStyle(
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: EdgeInsets.all(16),
                  itemCount: filteredDocs.length,
                  separatorBuilder: (context, index) => SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    var report = filteredDocs[index];
                    String toiletName = report['toiletName'];
                    String issue = report['issue'];
                    String user = report['user'];
                    Timestamp timestamp = report['timestamp'];
                    String category = report['category'] ?? 'General';
                    String status = report['status'] ?? 'Pending';
                    String imageUrl = report['imageUrl'];

                    Color statusColor;
                    switch (status) {
                      case 'Resolved':
                        statusColor = Colors.green;
                        break;
                      case 'In Progress':
                        statusColor = Colors.orange;
                        break;
                      default:
                        statusColor = Colors.red;
                    }

                    Color categoryColor;
                    IconData categoryIcon;
                    switch (category) {
                      case 'Maintenance':
                        categoryColor = Colors.blue;
                        categoryIcon = Icons.build;
                        break;
                      case 'Cleanliness':
                        categoryColor = Colors.green;
                        categoryIcon = Icons.cleaning_services;
                        break;
                      case 'Safety':
                        categoryColor = Colors.red;
                        categoryIcon = Icons.security;
                        break;
                      default:
                        categoryColor = Colors.purple;
                        categoryIcon = Icons.report_problem;
                    }

                    return Dismissible(
                      key: Key(report.id),
                      background: Container(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(Icons.delete, color: Colors.white),
                            Icon(Icons.delete, color: Colors.white),
                          ],
                        ),
                      ),
                      confirmDismiss: (direction) async {
                        return await showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: Text("Delete Report"),
                              content: Text(
                                  "Are you sure you want to delete this report?"),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: Text("Cancel"),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: Text("Delete",
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      onDismissed: (direction) {
                        _deleteReport(report.id);
                      },
                      child: Card(
                        margin: EdgeInsets.zero,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(12)),
                              child: Container(
                                color: categoryColor.withOpacity(0.1),
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Icon(categoryIcon,
                                        color: categoryColor, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      category,
                                      style: TextStyle(
                                        color: categoryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Spacer(),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              toiletName,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18,
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              issue,
                                              style: TextStyle(
                                                fontSize: 15,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (imageUrl != null &&
                                          imageUrl.isNotEmpty)
                                        InkWell(
                                          onTap: () {
                                            showDialog(
                                              context: context,
                                              builder: (context) => Dialog(
                                                child: Image.network(imageUrl),
                                              ),
                                            );
                                          },
                                          child: Container(
                                            width: 60,
                                            height: 60,
                                            margin: EdgeInsets.only(left: 8),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              image: DecorationImage(
                                                image: NetworkImage(imageUrl),
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                            child: Center(
                                              child: Container(
                                                padding: EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: Colors.black54,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons.zoom_in,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: 16),
                                  Divider(),
                                  SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.person_outline,
                                          size: 16, color: Colors.grey[600]),
                                      SizedBox(width: 4),
                                      Text(
                                        user,
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 14,
                                        ),
                                      ),
                                      Spacer(),
                                      Icon(Icons.access_time,
                                          size: 16, color: Colors.grey[600]),
                                      SizedBox(width: 4),
                                      Text(
                                        DateFormat('MMM d, yyyy · h:mm a')
                                            .format(timestamp.toDate()),
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Divider(height: 1),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildActionButton(
                                  'Change Status',
                                  Icons.update,
                                  Colors.blue,
                                  () {
                                    _showChangeStatusBottomSheet(
                                        context, report);
                                  },
                                ),
                                Container(
                                  width: 1,
                                  height: 24,
                                  color: Colors.grey[300],
                                ),
                                _buildActionButton(
                                  'Delete',
                                  Icons.delete_outline,
                                  Colors.red,
                                  () async {
                                    bool confirm = await showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return AlertDialog(
                                          title: Text("Delete Report"),
                                          content: Text(
                                              "Are you sure you want to delete this report?"),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context)
                                                      .pop(false),
                                              child: Text("Cancel"),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context)
                                                      .pop(true),
                                              child: Text("Delete",
                                                  style: TextStyle(
                                                      color: Colors.red)),
                                            ),
                                          ],
                                        );
                                      },
                                    );

                                    if (confirm == true) {
                                      _deleteReport(report.id);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
      String label, IconData icon, Color color, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeStatusBottomSheet(
      BuildContext context, DocumentSnapshot report) {
    final statuses = ['Pending', 'In Progress', 'Resolved'];
    final currentStatus = report['status'] ?? 'Pending';

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Update Report Status',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Divider(),
              SizedBox(height: 10),
              ...statuses.map((status) {
                bool isSelected = status == currentStatus;

                Color statusColor;
                switch (status) {
                  case 'Resolved':
                    statusColor = Colors.green;
                    break;
                  case 'In Progress':
                    statusColor = Colors.orange;
                    break;
                  default:
                    statusColor = Colors.red;
                }

                return ListTile(
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    status,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? statusColor : Colors.black87,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    if (status != currentStatus) {
                      _updateReportStatus(report.id, status);
                    }
                  },
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  void _updateReportStatus(String reportId, String newStatus) async {
    try {
      await reportsCollection.doc(reportId).update({'status': newStatus});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Report status updated to $newStatus"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to update status: $e"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _deleteReport(String reportId) async {
    if (_isDeleteLoading) return;

    setState(() {
      _isDeleteLoading = true;
    });

    try {
      await reportsCollection.doc(reportId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Report deleted"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to delete report: $e"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() {
        _isDeleteLoading = false;
      });
    }
  }
}
