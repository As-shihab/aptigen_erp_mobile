import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/jobs_service.dart';
import '../models/job_model.dart';

/// Read-only detail view for one job posting — no apply flow (that's the
/// public site's job, with CV/photo upload); staff just need to see the
/// full description/requirements here.
class JobDetailPage extends StatefulWidget {
  final int jobId;
  const JobDetailPage({super.key, required this.jobId});

  @override
  State<JobDetailPage> createState() => _JobDetailPageState();
}

class _JobDetailPageState extends State<JobDetailPage> {
  final _service = JobsService(ApiClient());
  bool _loading = true;
  Job? _job;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final job = await _service.loadJob(widget.jobId);
      if (!mounted) return;
      setState(() => _job = job);
    } catch (_) {
      // leave _job null — the empty state below covers it
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    return Scaffold(
      appBar: AppBar(title: Text(job?.title ?? 'Job details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
          : job == null
              ? Center(child: Text('Could not load this job posting.', style: TextStyle(color: AppColors.slate600)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(job.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (job.department != null) _tag(job.department!),
                        if (job.employmentType != null) _tag(job.employmentType!),
                        if ((job.location ?? '').isNotEmpty) _tag(job.location!),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _statRow(),
                    if ((job.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _sectionTitle('Description'),
                      const SizedBox(height: 6),
                      Text(job.description!, style: const TextStyle(fontSize: 14, height: 1.5)),
                    ],
                    if ((job.requirements ?? '').isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _sectionTitle('Requirements'),
                      const SizedBox(height: 6),
                      Text(job.requirements!, style: const TextStyle(fontSize: 14, height: 1.5)),
                    ],
                  ],
                ),
    );
  }

  Widget _sectionTitle(String text) => Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15));

  Widget _tag(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 12, color: AppColors.slate600, fontWeight: FontWeight.w600)),
      );

  Widget _statRow() {
    final job = _job!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          _stat(Icons.payments_outlined, job.salaryRange ?? '—', 'Salary'),
          _stat(Icons.groups_outlined, '${job.vacancies}', 'Vacancies'),
          _stat(Icons.people_outline, '${job.applicationsCount}', 'Applicants'),
          _stat(Icons.visibility_outlined, '${job.viewsCount}', 'Views'),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) => Expanded(
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppColors.brand),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(label, style: TextStyle(fontSize: 10, color: AppColors.slate600)),
          ],
        ),
      );
}
