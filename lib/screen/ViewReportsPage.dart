import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class ViewReportsPage extends StatefulWidget {
  @override
  _ViewReportsPageState createState() => _ViewReportsPageState();
}

class _ViewReportsPageState extends State<ViewReportsPage> {
  final CollectionReference reportsCollection =
      FirebaseFirestore.instance.collection('toilet_reports');
  final CollectionReference toiletsCollection =
      FirebaseFirestore.instance.collection('toilets');

  bool _isDeleteLoading = false;
  bool _isLoading = true;
  String _selectedFilter = 'All Reports';
  final List<String> _filterOptions = [
    'All Reports',
    'Recent',
    'Maintenance',
    'Cleanliness',
    'Safety',
    'Other'
  ];

  // Get current user ID
  String? _currentUserId;
  List<String> _ownedToiletIds = [];

  @override
  void initState() {
    super.initState();
    _getCurrentUserAndToilets();
  }

  Future<void> _getCurrentUserAndToilets() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get current user
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        _currentUserId = currentUser.uid;

        // Fetch all toilets owned by this user
        QuerySnapshot toiletsQuery = await toiletsCollection
            .where('ownerId', isEqualTo: _currentUserId)
            .get();

        // Extract toilet IDs
        _ownedToiletIds = toiletsQuery.docs.map((doc) => doc.id).toList();

        // Debug prints
        print(
            'Found ${_ownedToiletIds.length} toilets owned by ${_currentUserId}');
        if (_ownedToiletIds.isEmpty) {
          print('No toilets found for this user');
        } else {
          print('Toilet IDs: $_ownedToiletIds');
        }

        // Alternative approach: fetch reports directly from the reports collection
        // where the owner ID matches the current user ID
        if (_ownedToiletIds.isEmpty) {
          QuerySnapshot reportsQuery = await reportsCollection
              .where('toiletOwnerId', isEqualTo: _currentUserId)
              .get();

          print(
              'Found ${reportsQuery.docs.length} reports for owner ID: $_currentUserId');
        }
      } else {
        print('No user is currently logged in');
      }
    } catch (e) {
      print('Error getting user and toilets: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading toilets: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My Toilet Reports',
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
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _buildReportsStream(),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsStream() {
    if (_currentUserId == null) {
      return _buildNoAuthMessage();
    }

    // Using a different approach for querying reports - without orderBy to avoid composite index issues
    return StreamBuilder<QuerySnapshot>(
      stream: reportsCollection
          .where('toiletOwnerId', isEqualTo: _currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          print('Error in stream: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red),
                SizedBox(height: 16),
                Text(
                  'Error loading reports',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[600],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: TextStyle(color: Colors.red[400]),
                ),
                SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _getCurrentUserAndToilets(),
                  icon: Icon(Icons.refresh),
                  label: Text('Refresh'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildNoReportsMessage();
        }

        // Sort reports manually and filter
        var filteredDocs = snapshot.data!.docs;

        // Sort manually by timestamp (descending)
        if (filteredDocs.isNotEmpty) {
          filteredDocs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;

            // Get timestamps (default to current time if not available)
            final aTimestamp = aData.containsKey('timestamp')
                ? aData['timestamp'] as Timestamp? ?? Timestamp.now()
                : Timestamp.now();
            final bTimestamp = bData.containsKey('timestamp')
                ? bData['timestamp'] as Timestamp? ?? Timestamp.now()
                : Timestamp.now();

            // Sort descending (newer first)
            return bTimestamp.compareTo(aTimestamp);
          });
        }

        // Apply category filters
        if (_selectedFilter != 'All Reports') {
          if (_selectedFilter == 'Recent') {
            // Get reports from the last 7 days
            final DateTime sevenDaysAgo =
                DateTime.now().subtract(Duration(days: 7));
            filteredDocs = filteredDocs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              if (!data.containsKey('timestamp')) return false;

              final timestamp = data['timestamp'] as Timestamp?;
              if (timestamp == null) return false;

              return timestamp.toDate().isAfter(sevenDaysAgo);
            }).toList();
          } else {
            // Filter by category
            filteredDocs = filteredDocs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              if (!data.containsKey('category')) return false;

              return data['category'] == _selectedFilter;
            }).toList();
          }
        }

        if (filteredDocs.isEmpty) {
          return _buildNoFilteredReportsMessage();
        }

        return ListView.separated(
          padding: EdgeInsets.all(16),
          itemCount: filteredDocs.length,
          separatorBuilder: (context, index) => SizedBox(height: 12),
          itemBuilder: (context, index) {
            var doc = filteredDocs[index];
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

            // Safely get field values with null checks
            String toiletName = data.containsKey('toiletName')
                ? data['toiletName'] ?? 'Unknown Toilet'
                : 'Unknown Toilet';

            String issue = data.containsKey('issue')
                ? data['issue'] ?? 'No description provided'
                : 'No description provided';

            String user = data.containsKey('reporterEmail')
                ? data['reporterEmail'] ?? 'Anonymous User'
                : (data.containsKey('user')
                    ? data['user'] ?? 'Anonymous User'
                    : 'Anonymous User');

            Timestamp timestamp = data.containsKey('timestamp')
                ? data['timestamp'] ?? Timestamp.now()
                : Timestamp.now();

            String category = data.containsKey('category')
                ? data['category'] ?? 'General'
                : 'General';

            String status = data.containsKey('status')
                ? data['status'] ?? 'Pending'
                : 'Pending';

            // Safely handle severity
            String severity = data.containsKey('severity')
                ? data['severity'] ?? 'Medium'
                : 'Medium';

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
              case 'Supplies':
                categoryColor = Colors.amber;
                categoryIcon = Icons.inventory;
                break;
              case 'Accessibility':
                categoryColor = Colors.purple;
                categoryIcon = Icons.accessible;
                break;
              default:
                categoryColor = Colors.grey;
                categoryIcon = Icons.report_problem;
            }

            return Card(
              margin: EdgeInsets.zero,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category header
                  ClipRRect(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(12)),
                    child: Container(
                      color: categoryColor.withOpacity(0.1),
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(categoryIcon, color: categoryColor, size: 20),
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

                  // Report content
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          toiletName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        SizedBox(height: 8),
                        Container(
                          constraints: BoxConstraints(maxHeight: 80),
                          child: Text(
                            issue,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 3,
                          ),
                        ),
                        SizedBox(height: 16),
                        Divider(),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.person_outline,
                                size: 16, color: Colors.grey[600]),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                user,
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
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

                  // Actions row
                  Divider(height: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(
                        'Change Status',
                        Icons.update,
                        Colors.blue,
                        () {
                          _showChangeStatusBottomSheet(context, doc);
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

                          if (confirm == true) {
                            _deleteReport(doc.id);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNoAuthMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_circle_outlined,
              size: 70, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'Not Logged In',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Please log in to view reports for your toilets',
            style: TextStyle(
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoToiletsMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wc_outlined, size: 70, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'No Toilets Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'You need to add toilets first to see reports',
            style: TextStyle(
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              _getCurrentUserAndToilets();
            },
            icon: Icon(Icons.refresh),
            label: Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoReportsMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.report_problem_outlined,
              size: 70, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'No Reports Available',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'No one has reported issues with your toilets yet',
            style: TextStyle(
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              _getCurrentUserAndToilets();
            },
            icon: Icon(Icons.refresh),
            label: Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoFilteredReportsMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.filter_list_off, size: 70, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'No Reports Match Filter',
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

    // Safely get current status
    final reportData = report.data() as Map<String, dynamic>;
    final currentStatus = reportData.containsKey('status')
        ? reportData['status'] ?? 'Pending'
        : 'Pending';

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
