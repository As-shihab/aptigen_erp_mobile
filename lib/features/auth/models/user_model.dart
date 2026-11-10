import 'workplace_model.dart';

class UserModel {
  final int id;
  final String name;
  final String email;
  final WorkplaceOption? selectedWorkplace;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.selectedWorkplace,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final workplaceJson = (json['selectedWorkplace'] ?? json['workplace']) as Map<String, dynamic>?;
    return UserModel(
      id: int.tryParse(json['id'].toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      selectedWorkplace: workplaceJson != null ? WorkplaceOption.fromJson(workplaceJson) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        if (selectedWorkplace != null) 'selectedWorkplace': selectedWorkplace!.toJson(),
        if (selectedWorkplace != null) 'workplace': selectedWorkplace!.toJson(),
      };

  UserModel copyWithWorkplace(WorkplaceOption workplace) => UserModel(
        id: id,
        name: name,
        email: email,
        selectedWorkplace: workplace,
      );

  /// The active workplace's name, or '' — for receipts, which print the
  /// workplace (e.g. "Walkbd") and nothing in its place when it's unknown.
  String get workplaceName => selectedWorkplace?.name.trim() ?? '';

  String get companyName => selectedWorkplace?.name.trim().isNotEmpty == true
      ? selectedWorkplace!.name
      : 'my company ltd';
}
