import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/admin_login_accounts.dart';

void main() {
  test('ADM-001 login selects the admin created by Super Admin', () {
    final matches = [
      {
        'role': 'admin',
        'adminId': 'ADM-001',
        'firstName': 'Warren',
        'lastName': 'Soniega',
      },
      {
        'role': 'admin',
        'adminId': 'ADM-0001',
        'username': 'ADM-001',
        'firstName': 'Test',
        'lastName': 'Admin',
        'requiresBranchAssignment': true,
      },
    ];

    final selected = preferSuperAdminCreatedAdmins(
      matches,
      dataOf: (account) => account,
      username: 'ADM-001',
    );

    expect(selected, hasLength(1));
    expect(selected.single['firstName'], 'Test');
  });

  test('legacy Warren ADM-001 is disabled when no replacement exists', () {
    final selected = preferSuperAdminCreatedAdmins(
      [
        {
          'role': 'admin',
          'adminId': 'ADM-0001',
          'firstName': 'Warren',
          'lastName': 'Soniega',
        },
      ],
      dataOf: (account) => account,
      username: 'ADM-001',
    );

    expect(selected, isEmpty);
  });

  test('other admin IDs keep their existing account lookup', () {
    final matches = [
      {'role': 'admin', 'adminId': 'ADM-002', 'firstName': 'Another'},
    ];

    final selected = preferSuperAdminCreatedAdmins(
      matches,
      dataOf: (account) => account,
      username: 'ADM-002',
    );

    expect(selected, matches);
  });
}
