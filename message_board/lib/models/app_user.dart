import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String firstName;
  final String lastName;
  final String role;
  final DateTime? registrationDateTime;

  const AppUser({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.registrationDateTime,
  });

  String get fullName => '$firstName $lastName'.trim();

  Map<String, dynamic> toCreateMap() {
    return {
      'uid': uid,
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'role': role.trim(),
      'registrationDateTime': FieldValue.serverTimestamp(),
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> data) {
    final rawTs = data['registrationDateTime'];
    return AppUser(
      uid: (data['uid'] ?? '').toString(),
      firstName: (data['firstName'] ?? '').toString(),
      lastName: (data['lastName'] ?? '').toString(),
      role: (data['role'] ?? 'student').toString(),
      registrationDateTime: rawTs is Timestamp ? rawTs.toDate() : null,
    );
  }
}