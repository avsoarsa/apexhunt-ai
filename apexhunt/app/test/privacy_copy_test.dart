import 'package:apexhunt_ai/core/ai/llm.dart';
import 'package:apexhunt_ai/core/app_state.dart';
import 'package:apexhunt_ai/core/storage.dart';
import 'package:apexhunt_ai/core/theme.dart';
import 'package:apexhunt_ai/features/settings/ai_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// #8: the app must not promise "no AI training" when the user's own free-tier key may allow it.
void main() {
  Future<void> pumpForm(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(LocalStore.memory())],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const Scaffold(body: SingleChildScrollView(child: ByokForm())),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('choosing Gemini shows the free-tier data warning', (tester) async {
    await pumpForm(tester);
    expect(find.byType(GeminiFreeTierNotice), findsOneWidget, reason: 'Gemini is the default provider');
    expect(find.textContaining('human reviewers may read it'), findsOneWidget);
    expect(find.textContaining('In the EU/EEA, Switzerland and the UK, use a paid key'), findsOneWidget);
  });

  testWidgets('other providers do not show the Gemini warning', (tester) async {
    await pumpForm(tester);
    await tester.tap(find.byType(DropdownButtonFormField<ByokProvider>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ByokProvider.openAi.label).last);
    await tester.pumpAndSettle();
    expect(find.byType(GeminiFreeTierNotice), findsNothing);
    expect(find.textContaining('sent only to ${ByokProvider.openAi.label}'), findsOneWidget);
  });
}
