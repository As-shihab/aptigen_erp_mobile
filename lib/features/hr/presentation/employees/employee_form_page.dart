import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/data/media_library_service.dart';
import '../../../../shared/ui/entity_crud.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../../../shared/widgets/media_library_dialog.dart';
import 'employee_shared.dart';

/// Multi-step create / edit form — port of erp/desktop's EmployeeForm.tsx.
/// Create runs the same flow as desktop: look the email up with
/// `auth/find-user`, sign the user up when unknown (default password),
/// add the `workplace_members` row when missing, then create the
/// `employees` row. Edit is a plain PUT plus the member-photo sync.
class EmployeeFormPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const EmployeeFormPage({super.key, this.existing});

  @override
  State<EmployeeFormPage> createState() => _EmployeeFormPageState();
}

class _Step {
  final String title;
  final String caption;
  final IconData icon;
  const _Step(this.title, this.caption, this.icon);
}

const _steps = [
  _Step('Basic information', 'Name, email and contact', Icons.person_outline_rounded),
  _Step('Organization', 'Department, role and shift', Icons.account_tree_outlined),
  _Step('Personal details', 'Identity and emergency contact', Icons.badge_outlined),
  _Step('Dates and addresses', 'Joining, birth and addresses', Icons.event_note_outlined),
];

class _EmployeeFormPageState extends State<EmployeeFormPage> {
  final _client = ApiClient();
  final _picker = ImagePicker();
  int _step = 0;
  bool _saving = false;
  bool _uploading = false;
  bool _sameAddress = false;

  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _contact = TextEditingController();
  final _empNo = TextEditingController();
  final _nid = TextEditingController();
  final _referred = TextEditingController();
  final _emName = TextEditingController();
  final _emNumber = TextEditingController();
  final _emRelation = TextEditingController();
  final _present = TextEditingController();
  final _permanent = TextEditingController();

  bool _active = true;
  bool _shiftFixed = false;
  bool _fingerprint = false;
  Object? _deptId;
  Object? _desgId;
  Object? _typeId;
  Object? _sectionId;
  Object? _shiftId;
  String? _gender;
  String? _religion;
  String? _blood;
  DateTime? _joining;
  DateTime? _dob;
  String _photo = '';

  Map<String, List<Map<String, dynamic>>> _lookups = {};
  bool _lookupsLoading = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _active = asBool(e['is_active'], fallback: true);
      _shiftFixed = asBool(e['is_shift_fixed']);
      _fingerprint = asBool(e['enable_fingerprint']);
      _first.text = str(e['first_name']);
      _last.text = str(e['last_name']);
      _email.text = str(e['email']);
      _contact.text = str(e['contact_number']);
      _empNo.text = str(e['employee_no']);
      _nid.text = str(e['nid']);
      _referred.text = str(e['referred_by']);
      _emName.text = str(e['emergency_contact_name']);
      _emNumber.text = str(e['emergency_contact_number']);
      _emRelation.text = str(e['emergency_contact_relation']);
      _present.text = str(e['present_address']);
      _permanent.text = str(e['permanent_address']);
      _deptId = e['department_id'];
      _desgId = e['designation_id'];
      _typeId = e['employee_type_id'];
      _sectionId = e['employee_section_id'];
      _shiftId = e['shift_id'];
      _gender = str(e['gender']).isEmpty ? null : str(e['gender']);
      _religion = str(e['religion']).isEmpty ? null : str(e['religion']);
      _blood = str(e['blood_group']).isEmpty ? null : str(e['blood_group']);
      _joining = parseDate(e['joining_date']);
      _dob = parseDate(e['date_of_birth']);
      _photo = str(e['profile_photo']);
    }
    for (final c in [_first, _last, _empNo]) {
      c.addListener(() => setState(() {}));
    }
    _present.addListener(() {
      if (_sameAddress && _permanent.text != _present.text) _permanent.text = _present.text;
    });
    _loadLookups();
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _email, _contact, _empNo, _nid, _referred, _emName, _emNumber, _emRelation, _present, _permanent]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLookups() async {
    const q = '\$select=id,name&\$filter=is_active eq true&\$top=500';
    try {
      final data = await batchLoad(_client, {
        'departments': 'departments?\$select=id,name&\$top=500',
        'designations': 'designations?$q',
        'types': 'employee_types?$q',
        'sections': 'employee_sections?$q',
        'shifts': 'employee_shifts?$q',
      });
      if (mounted) setState(() => _lookups = data);
    } catch (_) {
      // Dropdowns stay empty; the form itself still works.
    } finally {
      if (mounted) setState(() => _lookupsLoading = false);
    }
  }

  List<PickOption> _opts(String key) => [for (final r in _lookups[key] ?? const <Map<String, dynamic>>[]) PickOption(r['id'], str(r['name']))];

  int? _int(Object? v) => v == null ? null : int.tryParse(v.toString());
  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
  String? _d(DateTime? d) => d == null ? null : DateTime.utc(d.year, d.month, d.day).toIso8601String();

  // ── Photo ────────────────────────────────────────────────────────────

  Future<void> _photoActions() async {
    final key = await showActionSheet(context, title: 'Profile photo', actions: [
      (key: 'camera', label: 'Take a photo', icon: Icons.photo_camera_outlined, destructive: false),
      (key: 'gallery', label: 'Upload from gallery', icon: Icons.photo_library_outlined, destructive: false),
      (key: 'library', label: 'Choose from media library', icon: Icons.perm_media_outlined, destructive: false),
      if (_photo.isNotEmpty) (key: 'remove', label: 'Remove photo', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted || key == null) return;
    if (key == 'remove') return setState(() => _photo = '');
    if (key == 'library') {
      final picked = await showMediaLibraryDialog(context, title: 'Select profile photo', defaultCategoryName: 'Employees');
      if (picked != null && picked.isNotEmpty && mounted) setState(() => _photo = picked.first.fileUrl);
      return;
    }
    final file = await _picker.pickImage(source: key == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final service = MediaLibraryService(_client);
      final category = await service.ensureCategoryByName('Employees');
      final item = await service.uploadFile(bytes: await file.readAsBytes(), filename: file.name, categoryId: category.id);
      if (item != null && mounted) setState(() => _photo = item.fileUrl);
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not upload photo'), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────

  Future<void> _syncMemberPhoto(dynamic userId) async {
    if (userId == null) return;
    try {
      final res = await _client.get('workplace_members?\$filter=user_id eq $userId&\$select=id&\$top=1');
      final rows = unwrapList(res);
      final memberId = rows.isNotEmpty && rows.first is Map ? (rows.first as Map)['id'] : null;
      if (memberId != null) await _client.put('workplace_members', memberId, {'image_url': _photo.isEmpty ? null : _photo});
    } catch (_) {
      // non-critical, same as desktop
    }
  }

  bool _validate() {
    if (_first.text.trim().isEmpty) {
      marketToast(context, 'First name is required', error: true);
      setState(() => _step = 0);
      return false;
    }
    if (_email.text.trim().isEmpty) {
      marketToast(context, 'Email is required', error: true);
      setState(() => _step = 0);
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _saving = true);
    final email = _email.text.trim();
    final body = <String, dynamic>{
      'is_active': _active,
      'is_shift_fixed': _shiftFixed,
      'enable_fingerprint': _fingerprint,
      'employee_no': _t(_empNo),
      'first_name': _first.text.trim(),
      'last_name': _t(_last),
      'email': email,
      'contact_number': _t(_contact),
      'department_id': _int(_deptId),
      'designation_id': _int(_desgId),
      'employee_type_id': _int(_typeId),
      'employee_section_id': _int(_sectionId),
      'shift_id': _shiftFixed ? _int(_shiftId) : null,
      'gender': _gender,
      'religion': _religion,
      'nid': _t(_nid),
      'referred_by': _t(_referred),
      'emergency_contact_name': _t(_emName),
      'emergency_contact_number': _t(_emNumber),
      'emergency_contact_relation': _t(_emRelation),
      'blood_group': _blood,
      'joining_date': _d(_joining),
      'date_of_birth': _d(_dob),
      'present_address': _t(_present),
      'permanent_address': _t(_permanent),
      'profile_photo': _photo.isEmpty ? null : _photo,
    };
    try {
      String done;
      if (_isEdit) {
        await _client.put('employees', widget.existing!['id'], body);
        await _syncMemberPhoto(widget.existing!['user_id']);
        done = 'Employee updated';
      } else {
        final check = await _client.get('auth/find-user?email=${Uri.encodeComponent(email)}', isV8: false);
        final existingUserId = check is Map ? check['userId'] : null;
        if (existingUserId != null) {
          final inWorkplace = asBool(check['inWorkplace']);
          if (!inWorkplace) {
            await _client.post('workplace_members', {'user_id': existingUserId, 'role': 'employee', 'image_url': _photo.isEmpty ? null : _photo}, isV8: true);
          }
          await _client.post('employees', {...body, 'user_id': existingUserId}, isV8: true);
          await _syncMemberPhoto(existingUserId);
          done = inWorkplace ? 'Employee created' : 'Existing user added as an employee of this workplace';
        } else {
          final last = _last.text.trim();
          final userRes = await _client.post('auth/signup', {
            'email': email,
            if (_contact.text.trim().isNotEmpty) 'phone': _contact.text.trim(),
            'password': 'aptigen321',
            'name': '${_first.text.trim()}${last.isNotEmpty ? ' $last' : ''}',
          });
          final userId = userRes is Map && userRes['user'] is Map ? (userRes['user'] as Map)['id'] : null;
          if (userId == null) throw ApiException(0, 'User creation did not return an ID');
          await _client.post('workplace_members', {'user_id': userId, 'role': 'employee', 'image_url': _photo.isEmpty ? null : _photo}, isV8: true);
          await _client.post('employees', {...body, 'user_id': userId}, isV8: true);
          done = 'Employee created';
        }
      }
      if (!mounted) return;
      marketToast(context, done);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      marketToast(context, errorMessage(e, 'Failed to save employee'), error: true);
    }
  }

  void _next() {
    if (_step == 0 && (_first.text.trim().isEmpty || _email.text.trim().isEmpty)) {
      _validate();
      return;
    }
    if (_step < _steps.length - 1) {
      FocusScope.of(context).unfocus();
      setState(() => _step++);
    } else {
      _save();
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final isLast = _step == _steps.length - 1;
    return PopScope(
      canPop: _step == 0 || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        backgroundColor: p.bg,
        body: Column(children: [
          _header(context),
          _stepper(context),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(anim), child: child),
              ),
              child: SingleChildScrollView(
                key: ValueKey(_step),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, w) in _stepFields(context).indexed) FadeSlideIn(index: i, offsetY: 12, child: w),
                ]),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
              child: Row(children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  child: _step == 0
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : () => setState(() => _step--),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            icon: const Icon(Icons.arrow_back_rounded, size: 18),
                            label: const Text('Back'),
                          ),
                        ),
                ),
                Expanded(
                  child: GradientButton(
                    label: isLast ? (_isEdit ? 'Save changes' : 'Create employee') : 'Next',
                    icon: isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                    busy: _saving,
                    onTap: _uploading ? null : _next,
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final name = [_first.text.trim(), _last.text.trim()].where((s) => s.isNotEmpty).join(' ');
    final desg = lookupName(_lookups['designations'], _desgId);
    final photo = absMediaUrl(_photo);
    Widget avatar = InitialsAvatar(name.isEmpty ? 'New employee' : name, imageUrl: photo, size: 76);
    if (_isEdit) avatar = Hero(tag: 'employee-avatar-${widget.existing!['id']}', child: avatar);
    return Container(
      padding: EdgeInsets.fromLTRB(8, top + 4, 16, 18),
      decoration: BoxDecoration(gradient: Accent.ocean.gradient),
      child: Column(children: [
        Row(children: [
          IconButton(onPressed: _saving ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
          Expanded(
            child: Text(_isEdit ? 'Edit employee' : 'Add employee', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          if (_isEdit)
            TextButton(
              onPressed: _saving || _uploading ? null : _save,
              child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const SizedBox(width: 8),
          PressScale(
            onTap: _uploading ? null : _photoActions,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                child: avatar,
              ),
              if (_uploading)
                const Positioned.fill(child: Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white)))),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6)]),
                  child: Icon(Icons.photo_camera_rounded, size: 16, color: Accent.ocean.primary),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(name.isEmpty ? 'New employee' : name,
                    key: ValueKey(name), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              if (desg.isNotEmpty) Text(desg, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _headerPill(_active ? 'Active' : 'Inactive', _active ? Icons.check_circle_rounded : Icons.pause_circle_rounded),
                if (_empNo.text.trim().isNotEmpty) _headerPill('#${_empNo.text.trim()}', Icons.tag_rounded),
              ]),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _headerPill(String label, IconData icon) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _stepper(BuildContext context) {
    final p = MarketPalette.of(context);
    final s = _steps[_step];
    return Container(
      color: p.card,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 0; i < _steps.length; i++) ...[
            Expanded(
              child: GestureDetector(
                onTap: _saving ? null : () => setState(() => _step = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: i <= _step ? Accent.ocean.gradient : null,
                    color: i <= _step ? null : p.surface,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            if (i < _steps.length - 1) const SizedBox(width: 6),
          ],
        ]),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: Row(key: ValueKey(_step), children: [
            AccentIcon(s.icon, accent: Accent.ocean, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Step ${_step + 1} of ${_steps.length} · ${s.title}', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
                Text(s.caption, style: TextStyle(fontSize: 12, color: p.label)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _text(String label, TextEditingController c,
          {String? hint, IconData? icon, bool required = false, TextInputType? keyboard, bool readOnly = false, int lines = 1, String? help}) =>
      FormLabel(
        label: label,
        required: required,
        help: help,
        child: TextField(
          controller: c,
          readOnly: readOnly,
          keyboardType: keyboard,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          decoration: motionInput(context, hint: hint, icon: icon),
        ),
      );

  Widget _lookup(String label, String key, Object? value, ValueChanged<Object?> onChanged, IconData icon) => FormLabel(
        label: label,
        child: PickerField(
          value: value,
          hint: _lookupsLoading ? 'Loading…' : 'Select ${label.toLowerCase()}',
          icon: icon,
          options: _opts(key),
          onChanged: onChanged,
        ),
      );

  List<Widget> _stepFields(BuildContext context) {
    switch (_step) {
      case 0:
        return [
          _text('First name', _first, hint: 'e.g. John', icon: Icons.person_outline_rounded, required: true),
          _text('Last name', _last, hint: 'e.g. Smith', icon: Icons.person_outline_rounded),
          _text('Email address', _email, hint: 'email@company.com', icon: Icons.alternate_email_rounded, required: true, keyboard: TextInputType.emailAddress, readOnly: false),
          _text('Contact number', _contact, hint: '+880 1xxx xxxxxx', icon: Icons.phone_outlined, keyboard: TextInputType.phone),
          _text('Employee ID', _empNo,
              hint: 'Auto / manual ID', icon: Icons.tag_rounded, readOnly: _isEdit, help: _isEdit ? 'Employee ID cannot be changed after creation.' : null),
        ];
      case 1:
        return [
          _lookup('Department', 'departments', _deptId, (v) => setState(() => _deptId = v), Icons.account_tree_outlined),
          _lookup('Designation', 'designations', _desgId, (v) => setState(() => _desgId = v), Icons.workspace_premium_outlined),
          _lookup('Employee type', 'types', _typeId, (v) => setState(() => _typeId = v), Icons.category_outlined),
          _lookup('Section', 'sections', _sectionId, (v) => setState(() => _sectionId = v), Icons.view_module_outlined),
          const SizedBox(height: 4),
          SwitchField(label: 'Active', sub: 'Inactive employees cannot punch in', value: _active, onChanged: (v) => setState(() => _active = v)),
          SwitchField(label: 'Shift fixed', sub: 'Always work the same shift', value: _shiftFixed, onChanged: (v) => setState(() => _shiftFixed = v)),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: _shiftFixed ? _lookup('Shift', 'shifts', _shiftId, (v) => setState(() => _shiftId = v), Icons.schedule_rounded) : const SizedBox(width: double.infinity),
          ),
          SwitchField(label: 'Enable fingerprint', sub: 'Allow fingerprint attendance', value: _fingerprint, onChanged: (v) => setState(() => _fingerprint = v)),
        ];
      case 2:
        return [
          FormLabel(label: 'Gender', child: StringChoice(options: employeeGenders, value: _gender, onChanged: (v) => setState(() => _gender = v))),
          FormLabel(label: 'Religion', child: StringChoice(options: employeeReligions, value: _religion, onChanged: (v) => setState(() => _religion = v))),
          FormLabel(label: 'Blood group', child: StringChoice(options: employeeBloodGroups, value: _blood, onChanged: (v) => setState(() => _blood = v))),
          _text('NID / birth certificate', _nid, hint: 'NID or birth cert number', icon: Icons.credit_card_outlined),
          _text('Referred by', _referred, hint: 'Referral name', icon: Icons.record_voice_over_outlined),
          SectionHeader('Emergency contact', subtitle: 'Who to call in an emergency'),
          _text('Contact name', _emName, hint: 'Full name', icon: Icons.contact_emergency_outlined),
          _text('Contact number', _emNumber, hint: 'Phone number', icon: Icons.phone_in_talk_outlined, keyboard: TextInputType.phone),
          _text('Relation', _emRelation, hint: 'e.g. Father, spouse', icon: Icons.family_restroom_outlined),
        ];
      default:
        return [
          FormLabel(label: 'Date of joining', child: DatePickField(value: _joining, onChanged: (d) => setState(() => _joining = d))),
          FormLabel(label: 'Date of birth', child: DatePickField(value: _dob, lastDate: DateTime.now(), onChanged: (d) => setState(() => _dob = d))),
          _text('Present address', _present, hint: 'Enter present address', lines: 2),
          SwitchField(
            label: 'Same as present address',
            value: _sameAddress,
            onChanged: (v) {
              if (v && _present.text.trim().isEmpty) {
                marketToast(context, 'Enter the present address first', error: true);
                return;
              }
              setState(() {
                _sameAddress = v;
                if (v) _permanent.text = _present.text;
              });
            },
          ),
          _text('Permanent address', _permanent, hint: 'Enter permanent address', lines: 2, readOnly: _sameAddress),
        ];
    }
  }
}
