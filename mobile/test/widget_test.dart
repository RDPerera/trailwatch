import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailwatch_mobile/main.dart';

void main() {
  testWidgets('shows the ticket join and QR controls',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: JoinTripScreen(onJoined: (_) async {}),
      ),
    );
    await tester.pump();

    expect(find.text('TrailWatch'), findsOneWidget);
    expect(find.text('Start your trip'), findsOneWidget);
    expect(find.text('Scan ticket QR'), findsOneWidget);
    expect(find.text('Join trip'), findsOneWidget);
  });
}
