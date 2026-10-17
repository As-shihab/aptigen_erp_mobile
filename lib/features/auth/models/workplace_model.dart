/// Mirrors erp/desktop's WorkplaceSelectionOption. `currency` is the
/// workplace's ISO 4217 code (`workplaces.currency`) — drives every amount
/// shown across the app, see `core/utils/currency.dart`.
class WorkplaceOption {
  final String id;
  final String name;
  final bool isOwn;
  final String currency;

  const WorkplaceOption({required this.id, required this.name, this.isOwn = false, this.currency = 'USD'});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'isOwn': isOwn, 'currency': currency};

  factory WorkplaceOption.fromJson(Map<String, dynamic> json) => WorkplaceOption(
        id: json['id'].toString(),
        name: (json['name'] ?? '').toString(),
        isOwn: json['isOwn'] == true,
        currency: (json['currency'] ?? '').toString().trim().isEmpty ? 'USD' : json['currency'].toString().trim(),
      );
}
