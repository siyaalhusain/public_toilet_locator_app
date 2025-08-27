import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:project_x/screen/profile_page.dart';
import 'package:project_x/screen/view_counting_page.dart';

import 'AddCommentPage.dart';
import 'ViewReportsPage.dart';
import 'View_assign_task.dart';
import 'admin_payment_verification_screen.dart';

class NotificationPage extends StatefulWidget {
  @override
  _NotificationPageState createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isRefreshing = false;
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    _getCurrentUserRole();
  }

  Future<void> _getCurrentUserRole() async {
    User? user = _auth.currentUser;
    if (user != null) {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(user.uid).get();
      setState(() {
        _currentUserRole = userDoc['role'] ?? 'user';
      });
    }
  }

  Stream<List<Map<String, dynamic>>> _getNotifications() {
    User? user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('notifications')
        .where('isAdminNotification', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'title': doc['title'] ?? 'Notification',
          'message': doc['message'],
          'type': doc['type'] ?? 'general',
          'isRead': doc['isRead'] ?? false,
          'createdAt': doc['createdAt'],
          'relatedPage': doc['relatedPage'],
          'relatedId': doc['relatedUserId'],
        };
      }).toList();
    });
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });

    await Future.delayed(Duration(seconds: 1));
    await _getCurrentUserRole();

    setState(() {
      _isRefreshing = false;
    });
  }

  Future<void> _markAsRead(String notificationId) async {
    await _firestore
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  Future<void> _deleteNotification(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).delete();
  }

  Future<void> _markAllAsRead() async {
    User? user = _auth.currentUser;
    if (user == null) return;

    QuerySnapshot unreadNotifications = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('isRead', isEqualTo: false)
        .get();

    WriteBatch batch = _firestore.batch();
    for (var doc in unreadNotifications.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
  }

  Future<void> _clearAllNotifications() async {
    User? user = _auth.currentUser;
    if (user == null) return;

    QuerySnapshot userNotifications = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .get();

    WriteBatch batch = _firestore.batch();
    for (var doc in userNotifications.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  String _formatTimestamp(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    DateTime now = DateTime.now();

    if (dateTime.day == now.day &&
        dateTime.month == now.month &&
        dateTime.year == now.year) {
      return 'Today, ${DateFormat.jm().format(dateTime)}';
    } else if (dateTime.day == now.day - 1 &&
        dateTime.month == now.month &&
        dateTime.year == now.year) {
      return 'Yesterday, ${DateFormat.jm().format(dateTime)}';
    } else if (now.difference(dateTime).inDays < 7) {
      return DateFormat('EEEE, jm').format(dateTime); // Weekday
    } else {
      return DateFormat('MMM d, y - jm').format(dateTime);
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'alert':
        return Icons.warning_amber_rounded;
      case 'update':
        return Icons.system_update;
      case 'promotion':
        return Icons.local_offer;
      case 'report':
        return Icons.report_problem;
      case 'count':
        return Icons.people;
      case 'review':
        return Icons.rate_review;
      case 'task':
        return Icons.assignment;
      case 'payment':
        return Icons.payment;
      case 'comment':
        return Icons.comment;
      case 'maintenance':
        return Icons.build;
      case 'subscription':
        return Icons.card_membership;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'alert':
        return Colors.red;
      case 'update':
        return Colors.blue;
      case 'promotion':
        return Colors.green;
      case 'report':
        return Colors.orange;
      case 'count':
        return Colors.purple;
      case 'review':
        return Colors.teal;
      case 'task':
        return Colors.indigo;
      case 'payment':
        return Colors.green;
      case 'comment':
        return Colors.blueGrey;
      case 'maintenance':
        return Colors.deepOrange;
      case 'subscription':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  void _handleNotificationTap(Map<String, dynamic> notification) {
    if (!notification['isRead']) {
      _markAsRead(notification['id']);
    }

    switch (notification['type']) {
      case 'renewal_request':
      case 'new_owner':
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => AdminPaymentVerificationScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (BuildContext context) {
                  return Container(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: Icon(Icons.check_circle_outline),
                          title: Text('Mark all as read'),
                          onTap: () {
                            _markAllAsRead();
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Clear all notifications'),
                          onTap: () {
                            _clearAllNotifications();
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.settings_outlined),
                          title: Text('Notification settings'),
                          onTap: () {
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getNotifications(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !_isRefreshing) {
              return Center(
                child: CircularProgressIndicator(),
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No notifications',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'You\'re all caught up!',
                      style: TextStyle(
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              );
            }

            final notifications = snapshot.data!;

            Map<String, List<Map<String, dynamic>>> groupedNotifications = {};
            for (var notification in notifications) {
              final timestamp = notification['timestamp'] as Timestamp;
              final dateTime = timestamp.toDate();
              final date = DateFormat('yyyy-MM-dd').format(dateTime);

              if (!groupedNotifications.containsKey(date)) {
                groupedNotifications[date] = [];
              }
              groupedNotifications[date]!.add(notification);
            }

            final sortedDates = groupedNotifications.keys.toList()
              ..sort((a, b) => b.compareTo(a));

            return ListView.builder(
              physics: AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(top: 8, bottom: 20),
              itemCount: sortedDates.length,
              itemBuilder: (context, dateIndex) {
                final date = sortedDates[dateIndex];
                final dateNotifications = groupedNotifications[date]!;

                final headerDate = DateTime.parse(date);
                final now = DateTime.now();
                String headerText;

                if (headerDate.year == now.year &&
                    headerDate.month == now.month &&
                    headerDate.day == now.day) {
                  headerText = 'Today';
                } else if (headerDate.year == now.year &&
                    headerDate.month == now.month &&
                    headerDate.day == now.day - 1) {
                  headerText = 'Yesterday';
                } else if (now.difference(headerDate).inDays < 7) {
                  headerText = DateFormat('EEEE').format(headerDate);
                } else if (headerDate.year == now.year) {
                  headerText = DateFormat('MMMM d').format(headerDate);
                } else {
                  headerText = DateFormat('MMMM d, y').format(headerDate);
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text(
                        headerText,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                          fontSize: 14,
                        ),
                      ),
                    ),
                    ...dateNotifications.map((notification) {
                      final isRead = notification['isRead'] ?? false;
                      final type = notification['type'] ?? 'general';
                      final color = _getNotificationColor(type);

                      return Dismissible(
                        key: Key(notification['id']),
                        background: Container(
                          color: Colors.blue,
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Icon(Icons.check_circle, color: Colors.white),
                        ),
                        secondaryBackground: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          if (direction == DismissDirection.startToEnd) {
                            await _markAsRead(notification['id']);
                            return false;
                          } else {
                            return await showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text("Delete Notification"),
                                  content: Text(
                                      "Are you sure you want to delete this notification?"),
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
                          }
                        },
                        onDismissed: (direction) {
                          if (direction == DismissDirection.endToStart) {
                            _deleteNotification(notification['id']);
                          }
                        },
                        child: Container(
                          margin:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: isRead ? Colors.white : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 5,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: () => _handleNotificationTap(notification),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: notification['image'] != null
                                        ? ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Image.network(
                                              notification['image'],
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                return Icon(
                                                  _getNotificationIcon(type),
                                                  color: color,
                                                  size: 24,
                                                );
                                              },
                                            ),
                                          )
                                        : Icon(
                                            _getNotificationIcon(type),
                                            color: color,
                                            size: 24,
                                          ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (!isRead)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            margin: EdgeInsets.only(
                                                top: 4, bottom: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.blue,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        Text(
                                          notification['message'],
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: isRead
                                                ? FontWeight.normal
                                                : FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _formatTimestamp(
                                                    notification['timestamp']),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[500],
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
