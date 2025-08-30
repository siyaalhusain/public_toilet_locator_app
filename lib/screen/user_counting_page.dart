import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
//usercounting
class CounterPage extends StatefulWidget {
  final String?
      toiletId; // Make toiletId optional since we'll fetch assigned toilets

  const CounterPage({Key? key, this.toiletId}) : super(key: key);

  @override
  _CounterPageState createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int _todayCount = 0;
  bool _isLoading = true;
  bool _isAuthorized = false;
  String _toiletName = '';
  String _maintainerName = '';
  String? _errorMessage;
  String? _ownerId;
  String? _currentUserId;
  final TextEditingController _countController = TextEditingController();
  final TextEditingController _editCountController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final String _today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  List<DailyCount> _previousCounts = [];
  List<Map<String, dynamic>> _assignedToilets = [];
  String? _selectedToiletId;
  Map<String, dynamic>? _selectedToiletData;

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
    if (widget.toiletId != null) {
      _selectedToiletId = widget.toiletId;
    }
  }

  Future<void> _getCurrentUser() async {
    User? user = _auth.currentUser;
    if (user != null) {
      setState(() {
        _currentUserId = user.uid;
      });
      await _loadAssignedToilets();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'User not logged in';
      });
    }
  }

  Future<void> _loadAssignedToilets() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get all toilets assigned to this maintainer
      QuerySnapshot toiletSnapshot = await _firestore
          .collection('toilets')
          .where('assignedMaintainer.id', isEqualTo: _currentUserId)
          .get();

      if (toiletSnapshot.docs.isNotEmpty) {
        List<Map<String, dynamic>> toilets = toiletSnapshot.docs.map((doc) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            'name': data['name'] ?? 'Unnamed Toilet',
            ...data,
          };
        }).toList();

        setState(() {
          _assignedToilets = toilets;
          // If a specific toilet ID was provided, verify it's in the assigned list
          if (widget.toiletId != null &&
              toilets.any((t) => t['id'] == widget.toiletId)) {
            _selectedToiletId = widget.toiletId;
            _selectedToiletData =
                toilets.firstWhere((t) => t['id'] == widget.toiletId);
          } else if (toilets.isNotEmpty) {
            // Default to first assigned toilet if none was specified
            _selectedToiletId = toilets.first['id'];
            _selectedToiletData = toilets.first;
          }
        });

        if (_selectedToiletId != null) {
          await _loadToiletData(_selectedToiletId!);
        } else {
          setState(() {
            _isLoading = false;
            _isAuthorized = false;
            _errorMessage = 'No toilets assigned to you';
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _isAuthorized = false;
          _errorMessage = 'No toilets assigned to you';
        });
      }
    } catch (e) {
      print('Error loading assigned toilets: $e');
      setState(() {
        _isLoading = false;
        _isAuthorized = false;
        _errorMessage = 'Error loading toilet data: ${e.toString()}';
      });
    }
  }

  Future<void> _loadToiletData(String toiletId) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final doc = await _firestore.collection('toilets').doc(toiletId).get();

      if (doc.exists) {
        final toiletData = doc.data() as Map<String, dynamic>;
        _ownerId = toiletData['ownerId'];

        // Check if current user is assigned to this toilet
        bool isAssigned = false;
        if (toiletData['assignedMaintainer'] != null) {
          if (toiletData['assignedMaintainer'] is Map) {
            Map assignedMaintainer = toiletData['assignedMaintainer'] as Map;
            if (assignedMaintainer.containsKey('id') &&
                assignedMaintainer['id'] == _currentUserId) {
              isAssigned = true;
            }
          } else if (toiletData['assignedMaintainer'] is String) {
            isAssigned = toiletData['assignedMaintainer'] == _currentUserId;
          }
        }

        // Get toilet name with fallbacks
        String toiletName = 'Unknown Toilet';
        if (toiletData['name'] != null) {
          toiletName = toiletData['name'].toString();
        } else if (toiletData['toiletName'] != null) {
          toiletName = toiletData['toiletName'].toString();
        } else if (toiletData['details'] != null &&
            toiletData['details'] is Map) {
          final details = toiletData['details'] as Map;
          if (details['name'] != null) {
            toiletName = details['name'].toString();
          }
        }

        setState(() {
          _toiletName = toiletName;
          _maintainerName = toiletData['assignedMaintainer']?['name'] ??
              toiletData['maintainerName'] ??
              'Unknown Maintainer';
          _isAuthorized = isAssigned;
        });

        if (isAssigned) {
          await _loadTodayCount();
          await _loadPreviousCounts();
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = 'You are not assigned to maintain this toilet';
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _isAuthorized = false;
          _errorMessage = 'Toilet not found';
        });
      }
    } catch (e) {
      print('Error loading toilet data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading toilet data: ${e.toString()}')),
      );
      setState(() {
        _isLoading = false;
        _isAuthorized = false;
        _errorMessage = 'Failed to load toilet data: ${e.toString()}';
      });
    }
  }

  Future<void> _loadTodayCount() async {
    try {
      final doc = await _firestore
          .collection('toilets')
          .doc(_selectedToiletId)
          .collection('daily_counts')
          .doc(_today)
          .get();

      if (doc.exists) {
        setState(() {
          _todayCount = doc.data()?['count'] ?? 0;
          _countController.text = _todayCount.toString();
        });
      } else {
        _countController.text = '0';
      }
    } catch (e) {
      print('Error loading count: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading count: ${e.toString()}')),
      );
    }
  }

  Future<void> _loadPreviousCounts() async {
    try {
      final query = await _firestore
          .collection('toilets')
          .doc(_selectedToiletId)
          .collection('daily_counts')
          .orderBy('date', descending: true)
          .limit(30)
          .get();

      setState(() {
        _previousCounts = query.docs.map((doc) {
          return DailyCount(
            date: doc.data()['date'] as String,
            count: doc.data()['count'] as int,
            timestamp: (doc.data()['timestamp'] as Timestamp).toDate(),
            documentId: doc.id,
          );
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading previous counts: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error loading previous counts: ${e.toString()}')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateCount(int newCount) async {
    if (!_isAuthorized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You are not authorized to update this toilet')),
      );
      return;
    }

    if (newCount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Count cannot be negative')),
      );
      return;
    }

    setState(() {
      _todayCount = newCount;
      _isLoading = true;
    });

    try {
      await _firestore
          .collection('toilets')
          .doc(_selectedToiletId)
          .collection('daily_counts')
          .doc(_today)
          .set({
        'count': newCount,
        'date': _today,
        'timestamp': FieldValue.serverTimestamp(),
        'updatedBy': _currentUserId,
        'ownerId': _ownerId,
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Count updated successfully')),
      );
    } catch (e) {
      print('Error updating count: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating count: ${e.toString()}')),
      );
      setState(() {
        _todayCount = int.tryParse(_countController.text) ?? _todayCount;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _loadPreviousCounts();
    }
  }

  Future<void> _editCount(DailyCount count) async {
    if (!_isAuthorized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You are not authorized to edit this toilet')),
      );
      return;
    }

    _editCountController.text = count.count.toString();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            'Edit count for ${DateFormat('MMM d, yyyy').format(count.timestamp)}'),
        content: TextField(
          controller: _editCountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'New Count'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newCount =
                  int.tryParse(_editCountController.text) ?? count.count;
              if (newCount < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Count cannot be negative')),
                );
                return;
              }

              try {
                await _firestore
                    .collection('toilets')
                    .doc(_selectedToiletId)
                    .collection('daily_counts')
                    .doc(count.date)
                    .update({
                  'count': newCount,
                  'updatedBy': _currentUserId,
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Count updated successfully')),
                );
                Navigator.pop(context);
                _loadPreviousCounts();
              } catch (e) {
                print('Error updating count: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Error updating count: ${e.toString()}')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily User Counter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_selectedToiletId != null) {
                _loadToiletData(_selectedToiletId!);
              }
            },
            tooltip: 'Refresh data',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_isAuthorized
              ? _buildNotAuthorizedView()
              : _buildAuthorizedView(),
    );
  }

  Widget _buildNotAuthorizedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.no_accounts,
              size: 72,
              color: Colors.red[300],
            ),
            const SizedBox(height: 24),
            Text(
              'Not Authorized',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.red[800],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'You are not assigned to maintain any toilets',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorizedView() {
    return Column(
      children: [
        // Toilet selector dropdown if multiple toilets assigned
        if (_assignedToilets.length > 1)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: DropdownButton<String>(
                  value: _selectedToiletId,
                  isExpanded: true,
                  hint: const Text('Select Toilet'),
                  items: _assignedToilets.map((toilet) {
                    return DropdownMenuItem<String>(
                      value: toilet['id'],
                      child: Text(toilet['name'] ?? 'Unnamed Toilet'),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedToiletId = newValue;
                        _selectedToiletData = _assignedToilets
                            .firstWhere((t) => t['id'] == newValue);
                      });
                      _loadToiletData(newValue);
                    }
                  },
                ),
              ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Toilet info card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _toiletName,
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Maintained by: $_maintainerName',
                            style: const TextStyle(
                                fontSize: 16, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          if (_ownerId != null) ...[
                            Row(
                              children: [
                                Icon(Icons.person_outline,
                                    size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  'Owner ID: ${_ownerId!.length > 8 ? _ownerId!.substring(0, 8) + '...' : _ownerId}',
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              Icon(Icons.check_circle,
                                  color: Colors.green[600], size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'You are authorized to update this toilet',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Today's count card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Today: ${DateFormat('MMMM d, yyyy').format(DateTime.now())}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _countController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Enter Today\'s Count',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _todayCount =
                                          int.tryParse(value) ?? _todayCount;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: () => _updateCount(_todayCount),
                                child: const Text('Update'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 15),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: ElevatedButton.icon(
                              onPressed: () => _updateCount(_todayCount + 1),
                              icon: const Icon(Icons.add),
                              label: const Text('Add 1 User',
                                  style: TextStyle(fontSize: 18)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 40, vertical: 15),
                                backgroundColor: Colors.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Previous counts card
                  Card(
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
                            'Previous Counts:',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          _previousCounts.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Text(
                                      'No previous counts recorded',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _previousCounts.length,
                                  itemBuilder: (context, index) {
                                    final count = _previousCounts[index];
                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: ListTile(
                                        title: Text(DateFormat('MMMM d, yyyy')
                                            .format(count.timestamp)),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              count.count.toString(),
                                              style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.edit,
                                                  size: 20),
                                              onPressed: () =>
                                                  _editCount(count),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _countController.dispose();
    _editCountController.dispose();
    super.dispose();
  }
}

class DailyCount {
  final String date;
  final int count;
  final DateTime timestamp;
  final String documentId;

  DailyCount({
    required this.date,
    required this.count,
    required this.timestamp,
    required this.documentId,
  });
}
