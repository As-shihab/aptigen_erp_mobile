import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/jobs_service.dart';
import '../models/job_model.dart';
import 'job_detail_page.dart';

/// Read-only browse of this workplace's public job postings — mirrors
/// `frontend`'s customer-facing `/jobs` page, same public API
/// (`GET /api/public/jobs`). No apply flow here (no CV/photo upload); this
/// is staff checking what's live, matching stays_list_page.dart's layout
/// convention (search + status chips + card list).
class JobsListPage extends StatefulWidget {
  const JobsListPage({super.key});

  @override
  State<JobsListPage> createState() => _JobsListPageState();
}

class _JobsListPageState extends State<JobsListPage> {
  final _service = JobsService(ApiClient());
  final _searchController = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  String? _statusFilter; // null | 'open' | 'on_hold' | 'closed'
  List<Job> _jobs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _service.loadJobs(status: _statusFilter, query: _searchController.text);
      if (!mounted) return;
      setState(() => _jobs = result);
    } catch (_) {
      // leave whatever's already loaded on failure
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  void _onStatusSelected(String? value) {
    setState(() => _statusFilter = _statusFilter == value ? null : value);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jobs')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search jobs…', isDense: true),
                onChanged: _onSearchChanged,
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _statusChip(null, 'All'),
                  _statusChip('open', 'Open'),
                  _statusChip('on_hold', 'On Hold'),
                  _statusChip('closed', 'Closed'),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String? value, String label) {
    final selected = _statusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _onStatusSelected(value),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.brand));
    }

    if (_jobs.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.work_outline, size: 40, color: AppColors.slate400),
          const SizedBox(height: 12),
          Center(
            child: Text('No job postings found.', style: TextStyle(color: AppColors.slate600)),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _jobs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _JobCard(
        job: _jobs[index],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => JobDetailPage(jobId: _jobs[index].id)),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;
  const _JobCard({required this.job, required this.onTap});

  Color _statusColor() {
    switch (job.status) {
      case 'open':
        return AppColors.success;
      case 'closed':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(job.title.isEmpty ? 'Untitled posting' : job.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _statusColor().withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: Text(job.status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _statusColor())),
                ),
              ],
            ),
            if (job.department != null || job.employmentType != null) ...[
              const SizedBox(height: 4),
              Text(
                [job.department, job.employmentType].where((s) => (s ?? '').isNotEmpty).join(' · '),
                style: TextStyle(fontSize: 12, color: AppColors.slate600),
              ),
            ],
            if ((job.location ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 13, color: AppColors.slate600),
                  const SizedBox(width: 3),
                  Expanded(child: Text(job.location!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.slate600))),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (job.salaryRange != null)
                  Text(job.salaryRange!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const Spacer(),
                Icon(Icons.people_outline, size: 14, color: AppColors.slate600),
                const SizedBox(width: 3),
                Text('${job.applicationsCount}', style: TextStyle(fontSize: 12, color: AppColors.slate600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
