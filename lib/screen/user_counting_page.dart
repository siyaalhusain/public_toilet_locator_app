import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

// User Counting Repository (Handles data persistence)
class UserCountingRepository {
  static const String _userEntriesKey = 'toilet_user_entries';
  static const String _totalUsersKey = 'total_users';
  static const String _lastResetKey = 'last_reset_date';

  // Save user entries to local storage
  Future<void> saveUserEntries(List<UserEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final encodedEntries = entries.map((entry) => entry.toJson()).toList();
    await prefs.setStringList(
        _userEntriesKey, encodedEntries.map((e) => jsonEncode(e)).toList());
  }

  // Load user entries from local storage
  Future<List<UserEntry>> loadUserEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedEntries = prefs.getStringList(_userEntriesKey) ?? [];
    return encodedEntries
        .map((e) => UserEntry.fromJson(jsonDecode(e)))
        .toList();
  }

  // Save total user count
  Future<void> saveTotalUsers(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_totalUsersKey, count);
  }

  // Load total user count
  Future<int> loadTotalUsers() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_totalUsersKey) ?? 0;
  }

  // Save last reset date
  Future<void> saveLastResetDate(DateTime? date) async {
    final prefs = await SharedPreferences.getInstance();
    if (date == null) {
      await prefs.remove(_lastResetKey);
    } else {
      await prefs.setString(_lastResetKey, date.toIso8601String());
    }
  }

  // Load last reset date
  Future<DateTime?> loadLastResetDate() async {
    final prefs = await SharedPreferences.getInstance();
    final dateString = prefs.getString(_lastResetKey);
    return dateString != null ? DateTime.parse(dateString) : null;
  }
}

// User Entry Class with JSON serialization
class UserEntry {
  final DateTime timestamp;
  final String userId;
  final String toiletId;
  final String maintainerId;

  UserEntry({
    required this.timestamp,
    required this.userId,
    required this.toiletId,
    required this.maintainerId,
  });

  // Convert to JSON
  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'userId': userId,
        'toiletId': toiletId,
        'maintainerId': maintainerId,
      };

  // Create from JSON
  factory UserEntry.fromJson(Map<String, dynamic> json) => UserEntry(
        timestamp: DateTime.parse(json['timestamp']),
        userId: json['userId'],
        toiletId: json['toiletId'],
        maintainerId: json['maintainerId'],
      );
}

// User Counting Model with advanced functionality
class UserCountingModel extends ChangeNotifier {
  final UserCountingRepository _repository = UserCountingRepository();

  int _totalUsers = 0;
  DateTime? _lastCountUpdated;
  List<UserEntry> _userEntries = [];
  String _toiletId;
  String _maintainerId;

  UserCountingModel({
    required String toiletId,
    required String maintainerId,
  })  : _toiletId = toiletId,
        _maintainerId = maintainerId {
    _loadSavedData();
  }

  int get totalUsers => _totalUsers;
  DateTime? get lastCountUpdated => _lastCountUpdated;
  List<UserEntry> get userEntries => _userEntries;

  // Load saved data from local storage
  Future<void> _loadSavedData() async {
    _totalUsers = await _repository.loadTotalUsers();
    _userEntries = await _repository.loadUserEntries();
    _lastCountUpdated = await _repository.loadLastResetDate();
    notifyListeners();
  }

  // Increment user count
  Future<void> incrementUserCount(String userId) async {
    _totalUsers++;
    _lastCountUpdated = DateTime.now();

    final newEntry = UserEntry(
      timestamp: _lastCountUpdated!,
      userId: userId,
      toiletId: _toiletId,
      maintainerId: _maintainerId,
    );

    _userEntries.add(newEntry);

    // Save to local storage
    await _repository.saveTotalUsers(_totalUsers);
    await _repository.saveUserEntries(_userEntries);
    await _repository.saveLastResetDate(_lastCountUpdated);

    notifyListeners();
  }

  // Reset user count
  Future<void> resetUserCount() async {
    _totalUsers = 0;
    _lastCountUpdated = null;
    _userEntries.clear();

    // Clear local storage
    await _repository.saveTotalUsers(0);
    await _repository.saveUserEntries([]);
    await _repository.saveLastResetDate(null);

    notifyListeners();
  }

  // Get daily user count
  Map<String, int> getDailyUserCount() {
    final dailyCounts = <String, int>{};

    for (var entry in _userEntries) {
      final dateKey = DateFormat('yyyy-MM-dd').format(entry.timestamp);
      dailyCounts[dateKey] = (dailyCounts[dateKey] ?? 0) + 1;
    }

    return dailyCounts;
  }

  // Get user count by hour
  Map<int, int> getHourlyUserCount() {
    final hourlyCounts = <int, int>{};

    for (var entry in _userEntries) {
      final hour = entry.timestamp.hour;
      hourlyCounts[hour] = (hourlyCounts[hour] ?? 0) + 1;
    }

    return hourlyCounts;
  }
}

// Toilet Maintainer User Counting Page
class ToiletUserCountingPage extends StatefulWidget {
  final String toiletId;
  final String maintainerId;

  const ToiletUserCountingPage({
    Key? key,
    required this.toiletId,
    required this.maintainerId,
  }) : super(key: key);

  @override
  _ToiletUserCountingPageState createState() => _ToiletUserCountingPageState();
}

class _ToiletUserCountingPageState extends State<ToiletUserCountingPage> {
  final TextEditingController _userIdController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => UserCountingModel(
        toiletId: widget.toiletId,
        maintainerId: widget.maintainerId,
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Toilet User Counting - ${widget.toiletId}'),
          actions: [
            // Reset Button
            Consumer<UserCountingModel>(
              builder: (context, model, child) => IconButton(
                icon: Icon(Icons.refresh),
                onPressed: () {
                  _showResetConfirmationDialog(context, model);
                },
              ),
            ),
            // Statistics Button
            IconButton(
              icon: Icon(Icons.bar_chart),
              onPressed: () {
                _showUserStatisticsDialog(context);
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User ID Input
              TextField(
                controller: _userIdController,
                decoration: InputDecoration(
                  labelText: 'Enter User ID',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.person),
                ),
              ),
              SizedBox(height: 20),

              // Total User Count Card
              Consumer<UserCountingModel>(
                builder: (context, model, child) => Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text(
                          'Total Users',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        SizedBox(height: 10),
                        Text(
                          '${model.totalUsers}',
                          style: Theme.of(context)
                              .textTheme
                              .displayMedium
                              ?.copyWith(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),

              // Add User Button
              Consumer<UserCountingModel>(
                builder: (context, model, child) => ElevatedButton.icon(
                  onPressed: () {
                    final userId = _userIdController.text.trim();
                    if (userId.isNotEmpty) {
                      model.incrementUserCount(userId);
                      _userIdController.clear();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('User $userId added')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Please enter a User ID')),
                      );
                    }
                  },
                  icon: Icon(Icons.add),
                  label: Text('Add User'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
              SizedBox(height: 20),

              // User Entries List
              Expanded(
                child: Consumer<UserCountingModel>(
                  builder: (context, model, child) => Card(
                    elevation: 4,
                    child: ListView.builder(
                      itemCount: model.userEntries.length,
                      itemBuilder: (context, index) {
                        final entry = model.userEntries[index];
                        return ListTile(
                          leading: Icon(Icons.person),
                          title: Text(entry.userId),
                          subtitle: Text(
                            'Timestamp: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(entry.timestamp)}',
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Reset Confirmation Dialog
  void _showResetConfirmationDialog(
      BuildContext context, UserCountingModel model) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset User Count'),
        content: Text('Are you sure you want to reset the user count?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              model.resetUserCount();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('User count reset')),
              );
            },
            child: Text('Confirm'),
          ),
        ],
      ),
    );
  }

  // User Statistics Dialog
  void _showUserStatisticsDialog(BuildContext context) {
    final model = Provider.of<UserCountingModel>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('User Statistics'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Daily User Count:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...model
                  .getDailyUserCount()
                  .entries
                  .map((entry) => Text('${entry.key}: ${entry.value} users'))
                  .toList(),
              SizedBox(height: 10),
              Text('Hourly User Count:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...model
                  .getHourlyUserCount()
                  .entries
                  .map((entry) => Text(
                      '${entry.key}:00 - ${entry.key}:59: ${entry.value} users'))
                  .toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }
}
