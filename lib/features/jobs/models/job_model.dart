int _toIntSafe(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

double? _toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  return double.tryParse(v.toString());
}

/// A public job posting — mirrors `frontend`'s customer-facing site
/// (`app/(public)/jobs`) and the backend's `PUBLIC_JOB_SELECT`
/// (`cloud/src/module/hrm/recruitment-public.service.ts`). Read-only here —
/// this is workplace staff browsing/checking their own postings, matching
/// what's live on the public site, not the apply flow (no CV/photo upload).
class Job {
  final int id;
  final String? customId;
  final String title;
  final String? department;
  final String? employmentType;
  final int vacancies;
  final double? salaryMin;
  final double? salaryMax;
  final String? location;
  final String? deadline;
  final String? description;
  final String? requirements;
  final String status; // 'open' | 'on_hold' | 'closed'
  final bool isActive;
  final int viewsCount;
  final int applicationsCount;
  final String? workplaceName;
  final String createdAt;

  const Job({
    required this.id,
    this.customId,
    required this.title,
    this.department,
    this.employmentType,
    this.vacancies = 1,
    this.salaryMin,
    this.salaryMax,
    this.location,
    this.deadline,
    this.description,
    this.requirements,
    this.status = 'open',
    this.isActive = true,
    this.viewsCount = 0,
    this.applicationsCount = 0,
    this.workplaceName,
    this.createdAt = '',
  });

  String? get salaryRange {
    if (salaryMin == null && salaryMax == null) return null;
    if (salaryMin != null && salaryMax != null) {
      return '${salaryMin!.toStringAsFixed(0)} - ${salaryMax!.toStringAsFixed(0)}';
    }
    return (salaryMin ?? salaryMax)!.toStringAsFixed(0);
  }

  factory Job.fromJson(Map<String, dynamic> json) {
    final workplace = json['workplace'];
    return Job(
      id: _toIntSafe(json['id']),
      customId: json['custom_id']?.toString(),
      title: (json['title'] ?? '').toString(),
      department: json['department']?.toString(),
      employmentType: json['employment_type']?.toString(),
      vacancies: json['vacancies'] != null ? _toIntSafe(json['vacancies']) : 1,
      salaryMin: _toDoubleOrNull(json['salary_min']),
      salaryMax: _toDoubleOrNull(json['salary_max']),
      location: json['location']?.toString(),
      deadline: json['deadline']?.toString(),
      description: json['description']?.toString(),
      requirements: json['requirements']?.toString(),
      status: (json['status'] ?? 'open').toString(),
      isActive: json['is_active'] != false,
      viewsCount: _toIntSafe(json['views_count']),
      applicationsCount: _toIntSafe(json['applications_count']),
      workplaceName: workplace is Map ? workplace['name']?.toString() : null,
      createdAt: (json['created_at'] ?? '').toString(),
    );
  }
}
