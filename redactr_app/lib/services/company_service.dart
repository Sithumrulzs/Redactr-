import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

// TODO(checkpoint): replace with the deployed Render URL once available,
// e.g. "https://redactr-api.onrender.com". See server/index.js — this is
// the plain Express app that replaced the Cloud Functions (which needed
// the Blaze billing plan).
const _apiBaseUrl = "REPLACE_ME";

/// Thin wrapper around the `users/{uid}` Firestore doc and the small
/// Express API in ../../../server/index.js (claimOrJoinCompany,
/// inviteEmployee, getEntitlement). Reads are direct Firestore (allowed by
/// firestore.rules for your own doc); the company-creating/joining write
/// always goes through the server, never a direct client write.
class CompanyService {
  final FirebaseFirestore _firestore;

  CompanyService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<Map<String, dynamic>> _callApi(String method, String path, {Map<String, dynamic>? body}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in.');

    final idToken = await user.getIdToken();
    final uri = Uri.parse('$_apiBaseUrl$path');
    final headers = {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'};

    final response = method == 'GET'
        ? await http.get(uri, headers: headers)
        : await http.post(uri, headers: headers, body: jsonEncode(body ?? {}));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(data['error'] as String? ?? 'Request failed (${response.statusCode}).');
    }
    return data;
  }

  /// Null means this user has no company yet (needs CompanySetupScreen).
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<String?> getCompanyName(String companyId) async {
    final doc = await _firestore.collection('companies').doc(companyId).get();
    return doc.data()?['name'] as String?;
  }

  /// Convenience for UI that wants "Admin · Acme Corp" in one call.
  Future<({String role, String companyName})?> getRoleAndCompanyName(String uid) async {
    final profile = await getUserProfile(uid);
    if (profile == null) return null;
    final companyId = profile['companyId'] as String?;
    if (companyId == null) return null;
    final companyName = await getCompanyName(companyId) ?? 'Unknown company';
    return (role: profile['role'] as String? ?? '', companyName: companyName);
  }

  Future<void> claimOrJoinCompany({String? companyName}) async {
    await _callApi('POST', '/claimOrJoinCompany', body: {
      if (companyName != null) 'companyName': companyName,
    });
  }

  /// Tier-2 NER is gated to the Enterprise plan, per the pricing copy
  /// already on the website — called once after sign-in, never cached
  /// indefinitely client-side.
  Future<({String plan, bool tier2Allowed})> getEntitlement() async {
    final data = await _callApi('GET', '/getEntitlement');
    return (
      plan: data['plan'] as String? ?? 'starter',
      tier2Allowed: data['tier2Allowed'] as bool? ?? false,
    );
  }

  /// Admin-only — writes an invites/{email} doc server-side so the next
  /// matching sign-in joins this admin's company instead of creating a
  /// new one (see claimOrJoinCompany).
  Future<void> inviteEmployee(String email) async {
    await _callApi('POST', '/inviteEmployee', body: {'email': email});
  }

  /// Pending invites for an admin's own company — allowed by
  /// firestore.rules directly (scoped to the caller's companyId), no
  /// server round-trip needed just to read.
  Stream<List<Map<String, dynamic>>> watchPendingInvites(String companyId) {
    return _firestore
        .collection('invites')
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => {...doc.data(), 'email': doc.id}).toList());
  }

  /// Saves this device's FCM token onto the signed-in user's own doc — the
  /// only field firestore.rules lets a client write directly on users/{uid}.
  Future<void> saveFcmToken(String uid, String token) {
    return _firestore.collection('users').doc(uid).update({'fcmToken': token});
  }
}
