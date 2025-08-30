import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
// Owner Counting Page
class OwnerCountingPage extends StatefulWidget {
  const OwnerCountingPage({Key? key}) : super(key: key);

  @override
  _OwnerCountingPageState createState() => _OwnerCountingPageState();
}

class _OwnerCountingPageState extends State<OwnerCountingPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<ToiletCount> _toiletCounts = [];
  bool _isLoading = true;
  String? _currentOwnerId;
  String? _currentUserEmail;
  DateTime? _selectedDate; // Changed from DateTimeRange to DateTime
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
  }

  Future<void> _getCurrentUser() async {
    setState(() {
      _isLoading = true;
    });

    User? user = _auth.currentUser;
    if (user != null) {
      setState(() {
        _currentOwnerId = user.uid;
        _currentUserEmail = user.email;
      });
      await _loadToiletCounts();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'User not logged in';
      });
    }
  }

  Future<void> _loadToiletCounts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get all toilets belonging to this owner
      final toiletsQuery = await _firestore
          .collection('toilets')
          .where('ownerId', isEqualTo: _currentOwnerId)
          .get();

      final counts = <ToiletCount>[];

      if (toiletsQuery.docs.isEmpty) {
        // No toilets found for this owner
        setState(() {
          _toiletCounts = [];
          _isLoading = false;
        });
        return;
      }

      for (final toiletDoc in toiletsQuery.docs) {
        final toiletData = toiletDoc.data();
        String toiletId = toiletDoc.id;

        // Get daily counts for this toilet
        QuerySnapshot countsQuery;

        if (_selectedDate != null) {
          // For a specific date selection
          final selectedDate = DateFormat('yyyy-MM-dd').format(_selectedDate!);

          countsQuery = await _firestore
              .collection('toilets')
              .doc(toiletId)
              .collection('daily_counts')
              .where('date', isEqualTo: selectedDate)
              .get();
        } else {
          // If no date selected, use today's date
          final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

          countsQuery = await _firestore
              .collection('toilets')
              .doc(toiletId)
              .collection('daily_counts')
              .where('date', isEqualTo: today)
              .get();
        }

        int total = 0;
        List<DailyCount> dailyCounts = [];

        if (countsQuery.docs.isEmpty) {
          // No records found for the selected date or today
          final dateToUse = _selectedDate ?? DateTime.now();
          dailyCounts = [
            DailyCount(
              date: DateFormat('yyyy-MM-dd').format(dateToUse),
              count: 0,
              timestamp: dateToUse,
            )
          ];
        } else {
          dailyCounts = countsQuery.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final count = data['count'] as int? ?? 0;
            total += count;
            return DailyCount(
              date: data['date'] as String? ?? 'Unknown',
              count: count,
              timestamp:
                  (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            );
          }).toList();
        }

        // Get maintainer info
        String maintainerName = 'Unassigned';
        if (toiletData.containsKey('assignedMaintainer') &&
            toiletData['assignedMaintainer'] != null) {
          if (toiletData['assignedMaintainer'] is Map) {
            maintainerName = toiletData['assignedMaintainer']['name'] ??
                'Unknown Maintainer';
          } else {
            maintainerName = 'Assigned';
          }
        }

        counts.add(ToiletCount(
          toiletId: toiletId,
          name: toiletData['name'] ?? 'Unnamed Toilet',
          maintainerName: maintainerName,
          counts: dailyCounts,
          total: total,
          status: toiletData['maintenanceStatus'] ?? 'Unknown',
          location: toiletData['location'] != null
              ? Location(
                  latitude: toiletData['location']['latitude'] ?? 0.0,
                  longitude: toiletData['location']['longitude'] ?? 0.0)
              : null,
        ));
      }

      setState(() {
        _toiletCounts = counts;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading toilet counts: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading counts: ${e.toString()}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading counts: ${e.toString()}')),
      );
    }
  }

  // Changed to select a specific date instead of date range
  Future<void> _selectDate(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
      await _loadToiletCounts();
    }
  }

  // Added to quickly set to today
  void _selectToday() {
    setState(() {
      _selectedDate = DateTime.now();
    });
    _loadToiletCounts();
  }

  void _resetDateFilter() {
    setState(() {
      _selectedDate = null; // Changed from DateTimeRange to null
    });
    _loadToiletCounts();
  }

  // Export functionality removed

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Toilet Usage Statistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Select specific date',
            onPressed: () => _selectDate(context),
          ),
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Show today',
            onPressed: _selectToday,
          ),
          if (_selectedDate != null)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              tooltip: 'Reset to today',
              onPressed: _resetDateFilter,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload data',
            onPressed: _loadToiletCounts,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorWidget()
              : _toiletCounts.isEmpty
                  ? _buildEmptyState()
                  : _buildToiletsList(),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            'Error',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              _errorMessage ?? 'An unknown error occurred',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadToiletCounts,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wc, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'No Toilets Found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Text(
              _selectedDate != null
                  ? 'No data available for ${DateFormat('MMMM d, yyyy').format(_selectedDate!)}'
                  : 'You don\'t have any toilets registered yet',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 24),
          if (_selectedDate != null)
            ElevatedButton.icon(
              onPressed: _resetDateFilter,
              icon: const Icon(Icons.today),
              label: const Text('Show Today'),
            )
          else
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to add toilet page
                Navigator.pop(context); // Go back to main page
                // Assuming you have a way to navigate to add toilet page from there
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Toilet'),
            ),
        ],
      ),
    );
  }

  Widget _buildToiletsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date selection indicator
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Icon(Icons.date_range, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Date: ${DateFormat('MMMM d, yyyy').format(_selectedDate ?? DateTime.now())}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_selectedDate != null)
                    IconButton(
                      icon: const Icon(Icons.today, size: 20),
                      onPressed: _resetDateFilter,
                      tooltip: 'Show today',
                    ),
                ],
              ),
            ),
          ),
        ),

        // Summary card showing total users across all toilets
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Summary',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem(
                        icon: Icons.wc,
                        title: 'Total Toilets',
                        value: _toiletCounts.length.toString(),
                        color: Colors.blue,
                      ),
                      _buildSummaryItem(
                        icon: Icons.people,
                        title: 'Total Users',
                        value: _toiletCounts
                            .fold(0, (sum, toilet) => sum + toilet.total)
                            .toString(),
                        color: Colors.green,
                      ),
                      _buildSummaryItem(
                        icon: Icons.calendar_today,
                        title: 'Date',
                        value: DateFormat('MMM d')
                            .format(_selectedDate ?? DateTime.now()),
                        color: Colors.orange,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // List of toilets
        Expanded(
          child: ListView.builder(
            itemCount: _toiletCounts.length,
            itemBuilder: (context, index) {
              final toilet = _toiletCounts[index];
              return Card(
                margin: const EdgeInsets.all(8.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: ExpansionTile(
                  leading: const Icon(Icons.wc, color: Colors.blue),
                  title: Text(
                    toilet.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Maintainer: ${toilet.maintainerName}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Count: ${toilet.total}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Status: ${toilet.status}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _getStatusColor(toilet.status),
                        ),
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: Column(
                        children: [
                          // Daily count display
                          if (toilet.counts.isNotEmpty) ...[
                            const Text(
                              'Daily Usage',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ListTile(
                              dense: true,
                              title: Text(
                                DateFormat('MMMM d, yyyy')
                                    .format(toilet.counts.first.timestamp),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${toilet.counts.first.count} users',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Divider(),
                          ] else
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                'No usage data available for this toilet',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),

                          // Location info
                          if (toilet.location != null) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Location Information',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ListTile(
                              leading: Icon(Icons.location_on,
                                  color: Colors.red.shade700),
                              title: const Text('Coordinates'),
                              subtitle: Text(
                                'Lat: ${toilet.location!.latitude.toStringAsFixed(6)}, Lng: ${toilet.location!.longitude.toStringAsFixed(6)}',
                              ),
                              dense: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return Colors.green;
      case 'unassigned':
        return Colors.red;
      case 'maintenance':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

class ToiletCount {
  final String toiletId;
  final String name;
  final String maintainerName;
  final List<DailyCount> counts;
  final int total;
  final String status;
  final Location? location;

  ToiletCount({
    required this.toiletId,
    required this.name,
    required this.maintainerName,
    required this.counts,
    required this.total,
    required this.status,
    this.location,
  });
}

class DailyCount {
  final String date;
  final int count;
  final DateTime timestamp;

  DailyCount({
    required this.date,
    required this.count,
    required this.timestamp,
  });
}

class Location {
  final double latitude;
  final double longitude;

  Location({
    required this.latitude,
    required this.longitude,
  });
}
