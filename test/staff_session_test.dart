import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/branch_staff_activity_dialog.dart';
import 'package:sales_tracking/widgets/admin_recent_sales.dart';

void main() {
  test('work hours handle overnight sessions and missing logout honestly', () {
    expect(
      sessionHours({
        'loginAt': '2026-09-25T22:30:00',
        'logoutAt': '2026-09-26T06:45:00',
      }),
      '8h 15m',
    );
    expect(sessionHours({'loginAt': '2026-09-25T22:30:00'}), 'Not closed');
    expect(
      sessionHours({
        'loginAt': '2026-09-25T22:30:00',
        'logoutAt': '2026-09-25T20:00:00',
      }),
      'Invalid times',
    );
  });
  test('legacy branch code matches admin format deterministically', () {
    expect(
      publicBranchCode('9oKXpOlgEbExSytRGUJ5'),
      matches(RegExp(r'^BR-\d{5}-\d{4}-\d$')),
    );
    expect(publicBranchCode('abc'), 'BR-00000-9635-4');
  });
  testWidgets(
    'session table displays identity and safely scrolls on narrow screens',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: StaffSessionTable(
                sessions: [
                  {
                    'staffId': 'STF-0001',
                    'staffName': 'Qwerty Pngovue',
                    'branchName': 'Sm dagupan',
                    'type': 'User',
                    'loginAt': '2026-09-25T08:00:00',
                    'logoutAt': '2026-09-25T17:00:00',
                    'ipAddress': '192.168.1.2',
                  },
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Qwerty Pngovue'), findsOneWidget);
      expect(find.text('9h 0m'), findsOneWidget);
      expect(find.byIcon(Icons.account_circle), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
