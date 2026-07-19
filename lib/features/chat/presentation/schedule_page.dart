import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/network/http_client.dart';
import '../../../core/network/socket_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_service.dart';
import '../models/chat_model.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final _service = ChatService(ApiClient());
  SocketContext? _context;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<Map<String, dynamic>> _meetings = [];
  List<Map<String, dynamic>> _rooms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final context = await _service.resolveContext();
      if (context == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final from = DateTime(_month.year, _month.month, 1);
      final to = DateTime(_month.year, _month.month + 1, 0, 23, 59, 59);
      final meetings = await _service.loadMeetingsForRange(workplaceId: context.workplaceId, from: from, to: to);
      if (!mounted) return;
      setState(() {
        _context = context;
        _meetings = meetings;
      });
    } catch (_) {
      // leave list empty on failure
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRoomsIfNeeded() async {
    if (_rooms.isNotEmpty || _context == null) return;
    try {
      final result = await _service.loadGroupsForMember(_context!.memberId);
      if (!mounted) return;
      setState(() => _rooms = result.rooms);
    } catch (_) {
      // room picker is optional
    }
  }

  Future<void> _openNewMeetingDialog([DateTime? prefillDate]) async {
    final scheduleContext = _context;
    if (scheduleContext == null) return;
    await _loadRoomsIfNeeded();
    if (!mounted) return;

    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final locationController = TextEditingController();
    var scheduledAt = prefillDate ?? DateTime.now();
    var durationMinutes = 30;
    var mode = 'video';
    int? roomId;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New Meeting', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 12),
                TextField(controller: descriptionController, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(DateFormat('dd MMM yyyy, hh:mm a').format(scheduledAt)),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: sheetContext,
                      initialDate: scheduledAt,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date == null) return;
                    if (!sheetContext.mounted) return;
                    final time = await showTimePicker(context: sheetContext, initialTime: TimeOfDay.fromDateTime(scheduledAt));
                    if (time == null) return;
                    setSheetState(() => scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(labelText: 'Duration (min)'),
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(text: durationMinutes.toString()),
                        onChanged: (value) => durationMinutes = int.tryParse(value) ?? 30,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'video', label: Text('Video')),
                          ButtonSegment(value: 'voice', label: Text('Voice')),
                        ],
                        selected: {mode},
                        onSelectionChanged: (selection) => setSheetState(() => mode = selection.first),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: roomId,
                  decoration: const InputDecoration(labelText: 'Link to a group (optional)'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('No room')),
                    ..._rooms.map((room) => DropdownMenuItem<int?>(value: toNum(room['id']), child: Text((room['name'] ?? 'Room').toString()))),
                  ],
                  onChanged: (value) => setSheetState(() => roomId = value),
                ),
                const SizedBox(height: 12),
                TextField(controller: locationController, decoration: const InputDecoration(labelText: 'Location')),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final title = titleController.text.trim();
                      if (title.isEmpty) return;
                      try {
                        await _service.createMeeting(
                          workplaceId: scheduleContext.workplaceId,
                          title: title,
                          description: descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
                          scheduledAtIso: scheduledAt.toUtc().toIso8601String(),
                          durationMinutes: durationMinutes,
                          mode: mode,
                          location: locationController.text.trim().isEmpty ? null : locationController.text.trim(),
                          roomId: roomId,
                          createdByMemberId: scheduleContext.memberId,
                        );
                        if (!sheetContext.mounted) return;
                        Navigator.of(sheetContext).pop();
                        _load();
                      } catch (_) {
                        if (!sheetContext.mounted) return;
                        ScaffoldMessenger.of(sheetContext).showSnackBar(const SnackBar(content: Text('Could not create meeting.')));
                      }
                    },
                    child: const Text('Create Meeting'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _joinMeeting(Map<String, dynamic> meeting) {
    final roomId = toNum(meeting['room_id']);
    if (roomId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No room linked to this meeting.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open Groups to join this meeting\'s room.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _openNewMeetingDialog(), icon: const Icon(Icons.add), label: const Text('Meeting')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() => _month = DateTime(_month.year, _month.month - 1, 1));
                    _load();
                  },
                ),
                Expanded(child: Center(child: Text(DateFormat('MMMM yyyy').format(_month), style: const TextStyle(fontWeight: FontWeight.w700)))),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() => _month = DateTime(_month.year, _month.month + 1, 1));
                    _load();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                : _meetings.isEmpty
                    ? Center(child: Text('No meetings scheduled this month.', style: TextStyle(color: AppColors.slate600)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                          itemCount: _meetings.length,
                          itemBuilder: (context, index) {
                            final meeting = _meetings[index];
                            final scheduledAt = DateTime.tryParse((meeting['scheduled_at'] ?? '').toString())?.toLocal();
                            final mode = (meeting['mode'] ?? 'video').toString();
                            final location = (meeting['location'] ?? '').toString();
                            final roomName = ((meeting['room'] as Map?)?['name'] ?? '').toString();
                            final createdBy = toNum(meeting['created_by_member_id']);
                            final isMine = _context != null && createdBy == _context!.memberId;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: Icon(mode == 'video' ? Icons.videocam : Icons.call, color: AppColors.brand),
                                title: Text((meeting['title'] ?? 'Meeting').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  '${scheduledAt != null ? DateFormat('dd MMM, hh:mm a').format(scheduledAt) : '—'}\n${location.isNotEmpty ? location : (roomName.isNotEmpty ? roomName : 'No location set')}',
                                ),
                                isThreeLine: true,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(onPressed: () => _joinMeeting(meeting), child: const Text('Join')),
                                    if (isMine)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 20),
                                        onPressed: () async {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (dialogContext) => AlertDialog(
                                              title: const Text('Delete Meeting'),
                                              content: const Text('This meeting will be permanently removed.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
                                                TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
                                              ],
                                            ),
                                          );
                                          if (confirmed != true) return;
                                          try {
                                            await ApiClient().delete('chat_meetings', toNum(meeting['id']));
                                            _load();
                                          } catch (_) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete meeting.')));
                                          }
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
