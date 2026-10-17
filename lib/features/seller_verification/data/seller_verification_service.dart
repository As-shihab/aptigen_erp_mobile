import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../../core/network/http_client.dart';

/// The store's verification state (GET /api/market/seller-verification).
class SellerVerificationStatus {
  final int? storeId;
  final String? storeName;
  final bool isVerified;
  final String? latestStatus; // pending | approved | rejected
  final String? maskedNid;
  final String? fullName;
  final String? rejectionReason;
  final DateTime? submittedAt;

  const SellerVerificationStatus({
    this.storeId,
    this.storeName,
    this.isVerified = false,
    this.latestStatus,
    this.maskedNid,
    this.fullName,
    this.rejectionReason,
    this.submittedAt,
  });

  bool get hasProfile => storeId != null;
  bool get pending => latestStatus == 'pending';
  bool get rejected => latestStatus == 'rejected';

  factory SellerVerificationStatus.fromJson(dynamic json) {
    final body = json is Map<String, dynamic> && json['value'] is Map<String, dynamic> ? json['value'] : json;
    final profile = body is Map ? body['profile'] as Map? : null;
    final latest = body is Map ? body['latest'] as Map? : null;
    return SellerVerificationStatus(
      storeId: profile?['id'] is num ? (profile!['id'] as num).toInt() : null,
      storeName: profile?['store_name'] as String?,
      isVerified: profile?['is_verified'] == true,
      latestStatus: latest?['status'] as String?,
      maskedNid: latest?['nid_number'] as String?,
      fullName: latest?['full_name'] as String?,
      rejectionReason: latest?['rejection_reason'] as String?,
      submittedAt: latest?['created_at'] is String ? DateTime.tryParse(latest!['created_at'] as String) : null,
    );
  }
}

class SellerVerificationService {
  final ApiClient _client;
  SellerVerificationService(this._client);

  static const _endpoint = 'market/seller-verification';

  Future<SellerVerificationStatus> status() async =>
      SellerVerificationStatus.fromJson(await _client.get(_endpoint, isV8: false));

  /// Sends the NID details and the three photos (JPEG bytes from the camera).
  Future<void> submit({
    required String nidNumber,
    required String fullName,
    String? dateOfBirth,
    String? scannedData,
    required Uint8List front,
    required Uint8List back,
    required Uint8List selfie,
  }) async {
    http.MultipartFile part(String field, Uint8List bytes) =>
        http.MultipartFile.fromBytes(field, bytes, filename: '$field.jpg', contentType: MediaType('image', 'jpeg'));
    await _client.uploadMultipart(
      _endpoint,
      fields: {
        'nid_number': nidNumber,
        'full_name': fullName,
        if (dateOfBirth != null && dateOfBirth.isNotEmpty) 'date_of_birth': dateOfBirth,
        if (scannedData != null && scannedData.isNotEmpty) 'scanned_data': scannedData,
      },
      files: [part('front', front), part('back', back), part('selfie', selfie)],
    );
  }
}
