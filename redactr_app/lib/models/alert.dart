import 'package:cloud_firestore/cloud_firestore.dart';

enum AlertStatus { pending, approved, denied }

class Alert {
  final String id;
  final String employee;
  final String whatWasBlocked;
  final String findingType;
  final int riskScore;
  final DateTime timestamp;
  AlertStatus status;

  Alert({
    required this.id,
    required this.employee,
    required this.whatWasBlocked,
    required this.findingType,
    required this.riskScore,
    required this.timestamp,
    this.status = AlertStatus.pending,
  });

  /// Maps a `companies/{companyId}/alerts/{alertId}` doc (written by the
  /// createAlert Cloud Function — see firebase/functions/index.js) into
  /// this model.
  factory Alert.fromFirestore(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Alert(
      id: doc.id,
      employee: data['employeeName'] as String? ?? 'Unknown',
      whatWasBlocked: data['whatWasBlocked'] as String? ?? '',
      findingType: data['findingType'] as String? ?? '',
      riskScore: (data['riskScore'] as num?)?.toInt() ?? 0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: AlertStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => AlertStatus.pending,
      ),
    );
  }

  String get statusLabel {
    switch (status) {
      case AlertStatus.approved:
        return 'Approved';
      case AlertStatus.denied:
        return 'Denied';
      case AlertStatus.pending:
        return 'Pending review';
    }
  }
}
