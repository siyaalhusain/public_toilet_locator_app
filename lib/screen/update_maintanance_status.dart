import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// Enhanced ToiletFacility to include more detailed status options
class ToiletFacility {
  final String id;
  final String name;
  bool isOperational;
  String?
      statusDetails; // Additional status details (e.g., "Needs repair", "Under maintenance")
  String? notes;
  DateTime lastUpdated;

  ToiletFacility({
    required this.id,
    required this.name,
    this.isOperational = true,
    this.statusDetails,
    this.notes,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isOperational': isOperational,
      'statusDetails': statusDetails,
      'notes': notes,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory ToiletFacility.fromJson(Map<String, dynamic> json) {
    return ToiletFacility(
      id: json['id'],
      name: json['name'],
      isOperational: json['isOperational'] ?? true,
      statusDetails: json['statusDetails'],
      notes: json['notes'],
      lastUpdated: DateTime.parse(json['lastUpdated']),
    );
  }
}

enum ToiletStatus { operational, limitedService, outOfService }

// Public Toilet Model
class PublicToilet {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  ToiletStatus status;
  DateTime lastMaintenanceDate;
  List<ToiletFacility> facilities;
  String? maintenanceNotes;
  List<String> imageUrls;
  bool isAssigned;
  String? ownerId;
  String? ownerEmail;

  // Added fields for operating hours
  TimeOfDay openingTime;
  TimeOfDay closingTime;
  bool is24Hours;
  List<bool>
      operatingDays; // For days of the week [Mon, Tue, Wed, Thu, Fri, Sat, Sun]

  // Features list
  Map<String, bool> features;

  PublicToilet({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.status = ToiletStatus.operational,
    required this.lastMaintenanceDate,
    required this.facilities,
    this.maintenanceNotes,
    this.imageUrls = const [],
    this.isAssigned = false,
    this.ownerId,
    this.ownerEmail,
    TimeOfDay? openingTime,
    TimeOfDay? closingTime,
    this.is24Hours = false,
    List<bool>? operatingDays,
    Map<String, bool>? features,
  })  : this.openingTime = openingTime ?? TimeOfDay(hour: 6, minute: 0),
        this.closingTime = closingTime ?? TimeOfDay(hour: 22, minute: 0),
        this.operatingDays = operatingDays ?? List.filled(7, true),
        this.features = features ??
            {
              'Accessible': false,
              'Baby Changing': false,
              'Showers': false,
              'Paid Entry': false,
              'Gender Neutral': false,
              'Family Room': false,
            };

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'status': status.toString().split('.').last,
      'lastMaintenanceDate': lastMaintenanceDate.toIso8601String(),
      'facilities': facilities.map((facility) => facility.toJson()).toList(),
      'maintenanceNotes': maintenanceNotes,
      'imageUrls': imageUrls,
      'isAssigned': isAssigned,
      'ownerId': ownerId,
      'ownerEmail': ownerEmail,
      'openingTime': '${openingTime.hour}:${openingTime.minute}',
      'closingTime': '${closingTime.hour}:${closingTime.minute}',
      'is24Hours': is24Hours,
      'operatingDays': operatingDays,
      'features': features,
    };
  }

  factory PublicToilet.fromJson(Map<String, dynamic> json) {
    // Parse time strings into TimeOfDay objects
    TimeOfDay parseTimeOfDay(String? timeString) {
      if (timeString == null) return TimeOfDay(hour: 0, minute: 0);
      final parts = timeString.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    }

    return PublicToilet(
      id: json['id'],
      name: json['name'],
      address: json['address'] ?? 'No address provided',
      latitude: json['latitude'] ?? 0.0,
      longitude: json['longitude'] ?? 0.0,
      status: ToiletStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => ToiletStatus.operational,
      ),
      lastMaintenanceDate: json['lastMaintenanceDate'] != null
          ? DateTime.parse(json['lastMaintenanceDate'])
          : DateTime.now(),
      facilities: json['facilities'] != null
          ? (json['facilities'] as List)
              .map((facilityJson) => ToiletFacility.fromJson(facilityJson))
              .toList()
          : [],
      maintenanceNotes: json['maintenanceNotes'],
      imageUrls: List<String>.from(json['imageUrls'] ?? []),
      isAssigned: json['isAssigned'] ?? false,
      ownerId: json['ownerId'],
      ownerEmail: json['ownerEmail'],
      openingTime: json['openingTime'] != null
          ? parseTimeOfDay(json['openingTime'])
          : TimeOfDay(hour: 6, minute: 0),
      closingTime: json['closingTime'] != null
          ? parseTimeOfDay(json['closingTime'])
          : TimeOfDay(hour: 22, minute: 0),
      is24Hours: json['is24Hours'] ?? false,
      operatingDays: json['operatingDays'] != null
          ? List<bool>.from(json['operatingDays'])
          : List.filled(7, true),
      features: json['features'] != null
          ? Map<String, bool>.from(json['features'])
          : {
              'Accessible': false,
              'Baby Changing': false,
              'Showers': false,
              'Paid Entry': false,
              'Gender Neutral': false,
              'Family Room': false,
            },
    );
  }

  // Helper method to determine status based on facilities
  void updateStatusBasedOnFacilities() {
    bool hasNonOperational =
        facilities.any((facility) => !facility.isOperational);

    if (facilities.every((facility) => !facility.isOperational)) {
      status = ToiletStatus.outOfService;
    } else if (hasNonOperational) {
      status = ToiletStatus.limitedService;
    } else {
      status = ToiletStatus.operational;
    }
  }

  // Format opening hours as a string
  String getFormattedHours() {
    if (is24Hours) {
      return "Open 24 hours";
    }

    final formatter = DateFormat('h:mm a');
    final now = DateTime.now();
    final openDateTime = DateTime(
        now.year, now.month, now.day, openingTime.hour, openingTime.minute);
    final closeDateTime = DateTime(
        now.year, now.month, now.day, closingTime.hour, closingTime.minute);

    return "${formatter.format(openDateTime)} - ${formatter.format(closeDateTime)}";
  }

  // Get day names for operating days
  List<String> getOperatingDays() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final operatingDayNames = <String>[];

    for (int i = 0; i < 7; i++) {
      if (operatingDays[i]) {
        operatingDayNames.add(days[i]);
      }
    }

    return operatingDayNames;
  }
}

// Firebase Service for Maintainer-specific toilets
class MaintainerToiletService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _cachedToiletsKey = 'maintainer_assigned_toilets';
  static const String _pendingUpdatesKey = 'pending_updates';

  // Get all toilets assigned to the current maintainer
  Future<List<PublicToilet>> getAssignedToilets() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      final toilets = <PublicToilet>[];

      // First try to get from Firestore
      try {
        // Query toilets where this maintainer is assigned
        QuerySnapshot toiletSnapshot = await _firestore
            .collection('toilets')
            .where('assignedMaintainer.id', isEqualTo: currentUser.uid)
            .get();

        if (toiletSnapshot.docs.isNotEmpty) {
          for (var doc in toiletSnapshot.docs) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

            // Add necessary properties for the PublicToilet constructor
            Map<String, dynamic> toiletData = {
              'id': doc.id,
              'name': data['name'] ?? 'Unnamed Toilet',
              'address': data['address'] ?? 'No address',
              'latitude':
                  data['location'] != null ? data['location']['latitude'] : 0.0,
              'longitude': data['location'] != null
                  ? data['location']['longitude']
                  : 0.0,
              'status': data['maintenanceStatus'] ?? 'operational',
              'lastMaintenanceDate': data['lastMaintenanceDate'] ??
                  DateTime.now().toIso8601String(),
              'maintenanceNotes': data['maintenanceNotes'],
              'isAssigned': true,
              'ownerId': data['ownerId'],
              'ownerEmail': data['ownerEmail'],
              'imageUrls': data['imageUrls'] ?? []
            };

            // Create default facilities if none exist
            if (!data.containsKey('facilities') || data['facilities'] == null) {
              toiletData['facilities'] = _getDefaultFacilities();
            } else {
              toiletData['facilities'] = data['facilities'];
            }

            toilets.add(PublicToilet.fromJson(toiletData));
          }

          // Cache the data for offline use
          await _cacheToilets(toilets);
          return toilets;
        }
      } catch (e) {
        print('Firebase fetch error: $e');
        // Continue to try cached data
      }

      // If online fetch fails or returns empty, try to get from cache
      return await _getCachedToilets();
    } catch (e) {
      print('Error in getAssignedToilets: $e');
      // Return empty list if all else fails
      return [];
    }
  }

  // Get a specific toilet by ID
  Future<PublicToilet?> getToiletById(String id) async {
    try {
      // Try to get from Firestore first
      final docSnapshot = await _firestore.collection('toilets').doc(id).get();

      if (docSnapshot.exists) {
        Map<String, dynamic> data = docSnapshot.data() as Map<String, dynamic>;

        // Add necessary properties for the PublicToilet constructor
        Map<String, dynamic> toiletData = {
          'id': docSnapshot.id,
          'name': data['name'] ?? 'Unnamed Toilet',
          'address': data['address'] ?? 'No address',
          'latitude':
              data['location'] != null ? data['location']['latitude'] : 0.0,
          'longitude':
              data['location'] != null ? data['location']['longitude'] : 0.0,
          'status': data['maintenanceStatus'] ?? 'operational',
          'lastMaintenanceDate':
              data['lastMaintenanceDate'] ?? DateTime.now().toIso8601String(),
          'maintenanceNotes': data['maintenanceNotes'],
          'isAssigned': true,
          'ownerId': data['ownerId'],
          'ownerEmail': data['ownerEmail'],
          'imageUrls': data['imageUrls'] ?? []
        };

        // Create default facilities if none exist
        if (!data.containsKey('facilities') || data['facilities'] == null) {
          toiletData['facilities'] = _getDefaultFacilities();
        } else {
          toiletData['facilities'] = data['facilities'];
        }

        return PublicToilet.fromJson(toiletData);
      } else {
        // If not found in Firestore, check local cache
        final cachedToilets = await _getCachedToilets();
        return cachedToilets.firstWhere(
          (toilet) => toilet.id == id,
          orElse: () => throw Exception('Toilet not found'),
        );
      }
    } catch (e) {
      print('Error in getToiletById: $e');
      try {
        // Try local cache as fallback
        final cachedToilets = await _getCachedToilets();
        return cachedToilets.firstWhere(
          (toilet) => toilet.id == id,
          orElse: () => throw Exception('Toilet not found'),
        );
      } catch (error) {
        return null;
      }
    }
  }

  // Update the maintenance status of a toilet
  Future<bool> updateToiletMaintenance(PublicToilet toilet) async {
    try {
      // Update locally first for immediate feedback
      final cachedToilets = await _getCachedToilets();
      final toiletIndex = cachedToilets.indexWhere((t) => t.id == toilet.id);

      if (toiletIndex >= 0) {
        cachedToilets[toiletIndex] = toilet;
        await _cacheToilets(cachedToilets);
      }

      // Determine the status string for Firestore
      String statusString;
      switch (toilet.status) {
        case ToiletStatus.operational:
          statusString = 'Operational';
          break;
        case ToiletStatus.limitedService:
          statusString = 'Limited Service';
          break;
        case ToiletStatus.outOfService:
          statusString = 'Out of Service';
          break;
      }

      // Then send to Firestore
      await _firestore.collection('toilets').doc(toilet.id).update({
        'maintenanceStatus': statusString,
        'lastMaintenanceDate': toilet.lastMaintenanceDate.toIso8601String(),
        'maintenanceNotes': toilet.maintenanceNotes,
        'facilities':
            toilet.facilities.map((facility) => facility.toJson()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Create maintenance record
      await _firestore.collection('maintenanceRecords').add({
        'toiletId': toilet.id,
        'toiletName': toilet.name,
        'maintainerId': _auth.currentUser?.uid,
        'maintainerEmail': _auth.currentUser?.email,
        'status': statusString,
        'notes': toilet.maintenanceNotes,
        'timestamp': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('Error updating toilet: $e');
      // If offline, store update in pending queue
      await _storePendingUpdate(toilet);
      return true; // Return true since we've saved it locally
    }
  }

  // Upload maintenance images
  Future<List<String>> uploadImages(String toiletId, List<File> images) async {
    try {
      final List<String> uploadedUrls = [];

      // In a real implementation, you would use Firebase Storage to upload images
      // For this example, we'll mock the upload process

      // Store images locally if offline
      await _storePendingImages(toiletId, images);

      // Return mock URLs
      for (var i = 0; i < images.length; i++) {
        uploadedUrls.add('https://example.com/toilet-image-$toiletId-$i.jpg');
      }

      return uploadedUrls;
    } catch (e) {
      print('Error uploading images: $e');
      return [];
    }
  }

  // Sync pending updates when back online
  Future<bool> syncPendingUpdates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingUpdatesJson = prefs.getString(_pendingUpdatesKey);

      if (pendingUpdatesJson == null) return true;

      final List<dynamic> pendingUpdates = json.decode(pendingUpdatesJson);
      bool allSuccessful = true;

      for (var update in pendingUpdates) {
        try {
          final toilet = PublicToilet.fromJson(update);
          final success = await updateToiletMaintenance(toilet);
          if (!success) {
            allSuccessful = false;
          }
        } catch (e) {
          print('Error syncing update: $e');
          allSuccessful = false;
        }
      }

      if (allSuccessful) {
        await prefs.remove(_pendingUpdatesKey);
      }

      return allSuccessful;
    } catch (e) {
      print('Error in syncPendingUpdates: $e');
      return false;
    }
  }

  // Cache toilets for offline mode
  Future<void> _cacheToilets(List<PublicToilet> toilets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toiletsJson = json.encode(
        toilets.map((toilet) => toilet.toJson()).toList(),
      );
      await prefs.setString(_cachedToiletsKey, toiletsJson);
    } catch (e) {
      print('Error caching toilets: $e');
    }
  }

  // Get cached toilets
  Future<List<PublicToilet>> _getCachedToilets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toiletsJson = prefs.getString(_cachedToiletsKey);

      if (toiletsJson != null) {
        final List<dynamic> decoded = json.decode(toiletsJson);
        return decoded.map((json) => PublicToilet.fromJson(json)).toList();
      }
    } catch (e) {
      print('Error getting cached toilets: $e');
    }
    return [];
  }

  // Store pending updates for offline mode
  Future<void> _storePendingUpdate(PublicToilet toilet) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingUpdatesJson = prefs.getString(_pendingUpdatesKey);

      List<Map<String, dynamic>> pendingUpdates = [];

      if (pendingUpdatesJson != null) {
        pendingUpdates =
            List<Map<String, dynamic>>.from(json.decode(pendingUpdatesJson));
      }

      // Check if this toilet already has a pending update
      final existingIndex = pendingUpdates.indexWhere(
        (update) => update['id'] == toilet.id,
      );

      if (existingIndex >= 0) {
        pendingUpdates[existingIndex] = toilet.toJson();
      } else {
        pendingUpdates.add(toilet.toJson());
      }

      await prefs.setString(_pendingUpdatesKey, json.encode(pendingUpdates));
    } catch (e) {
      print('Error storing pending update: $e');
    }
  }

  // Store pending images for offline sync
  Future<void> _storePendingImages(String toiletId, List<File> images) async {
    // In a real implementation, you would store references to local image files
    // that need to be uploaded when back online
    print('Storing ${images.length} pending images for toilet $toiletId');
  }

  // Get default facilities if none are defined
  List<Map<String, dynamic>> _getDefaultFacilities() {
    final now = DateTime.now().subtract(Duration(days: 7));
    return [
      {
        'id': 'facility-001',
        'name': 'Water Supply',
        'isOperational': true,
        'lastUpdated': now.toIso8601String(),
      },
      {
        'id': 'facility-002',
        'name': 'Hand Dryer',
        'isOperational': true,
        'lastUpdated': now.toIso8601String(),
      },
      {
        'id': 'facility-003',
        'name': 'Toilet Seats',
        'isOperational': true,
        'lastUpdated': now.toIso8601String(),
      },
      {
        'id': 'facility-004',
        'name': 'Washbasins',
        'isOperational': true,
        'lastUpdated': now.toIso8601String(),
      },
      {
        'id': 'facility-005',
        'name': 'Soap Dispensers',
        'isOperational': true,
        'lastUpdated': now.toIso8601String(),
      },
      {
        'id': 'facility-006',
        'name': 'Lights',
        'isOperational': true,
        'lastUpdated': now.toIso8601String(),
      },
    ];
  }
}

// Main Maintenance Status Update Page
class UpdateMaintenanceStatusPage extends StatefulWidget {
  final String? toiletId;

  const UpdateMaintenanceStatusPage({
    Key? key,
    this.toiletId,
  }) : super(key: key);

  @override
  _UpdateMaintenanceStatusPageState createState() =>
      _UpdateMaintenanceStatusPageState();
}

class _UpdateMaintenanceStatusPageState
    extends State<UpdateMaintenanceStatusPage> with TickerProviderStateMixin {
  final MaintainerToiletService _toiletService = MaintainerToiletService();
  final TextEditingController _notesController = TextEditingController();
  PublicToilet? _toilet;
  List<PublicToilet> _assignedToilets = [];
  List<File> _newImages = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isInitialized = false;

  late TabController _tabController;

  // Tabs for the page
  final List<String> _tabs = [
    'Status',
    'Facilities',
    'Hours',
    'Features',
    'Photos'
  ];

  // For maintainer role color theme
  final Color _primaryColor = Color(0xFFF57C00); // Deep Orange
  final Color _secondaryColor = Color(0xFFFFE0B2); // Light Orange
  final Color _accentColor = Color(0xFFFF9800); // Vibrant Orange
  final Color _textColor = Color(0xFFE65100); // Dark Orange
  final Color _backgroundColor = Color(0xFFFFF3E0); // Very Light Orange

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadAssignedToilets();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadAssignedToilets() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load all toilets assigned to this maintainer
      final toilets = await _toiletService.getAssignedToilets();

      if (mounted) {
        setState(() {
          _assignedToilets = toilets;
          _isLoading = false;
        });

        // If a specific toilet ID was provided, load that toilet
        if (widget.toiletId != null) {
          _loadSpecificToilet(widget.toiletId!);
        }
        // Otherwise, if we have assigned toilets, load the first one
        else if (_assignedToilets.isNotEmpty) {
          _loadToilet(_assignedToilets.first);
        } else {
          // No toilets found
          setState(() {
            _isInitialized = true;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No toilets assigned to you'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('Error loading assigned toilets: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialized = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading assigned toilets: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadSpecificToilet(String toiletId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Try to find the toilet in already loaded assigned toilets
      PublicToilet? toilet = _assignedToilets.firstWhere(
        (t) => t.id == toiletId,
        orElse: () => throw Exception('Toilet not found in assigned toilets'),
      );

      _loadToilet(toilet);
    } catch (e) {
      // If not found in assigned toilets, try to load it directly
      try {
        final toilet = await _toiletService.getToiletById(toiletId);
        if (toilet != null) {
          _loadToilet(toilet);
        } else {
          throw Exception('Toilet not found');
        }
      } catch (error) {
        print('Error loading specific toilet: $error');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isInitialized = true;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading toilet: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _loadToilet(PublicToilet toilet) {
    if (mounted) {
      setState(() {
        _toilet = toilet;
        _notesController.text = _toilet?.maintenanceNotes ?? '';
        _isLoading = false;
        _isInitialized = true;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedImage = await picker.pickImage(source: ImageSource.camera);

    if (pickedImage != null) {
      setState(() {
        _newImages.add(File(pickedImage.path));
      });
    }
  }

  Future<void> _saveChanges() async {
    if (_toilet == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Create a copy with the updated fields
      final updatedToilet = PublicToilet(
        id: _toilet!.id,
        name: _toilet!.name,
        address: _toilet!.address,
        latitude: _toilet!.latitude,
        longitude: _toilet!.longitude,
        status: _toilet!.status,
        lastMaintenanceDate: DateTime.now(), // Update to current time
        facilities: _toilet!.facilities,
        maintenanceNotes: _notesController.text,
        imageUrls: List.from(_toilet!.imageUrls),
        isAssigned: _toilet!.isAssigned,
        ownerId: _toilet!.ownerId,
        ownerEmail: _toilet!.ownerEmail,
        openingTime: _toilet!.openingTime,
        closingTime: _toilet!.closingTime,
        is24Hours: _toilet!.is24Hours,
        operatingDays: _toilet!.operatingDays,
        features: _toilet!.features,
      );

      // Update toilet status based on facility conditions
      updatedToilet.updateStatusBasedOnFacilities();

      // Upload new images if any
      if (_newImages.isNotEmpty) {
        final imageUrls = await _toiletService.uploadImages(
          updatedToilet.id,
          _newImages,
        );

        if (imageUrls.isNotEmpty) {
          updatedToilet.imageUrls.addAll(imageUrls);
        }
      }

      // Save changes to the toilet
      final success =
          await _toiletService.updateToiletMaintenance(updatedToilet);

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maintenance status updated successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Update the local toilet data
        setState(() {
          _toilet = updatedToilet;
          _newImages.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Changes saved offline and will sync when online'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('Error saving changes: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating maintenance status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _onToiletChanged(String? toiletId) {
    if (toiletId == null) return;

    final selectedToilet = _assignedToilets.firstWhere(
      (toilet) => toilet.id == toiletId,
      orElse: () => throw Exception('Toilet not found'),
    );

    _loadToilet(selectedToilet);
  }

  String _getStatusDisplayName(ToiletStatus status) {
    switch (status) {
      case ToiletStatus.operational:
        return 'Operational';
      case ToiletStatus.limitedService:
        return 'Limited Service';
      case ToiletStatus.outOfService:
        return 'Out of Service';
    }
  }

  Color _getStatusColor(ToiletStatus status) {
    switch (status) {
      case ToiletStatus.operational:
        return Colors.green;
      case ToiletStatus.limitedService:
        return Colors.orange;
      case ToiletStatus.outOfService:
        return Colors.red;
    }
  }

  // Convert TimeOfDay to formatted string
  String _formatTimeOfDay(TimeOfDay timeOfDay) {
    final now = DateTime.now();
    final dt = DateTime(
        now.year, now.month, now.day, timeOfDay.hour, timeOfDay.minute);
    final format = DateFormat.jm(); // 6:00 AM format
    return format.format(dt);
  }

  // Format day name
  String _getDayName(int index) {
    final days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return days[index];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        title: Text(
          'Update Toilet Information',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_isSaving)
            Container(
              margin: const EdgeInsets.all(14),
              width: 20,
              height: 20,
              child: const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          else
            IconButton(
              icon: const Icon(
                Icons.save_rounded,
                color: Colors.white,
              ),
              onPressed: _toilet != null ? _saveChanges : null,
              tooltip: 'Save changes',
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: _primaryColor,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading toilet data...',
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : !_isInitialized || _assignedToilets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 64,
                        color: _primaryColor,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No toilets assigned to you',
                        style: TextStyle(
                          color: _textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Contact the toilet owner to get assignments',
                        style: TextStyle(
                          color: _textColor.withOpacity(0.7),
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadAssignedToilets,
                        icon: Icon(Icons.refresh),
                        label: Text('Refresh Assignments'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          padding: EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Toilet selector dropdown
                    if (_assignedToilets.length > 1)
                      Container(
                        color: Colors.white,
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'Select Toilet',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.wc),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 0),
                          ),
                          value: _toilet?.id,
                          items: _assignedToilets.map((toilet) {
                            return DropdownMenuItem<String>(
                              value: toilet.id,
                              child: Text(
                                toilet.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: _onToiletChanged,
                        ),
                      ),

                    // Main content with selected toilet
                    if (_toilet != null) Expanded(child: _buildMainContent()),
                  ],
                ),
      bottomNavigationBar: _toilet == null || _isLoading
          ? null
          : Container(
              color: Colors.white,
              padding: EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
                child: _isSaving
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'SAVING...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'SAVE TOILET INFORMATION',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
    );
  }

  Widget _buildMainContent() {
    if (_toilet == null) return Container();

    return Column(
      children: [
        // Toilet info card
        _buildToiletInfoCard(),

        // Tabs for different sections
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 3,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: _tabs.map((tab) => Tab(text: tab)).toList(),
            labelColor: _primaryColor,
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: _primaryColor,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverallStatusSection(), // Status tab
              _buildFacilitiesSection(), // Facilities tab
              _buildOperatingHoursSection(), // Hours tab
              _buildFeaturesSection(), // Features tab
              _buildPhotoDocumentationSection(), // Photos tab
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToiletInfoCard() {
    if (_toilet == null) return Container();

    return Container(
      padding: EdgeInsets.all(16),
      margin: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            spreadRadius: 0,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status indicator
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(_toilet!.status).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _getStatusColor(_toilet!.status),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _toilet!.status == ToiletStatus.operational
                          ? Icons.check_circle
                          : _toilet!.status == ToiletStatus.limitedService
                              ? Icons.warning
                              : Icons.error,
                      size: 16,
                      color: _getStatusColor(_toilet!.status),
                    ),
                    SizedBox(width: 4),
                    Text(
                      _getStatusDisplayName(_toilet!.status),
                      style: TextStyle(
                        color: _getStatusColor(_toilet!.status),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(width: 8),

              // Last maintenance date
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Colors.grey[700],
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Last: ${DateFormat('MMM d, yyyy').format(_toilet!.lastMaintenanceDate)}',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: 12),

          // Toilet name
          Text(
            _toilet!.name,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),

          SizedBox(height: 4),

          // Address
          Row(
            children: [
              Icon(
                Icons.location_on,
                size: 16,
                color: Colors.grey[600],
              ),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  _toilet!.address,
                  style: TextStyle(
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          SizedBox(height: 8),

          // Owner info if available
          if (_toilet!.ownerEmail != null)
            Row(
              children: [
                Icon(
                  Icons.person,
                  size: 16,
                  color: Colors.grey[600],
                ),
                SizedBox(width: 4),
                Text(
                  'Owner: ${_toilet!.ownerEmail}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),

          SizedBox(height: 8),

          // Operating hours summary
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: 16,
                color: Colors.grey[600],
              ),
              SizedBox(width: 4),
              Text(
                _toilet!.is24Hours
                    ? 'Open 24 hours'
                    : _toilet!.getFormattedHours(),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverallStatusSection() {
    if (_toilet == null) return Container();

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current Status Card
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getStatusColor(_toilet!.status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _getStatusColor(_toilet!.status).withOpacity(0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Status',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 12),

                // Status options
                Wrap(
                  spacing: 8,
                  children: [
                    _buildStatusOption(
                      status: ToiletStatus.operational,
                      icon: Icons.check_circle,
                      label: 'Operational',
                    ),
                    _buildStatusOption(
                      status: ToiletStatus.limitedService,
                      icon: Icons.warning,
                      label: 'Limited Service',
                    ),
                    _buildStatusOption(
                      status: ToiletStatus.outOfService,
                      icon: Icons.error,
                      label: 'Out of Service',
                    ),
                  ],
                ),

                SizedBox(height: 16),

                // Status description
                Text(
                  _toilet!.status == ToiletStatus.operational
                      ? 'All facilities are working properly.'
                      : _toilet!.status == ToiletStatus.limitedService
                          ? 'Some facilities have issues but the toilet is usable.'
                          : 'The toilet is currently not usable.',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 20),

          // Maintenance Notes
          Text(
            'Maintenance Notes',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 8),
          TextFormField(
            controller: _notesController,
            decoration: InputDecoration(
              hintText: 'Enter notes about maintenance performed...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            maxLines: 4,
          ),

          SizedBox(height: 20),

          // Last Maintenance Info
          Text(
            'Last Maintenance',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: _primaryColor),
                    SizedBox(width: 8),
                    Text(
                      'Date: ${DateFormat('MMMM d, yyyy').format(_toilet!.lastMaintenanceDate)}',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (_toilet!.maintenanceNotes != null &&
                    _toilet!.maintenanceNotes!.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Previous Notes:',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[700],
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          _toilet!.maintenanceNotes!,
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusOption({
    required ToiletStatus status,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _toilet!.status == status;
    final color = _getStatusColor(status);

    return InkWell(
      onTap: () {
        setState(() {
          if (_toilet != null) {
            final updatedToilet = PublicToilet(
              id: _toilet!.id,
              name: _toilet!.name,
              address: _toilet!.address,
              latitude: _toilet!.latitude,
              longitude: _toilet!.longitude,
              status: status,
              lastMaintenanceDate: _toilet!.lastMaintenanceDate,
              facilities: _toilet!.facilities,
              maintenanceNotes: _toilet!.maintenanceNotes,
              imageUrls: _toilet!.imageUrls,
              isAssigned: _toilet!.isAssigned,
              ownerId: _toilet!.ownerId,
              ownerEmail: _toilet!.ownerEmail,
              openingTime: _toilet!.openingTime,
              closingTime: _toilet!.closingTime,
              is24Hours: _toilet!.is24Hours,
              operatingDays: _toilet!.operatingDays,
              features: _toilet!.features,
            );
            _toilet = updatedToilet;
          }
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.grey[400]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? color : Colors.grey[600],
            ),
            SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey[800],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (isSelected)
              Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.check,
                  size: 16,
                  color: color,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFacilitiesSection() {
    if (_toilet == null) return Container();

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Facilities Status',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 16),

          // Facilities list
          ..._toilet!.facilities
              .map((facility) => _buildFacilityItem(facility))
              .toList(),

          // Add facility button
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: OutlinedButton.icon(
              onPressed: _showAddFacilityDialog,
              icon: Icon(Icons.add),
              label: Text('Add Facility'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryColor,
                side: BorderSide(color: _primaryColor),
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFacilityItem(ToiletFacility facility) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: facility.isOperational ? Colors.green[100]! : Colors.red[100]!,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Facility name
                Expanded(
                  child: Text(
                    facility.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),

                // Operational toggle
                Switch(
                  value: facility.isOperational,
                  onChanged: (value) {
                    setState(() {
                      // Update the facility status
                      final index = _toilet!.facilities.indexOf(facility);
                      if (index >= 0) {
                        _toilet!.facilities[index] = ToiletFacility(
                          id: facility.id,
                          name: facility.name,
                          isOperational: value,
                          statusDetails: facility.statusDetails,
                          notes: facility.notes,
                          lastUpdated: DateTime.now(),
                        );

                        // Update overall toilet status
                        _toilet!.updateStatusBasedOnFacilities();
                      }
                    });
                  },
                  activeColor: Colors.green,
                  activeTrackColor: Colors.green[100],
                ),
              ],
            ),

            SizedBox(height: 8),

            // Operational status
            Row(
              children: [
                Icon(
                  facility.isOperational ? Icons.check_circle : Icons.error,
                  color: facility.isOperational ? Colors.green : Colors.red,
                  size: 16,
                ),
                SizedBox(width: 6),
                Text(
                  facility.isOperational ? 'Operational' : 'Not Operational',
                  style: TextStyle(
                    color: facility.isOperational ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            // Status details if any
            if (facility.statusDetails != null &&
                facility.statusDetails!.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        facility.statusDetails!,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            SizedBox(height: 8),

            // Last updated date
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Last updated: ${DateFormat('MMM d, yyyy').format(facility.lastUpdated)}',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            // Edit and delete buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showEditFacilityDialog(facility),
                  icon: Icon(Icons.edit, size: 16),
                  label: Text('Edit'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                    padding: EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showDeleteFacilityConfirmation(facility),
                  icon: Icon(Icons.delete, size: 16),
                  label: Text('Delete'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddFacilityDialog() {
    final nameController = TextEditingController();
    final detailsController = TextEditingController();
    bool isOperational = true;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add New Facility'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Facility Name',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              StatefulBuilder(
                builder: (context, setState) => Row(
                  children: [
                    Text('Operational: '),
                    Switch(
                      value: isOperational,
                      onChanged: (value) {
                        setState(() {
                          isOperational = value;
                        });
                      },
                      activeColor: Colors.green,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: detailsController,
                decoration: InputDecoration(
                  labelText: 'Status Details (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Validate
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Facility name is required')),
                );
                return;
              }

              // Add the new facility
              setState(() {
                if (_toilet != null) {
                  _toilet!.facilities.add(
                    ToiletFacility(
                      id: 'facility-${DateTime.now().millisecondsSinceEpoch}',
                      name: nameController.text.trim(),
                      isOperational: isOperational,
                      statusDetails: detailsController.text.trim().isNotEmpty
                          ? detailsController.text.trim()
                          : null,
                      lastUpdated: DateTime.now(),
                    ),
                  );

                  // Update overall toilet status
                  _toilet!.updateStatusBasedOnFacilities();
                }
              });

              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
            child: Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditFacilityDialog(ToiletFacility facility) {
    final nameController = TextEditingController(text: facility.name);
    final detailsController =
        TextEditingController(text: facility.statusDetails ?? '');
    bool isOperational = facility.isOperational;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Facility'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Facility Name',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              StatefulBuilder(
                builder: (context, setState) => Row(
                  children: [
                    Text('Operational: '),
                    Switch(
                      value: isOperational,
                      onChanged: (value) {
                        setState(() {
                          isOperational = value;
                        });
                      },
                      activeColor: Colors.green,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: detailsController,
                decoration: InputDecoration(
                  labelText: 'Status Details (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Validate
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Facility name is required')),
                );
                return;
              }

              // Update the facility
              setState(() {
                if (_toilet != null) {
                  final index = _toilet!.facilities.indexOf(facility);
                  if (index >= 0) {
                    _toilet!.facilities[index] = ToiletFacility(
                      id: facility.id,
                      name: nameController.text.trim(),
                      isOperational: isOperational,
                      statusDetails: detailsController.text.trim().isNotEmpty
                          ? detailsController.text.trim()
                          : null,
                      notes: facility.notes,
                      lastUpdated: DateTime.now(),
                    );

                    // Update overall toilet status
                    _toilet!.updateStatusBasedOnFacilities();
                  }
                }
              });

              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteFacilityConfirmation(ToiletFacility facility) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Facility?'),
        content: Text(
            'Are you sure you want to delete "${facility.name}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                if (_toilet != null) {
                  _toilet!.facilities.removeWhere((f) => f.id == facility.id);

                  // Update overall toilet status
                  _toilet!.updateStatusBasedOnFacilities();
                }
              });

              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Facility "${facility.name}" deleted'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildOperatingHoursSection() {
    if (_toilet == null) return Container();

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Operating Hours',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 16),

          // 24 hours toggle
          Card(
            margin: EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '24-Hour Operation',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Toggle if this toilet is open 24 hours a day',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _toilet!.is24Hours,
                    onChanged: (value) {
                      setState(() {
                        final updatedToilet = PublicToilet(
                          id: _toilet!.id,
                          name: _toilet!.name,
                          address: _toilet!.address,
                          latitude: _toilet!.latitude,
                          longitude: _toilet!.longitude,
                          status: _toilet!.status,
                          lastMaintenanceDate: _toilet!.lastMaintenanceDate,
                          facilities: _toilet!.facilities,
                          maintenanceNotes: _toilet!.maintenanceNotes,
                          imageUrls: _toilet!.imageUrls,
                          isAssigned: _toilet!.isAssigned,
                          ownerId: _toilet!.ownerId,
                          ownerEmail: _toilet!.ownerEmail,
                          openingTime: _toilet!.openingTime,
                          closingTime: _toilet!.closingTime,
                          is24Hours: value,
                          operatingDays: _toilet!.operatingDays,
                          features: _toilet!.features,
                        );
                        _toilet = updatedToilet;
                      });
                    },
                    activeColor: _primaryColor,
                  ),
                ],
              ),
            ),
          ),

          // Opening Hours (only if not 24 hours)
          if (!_toilet!.is24Hours)
            Card(
              margin: EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Opening Hours',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectTimeOfDay(true),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Opening Time',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                prefixIcon: Icon(Icons.access_time),
                              ),
                              child:
                                  Text(_formatTimeOfDay(_toilet!.openingTime)),
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectTimeOfDay(false),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Closing Time',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                prefixIcon: Icon(Icons.access_time),
                              ),
                              child:
                                  Text(_formatTimeOfDay(_toilet!.closingTime)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Operating Days Section
          Card(
            margin: EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Operating Days',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 12),
                  ...List.generate(7, (index) {
                    return CheckboxListTile(
                      title: Text(_getDayName(index)),
                      value: _toilet!.operatingDays.length > index
                          ? _toilet!.operatingDays[index]
                          : true,
                      onChanged: (value) {
                        setState(() {
                          final newOperatingDays =
                              List<bool>.from(_toilet!.operatingDays);
                          if (newOperatingDays.length <= index) {
                            newOperatingDays.addAll(List.filled(
                                index + 1 - newOperatingDays.length, true));
                          }
                          newOperatingDays[index] = value!;

                          final updatedToilet = PublicToilet(
                            id: _toilet!.id,
                            name: _toilet!.name,
                            address: _toilet!.address,
                            latitude: _toilet!.latitude,
                            longitude: _toilet!.longitude,
                            status: _toilet!.status,
                            lastMaintenanceDate: _toilet!.lastMaintenanceDate,
                            facilities: _toilet!.facilities,
                            maintenanceNotes: _toilet!.maintenanceNotes,
                            imageUrls: _toilet!.imageUrls,
                            isAssigned: _toilet!.isAssigned,
                            ownerId: _toilet!.ownerId,
                            ownerEmail: _toilet!.ownerEmail,
                            openingTime: _toilet!.openingTime,
                            closingTime: _toilet!.closingTime,
                            is24Hours: _toilet!.is24Hours,
                            operatingDays: newOperatingDays,
                            features: _toilet!.features,
                          );
                          _toilet = updatedToilet;
                        });
                      },
                      activeColor: _primaryColor,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.trailing,
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectTimeOfDay(bool isOpeningTime) async {
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: isOpeningTime ? _toilet!.openingTime : _toilet!.closingTime,
    );

    if (selectedTime != null) {
      setState(() {
        final updatedToilet = PublicToilet(
          id: _toilet!.id,
          name: _toilet!.name,
          address: _toilet!.address,
          latitude: _toilet!.latitude,
          longitude: _toilet!.longitude,
          status: _toilet!.status,
          lastMaintenanceDate: _toilet!.lastMaintenanceDate,
          facilities: _toilet!.facilities,
          maintenanceNotes: _toilet!.maintenanceNotes,
          imageUrls: _toilet!.imageUrls,
          isAssigned: _toilet!.isAssigned,
          ownerId: _toilet!.ownerId,
          ownerEmail: _toilet!.ownerEmail,
          openingTime: isOpeningTime ? selectedTime : _toilet!.openingTime,
          closingTime: isOpeningTime ? _toilet!.closingTime : selectedTime,
          is24Hours: _toilet!.is24Hours,
          operatingDays: _toilet!.operatingDays,
          features: _toilet!.features,
        );
        _toilet = updatedToilet;
      });
    }
  }

  Widget _buildFeaturesSection() {
    if (_toilet == null) return Container();

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Toilet Features',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 16),

          // Features Grid
          GridView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _toilet!.features.length,
            itemBuilder: (context, index) {
              final feature = _toilet!.features.entries.elementAt(index);
              return _buildFeatureItem(feature.key, feature.value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String featureName, bool hasFeature) {
    IconData featureIcon;
    switch (featureName) {
      case 'Accessible':
        featureIcon = Icons.accessible;
        break;
      case 'Baby Changing':
        featureIcon = Icons.baby_changing_station;
        break;
      case 'Showers':
        featureIcon = Icons.shower;
        break;
      case 'Paid Entry':
        featureIcon = Icons.monetization_on;
        break;
      case 'Gender Neutral':
        featureIcon = Icons.wc;
        break;
      case 'Family Room':
        featureIcon = Icons.family_restroom;
        break;
      default:
        featureIcon = Icons.check_box;
    }

    return InkWell(
      onTap: () {
        setState(() {
          if (_toilet != null) {
            final updatedFeatures = Map<String, bool>.from(_toilet!.features);
            updatedFeatures[featureName] = !hasFeature;

            final updatedToilet = PublicToilet(
              id: _toilet!.id,
              name: _toilet!.name,
              address: _toilet!.address,
              latitude: _toilet!.latitude,
              longitude: _toilet!.longitude,
              status: _toilet!.status,
              lastMaintenanceDate: _toilet!.lastMaintenanceDate,
              facilities: _toilet!.facilities,
              maintenanceNotes: _toilet!.maintenanceNotes,
              imageUrls: _toilet!.imageUrls,
              isAssigned: _toilet!.isAssigned,
              ownerId: _toilet!.ownerId,
              ownerEmail: _toilet!.ownerEmail,
              openingTime: _toilet!.openingTime,
              closingTime: _toilet!.closingTime,
              is24Hours: _toilet!.is24Hours,
              operatingDays: _toilet!.operatingDays,
              features: updatedFeatures,
            );
            _toilet = updatedToilet;
          }
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasFeature ? _primaryColor.withOpacity(0.2) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasFeature ? _primaryColor : Colors.grey[400]!,
          ),
        ),
        child: Row(
          children: [
            Icon(
              featureIcon,
              size: 20,
              color: hasFeature ? _primaryColor : Colors.grey[600],
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                featureName,
                style: TextStyle(
                  color: hasFeature ? _primaryColor : Colors.grey[800],
                  fontWeight: hasFeature ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoDocumentationSection() {
    if (_toilet == null) return Container();

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Photo Documentation',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 16),

          // Existing photos
          if (_toilet!.imageUrls.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Existing Photos',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _toilet!.imageUrls.length,
                  itemBuilder: (context, index) {
                    final imageUrl = _toilet!.imageUrls[index];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey[300],
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.grey[600],
                                  size: 40,
                                ),
                              );
                            },
                          ),
                          Positioned(
                            right: 4,
                            top: 4,
                            child: InkWell(
                              onTap: () => _showDeleteImageConfirmation(index),
                              child: Container(
                                padding: EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.delete,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                SizedBox(height: 24),
              ],
            ),

          // New photos
          if (_newImages.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New Photos (Not Yet Saved)',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _newImages.length,
                  itemBuilder: (context, index) {
                    final image = _newImages[index];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            image,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey[300],
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.grey[600],
                                  size: 40,
                                ),
                              );
                            },
                          ),
                          Positioned(
                            right: 4,
                            top: 4,
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _newImages.removeAt(index)),
                              child: Container(
                                padding: EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.delete,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 4,
                            top: 4,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _primaryColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'New',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                SizedBox(height: 24),
              ],
            ),

          // Add photo button
          Center(
            child: ElevatedButton.icon(
              onPressed: _pickImage,
              icon: Icon(Icons.add_a_photo),
              label: Text('Add New Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          SizedBox(height: 8),

          // Information text
          Center(
            child: Text(
              'Photos will be saved when you click "Save" button',
              style: TextStyle(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteImageConfirmation(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Photo?'),
        content: Text(
            'Are you sure you want to delete this photo? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                if (_toilet != null) {
                  // Remove the image URL at this index
                  final updatedImageUrls =
                      List<String>.from(_toilet!.imageUrls);
                  updatedImageUrls.removeAt(index);

                  final updatedToilet = PublicToilet(
                    id: _toilet!.id,
                    name: _toilet!.name,
                    address: _toilet!.address,
                    latitude: _toilet!.latitude,
                    longitude: _toilet!.longitude,
                    status: _toilet!.status,
                    lastMaintenanceDate: _toilet!.lastMaintenanceDate,
                    facilities: _toilet!.facilities,
                    maintenanceNotes: _toilet!.maintenanceNotes,
                    imageUrls: updatedImageUrls,
                    isAssigned: _toilet!.isAssigned,
                    ownerId: _toilet!.ownerId,
                    ownerEmail: _toilet!.ownerEmail,
                    openingTime: _toilet!.openingTime,
                    closingTime: _toilet!.closingTime,
                    is24Hours: _toilet!.is24Hours,
                    operatingDays: _toilet!.operatingDays,
                    features: _toilet!.features,
                  );
                  _toilet = updatedToilet;
                }
              });

              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Photo deleted'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }
}
