import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> createNotification({
    required String userId,
    required String message,
    required String type,
    String? sender,
    String? imageUrl,
    String? actionUrl,
    String? relatedPage,
    String? relatedId,
    String role = 'user',
  }) async {
    await _firestore.collection('notifications').add({
      'userId': userId,
      'message': message,
      'sender': sender ?? 'System',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      'type': type,
      'image': imageUrl,
      'actionUrl': actionUrl,
      'relatedPage': relatedPage,
      'relatedId': relatedId,
      'role': role,
    });
  }

  Future<void> createRoleBasedNotification({
    required String role,
    required String message,
    required String type,
    String? sender,
    String? imageUrl,
    String? actionUrl,
    String? relatedPage,
    String? relatedId,
  }) async {
    await _firestore.collection('notifications').add({
      'role': role,
      'message': message,
      'sender': sender ?? 'System',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      'type': type,
      'image': imageUrl,
      'actionUrl': actionUrl,
      'relatedPage': relatedPage,
      'relatedId': relatedId,
    });
  }

  Future<void> createAdminNotification({
    required String message,
    required String type,
    String? sender,
    String? imageUrl,
    String? actionUrl,
    String? relatedPage,
    String? relatedId,
  }) async {
    // Get all admin users
    QuerySnapshot admins = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'admin')
        .get();

    // Create notification for each admin
    for (var adminDoc in admins.docs) {
      await createNotification(
        userId: adminDoc.id,
        message: message,
        type: type,
        sender: sender,
        imageUrl: imageUrl,
        actionUrl: actionUrl,
        relatedPage: relatedPage,
        relatedId: relatedId,
        role: 'admin',
      );
    }
  }

  Future<void> markAsRead(String notificationId) async {
    await _firestore
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  Future<void> deleteNotification(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).delete();
  }

  Future<int> getUnreadCount(String userId) async {
    QuerySnapshot unread = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    return unread.size;
  }
}