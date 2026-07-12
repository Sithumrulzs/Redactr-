import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

// See server/index.js — the plain Express app that replaced the Cloud
// Functions (which needed the Blaze billing plan), hosted on Render.
const _apiBaseUrl = "https://redactr-ln5t.onrender.com";

/// Thin wrapper around the `users/{uid}` Firestore doc and the small
/// Express API in ../../../server/index.js (claimOrJoinCompany,
/// inviteEmployee, getEntitlement). Reads are direct Firestore (allowed by
/// firestore.rules for your own doc); the company-creating/joining write
/// always goes through the server, never a direct client write.
class CompanyService {
  final FirebaseFirestore _firestore;

  CompanyService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<Map<String, dynamic>> _callApi(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in.');

    final idToken = await user.getIdToken();
    final uri = Uri.parse('$_apiBaseUrl$path');
    final headers = {
      'Authorization': 'Bearer $idToken',
      'Content-Type': 'application/json',
    };

    // 30s timeout — Render free tier can cold-start for ~20s.
    const timeout = Duration(seconds: 30);

    final response = method == 'GET'
        ? await http.get(uri, headers: headers).timeout(timeout)
        : await http
            .post(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(timeout);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(
        data['error'] as String? ?? 'Request failed (${response.statusCode}).',
      );
    }
    return data;
  }

  /// Null means this user has no company yet (needs CompanySetupScreen).
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  Future<String?> getCompanyName(String companyId) async {
    final doc = await _firestore.collection('companies').doc(companyId).get();
    return doc.data()?['name'] as String?;
  }

  /// Convenience for UI that wants "Admin · Acme Corp" in one call.
  Future<({String role, String companyName})?> getRoleAndCompanyName(
    String uid,
  ) async {
    final profile = await getUserProfile(uid);
    if (profile == null) return null;
    final companyId = profile['companyId'] as String?;
    if (companyId == null) return null;
    final companyName = await getCompanyName(companyId) ?? 'Unknown company';
    return (role: profile['role'] as String? ?? '', companyName: companyName);
  }

  /// Returns { companyId, role } on success so callers can use the result
  /// directly without a Firestore round-trip (avoids client-cache staleness).
  Future<Map<String, dynamic>> claimOrJoinCompany({String? companyName}) async {
    return await _callApi(
      'POST',
      '/claimOrJoinCompany',
      body: companyName != null ? {'companyName': companyName} : {},
    );
  }

  /// Tier-2 NER is gated to the Enterprise plan, per the pricing copy
  /// already on the website — called once after sign-in, never cached
  /// indefinitely client-side. Trial users return plan="trial" with
  /// trialDaysLeft and trialExpired populated.
  Future<({String plan, bool tier2Allowed, List<String> customKeywords, List<String> customEntities, int trialDaysLeft, bool trialExpired})>
  getEntitlement() async {
    final data = await _callApi('GET', '/getEntitlement');
    return (
      plan: data['plan'] as String? ?? 'starter',
      tier2Allowed: data['tier2Allowed'] as bool? ?? false,
      customKeywords:
          (data['customKeywords'] as List<dynamic>?)?.cast<String>() ??
          const [],
      customEntities:
          (data['customEntities'] as List<dynamic>?)?.cast<String>() ??
          const [],
      trialDaysLeft: (data['trialDaysLeft'] as num?)?.toInt() ?? 0,
      trialExpired: data['trialExpired'] as bool? ?? false,
    );
  }

  /// Activates a 7-day free trial for the signed-in user. Safe to call
  /// repeatedly — returns immediately if a trial is already active.
  Future<DateTime> createTrial() async {
    final data = await _callApi('POST', '/createTrial');
    final trialEnd = data['trialEnd'] as String?;
    if (trialEnd == null) throw Exception('Server did not return a trial end date.');
    return DateTime.parse(trialEnd);
  }

  /// Admin-only — writes an invites/{email} doc server-side so the next
  /// matching sign-in joins this admin's company instead of creating a
  /// new one (see claimOrJoinCompany).
  Future<void> inviteEmployee(String email) async {
    await _callApi('POST', '/inviteEmployee', body: {'email': email});
  }

  /// Enterprise + admin-only. Literal phrases, not regex — the matching
  /// server route deliberately rejects arbitrary patterns to avoid a
  /// ReDoS risk running in every employee's browser.
  Future<List<String>> addCustomKeyword(String keyword) async {
    final data = await _callApi(
      'POST',
      '/addCustomKeyword',
      body: {'keyword': keyword},
    );
    return (data['customKeywords'] as List<dynamic>?)?.cast<String>() ??
        const [];
  }

  Future<void> removeCustomKeyword(String keyword) async {
    await _callApi('POST', '/removeCustomKeyword', body: {'keyword': keyword});
  }

  /// Enterprise + admin-only. Plain-English concept labels (e.g. "internal
  /// project codename") that the GLiNER Tier-2 engine matches on-device.
  /// Server validates: non-empty, ≤40 chars, letters/digits/spaces/hyphens.
  Future<List<String>> addCustomEntity(String label) async {
    final data = await _callApi(
      'POST',
      '/addCustomEntity',
      body: {'label': label},
    );
    return (data['customEntities'] as List<dynamic>?)?.cast<String>() ??
        const [];
  }

  Future<void> removeCustomEntity(String label) async {
    await _callApi('POST', '/removeCustomEntity', body: {'label': label});
  }

  /// Pending invites for an admin's own company — allowed by
  /// firestore.rules directly (scoped to the caller's companyId), no
  /// server round-trip needed just to read.
  Stream<List<Map<String, dynamic>>> watchPendingInvites(String companyId) {
    return _firestore
        .collection('invites')
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {...doc.data(), 'email': doc.id})
              .toList(),
        );
  }

  /// All users that belong to [companyId] — used by TeamScreen.
  Stream<List<Map<String, dynamic>>> watchTeamMembers(String companyId) {
    return _firestore
        .collection('users')
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => {...doc.data(), 'uid': doc.id})
            .toList());
  }

  /// Generates a 7-day download token for the extension zip. Only works for
  /// admins of companies with an active subscription (i.e. after purchase).
  /// Returns the full download URL ready to share.
  Future<String> generateDownloadLink() async {
    final data = await _callApi('POST', '/generateDownloadToken');
    final url = data['downloadUrl'] as String?;
    if (url == null) throw Exception('Server did not return a download URL.');
    return url;
  }

  /// Deletes the caller's users/{uid} Firestore doc. Must be followed by
  /// Firebase Auth user.delete() on the client to fully remove the account.
  Future<void> deleteUserData() async {
    await _callApi('POST', '/deleteAccount');
  }

  /// Saves this device's FCM token onto the signed-in user's own doc — the
  /// only field firestore.rules lets a client write directly on users/{uid}.
  Future<void> saveFcmToken(String uid, String token) {
    // set+merge instead of update() so this works even before the users doc exists.
    return _firestore
        .collection('users')
        .doc(uid)
        .set({'fcmToken': token}, SetOptions(merge: true));
  }
}
