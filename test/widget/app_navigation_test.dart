import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spothub/app/providers.dart';
import 'package:spothub/app/router.dart';
import 'package:spothub/app/theme/app_theme.dart';

void main() {
  testWidgets('main navigation opens the search destination', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playlistsProvider.overrideWith((ref) async => []),
          recentlyPlayedProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: appRouter,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Home'), findsNWidgets(2));
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Your Library'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Explore your genres'), findsOneWidget);
  });
}
