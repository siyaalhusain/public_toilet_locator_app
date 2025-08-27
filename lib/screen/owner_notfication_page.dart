import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class OwnerNotificationsPage extends StatefulWidget {
  @override
  _OwnerNotificationsPageState createState() => _OwnerNotificationsPageState();
}

class _OwnerNotificationsPageState extends State<OwnerNotificationsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late Stream<QuerySnapshot> _notificationsStream;

  @override
  void initState() {
    super.initState();
    _initializeStream();
  }

  void _initializeStream() {
    final user = _auth.currentUser;
    if (user != null) {
      print('✅ Firebase UID: ${user.uid}');
      _notificationsStream = _firestore
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('isAdminNotification', isEqualTo: false)
          //.orderBy('createdAt', descending: true) // 🔥 Temporarily removed for safety
          .snapshots();
    } else {
      print('⚠️ No logged-in user!');
      _notificationsStream = const Stream.empty();
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('❌ Error marking as read: $e');
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
    } catch (e) {
      debugPrint('❌ Error deleting notification: $e');
    }
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    setState(() {
      _initializeStream();
    });
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null || timestamp is! Timestamp) return 'No time';
    final dateTime = timestamp.toDate();
    return DateFormat('MMM d, y - jm').format(dateTime);
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'payment_approved':
        return Icons.check_circle;
      case 'payment_rejected':
      case 'account_deactivated':
        return Icons.error;
      case 'subscription_expired':
        return Icons.timer_off;
      case 'subscription_expiring_soon':
        return Icons.timer;
      case 'payment_verification_deleted':
        return Icons.delete_forever;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'payment_approved':
        return Colors.green;
      case 'payment_rejected':
      case 'account_deactivated':
        return Colors.red;
      case 'subscription_expired':
        return Colors.orange;
      case 'subscription_expiring_soon':
        return Colors.amber;
      case 'payment_verification_deleted':
        return Colors.deepOrange;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _notificationsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('❌ Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];
          print('🔍 Notifications: ${docs.length}');
          for (var doc in docs) {
            print('📨 ${doc.id}: ${doc.data()}');
          }

          if (docs.isEmpty) {
            return _buildEmptyState();
          }

          return _buildNotificationList(docs);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined,
              size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('No notifications',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('You\'re all caught up!',
              style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildNotificationList(List<QueryDocumentSnapshot> notifications) {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final doc = notifications[index];
          final data = doc.data() as Map<String, dynamic>;

          final isRead = data['isRead'] ?? false;
          final type = data['type'] ?? 'general';
          final color = _getNotificationColor(type);

          return Dismissible(
            key: Key(doc.id),
            direction: DismissDirection.horizontal,
            background: Container(
              color: Colors.blue,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const Icon(Icons.check_circle, color: Colors.white),
            ),
            secondaryBackground: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                await _markAsRead(doc.id);
                return false;
              }
              return await _showDeleteConfirmation(context);
            },
            onDismissed: (direction) {
              if (direction == DismissDirection.endToStart) {
                _deleteNotification(doc.id);
              }
            },
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              elevation: isRead ? 1 : 2,
              color: isRead ? Colors.white : Colors.blue[50],
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_getNotificationIcon(type), color: color),
                ),
                title: Text(
                  data['message'] ?? '⚠️ No message',
                  style: TextStyle(
                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  _formatTimestamp(data['createdAt']),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isRead)
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'delete') {
                          _deleteNotification(doc.id);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
                onTap: () => _handleNotificationTap(doc.id, isRead),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Delete Notification"),
            content: const Text(
                "Are you sure you want to delete this notification?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child:
                    const Text("Delete", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _handleNotificationTap(String notificationId, bool isRead) {
    if (!isRead) {
      _markAsRead(notificationId);
    }
  }
}
