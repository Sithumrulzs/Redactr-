import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/alert.dart';

/// Live alert data for a company. Reads are a direct Firestore stream
/// (allowed by firestore.rules for any member of the company); writes are
/// limited to status updates, which the rules explicitly allow for admins
/// only — creating an alert always goes through the createAlert Cloud
/// Function (called by the extension), never a direct client write.
class AlertService {
  final FirebaseFirestore _firestore;

  AlertService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<Alert>> watchAlerts(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('alerts')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Alert.fromFirestore).toList());
  }

  Future<void> updateStatus(String companyId, String alertId, AlertStatus status) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('alerts')
        .doc(alertId)
        .update({'status': status.name});
  }
}
