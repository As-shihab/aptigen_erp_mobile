import 'package:flutter_test/flutter_test.dart';
import 'package:aptigen_erp/features/modules/models/module_model.dart';

/// Regression test for a real bug: `code` from cloud/src/seed/permission.seed.ts
/// is "HR" (lowercased "hr"), not "hr-management" — the launcher was matching
/// on the wrong id and the HR tile always fell through to "coming soon".
void main() {
  test('HR module row resolves to a real, tappable tile', () {
    final installedRows = [
      {
        'is_enabled': true,
        'status': 'installed',
        'module': {
          'id': 3,
          'code': 'HR',
          'name': 'HRM',
          'route': '/hr-management',
          'color': '#0A6ED1',
        },
      },
    ];

    final modules = buildLaunchpadModules(installedRows, {});
    expect(modules, hasLength(1));
    expect(modules.first.id, 'hr');
    expect(modules.first.isHr, isTrue);
  });

  test('non-HR module never resolves as HR', () {
    final installedRows = [
      {
        'is_enabled': true,
        'status': 'installed',
        'module': {'id': 7, 'code': 'STORE', 'name': 'Store', 'route': '/store', 'color': '#EF4444'},
      },
    ];

    final modules = buildLaunchpadModules(installedRows, {});
    expect(modules.first.isHr, isFalse);
  });
}
