// Create a new file admin_notifications_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'admin_payment_verification_screen.dart';

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({Key? key}) : super(key: key);

  @override
  _AdminNotificationsPageState createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.mark_as_unread),
            onPressed: _markAllAsRead,
            tooltip: 'Mark all as read',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('notifications')
            .where('userId', isEqualTo: _auth.currentUser?.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            print('Firestore Error: ${snapshot.error}');
            // Fallback query without ordering for now
            return _buildFallbackNotifications();
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.data?.docs.isEmpty ?? true) {
            return const Center(
              child: Text('No notifications yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey)),
            );
          }

          return ListView.builder(
            itemCount: snapshot.data?.docs.length ?? 0,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isRead = data['isRead'] ?? false;

              return Dismissible(
                key: Key(doc.id),
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (direction) => _deleteNotification(doc.id),
                child: Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: isRead ? Colors.white : Colors.blue[50],
                  child: ListTile(
                    leading: _getNotificationIcon(data['type']),
                    title: Text(
                      data['title'] ?? 'Notification',
                      style: TextStyle(
                        fontWeight:
                            isRead ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['message'] ?? ''),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(data['createdAt']),
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    trailing: isRead
                        ? null
                        : const Icon(Icons.circle,
                            color: Colors.blue, size: 12),
                    onTap: () => _handleNotificationTap(doc.id, data),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Fallback widget when the main query fails due to missing index
  Widget _buildFallbackNotifications() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('notifications')
          .where('userId', isEqualTo: _auth.currentUser?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Error loading notifications'),
                const SizedBox(height: 8),
                Text('${snapshot.error}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.data?.docs.isEmpty ?? true) {
          return const Center(
            child: Text('No notifications yet',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
          );
        }

        // Sort the documents manually since we can't use orderBy
        List<QueryDocumentSnapshot> sortedDocs = snapshot.data!.docs.toList();
        sortedDocs.sort((a, b) {
          final aTime =
              (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          final bTime =
              (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;

          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;

          return bTime.compareTo(aTime); // Descending order
        });

        return ListView.builder(
          itemCount: sortedDocs.length,
          itemBuilder: (context, index) {
            final doc = sortedDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final isRead = data['isRead'] ?? false;

            return Dismissible(
              key: Key(doc.id),
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (direction) => _deleteNotification(doc.id),
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: isRead ? Colors.white : Colors.blue[50],
                child: ListTile(
                  leading: _getNotificationIcon(data['type']),
                  title: Text(
                    data['title'] ?? 'Notification',
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['message'] ?? ''),
                      const SizedBox(height: 4),
                      Text(
                        _formatTimestamp(data['createdAt']),
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  trailing: isRead
                      ? null
                      : const Icon(Icons.circle, color: Colors.blue, size: 12),
                  onTap: () => _handleNotificationTap(doc.id, data),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Icon _getNotificationIcon(String? type) {
    switch (type) {
      case 'new_owner':
        return const Icon(Icons.person_add, color: Colors.blue);
      case 'payment_verification':
        return const Icon(Icons.payment, color: Colors.green);
      case 'system':
        return const Icon(Icons.info, color: Colors.orange);
      default:
        return const Icon(Icons.notifications, color: Colors.blue);
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return DateFormat('MMM dd, yyyy').format(date);
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
      });
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final notifications = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: _auth.currentUser?.uid)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (var doc in notifications.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications marked as read')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification deleted')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting notification: $e')),
      );
    }
  }

  void _handleNotificationTap(
      String notificationId, Map<String, dynamic> data) {
    _markAsRead(notificationId);

    switch (data['type']) {
      case 'new_owner':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdminPaymentVerificationScreen(),
          ),
        );
        break;
      case 'payment_verification':
        // Handle payment verification notification
        break;
      default:
        // Handle other notification types
        break;
    }
  }
}
