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
  String? statusDetails;
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

enum ToiletStatus { operational, outOfService }

class MaintenanceRecord {
  final String id;
  final String toiletId;
  final String toiletName;
  final String? maintainerId;
  final String? maintainerEmail;
  final String status;
  final List<ToiletFacility> facilities;
  final Map<String, bool> features;
  final bool is24Hours;
  final TimeOfDay openingTime;
  final TimeOfDay closingTime;
  final List<bool> operatingDays;
  final List<String> imageUrls;
  final DateTime timestamp;

  MaintenanceRecord({
    required this.id,
    required this.toiletId,
    required this.toiletName,
    this.maintainerId,
    this.maintainerEmail,
    required this.status,
    required this.facilities,
    required this.features,
    required this.is24Hours,
    required this.openingTime,
    required this.closingTime,
    required this.operatingDays,
    required this.imageUrls,
    required this.timestamp,
  });

  factory MaintenanceRecord.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    TimeOfDay parseTimeOfDay(String timeString) {
      final parts = timeString.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    return MaintenanceRecord(
      id: doc.id,
      toiletId: data['toiletId'],
      toiletName: data['toiletName'],
      maintainerId: data['maintainerId'],
      maintainerEmail: data['maintainerEmail'],
      status: data['status'],
      facilities: (data['facilities'] as List)
          .map((f) => ToiletFacility.fromJson(f))
          .toList(),
      features: Map<String, bool>.from(data['features'] ?? {}),
      is24Hours: data['operatingHours']['is24Hours'] ?? false,
      openingTime:
          parseTimeOfDay(data['operatingHours']['openingTime'] ?? '6:00'),
      closingTime:
          parseTimeOfDay(data['operatingHours']['closingTime'] ?? '22:00'),
      operatingDays: List<bool>.from(
          data['operatingHours']['operatingDays'] ?? List.filled(7, true)),
      imageUrls: List<String>.from(data['imageUrls'] ?? []),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
    );
  }
}

class PublicToilet {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  ToiletStatus status;
  DateTime lastMaintenanceDate;
  List<ToiletFacility> facilities;
  List<String> imageUrls;
  bool isAssigned;
  String? ownerId;
  String? ownerEmail;
  TimeOfDay openingTime;
  TimeOfDay closingTime;
  bool is24Hours;
  List<bool> operatingDays;
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
            },
    );
  }

  void updateStatusBasedOnFacilities() {
    bool hasNonOperational =
        facilities.any((facility) => !facility.isOperational);
    status = hasNonOperational
        ? ToiletStatus.outOfService
        : ToiletStatus.operational;
  }

  String getFormattedHours() {
    if (is24Hours) return "Open 24 hours";
    final formatter = DateFormat('h:mm a');
    final now = DateTime.now();
    final openDateTime = DateTime(
        now.year, now.month, now.day, openingTime.hour, openingTime.minute);
    final closeDateTime = DateTime(
        now.year, now.month, now.day, closingTime.hour, closingTime.minute);
    return "${formatter.format(openDateTime)} - ${formatter.format(closeDateTime)}";
  }
}

class MaintainerToiletService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _cachedToiletsKey = 'maintainer_assigned_toilets';

  Future<MaintenanceRecord?> getMaintenanceRecord(String toiletId) async {
    try {
      final querySnapshot = await _firestore
          .collection('maintenanceRecords')
          .where('toiletId', isEqualTo: toiletId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return MaintenanceRecord.fromFirestore(querySnapshot.docs.first);
      }
      return null;
    } catch (e) {
      print('Error getting maintenance record: $e');
      return null;
    }
  }

  Future<List<PublicToilet>> getAssignedToilets() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('User not logged in');

      final toilets = <PublicToilet>[];
      QuerySnapshot toiletSnapshot = await _firestore
          .collection('toilets')
          .where('assignedMaintainer.id', isEqualTo: currentUser.uid)
          .get();

      for (var doc in toiletSnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        Map<String, dynamic> toiletData = {
          'id': doc.id,
          'name': data['name'] ?? 'Unnamed Toilet',
          'address': data['address'] ?? 'No address',
          'latitude':
              data['location'] != null ? data['location']['latitude'] : 0.0,
          'longitude':
              data['location'] != null ? data['location']['longitude'] : 0.0,
          'status': data['maintenanceStatus'] ?? 'operational',
          'lastMaintenanceDate':
              data['lastMaintenanceDate'] ?? DateTime.now().toIso8601String(),
          'isAssigned': true,
          'ownerId': data['ownerId'],
          'ownerEmail': data['ownerEmail'],
          'imageUrls': data['imageUrls'] ?? []
        };

        if (!data.containsKey('facilities') || data['facilities'] == null) {
          toiletData['facilities'] = _getDefaultFacilities();
        } else {
          toiletData['facilities'] = data['facilities'];
        }

        toilets.add(PublicToilet.fromJson(toiletData));
      }

      await _cacheToilets(toilets);
      return toilets;
    } catch (e) {
      print('Error in getAssignedToilets: $e');
      return await _getCachedToilets();
    }
  }

  Future<PublicToilet?> getToiletById(String id) async {
    try {
      final docSnapshot = await _firestore.collection('toilets').doc(id).get();
      if (docSnapshot.exists) {
        Map<String, dynamic> data = docSnapshot.data() as Map<String, dynamic>;
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
          'isAssigned': true,
          'ownerId': data['ownerId'],
          'ownerEmail': data['ownerEmail'],
          'imageUrls': data['imageUrls'] ?? []
        };

        if (!data.containsKey('facilities') || data['facilities'] == null) {
          toiletData['facilities'] = _getDefaultFacilities();
        } else {
          toiletData['facilities'] = data['facilities'];
        }

        return PublicToilet.fromJson(toiletData);
      }
      return null;
    } catch (e) {
      print('Error in getToiletById: $e');
      return null;
    }
  }

  Future<bool> updateToiletMaintenance(PublicToilet toilet) async {
    try {
      String statusString = toilet.status == ToiletStatus.operational
          ? 'Operational'
          : 'Out of Service';

      // First update the toilet document
      await _firestore.collection('toilets').doc(toilet.id).update({
        'maintenanceStatus': statusString,
        'lastMaintenanceDate': toilet.lastMaintenanceDate.toIso8601String(),
        'facilities':
            toilet.facilities.map((facility) => facility.toJson()).toList(),
        'imageUrls': toilet.imageUrls,
        'openingTime':
            '${toilet.openingTime.hour}:${toilet.openingTime.minute}',
        'closingTime':
            '${toilet.closingTime.hour}:${toilet.closingTime.minute}',
        'is24Hours': toilet.is24Hours,
        'operatingDays': toilet.operatingDays,
        'features': toilet.features,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Check if a maintenance record already exists for this toilet
      final querySnapshot = await _firestore
          .collection('maintenanceRecords')
          .where('toiletId', isEqualTo: toilet.id)
          .limit(1)
          .get();

      final maintenanceData = {
        'toiletId': toilet.id,
        'toiletName': toilet.name,
        'maintainerId': _auth.currentUser?.uid,
        'maintainerEmail': _auth.currentUser?.email,
        'status': statusString,
        'facilities': toilet.facilities.map((f) => f.toJson()).toList(),
        'features': toilet.features,
        'operatingHours': {
          'is24Hours': toilet.is24Hours,
          'openingTime':
              '${toilet.openingTime.hour}:${toilet.openingTime.minute}',
          'closingTime':
              '${toilet.closingTime.hour}:${toilet.closingTime.minute}',
          'operatingDays': toilet.operatingDays,
        },
        'imageUrls': toilet.imageUrls,
        'lastUpdated': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
      };

      if (querySnapshot.docs.isNotEmpty) {
        // Update existing record
        await _firestore
            .collection('maintenanceRecords')
            .doc(querySnapshot.docs.first.id)
            .update(maintenanceData);
      } else {
        // Create new record
        await _firestore.collection('maintenanceRecords').add(maintenanceData);
      }

      return true;
    } catch (e) {
      print('Error updating toilet: $e');
      return false;
    }
  }

  Future<List<String>> uploadImages(String toiletId, List<File> images) async {
    // In a real implementation, upload to Firebase Storage
    // For demo purposes, we'll return mock URLs
    return List.generate(images.length,
        (index) => 'https://example.com/toilet-image-$toiletId-$index.jpg');
  }

  Future<void> _cacheToilets(List<PublicToilet> toilets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toiletsJson =
          json.encode(toilets.map((toilet) => toilet.toJson()).toList());
      await prefs.setString(_cachedToiletsKey, toiletsJson);
    } catch (e) {
      print('Error caching toilets: $e');
    }
  }

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

  List<Map<String, dynamic>> _getDefaultFacilities() {
    final now = DateTime.now().subtract(Duration(days: 7));
    return [
      {
        'id': 'facility-001',
        'name': 'Water Supply',
        'isOperational': true,
        'lastUpdated': now.toIso8601String()
      },
      {
        'id': 'facility-002',
        'name': 'Hand Dryer',
        'isOperational': true,
        'lastUpdated': now.toIso8601String()
      },
      {
        'id': 'facility-003',
        'name': 'Toilet Seats',
        'isOperational': true,
        'lastUpdated': now.toIso8601String()
      },
      {
        'id': 'facility-004',
        'name': 'Washbasins',
        'isOperational': true,
        'lastUpdated': now.toIso8601String()
      },
      {
        'id': 'facility-005',
        'name': 'Soap Dispensers',
        'isOperational': true,
        'lastUpdated': now.toIso8601String()
      },
      {
        'id': 'facility-006',
        'name': 'Lights',
        'isOperational': true,
        'lastUpdated': now.toIso8601String()
      },
    ];
  }
}

class UpdateMaintenanceStatusPage extends StatefulWidget {
  final String? toiletId;

  const UpdateMaintenanceStatusPage({Key? key, this.toiletId})
      : super(key: key);

  @override
  _UpdateMaintenanceStatusPageState createState() =>
      _UpdateMaintenanceStatusPageState();
}

class _UpdateMaintenanceStatusPageState
    extends State<UpdateMaintenanceStatusPage> {
  final MaintainerToiletService _toiletService = MaintainerToiletService();
  PublicToilet? _toilet;
  List<PublicToilet> _assignedToilets = [];
  List<File> _newImages = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isInitialized = false;

  final Color _primaryColor = Color(0xFFF57C00);
  final Color _secondaryColor = Color(0xFFFFE0B2);
  final Color _accentColor = Color(0xFFFF9800);
  final Color _textColor = Color(0xFFE65100);
  final Color _backgroundColor = Color(0xFFFFF3E0);

  @override
  void initState() {
    super.initState();
    _loadAssignedToilets();
  }

  Future<void> _loadAssignedToilets() async {
    setState(() => _isLoading = true);
    try {
      final toilets = await _toiletService.getAssignedToilets();
      setState(() => _assignedToilets = toilets);

      if (widget.toiletId != null) {
        _loadSpecificToilet(widget.toiletId!);
      } else if (_assignedToilets.isNotEmpty) {
        _loadToilet(_assignedToilets.first);
      } else {
        setState(() => _isInitialized = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('No toilets assigned to you'),
              backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      print('Error loading assigned toilets: $e');
      setState(() {
        _isLoading = false;
        _isInitialized = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error loading assigned toilets: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadSpecificToilet(String toiletId) async {
    setState(() => _isLoading = true);
    try {
      PublicToilet? toilet = _assignedToilets.firstWhere(
        (t) => t.id == toiletId,
        orElse: () => throw Exception('Toilet not found in assigned toilets'),
      );
      _loadToilet(toilet);
    } catch (e) {
      try {
        final toilet = await _toiletService.getToiletById(toiletId);
        if (toilet != null) {
          _loadToilet(toilet);
        } else {
          throw Exception('Toilet not found');
        }
      } catch (error) {
        print('Error loading specific toilet: $error');
        setState(() {
          _isLoading = false;
          _isInitialized = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error loading toilet: $error'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _loadToilet(PublicToilet toilet) {
    if (mounted) {
      setState(() {
        _toilet = toilet;
        _isLoading = false;
        _isInitialized = true;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedImage = await showModalBottomSheet<XFile?>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.camera),
            title: Text('Take Photo'),
            onTap: () async {
              Navigator.pop(
                  context, await picker.pickImage(source: ImageSource.camera));
            },
          ),
          ListTile(
            leading: Icon(Icons.photo_library),
            title: Text('Choose from Gallery'),
            onTap: () async {
              Navigator.pop(
                  context, await picker.pickImage(source: ImageSource.gallery));
            },
          ),
        ],
      ),
    );

    if (pickedImage != null) {
      setState(() => _newImages.add(File(pickedImage.path)));
    }
  }

  Future<void> _saveChanges() async {
    if (_toilet == null) return;
    setState(() => _isSaving = true);

    try {
      final updatedToilet = PublicToilet(
        id: _toilet!.id,
        name: _toilet!.name,
        address: _toilet!.address,
        latitude: _toilet!.latitude,
        longitude: _toilet!.longitude,
        status: _toilet!.status,
        lastMaintenanceDate: DateTime.now(),
        facilities: _toilet!.facilities,
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

      if (_newImages.isNotEmpty) {
        final imageUrls =
            await _toiletService.uploadImages(updatedToilet.id, _newImages);
        updatedToilet.imageUrls.addAll(imageUrls);
      }

      final success =
          await _toiletService.updateToiletMaintenance(updatedToilet);
      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Toilet updated successfully'),
              backgroundColor: Colors.green),
        );
        setState(() {
          _toilet = updatedToilet;
          _newImages.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to update toilet'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      print('Error saving changes: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error updating toilet: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onToiletChanged(String? toiletId) {
    if (toiletId == null) return;
    final selectedToilet =
        _assignedToilets.firstWhere((toilet) => toilet.id == toiletId);
    _loadToilet(selectedToilet);
  }

  String _getStatusDisplayName(ToiletStatus status) {
    return status == ToiletStatus.operational
        ? 'Operational'
        : 'Out of Service';
  }

  Color _getStatusColor(ToiletStatus status) {
    return status == ToiletStatus.operational ? Colors.green : Colors.red;
  }

  String _formatTimeOfDay(TimeOfDay timeOfDay) {
    final now = DateTime.now();
    final dt = DateTime(
        now.year, now.month, now.day, timeOfDay.hour, timeOfDay.minute);
    return DateFormat.jm().format(dt);
  }

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
        title: Text('Update Toilet Information',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (_isSaving)
            Container(
              margin: const EdgeInsets.all(14),
              width: 20,
              height: 20,
              child: const CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_rounded, color: Colors.white),
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
                  CircularProgressIndicator(color: _primaryColor),
                  SizedBox(height: 16),
                  Text('Loading toilet data...',
                      style: TextStyle(color: _textColor, fontSize: 16)),
                ],
              ),
            )
          : !_isInitialized || _assignedToilets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 64, color: _primaryColor),
                      SizedBox(height: 16),
                      Text('No toilets assigned to you',
                          style: TextStyle(
                              color: _textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Contact the toilet owner to get assignments',
                          style: TextStyle(
                              color: _textColor.withOpacity(0.7),
                              fontSize: 16)),
                      SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadAssignedToilets,
                        icon: Icon(Icons.refresh),
                        label: Text('Refresh Assignments'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            padding: EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12)),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (_assignedToilets.length > 1)
                      Container(
                        color: Colors.white,
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'Select Toilet',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            prefixIcon: Icon(Icons.wc),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 0),
                          ),
                          value: _toilet?.id,
                          items: _assignedToilets.map((toilet) {
                            return DropdownMenuItem<String>(
                              value: toilet.id,
                              child: Text(toilet.name,
                                  overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: _onToiletChanged,
                        ),
                      ),
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
                      borderRadius: BorderRadius.circular(12)),
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
                                  color: Colors.white, strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('SAVING...',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ],
                      )
                    : Text('SAVE TOILET INFORMATION',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
              ),
            ),
    );
  }

  Widget _buildMainContent() {
    if (_toilet == null) return Container();
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildToiletInfoCard(),
          _buildStatusSection(),
          _buildFeaturesSection(),
          _buildPhotoSection(),
          SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildToiletInfoCard() {
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
              offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(_toilet!.status).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: _getStatusColor(_toilet!.status), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _toilet!.status == ToiletStatus.operational
                          ? Icons.check_circle
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
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today,
                        size: 14, color: Colors.grey[700]),
                    SizedBox(width: 4),
                    Text(
                      'Last: ${DateFormat('MMM d, yyyy').format(_toilet!.lastMaintenanceDate)}',
                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(_toilet!.name,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
          SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
              SizedBox(width: 4),
              Expanded(
                child: Text(_toilet!.address,
                    style: TextStyle(color: Colors.grey[600]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (_toilet!.ownerEmail != null) ...[
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person, size: 16, color: Colors.grey[600]),
                SizedBox(width: 4),
                Text('Owner: ${_toilet!.ownerEmail}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ],
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
              SizedBox(width: 4),
              Text(
                  _toilet!.is24Hours
                      ? 'Open 24 hours'
                      : _toilet!.getFormattedHours(),
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection() {
    return Container(
      padding: EdgeInsets.all(16),
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 3,
              offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current Status',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800])),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              _buildStatusOption(
                  status: ToiletStatus.operational,
                  icon: Icons.check_circle,
                  label: 'Operational'),
              _buildStatusOption(
                  status: ToiletStatus.outOfService,
                  icon: Icons.error,
                  label: 'Out of Service'),
            ],
          ),
          SizedBox(height: 16),
          Text(
            _toilet!.status == ToiletStatus.operational
                ? 'All facilities are working properly.'
                : 'The toilet is currently not usable.',
            style:
                TextStyle(color: Colors.grey[700], fontStyle: FontStyle.italic),
          ),
          SizedBox(height: 20),
          Text('Operating Hours',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800])),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text('24-Hour Operation',
                    style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              Switch(
                value: _toilet!.is24Hours,
                onChanged: (value) {
                  setState(() {
                    _toilet = PublicToilet(
                      id: _toilet!.id,
                      name: _toilet!.name,
                      address: _toilet!.address,
                      latitude: _toilet!.latitude,
                      longitude: _toilet!.longitude,
                      status: _toilet!.status,
                      lastMaintenanceDate: _toilet!.lastMaintenanceDate,
                      facilities: _toilet!.facilities,
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
                  });
                },
                activeColor: _primaryColor,
              ),
            ],
          ),
          if (!_toilet!.is24Hours) ...[
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectTimeOfDay(true),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Opening Time',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        prefixIcon: Icon(Icons.access_time),
                      ),
                      child: Text(_formatTimeOfDay(_toilet!.openingTime)),
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
                            borderRadius: BorderRadius.circular(8)),
                        prefixIcon: Icon(Icons.access_time),
                      ),
                      child: Text(_formatTimeOfDay(_toilet!.closingTime)),
                    ),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 16),
          Text('Operating Days', style: TextStyle(fontWeight: FontWeight.w500)),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(7, (index) {
              return FilterChip(
                label: Text(_getDayName(index).substring(0, 3)),
                selected: _toilet!.operatingDays[index],
                onSelected: (selected) {
                  setState(() {
                    final newOperatingDays =
                        List<bool>.from(_toilet!.operatingDays);
                    newOperatingDays[index] = selected;
                    _toilet = PublicToilet(
                      id: _toilet!.id,
                      name: _toilet!.name,
                      address: _toilet!.address,
                      latitude: _toilet!.latitude,
                      longitude: _toilet!.longitude,
                      status: _toilet!.status,
                      lastMaintenanceDate: _toilet!.lastMaintenanceDate,
                      facilities: _toilet!.facilities,
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
                  });
                },
                selectedColor: _primaryColor,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                    color: _toilet!.operatingDays[index]
                        ? Colors.white
                        : Colors.black87),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesSection() {
    return Container(
      padding: EdgeInsets.all(16),
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 3,
              offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Toilet Features',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800])),
          SizedBox(height: 16),
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

  Widget _buildPhotoSection() {
    return Container(
      padding: EdgeInsets.all(16),
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 3,
              offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Photo Documentation',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800])),
          SizedBox(height: 16),
          if (_toilet!.imageUrls.isNotEmpty) ...[
            Text('Existing Photos',
                style: TextStyle(
                    fontWeight: FontWeight.w500, color: Colors.grey[700])),
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
                return _buildImageItem(_toilet!.imageUrls[index], index, false);
              },
            ),
            SizedBox(height: 16),
          ],
          if (_newImages.isNotEmpty) ...[
            Text('New Photos (Not Yet Saved)',
                style: TextStyle(
                    fontWeight: FontWeight.w500, color: Colors.grey[700])),
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
                return _buildImageItem(_newImages[index].path, index, true);
              },
            ),
            SizedBox(height: 16),
          ],
          Center(
            child: ElevatedButton.icon(
              onPressed: _pickImage,
              icon: Icon(Icons.add_a_photo),
              label: Text('Add Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          SizedBox(height: 8),
          Center(
            child: Text(
              'Photos will be saved when you click "Save" button',
              style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                  fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageItem(String imagePath, int index, bool isNew) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          isNew
              ? Image.file(File(imagePath), fit: BoxFit.cover)
              : Image.network(imagePath, fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[300],
                    child: Icon(Icons.broken_image,
                        color: Colors.grey[600], size: 40),
                  );
                }),
          Positioned(
            right: 4,
            top: 4,
            child: InkWell(
              onTap: () => isNew
                  ? setState(() => _newImages.removeAt(index))
                  : _showDeleteImageConfirmation(index),
              child: Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle),
                child: Icon(Icons.delete, color: Colors.white, size: 20),
              ),
            ),
          ),
          if (isNew)
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: _primaryColor,
                    borderRadius: BorderRadius.circular(12)),
                child: Text('New',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusOption(
      {required ToiletStatus status,
      required IconData icon,
      required String label}) {
    final isSelected = _toilet!.status == status;
    final color = _getStatusColor(status);

    return InkWell(
      onTap: () {
        setState(() {
          _toilet = PublicToilet(
            id: _toilet!.id,
            name: _toilet!.name,
            address: _toilet!.address,
            latitude: _toilet!.latitude,
            longitude: _toilet!.longitude,
            status: status,
            lastMaintenanceDate: _toilet!.lastMaintenanceDate,
            facilities: _toilet!.facilities,
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
              width: isSelected ? 2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isSelected ? color : Colors.grey[600]),
            SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: isSelected ? color : Colors.grey[800],
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal)),
            if (isSelected)
              Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.check, size: 16, color: color)),
          ],
        ),
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
      default:
        featureIcon = Icons.check_box;
    }

    return InkWell(
      onTap: () {
        setState(() {
          final updatedFeatures = Map<String, bool>.from(_toilet!.features);
          updatedFeatures[featureName] = !hasFeature;
          _toilet = PublicToilet(
            id: _toilet!.id,
            name: _toilet!.name,
            address: _toilet!.address,
            latitude: _toilet!.latitude,
            longitude: _toilet!.longitude,
            status: _toilet!.status,
            lastMaintenanceDate: _toilet!.lastMaintenanceDate,
            facilities: _toilet!.facilities,
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
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasFeature ? _primaryColor.withOpacity(0.2) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: hasFeature ? _primaryColor : Colors.grey[400]!),
        ),
        child: Row(
          children: [
            Icon(featureIcon,
                size: 20, color: hasFeature ? _primaryColor : Colors.grey[600]),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                featureName,
                style: TextStyle(
                    color: hasFeature ? _primaryColor : Colors.grey[800],
                    fontWeight:
                        hasFeature ? FontWeight.bold : FontWeight.normal),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
        _toilet = PublicToilet(
          id: _toilet!.id,
          name: _toilet!.name,
          address: _toilet!.address,
          latitude: _toilet!.latitude,
          longitude: _toilet!.longitude,
          status: _toilet!.status,
          lastMaintenanceDate: _toilet!.lastMaintenanceDate,
          facilities: _toilet!.facilities,
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
      });
    }
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
              onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                final updatedImageUrls = List<String>.from(_toilet!.imageUrls);
                updatedImageUrls.removeAt(index);
                _toilet = PublicToilet(
                  id: _toilet!.id,
                  name: _toilet!.name,
                  address: _toilet!.address,
                  latitude: _toilet!.latitude,
                  longitude: _toilet!.longitude,
                  status: _toilet!.status,
                  lastMaintenanceDate: _toilet!.lastMaintenanceDate,
                  facilities: _toilet!.facilities,
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
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Photo deleted'), backgroundColor: Colors.red));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }
}
