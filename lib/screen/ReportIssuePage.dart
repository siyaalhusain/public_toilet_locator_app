import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

// Toilet Model with improved error handling
class Toilet {
  final String id;
  final String name;
  final String location;
  final String ownerId;
  final GeoPoint? coordinates;
  double? distance;

  Toilet({
    required this.id,
    required this.name,
    required this.location,
    required this.ownerId,
    this.coordinates,
    this.distance,
  });

  // Safe conversion from Firestore with proper error handling
  factory Toilet.fromFirestore(DocumentSnapshot doc) {
    try {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

      // Safely extract strings
      String name = _extractString(data, 'name');
      String location = _extractString(data, 'location');
      String ownerId = _extractString(data, 'ownerId');

      // Safely extract coordinates
      GeoPoint? coordinates;
      try {
        if (data['coordinates'] is GeoPoint) {
          coordinates = data['coordinates'] as GeoPoint;
        }
      } catch (e) {
        print('Error extracting coordinates: $e');
      }

      return Toilet(
        id: doc.id,
        name: name,
        location: location,
        ownerId: ownerId,
        coordinates: coordinates,
      );
    } catch (e) {
      print('Error creating Toilet from Firestore document ${doc.id}: $e');
      // Return a fallback toilet
      return Toilet(
        id: doc.id,
        name: 'Unknown Toilet',
        location: 'Location unavailable',
        ownerId: '',
      );
    }
  }

  // Helper method to safely extract strings
  static String _extractString(Map<String, dynamic> data, String key) {
    try {
      var value = data[key];
      if (value is String) {
        return value;
      } else if (value == null) {
        return '';
      } else {
        // Convert non-string values to string
        return value.toString();
      }
    } catch (e) {
      print('Error extracting $key: $e');
      return '';
    }
  }
}

class ReportIssuePage extends StatefulWidget {
  const ReportIssuePage({Key? key}) : super(key: key);

  @override
  ReportIssuePageState createState() => ReportIssuePageState();
}

class ReportIssuePageState extends State<ReportIssuePage> {
  final TextEditingController _toiletNameController = TextEditingController();
  final TextEditingController _issueController = TextEditingController();

  final List<String> _issueCategories = [
    'Cleanliness',
    'Maintenance',
    'Supplies',
    'Accessibility',
    'Other'
  ];

  final List<String> _severityLevels = ['Low', 'Medium', 'High', 'Critical'];

  String? _selectedCategory;
  String? _selectedSeverity;
  Toilet? _selectedToilet;
  Position? _userPosition;
  bool _isLoadingLocation = false;
  bool _isLoadingToilets = false;
  List<Toilet> _availableToilets = [];
  List<Toilet> _filteredToilets = [];
  bool _isSearching = false;
  String? _errorMessage;
  bool _isLoadingReports = false;

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    _fetchAllToilets();
    _checkCurrentUser(); // Add this to verify user authentication on init

    // Initialize loading state for reports here
    _isLoadingReports = true;

    // Add listener to toilet name controller
    _toiletNameController.addListener(_onSearchTextChanged);

    // Schedule a post-frame callback to safely update state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isLoadingReports = false;
        });
      }
    });
  }

  // Added method to check if the user is authenticated
  void _checkCurrentUser() {
    User? currentUser = FirebaseAuth.instance.currentUser;
    print('Current user: ${currentUser?.uid ?? 'Not logged in'}');
    print('Current user email: ${currentUser?.email ?? 'No email'}');
  }

  void _onSearchTextChanged() {
    if (_toiletNameController.text.isEmpty) {
      setState(() {
        _filteredToilets = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _filteredToilets = _availableToilets.where((toilet) {
        return toilet.name
            .toLowerCase()
            .contains(_toiletNameController.text.toLowerCase());
      }).toList();

      // Sort results
      _filteredToilets.sort((a, b) {
        // Exact match
        bool aExactMatch =
            a.name.toLowerCase() == _toiletNameController.text.toLowerCase();
        bool bExactMatch =
            b.name.toLowerCase() == _toiletNameController.text.toLowerCase();

        if (aExactMatch && !bExactMatch) return -1;
        if (!aExactMatch && bExactMatch) return 1;

        // Starts with
        bool aStartsWith = a.name
            .toLowerCase()
            .startsWith(_toiletNameController.text.toLowerCase());
        bool bStartsWith = b.name
            .toLowerCase()
            .startsWith(_toiletNameController.text.toLowerCase());

        if (aStartsWith && !bStartsWith) return -1;
        if (!aStartsWith && bStartsWith) return 1;

        // Alphabetical
        return a.name.compareTo(b.name);
      });
    });
  }

  Future<void> _getUserLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Location permissions are denied, nearby toilets will not be shown'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() {
            _isLoadingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Location permissions are permanently denied, please enable in settings'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _userPosition = position;
        _isLoadingLocation = false;
      });

      // Update distances for toilets
      _updateToiletDistances();
    } catch (e) {
      print('Error getting location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not get your location: $e'),
          backgroundColor: Colors.orange,
        ),
      );
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  // Fetch all toilets on page load with better error handling
  Future<void> _fetchAllToilets() async {
    setState(() {
      _isLoadingToilets = true;
      _errorMessage = null;
    });

    try {
      print('Fetching toilets from Firestore...');

      QuerySnapshot querySnapshot =
          await FirebaseFirestore.instance.collection('toilets').get();

      print('Received ${querySnapshot.docs.length} toilets from Firestore');

      // Create a list to store valid toilets
      List<Toilet> loadedToilets = [];

      // Process each document with proper error handling
      for (var doc in querySnapshot.docs) {
        try {
          print('Processing toilet: ${doc.id}');
          Toilet toilet = Toilet.fromFirestore(doc);
          loadedToilets.add(toilet);
        } catch (e) {
          print('Error processing toilet ${doc.id}: $e');
          // Continue to next document
        }
      }

      setState(() {
        _availableToilets = loadedToilets;
        _isLoadingToilets = false;

        if (_availableToilets.isEmpty) {
          _errorMessage = 'No toilets found in the database.';
        }
      });

      // Update distances if location is available
      _updateToiletDistances();

      print('Successfully loaded ${_availableToilets.length} toilets');
    } catch (e) {
      print('Error fetching toilets: $e');
      setState(() {
        _isLoadingToilets = false;
        _errorMessage = 'Failed to load toilets: $e';
      });
    }
  }

  void _updateToiletDistances() {
    if (_userPosition == null || _availableToilets.isEmpty) return;

    for (var toilet in _availableToilets) {
      if (toilet.coordinates != null) {
        toilet.distance = Geolocator.distanceBetween(
          _userPosition!.latitude,
          _userPosition!.longitude,
          toilet.coordinates!.latitude,
          toilet.coordinates!.longitude,
        );
      }
    }

    // Sort toilets by distance
    _availableToilets.sort((a, b) {
      if (a.distance == null && b.distance == null) return 0;
      if (a.distance == null) return 1;
      if (b.distance == null) return -1;
      return a.distance!.compareTo(b.distance!);
    });
  }

  void _selectToilet(Toilet toilet) {
    setState(() {
      _selectedToilet = toilet;
      _toiletNameController.text = toilet.name;
      _isSearching = false;
    });
    FocusScope.of(context).unfocus(); // Hide keyboard
  }

  // Find toilet by name (for when user types full name)
  Toilet? _findToiletByName(String name) {
    for (var toilet in _availableToilets) {
      if (toilet.name.toLowerCase() == name.toLowerCase()) {
        return toilet;
      }
    }
    return null;
  }

  Future<void> _submitReport() async {
    // Validate inputs
    if (_selectedToilet == null) {
      // Try to find an exact match from the name
      _selectedToilet = _findToiletByName(_toiletNameController.text);

      if (_selectedToilet == null) {
        _showValidationError('Please select a valid toilet from the list');
        return;
      }
    }

    if (_selectedCategory == null) {
      _showValidationError('Please select an issue category');
      return;
    }

    String issueText = _issueController.text.trim();
    if (issueText.isEmpty) {
      _showValidationError('Please describe the specific issue');
      return;
    }

    if (_selectedSeverity == null) {
      _showValidationError('Please select the severity of the issue');
      return;
    }

    // Get current user
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showValidationError('You must be logged in to report an issue');
      return;
    }

    try {
      print('Submitting report for user: ${currentUser.uid}');

      // Submit report to Firestore
      DocumentReference reportRef =
          await FirebaseFirestore.instance.collection('toilet_reports').add({
        'toiletId': _selectedToilet!.id,
        'toiletName': _selectedToilet!.name,
        'toiletOwnerId': _selectedToilet!.ownerId,
        'reporterId': currentUser.uid,
        'reporterEmail': currentUser.email,
        'category': _selectedCategory,
        'issue': issueText,
        'severity': _selectedSeverity,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'Pending',
        'resolved': false
      });

      print('Report submitted successfully with ID: ${reportRef.id}');

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('Issue reported successfully for ${_selectedToilet!.name}'),
        backgroundColor: Colors.green,
      ));

      // Clear form
      setState(() {
        _toiletNameController.clear();
        _issueController.clear();
        _selectedCategory = null;
        _selectedSeverity = null;
        _selectedToilet = null;
      });

      // Refresh reports tab
      DefaultTabController.of(context)?.animateTo(1);
    } catch (e) {
      print('Error submitting report: $e');
      // Handle any errors
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to submit report: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
    ));
  }

  Widget _buildReportsList() {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Center(child: Text('Please log in to view reports'));
    }

    print('Building reports list for user: ${currentUser.uid}');

    // Don't call setState inside build method - this is causing the error
    // Instead, use initState or didChangeDependencies to set loading states

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('toilet_reports')
          .where('reporterId', isEqualTo: currentUser.uid)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        // Don't call setState here - it's inside the build method
        // We'll handle loading state differently

        if (snapshot.connectionState == ConnectionState.waiting) {
          print('Waiting for reports data...');
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          print('Error fetching reports: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 50, color: Colors.red[400]),
                const SizedBox(height: 16),
                Text(
                  'Error loading reports',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: TextStyle(
                    color: Colors.red[500],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    DefaultTabController.of(context)?.animateTo(1);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        print('Connection state: ${snapshot.connectionState}');
        print('Has data: ${snapshot.hasData}');
        print(
            'Docs count: ${snapshot.hasData ? snapshot.data!.docs.length : 'N/A'}');

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.report_off, size: 70, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No reports found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Issues you report will appear here',
                  style: TextStyle(
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    // Test direct query
                    _testDirectQuery(currentUser.uid);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var report = snapshot.data!.docs[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                title: Text('${report['toiletName']} - ${report['category']}'),
                subtitle: Text(report['issue']),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        _getSeverityColor(report['severity']).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    report['severity'],
                    style: TextStyle(
                      color: _getSeverityColor(report['severity']),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                onTap: () {
                  _showReportDetails(report);
                },
              ),
            );
          },
        );
      },
    );
  }

  // Added test method to debug report fetching
  Future<void> _testDirectQuery(String userId) async {
    try {
      print('Performing direct query for user: $userId');

      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('toilet_reports')
          .where('reporterId', isEqualTo: userId)
          .get();

      print('Direct query result: ${querySnapshot.docs.length} reports found');

      if (querySnapshot.docs.isEmpty) {
        print('No reports found in direct query');
      } else {
        for (var doc in querySnapshot.docs) {
          print('Report ID: ${doc.id}');
          print('Report data: ${doc.data()}');
        }
      }

      // Check if the collection exists and has documents
      QuerySnapshot allReports = await FirebaseFirestore.instance
          .collection('toilet_reports')
          .limit(5)
          .get();

      print(
          'Collection check: ${allReports.docs.length} total reports in collection');

      // Force refresh the UI
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error in test direct query: $e');
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'Critical':
        return Colors.red;
      case 'High':
        return Colors.orange;
      case 'Medium':
        return Colors.amber;
      case 'Low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _showReportDetails(DocumentSnapshot report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report for ${report['toiletName']}'),
        content: SingleChildScrollView(
          child: ListBody(
            children: [
              _buildReportDetailRow('Category', report['category']),
              _buildReportDetailRow('Issue', report['issue']),
              _buildReportDetailRow('Severity', report['severity']),
              _buildReportDetailRow('Status', report['status']),
              _buildReportDetailRow('Reported on',
                  report['timestamp']?.toDate().toString() ?? 'Unknown'),
              _buildReportDetailRow('Report ID', report.id),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Toilet Reports'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Report Issue'),
              Tab(text: 'My Reports'),
            ],
          ),
          actions: [
            if (_isLoadingLocation || _isLoadingToilets || _isLoadingReports)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: () {
                  // Check which tab is active
                  int currentIndex =
                      DefaultTabController.of(context)?.index ?? 0;
                  if (currentIndex == 0) {
                    _fetchAllToilets();
                  } else {
                    User? currentUser = FirebaseAuth.instance.currentUser;
                    if (currentUser != null) {
                      _testDirectQuery(currentUser.uid);
                    }
                  }
                },
              ),
          ],
        ),
        body: TabBarView(
          children: [
            // Report Issue Tab
            SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Error message if any
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // User info display (for debugging)
                  FutureBuilder<User?>(
                    future: Future.value(FirebaseAuth.instance.currentUser),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.account_circle,
                                  color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Logged in as: ${snapshot.data!.email} (${snapshot.data!.uid})',
                                  style: TextStyle(color: Colors.blue.shade700),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return Container();
                    },
                  ),

                  // Toilet Name Search with autocomplete
                  Column(
                    children: [
                      // Toilet Search Field
                      TextField(
                        controller: _toiletNameController,
                        decoration: InputDecoration(
                          labelText: 'Search Toilet',
                          hintText: 'Start typing toilet name...',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _toiletNameController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _toiletNameController.clear();
                                    setState(() {
                                      _selectedToilet = null;
                                    });
                                  },
                                )
                              : null,
                        ),
                        onTap: () {
                          setState(() {
                            _isSearching = true;
                          });
                        },
                      ),

                      // No toilets available message
                      if (_availableToilets.isEmpty && !_isLoadingToilets)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'No toilets available in the database',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ),

                      // Display search results
                      if (_isSearching && _filteredToilets.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(8),
                              bottomRight: Radius.circular(8),
                            ),
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.2),
                                spreadRadius: 1,
                                blurRadius: 2,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _filteredToilets.length,
                            itemBuilder: (context, index) {
                              final toilet = _filteredToilets[index];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  toilet.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(toilet.location),
                                trailing: toilet.distance != null
                                    ? Text(
                                        '${(toilet.distance! / 1000).toStringAsFixed(1)} km',
                                        style:
                                            TextStyle(color: Colors.blue[700]),
                                      )
                                    : null,
                                onTap: () => _selectToilet(toilet),
                              );
                            },
                          ),
                        ),

                      // No matching toilets message
                      if (_isSearching &&
                          _filteredToilets.isEmpty &&
                          _toiletNameController.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'No toilets match "${_toiletNameController.text}"',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ),

                      // Selected toilet indicator
                      if (_selectedToilet != null && !_isSearching)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Selected: ${_selectedToilet!.name}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text(_selectedToilet!.location),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _selectedToilet = null;
                                    _toiletNameController.clear();
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Issue Category Dropdown
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Issue Category',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                    value: _selectedCategory,
                    hint: const Text('Select Issue Category'),
                    items: _issueCategories
                        .map((category) => DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Issue Description TextField
                  TextField(
                    controller: _issueController,
                    decoration: const InputDecoration(
                      labelText: 'Describe the Specific Issue',
                      border: OutlineInputBorder(),
                      hintText:
                          'Provide detailed information about the problem',
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 4,
                    maxLength: 500,
                  ),
                  const SizedBox(height: 16),

                  // Severity Dropdown
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Severity',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.warning),
                    ),
                    value: _selectedSeverity,
                    hint: const Text('Select Severity Level'),
                    items: _severityLevels
                        .map((severity) => DropdownMenuItem(
                              value: severity,
                              child: Text(severity),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedSeverity = value;
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // Submit Button
                  ElevatedButton.icon(
                    onPressed: _submitReport,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.send),
                    label: const Text(
                      'Submit Issue Report',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),

            // My Reports Tab
            _buildReportsList(),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _toiletNameController.dispose();
    _issueController.dispose();
    super.dispose();
  }
}
