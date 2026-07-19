/// Mirrors erp/desktop's WorkplaceSelectionOption.
class WorkplaceOption {
  final String id;
  final String name;
  final bool isOwn;

  const WorkplaceOption({required this.id, required this.name, this.isOwn = false});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'isOwn': isOwn};

  factory WorkplaceOption.fromJson(Map<String, dynamic> json) => WorkplaceOption(
        id: json['id'].toString(),
        name: (json['name'] ?? '').toString(),
        isOwn: json['isOwn'] == true,
      );
}
