import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Settings → User list. Mirrors desktop UserList.tsx: workplace members
/// with their user, add (signup + member + roles), edit (user, member,
/// roles, photo, active), activate / deactivate, force logout, overview and
/// remove.
class UserListPage extends StatefulWidget {
  const UserListPage({super.key});

  @override
  State<UserListPage> createState() => _UserListPageState();
}

String memberName(JsonRow m) {
  final n = nested(m, 'user', 'name');
  return n.isNotEmpty ? n : str(m['name']);
}

String memberEmail(JsonRow m) {
  final e = nested(m, 'user', 'email');
  return e.isNotEmpty ? e : str(m['email']);
}

bool memberActive(JsonRow m) {
  if (m['is_active'] is bool) return m['is_active'] as bool;
  final s = str(m['status']).toLowerCase();
  if (s.isNotEmpty) return s == 'active';
  return true;
}

int? memberUserId(JsonRow m) => positiveInt(m['user_id'] ?? (m['user'] is Map ? m['user']['id'] : null));

class _UserListPageState extends State<UserListPage> {
  final _svc = UsersService();
  List<JsonRow> _members = [];
  List<JsonRow> _roles = [];
  bool _loading = true;
  String? _error;
  String _q = '';
  String _chip = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _members.isEmpty;
      _error = null;
    });
    try {
      final res = await _svc.load();
      if (!mounted) return;
      setState(() {
        _members = res.members;
        _roles = res.roles;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load users'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<JsonRow> get _visible {
    final q = _q.trim().toLowerCase();
    return _members.where((m) {
      if (_chip == 'active' && !memberActive(m)) return false;
      if (_chip == 'inactive' && memberActive(m)) return false;
      if (q.isEmpty) return true;
      return '${memberName(m)} ${memberEmail(m)} ${str(m['role'])}'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _form([JsonRow? m]) async {
    final ok = await showMotionSheet<bool>(context, (_) => UserFormSheet(member: m, roles: _roles, svc: _svc));
    if (ok == true) {
      if (mounted) marketToast(context, m == null ? 'User created' : 'User updated');
      _load();
    }
  }

  Future<void> _toggleActive(JsonRow m) async {
    final id = positiveInt(m['id']);
    if (id == null) return;
    final next = !memberActive(m);
    setState(() => m['is_active'] = next);
    try {
      await _svc.setActive(id, next);
      if (mounted) marketToast(context, next ? 'User activated' : 'User deactivated');
    } catch (e) {
      if (!mounted) return;
      setState(() => m['is_active'] = !next);
      marketToast(context, errorMessage(e, 'Could not update user'), error: true);
    }
  }

  void _logout(JsonRow m) {
    final target = memberEmail(m).isNotEmpty ? memberEmail(m) : '${memberUserId(m) ?? ''}';
    if (target.isEmpty) {
      marketToast(context, 'Could not determine target user', error: true);
      return;
    }
    final sent = _svc.forceLogout(target);
    marketToast(context, sent ? 'Logout request sent' : 'Live connection is offline, try again shortly', error: !sent);
  }

  Future<bool> _delete(JsonRow m) async {
    final id = positiveInt(m['id']);
    if (id == null) return false;
    final ok = await confirmMarket(context, title: 'Remove user?', message: '"${memberName(m)}" will lose access to this workplace.', confirm: 'Remove');
    if (!ok) return false;
    try {
      await _svc.removeMember(id);
      if (!mounted) return true;
      setState(() => _members.removeWhere((x) => x['id'] == m['id']));
      marketToast(context, 'User removed');
      return true;
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not remove user'), error: true);
      return false;
    }
  }

  Future<void> _actions(JsonRow m) async {
    final active = memberActive(m);
    final key = await showActionSheet(context, title: memberName(m), actions: [
      (key: 'view', label: 'Overview', icon: Icons.visibility_outlined, destructive: false),
      (key: 'edit', label: 'Edit', icon: Icons.edit_outlined, destructive: false),
      (key: 'toggle', label: active ? 'Deactivate' : 'Activate', icon: active ? Icons.person_off_outlined : Icons.person_add_alt_1_outlined, destructive: false),
      (key: 'logout', label: 'Force logout', icon: Icons.logout_rounded, destructive: false),
      (key: 'delete', label: 'Remove from workplace', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted || key == null) return;
    switch (key) {
      case 'view':
        _overview(m);
      case 'edit':
        _form(m);
      case 'toggle':
        _toggleActive(m);
      case 'logout':
        _logout(m);
      case 'delete':
        _delete(m);
    }
  }

  void _overview(JsonRow m) {
    showMotionSheet<void>(context, (ctx) {
      final p = MarketPalette.of(ctx);
      final active = memberActive(m);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SheetGrabber(),
            FadeSlideIn(child: InitialsAvatar(memberName(m), imageUrl: str(m['image_url']), size: 76)),
            const SizedBox(height: 10),
            Text(memberName(m).isEmpty ? 'Unnamed user' : memberName(m), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
            Text(memberEmail(m), style: TextStyle(fontSize: 13, color: p.label)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              StatusPill(active ? 'Active' : 'Inactive', tone: active ? MarketTone.ok : MarketTone.error),
              const SizedBox(width: 8),
              StatusPill(humanize(str(m['role']).isEmpty ? 'user' : str(m['role'])), tone: MarketTone.brand),
            ]),
            const SizedBox(height: 16),
            GlowCard(
              child: Column(children: [
                InfoRow('Name', memberName(m).isEmpty ? '-' : memberName(m)),
                InfoRow('Email', memberEmail(m).isEmpty ? '-' : memberEmail(m)),
                InfoRow('Role', humanize(str(m['role'])).isEmpty ? '-' : humanize(str(m['role']))),
                InfoRow('Status', active ? 'Active' : 'Inactive'),
                InfoRow('Joined', fmtDate(parseDate(m['joined_at'] ?? m['created_at'])).isEmpty ? '-' : fmtDate(parseDate(m['joined_at'] ?? m['created_at']))),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _logout(m);
                  },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Force logout'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GradientButton(
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  onTap: () {
                    Navigator.pop(ctx);
                    _form(m);
                  },
                ),
              ),
            ]),
          ]),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final active = _members.where(memberActive).length;
    return MotionScaffold(
      title: 'User list',
      subtitle: '${_members.length} members · $active active',
      icon: Icons.group_outlined,
      accent: Accent.ocean,
      onRefresh: _load,
      onFab: () => _form(),
      fabLabel: 'New user',
      fabIcon: Icons.person_add_alt_1_rounded,
      headerExtra: HeaderSearch(hint: 'Search name, email or role', onChanged: (v) => setState(() => _q = v)),
      slivers: [
        if (!_loading && _error == null && _members.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: KpiStrip(height: 112, children: [
                GradientKpi(icon: Icons.groups_rounded, label: 'Members', value: _members.length, accent: Accent.ocean, onTap: () => setState(() => _chip = 'all')),
                GradientKpi(icon: Icons.verified_user_rounded, label: 'Active', value: active, accent: Accent.emerald, onTap: () => setState(() => _chip = 'active')),
                GradientKpi(icon: Icons.person_off_rounded, label: 'Inactive', value: _members.length - active, accent: Accent.rose, onTap: () => setState(() => _chip = 'inactive')),
                GradientKpi(icon: Icons.badge_rounded, label: 'Roles', value: _roles.length, accent: Accent.indigo),
              ]),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 14),
          sliver: SliverToBoxAdapter(
            child: ChipFilter<String>(
              value: _chip,
              options: [
                (id: 'all', label: 'All', count: _members.length),
                (id: 'active', label: 'Active', count: active),
                (id: 'inactive', label: 'Inactive', count: _members.length - active),
              ],
              onChanged: (v) => setState(() => _chip = v),
            ),
          ),
        ),
        if (_loading)
          sliverSkeleton()
        else if (_error != null)
          sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
        else if (rows.isEmpty)
          sliverEmpty(icon: Icons.person_search_outlined, title: _members.isEmpty ? 'No users yet' : 'No matches', message: _members.isEmpty ? 'Tap new user to add the first one.' : null)
        else
          sliverStagger(
            count: rows.length,
            builder: (_, i) {
              final m = rows[i];
              final active = memberActive(m);
              final role = str(m['role']);
              return MotionTile(
                key: ValueKey(m['id']),
                leading: Stack(clipBehavior: Clip.none, children: [
                  InitialsAvatar(memberName(m).isEmpty ? '?' : memberName(m), imageUrl: str(m['image_url']), size: 44),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? MarketPalette.of(context).ok : MarketPalette.of(context).error,
                        border: Border.all(color: MarketPalette.of(context).card, width: 2),
                      ),
                    ),
                  ),
                ]),
                title: memberName(m).isEmpty ? 'Unnamed user' : memberName(m),
                subtitle: memberEmail(m),
                meta: role.isEmpty ? null : 'Role: ${humanize(role)}',
                trailing: StatusPill(active ? 'Active' : 'Inactive', tone: active ? MarketTone.ok : MarketTone.error),
                onTap: () => _actions(m),
                onLongPress: () => _overview(m),
                onDelete: () => _delete(m),
              );
            },
          ),
      ],
    );
  }
}

/// Create / edit user sheet: photo, active, name, email, password, roles.
class UserFormSheet extends StatefulWidget {
  final JsonRow? member;
  final List<JsonRow> roles;
  final UsersService svc;
  const UserFormSheet({super.key, this.member, required this.roles, required this.svc});

  @override
  State<UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<UserFormSheet> {
  late final _name = TextEditingController(text: widget.member == null ? '' : memberName(widget.member!));
  late final _email = TextEditingController(text: widget.member == null ? '' : memberEmail(widget.member!));
  final _password = TextEditingController();
  late bool _active = widget.member == null ? true : memberActive(widget.member!);
  late String _image = str(widget.member?['image_url']);
  final Set<int> _roleIds = {};
  bool _rolesLoading = false;
  bool _busy = false;
  bool _showPassword = false;

  bool get _edit => widget.member != null;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    if (m != null) {
      final byName = widget.roles.where((r) => str(r['name']).trim().toLowerCase() == str(m['role']).trim().toLowerCase()).firstOrNull;
      final id = positiveInt(byName?['id']);
      if (id != null) _roleIds.add(id);
      final uid = memberUserId(m);
      if (uid != null) {
        _rolesLoading = true;
        widget.svc.userRoleIds(uid).then((ids) {
          if (!mounted) return;
          setState(() {
            if (ids.isNotEmpty) {
              _roleIds
                ..clear()
                ..addAll(ids);
            }
            _rolesLoading = false;
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty || email.isEmpty) {
      marketToast(context, 'Name and email are required', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (_edit) {
        final m = widget.member!;
        final uid = memberUserId(m);
        if (uid == null) throw Exception('Missing user id');
        await widget.svc.update(
          userId: uid,
          memberId: positiveInt(m['id']),
          name: name,
          email: email,
          password: _password.text.trim(),
          isActive: _active,
          imageUrl: _image.isEmpty ? null : _image,
          roleIds: _roleIds,
        );
      } else {
        final existing = await widget.svc.create(name: name, email: email, password: _password.text, isActive: _active, imageUrl: _image.isEmpty ? null : _image, roleIds: _roleIds);
        if (existing && mounted) marketToast(context, 'Existing user added to this workplace');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      marketToast(context, errorMessage(e, _edit ? 'Could not update user' : 'Could not create user'), error: true);
    }
  }

  Future<void> _pickPhoto() async {
    final url = await pickMediaImage(context, title: 'Select profile photo');
    if (url != null && mounted) setState(() => _image = url);
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return FormSheet(
      title: _edit ? 'Edit user' : 'New user',
      subtitle: _edit ? memberEmail(widget.member!) : 'Creates an account and adds it to this workplace',
      busy: _busy,
      onSubmit: _save,
      submitLabel: _edit ? 'Save changes' : 'Create user',
      children: [
        Center(
          child: Column(children: [
            PressScale(
              onTap: _pickPhoto,
              child: Stack(children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: InitialsAvatar(_name.text.trim().isEmpty ? '?' : _name.text.trim(), key: ValueKey(_image), imageUrl: _image, size: 84),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle, border: Border.all(color: p.card, width: 2)),
                    child: const Icon(Icons.photo_camera_rounded, size: 15, color: Colors.white),
                  ),
                ),
              ]),
            ),
            if (_image.isNotEmpty)
              TextButton(onPressed: () => setState(() => _image = ''), child: Text('Remove photo', style: TextStyle(color: p.error, fontSize: 12.5)))
            else
              const SizedBox(height: 12),
          ]),
        ),
        SwitchField(label: 'Active', sub: 'Inactive users cannot sign in to this workplace', value: _active, onChanged: (v) => setState(() => _active = v)),
        FormLabel(
          label: 'Name',
          required: true,
          child: TextField(controller: _name, onChanged: (_) => setState(() {}), textCapitalization: TextCapitalization.words, decoration: motionInput(context, hint: 'Full name', icon: Icons.person_outline_rounded)),
        ),
        FormLabel(
          label: 'Email',
          required: true,
          child: TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: motionInput(context, hint: 'name@company.com', icon: Icons.alternate_email_rounded)),
        ),
        FormLabel(
          label: 'Password',
          required: !_edit,
          help: _edit ? 'Leave empty to keep the current password.' : 'Only needed for a new account.',
          child: TextField(
            controller: _password,
            obscureText: !_showPassword,
            decoration: motionInput(
              context,
              hint: _edit ? 'New password' : 'Password',
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 19, color: p.label),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
        ),
        FormLabel(
          label: 'Assign roles',
          help: 'Select one or more roles. Tap again to remove.',
          child: _rolesLoading
              ? const SkeletonBox(height: 40, radius: 12)
              : widget.roles.isEmpty
                  ? Text('No roles yet. Create them in role permission.', style: TextStyle(fontSize: 12.5, color: p.label))
                  : Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final r in widget.roles)
                        if (positiveInt(r['id']) != null)
                          FilterChip(
                            label: Text(str(r['name'])),
                            selected: _roleIds.contains(positiveInt(r['id'])),
                            onSelected: (sel) => setState(() => sel ? _roleIds.add(positiveInt(r['id'])!) : _roleIds.remove(positiveInt(r['id']))),
                          ),
                    ]),
        ),
      ],
    );
  }
}
