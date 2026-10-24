import 'package:flutter/material.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/settings_service.dart';

/// Settings → Role permission. Same flow as desktop RolePermission.tsx:
/// pick a role from the chip row, then grant / revoke permissions per
/// installed module and sync them in one save. Owner is read only.
class RolePermissionPage extends StatefulWidget {
  const RolePermissionPage({super.key});

  @override
  State<RolePermissionPage> createState() => _RolePermissionPageState();
}

class _RolePermissionPageState extends State<RolePermissionPage> {
  final _svc = RolesService();
  List<JsonRow> _roles = [];
  List<PermissionModule> _modules = [];
  bool _loading = true;
  String? _error;

  int? _roleId;
  Set<int> _granted = {};
  Set<int> _original = {};
  bool _permLoading = false;
  bool _saving = false;
  int _req = 0;
  String _q = '';
  final Set<String> _collapsed = {};

  JsonRow? get _role => _roles.where((r) => positiveInt(r['id']) == _roleId).firstOrNull;
  bool get _isOwner => isOwnerRole(_role?['name']);
  bool get _dirty => _granted.length != _original.length || !_granted.containsAll(_original);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _roles.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([_svc.roles(), _svc.permissionTree()]);
      if (!mounted) return;
      final roles = results[0] as List<JsonRow>;
      setState(() {
        _roles = roles;
        _modules = results[1] as List<PermissionModule>;
      });
      final keep = roles.any((r) => positiveInt(r['id']) == _roleId);
      if (!keep) {
        _roleId = null;
        if (roles.isNotEmpty) await _select(roles.first);
      } else {
        await _select(_role!);
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not load roles'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return confirmMarket(context, title: 'Discard changes?', message: 'Permission changes for this role have not been saved.', confirm: 'Discard');
  }

  Future<void> _select(JsonRow role) async {
    final id = positiveInt(role['id']);
    if (id == null) return;
    final req = ++_req;
    setState(() {
      _roleId = id;
      _permLoading = true;
    });
    try {
      final ids = await _svc.rolePermissionIds(id);
      if (!mounted || req != _req) return;
      setState(() {
        _granted = {...ids};
        _original = {...ids};
      });
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() {
        _granted = {};
        _original = {};
      });
      marketToast(context, errorMessage(e, 'Could not load role permissions'), error: true);
    } finally {
      if (mounted && req == _req) setState(() => _permLoading = false);
    }
  }

  Future<void> _tapRole(JsonRow role) async {
    if (positiveInt(role['id']) == _roleId) return;
    if (!await _confirmDiscard()) return;
    _select(role);
  }

  Future<void> _roleForm([JsonRow? role]) async {
    if (role != null && isOwnerRole(role['name'])) {
      marketToast(context, 'Owner role cannot be edited', error: true);
      return;
    }
    final ok = await showMotionSheet<bool>(context, (_) => _RoleNameSheet(role: role, svc: _svc));
    if (ok == true) {
      if (mounted) marketToast(context, role == null ? 'Role created' : 'Role updated');
      _load();
    }
  }

  Future<void> _roleMenu(JsonRow role) async {
    if (isOwnerRole(role['name'])) {
      marketToast(context, 'Owner role cannot be changed');
      return;
    }
    final key = await showActionSheet(context, title: str(role['name']), actions: [
      (key: 'edit', label: 'Rename role', icon: Icons.edit_outlined, destructive: false),
      (key: 'delete', label: 'Delete role', icon: Icons.delete_outline_rounded, destructive: true),
    ]);
    if (!mounted || key == null) return;
    if (key == 'edit') return _roleForm(role);
    final ok = await confirmMarket(context, title: 'Delete role?', message: '"${str(role['name'])}" will be removed. Users keep their other roles.');
    if (!ok) return;
    try {
      await _svc.deleteRole(positiveInt(role['id'])!);
      if (!mounted) return;
      marketToast(context, 'Role deleted');
      if (positiveInt(role['id']) == _roleId) {
        _roleId = null;
        _granted = {};
        _original = {};
      }
      _load();
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not delete role'), error: true);
    }
  }

  void _toggle(int id) {
    if (_isOwner || _permLoading) return;
    setState(() => _granted.contains(id) ? _granted.remove(id) : _granted.add(id));
  }

  void _toggleModule(List<PermissionItem> perms, bool grant) {
    if (_isOwner || _permLoading) return;
    setState(() {
      for (final p in perms) {
        grant ? _granted.add(p.id) : _granted.remove(p.id);
      }
    });
  }

  Future<void> _save() async {
    final id = _roleId;
    if (id == null || _isOwner) return;
    setState(() => _saving = true);
    try {
      await _svc.syncPermissions(id, _granted);
      if (!mounted) return;
      setState(() => _original = {..._granted});
      marketToast(context, 'Role permissions saved');
    } catch (e) {
      if (mounted) marketToast(context, errorMessage(e, 'Could not save permissions'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<({PermissionModule m, List<PermissionItem> perms})> get _visible {
    final q = _q.trim().toLowerCase();
    return [
      for (final m in _modules)
        if (q.isEmpty || m.name.toLowerCase().contains(q))
          (m: m, perms: m.permissions)
        else if (m.permissions.any((p) => p.name.toLowerCase().contains(q)))
          (m: m, perms: m.permissions.where((p) => p.name.toLowerCase().contains(q)).toList()),
    ].where((e) => e.perms.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final total = _modules.fold<int>(0, (s, m) => s + m.permissions.length);
    final visible = _visible;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) {
          setState(() => _original = {..._granted});
          nav.pop();
        }
      },
      child: MotionScaffold(
        title: 'Role permission',
        subtitle: '${_roles.length} roles · $total permissions',
        icon: Icons.admin_panel_settings_outlined,
        accent: Accent.indigo,
        onRefresh: _load,
        onFab: () => _roleForm(),
        fabLabel: 'New role',
        headerExtra: HeaderSearch(hint: 'Search modules or permissions', onChanged: (v) => setState(() => _q = v)),
        bottomBar: _roleId == null || _loading
            ? null
            : _SaveBar(
                owner: _isOwner,
                dirty: _dirty,
                saving: _saving,
                granted: _granted.length,
                total: total,
                onSave: _save,
                onReset: () => setState(() => _granted = {..._original}),
              ),
        slivers: [
          if (_loading) ...[
            sliverBox(const SkeletonBox(height: 38, radius: 12)),
            sliverSkeleton(count: 4, height: 150),
          ] else if (_error != null)
            sliverEmpty(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _error, actionLabel: 'Retry', onAction: _load)
          else ...[
            SliverPadding(
              padding: const EdgeInsets.only(top: 14),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _roles.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final r = _roles[i];
                      return FadeSlideIn(
                        index: i,
                        child: _RoleChip(
                          name: str(r['name']),
                          owner: isOwnerRole(r['name']),
                          selected: positiveInt(r['id']) == _roleId,
                          onTap: () => _tapRole(r),
                          onLongPress: () => _roleMenu(r),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (_roles.isEmpty)
              sliverEmpty(icon: Icons.badge_outlined, title: 'No roles yet', message: 'Tap new role to create the first one.')
            else ...[
              sliverBox(
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _isOwner ? 'Owner has every permission and is read only.' : 'Long-press a role to rename or delete it. Toggle a permission to grant or revoke it.',
                    key: ValueKey(_isOwner),
                    style: TextStyle(fontSize: 12, color: p.label),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              ),
              if (_permLoading)
                sliverSkeleton(count: 4, height: 140)
              else if (visible.isEmpty)
                sliverEmpty(icon: Icons.search_off_rounded, title: _modules.isEmpty ? 'No modules installed' : 'No matches')
              else
                sliverStagger(
                  count: visible.length,
                  builder: (_, i) {
                    final e = visible[i];
                    final granted = _isOwner ? e.perms.length : e.perms.where((x) => _granted.contains(x.id)).length;
                    final open = _q.isNotEmpty || !_collapsed.contains(e.m.id);
                    return _ModuleCard(
                      module: e.m,
                      perms: e.perms,
                      granted: _granted,
                      grantedCount: granted,
                      expanded: open,
                      readOnly: _isOwner,
                      onExpand: () => setState(() => _collapsed.contains(e.m.id) ? _collapsed.remove(e.m.id) : _collapsed.add(e.m.id)),
                      onToggle: _toggle,
                      onToggleAll: () => _toggleModule(e.perms, granted != e.perms.length),
                    );
                  },
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String name;
  final bool owner;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _RoleChip({required this.name, required this.owner, required this.selected, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return PressScale(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? Accent.ocean.gradient : null,
          color: selected ? null : p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Colors.transparent : p.line),
          boxShadow: selected ? [BoxShadow(color: Accent.indigo.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(owner ? Icons.workspace_premium_rounded : Icons.badge_outlined, size: 16, color: selected ? Colors.white : p.label),
          const SizedBox(width: 6),
          Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : p.text)),
        ]),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final PermissionModule module;
  final List<PermissionItem> perms;
  final Set<int> granted;
  final int grantedCount;
  final bool expanded;
  final bool readOnly;
  final VoidCallback onExpand;
  final ValueChanged<int> onToggle;
  final VoidCallback onToggleAll;
  const _ModuleCard({
    required this.module,
    required this.perms,
    required this.granted,
    required this.grantedCount,
    required this.expanded,
    required this.readOnly,
    required this.onExpand,
    required this.onToggle,
    required this.onToggleAll,
  });

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final all = perms.isNotEmpty && grantedCount == perms.length;
    final ratio = perms.isEmpty ? 0.0 : grantedCount / perms.length;
    final accent = accentFor(module.name);
    return GlowCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onExpand,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(children: [
              ProgressRing(
                value: ratio,
                size: 42,
                stroke: 5,
                color: accent.primary,
                center: Text('$grantedCount', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.text)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(humanize(module.name), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.text)),
                  Text('$grantedCount of ${perms.length} granted', style: TextStyle(fontSize: 12, color: p.label)),
                ]),
              ),
              if (!readOnly)
                TextButton(onPressed: onToggleAll, child: Text(all ? 'Clear all' : 'Select all', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 240),
                child: Icon(Icons.expand_more_rounded, color: p.label),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !expanded
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Column(children: [
                    Divider(height: 1, color: p.line),
                    for (final perm in perms)
                      _PermRow(
                        name: perm.name,
                        on: granted.contains(perm.id),
                        readOnly: readOnly,
                        onTap: () => onToggle(perm.id),
                      ),
                  ]),
                ),
        ),
      ]),
    );
  }
}

class _PermRow extends StatelessWidget {
  final String name;
  final bool on;
  final bool readOnly;
  final VoidCallback onTap;
  const _PermRow({required this.name, required this.on, required this.readOnly, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: readOnly ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: on ? p.ok : p.line),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(humanize(name), style: TextStyle(fontSize: 13.5, color: p.text))),
          Switch.adaptive(value: on || readOnly, onChanged: readOnly ? null : (_) => onTap()),
        ]),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  final bool owner;
  final bool dirty;
  final bool saving;
  final int granted;
  final int total;
  final VoidCallback onSave;
  final VoidCallback onReset;
  const _SaveBar({required this.owner, required this.dirty, required this.saving, required this.granted, required this.total, required this.onSave, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.dark ? 0.3 : 0.08), blurRadius: 8, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(owner ? 'Read only' : '$granted of $total granted', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    owner ? 'Owner always has full access' : (dirty ? 'Unsaved changes' : 'All changes saved'),
                    key: ValueKey('$owner$dirty'),
                    style: TextStyle(fontSize: 11.5, color: dirty ? p.warn : p.label),
                  ),
                ),
              ]),
            ),
            if (dirty && !owner)
              TextButton(onPressed: saving ? null : onReset, child: const Text('Undo')),
            const SizedBox(width: 6),
            SizedBox(
              width: 120,
              child: GradientButton(label: 'Save', icon: Icons.check_rounded, accent: Accent.indigo, busy: saving, onTap: owner || !dirty ? null : onSave),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RoleNameSheet extends StatefulWidget {
  final JsonRow? role;
  final RolesService svc;
  const _RoleNameSheet({this.role, required this.svc});

  @override
  State<_RoleNameSheet> createState() => _RoleNameSheetState();
}

class _RoleNameSheetState extends State<_RoleNameSheet> {
  late final _name = TextEditingController(text: str(widget.role?['name']));
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      marketToast(context, 'Role name is required', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final id = positiveInt(widget.role?['id']);
      if (id == null) {
        await widget.svc.createRole(name);
      } else {
        await widget.svc.renameRole(id, name);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        marketToast(context, errorMessage(e, 'Could not save role'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => FormSheet(
        title: widget.role == null ? 'New role' : 'Rename role',
        busy: _busy,
        onSubmit: _save,
        submitLabel: widget.role == null ? 'Create role' : 'Save',
        children: [
          FormLabel(
            label: 'Role name',
            required: true,
            child: TextField(controller: _name, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: motionInput(context, hint: 'e.g. Store manager', icon: Icons.badge_outlined)),
          ),
        ],
      );
}
