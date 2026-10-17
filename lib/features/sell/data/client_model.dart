import '../../store/data/store_util.dart';

/// `clients` — POS/Sales Order customer. Reuses Store's coercion helpers
/// (`toNum`/`toStringOrNull`/...) directly rather than duplicating them —
/// see store_util.dart, it's plain generic parsing, not Store-specific.
class Client {
  final int id;
  final int? groupId;
  final String? groupName;
  final String code;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? city;
  final String? country;
  final bool isActive;

  const Client({
    required this.id,
    this.groupId,
    this.groupName,
    required this.code,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.city,
    this.country,
    required this.isActive,
  });

  factory Client.fromJson(Map json) => Client(
        id: toNum(json['id']),
        groupId: toIntOrNull(json['group_id']),
        groupName: toStringOrNull((json['group'] as Map?)?['name']),
        code: (json['code'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        phone: toStringOrNull(json['phone']),
        email: toStringOrNull(json['email']),
        address: toStringOrNull(json['address']),
        city: toStringOrNull(json['city']),
        country: toStringOrNull(json['country']),
        isActive: toBool(json['is_active'], fallback: true),
      );
}
