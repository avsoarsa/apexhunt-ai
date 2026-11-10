import 'dart:convert';

import 'package:apexhunt_ai/core/ai/llm.dart';
import 'package:apexhunt_ai/core/app_state.dart';
import 'package:apexhunt_ai/core/models.dart';
import 'package:apexhunt_ai/core/storage.dart';
import 'package:apexhunt_ai/core/theme.dart';
import 'package:apexhunt_ai/features/discovery/mission_controller.dart';
import 'package:apexhunt_ai/features/tailor/tailor_engine.dart';
import 'package:apexhunt_ai/features/tailor/tailor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Build 4: the skill check-in Sk found hard to use on build 3, and "Fill from my CV".
MasterProfile _profile() => MasterProfile(
      contact: Contact(name: 'Sk'),
      headline: 'AI Developer',
      roles: [
        WorkRole(id: 'r1', company: 'Soham AI', title: 'AI Developer', start: '2024-01', bullets: [
          'Built an Android job-search app end to end using Claude Code.',
          'Shipped restocking robot software at an early-stage startup of 30 people.',
        ]),
      ],
      skills: ['Large Language Models'],
    );

/// How the JD analysis would label them: tools must be named in the CV quote; domain skills rely on the AI + the user.
Map<String, Object> _req(String s) => {
      'skill': s,
      'importance': 'MUST',
      'evidence': '$s please',
      'category': switch (s) {
        'AI Building Tools' => 'tool',
        'Early-Stage Startup Experience' || 'Product Management' || 'Team Leadership' || 'Pricing Strategy' || 'Go-to-market' || 'Fund Administration' => 'domain',
        _ => 'tool',
      },
      if (s == 'AI Building Tools') 'aliases': ['Claude Code', 'Cursor'],
    };

const _open = ['AI Building Tools', 'Early-Stage Startup Experience', 'Product Management', 'Kubernetes', 'Snowflake', 'dbt', 'Pricing Strategy', 'Go-to-market', 'Team Leadership', 'Fund Administration'];

class _Llm implements LlmClient {
  _Llm({this.failLetter = false});
  final bool failLetter;
  final calls = <String>[];
  @override
  String get label => 'Scripted';
  @override
  Future<LlmResult> complete(List<ChatMsg> m, {bool json = false, int maxTokens = 3000, double temperature = 0.4, String purpose = 'chat'}) async {
    calls.add(purpose);
    final out = switch (purpose) {
      'analyze_jd' => {'title': 'Group PM', 'company': 'Juniper', 'summary': 'Lead Dex.', 'requirements': [
          {'skill': 'Large Language Models', 'importance': 'MUST'},
          for (final s in _open) _req(s),
        ]},
      'suggest_evidence' => {'suggestions': [
          {'skill': 'AI Building Tools', 'found': true, 'quote': 'Built an Android job-search app end to end using Claude Code.', 'line': 'Built an Android job-search app end to end with Claude Code.'},
          {'skill': 'Early-Stage Startup Experience', 'found': true, 'quote': 'early-stage startup of 30 people', 'line': 'Shipped robot software at an early-stage startup.'},
          {'skill': 'Product Management', 'found': true, 'quote': 'Led product strategy for three years', 'line': 'Led product strategy.'}, // not in the CV
          {'skill': 'Team Leadership', 'found': true, 'quote': 'early-stage startup of 30 people', 'line': 'Led a team of 12 engineers at a startup.'}, // invented number
          {'skill': 'Snowflake', 'found': true, 'quote': 'Built an Android job-search app end to end using Claude Code.', 'line': 'Built the app on Kubernetes and Snowflake.'}, // smuggles Kubernetes
          {'skill': 'dbt', 'found': false, 'quote': '', 'line': ''},
        ]},
      'tailor_cv' => {'headline': 'AI Developer', 'summary': 'AI developer.', 'skills': ['Large Language Models'], 'roles': []},
      'prep' => {'pitch_60s': 'Hi.'},
      'cover_letter' => failLetter ? throw LlmException('The AI provider is having trouble.') : {'letter_markdown': 'Dear Juniper.'},
      _ => <String, Object>{},
    };
    return LlmResult(content: jsonEncode(out));
  }
}

class _Ai extends AiService {
  _Ai(super.ref, this.llm);
  final LlmClient llm;
  @override
  Future<LlmClient> client({bool allowFreeByok = false}) async => llm;
}

Future<ProviderContainer> _pump(WidgetTester tester, _Llm llm) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  final store = LocalStore.memory();
  await store.writeJson('profile.json', _profile().toJson());
  await store.writeJson('pipeline.json', [Opportunity(id: 'J:1', source: 'J', title: 'Group PM', company: 'Juniper', description: 'Lead Dex. ' * 30).toJson()]);
  final router = GoRouter(initialLocation: '/t', routes: [
    GoRoute(path: '/t', builder: (_, _) => const TailorScreen(opportunityId: 'J:1')),
    GoRoute(path: '/artifact/:id', builder: (_, s) => Scaffold(body: Text('ARTIFACT ${s.pathParameters['id']}'))),
  ]);
  final c = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store), aiServiceProvider.overrideWith((ref) => _Ai(ref, llm))]);
  addTearDown(c.dispose);
  await c.read(profileProvider.future);
  c.read(missionProvider);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp.router(theme: buildTheme(Brightness.dark), routerConfig: router)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Analyze requirements'));
  await tester.pumpAndSettle();
  return c;
}

Finder _card(String skill) => find.ancestor(of: find.text(skill), matching: find.byType(Column)).first;
Set<SkillDecision> _selected(WidgetTester t, String skill) =>
    t.widget<SegmentedButton<SkillDecision>>(find.descendant(of: _card(skill), matching: find.byType(SegmentedButton<SkillDecision>))).selected;

void main() {
  group('Fill from my CV: only suggestions backed by the real CV survive', () {
    test('quotes must be in the CV; no invented numbers; no other missing skills', () {
      final reqs = [for (final s in _open) Requirement.fromJson(_req(s)), Requirement(skill: 'AWS Lambda', category: 'tool', aliases: ['Lambda'])];
      final j = {'suggestions': [
        {'skill': 'AI Building Tools', 'found': true, 'quote': 'Built an Android job-search app end to end using Claude Code.', 'line': 'Built an Android app with Claude Code.'},
        {'skill': 'Product Management', 'found': true, 'quote': 'Led product strategy for three years', 'line': 'Led product strategy.'},
        {'skill': 'Team Leadership', 'found': true, 'quote': 'early-stage startup of 30 people', 'line': 'Led a team of 12 engineers.'},
        {'skill': 'Snowflake', 'found': true, 'quote': 'Built an Android job-search app end to end using Claude Code.', 'line': 'Built the app on Kubernetes and Snowflake.'},
        {'skill': 'dbt', 'found': false},
        {'skill': 'Kubernetes', 'found': true, 'quote': 'Built an Android job-search app end to end using Claude Code.', 'line': 'Built an Android job-search app.'}, // quote doesn't name it
        {'skill': 'AWS Lambda', 'found': true, 'quote': 'lambda expressions in payment rules', 'line': 'Used lambda expressions in payment rules.'},
      ]};
      final p = _profile()..roles.first.bullets.add('Refactored code with lambda expressions in payment rules.');
      final got = TailorEngine.verifiedSuggestions(p, reqs, j);
      expect(got.keys, ['AI Building Tools'], reason: 'AWS Lambda: "lambda" alone is an ordinary word; Kubernetes: quote never names it');
      expect(got['AI Building Tools']!.roleId, 'r1', reason: 'the quote is a bullet of role r1');
    });
  });

  testWidgets('Fill from my CV sets verified skills to "I have it" with drafted lines', (tester) async {
    final llm = _Llm();
    await _pump(tester, llm);
    await tester.tap(find.text('Fill from my CV'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('suggest_evidence'));
    expect(_selected(tester, 'AI Building Tools'), {SkillDecision.haveIt});
    expect(_selected(tester, 'Early-Stage Startup Experience'), {SkillDecision.haveIt});
    for (final s in ['Product Management', 'Team Leadership', 'Snowflake', 'dbt']) {
      expect(_selected(tester, s), {SkillDecision.gap}, reason: '$s: rejected or not found');
    }
    expect(find.textContaining('Drafted from your CV'), findsNWidgets(2));
    expect(find.textContaining('2 I have it'), findsOneWidget, reason: 'summary line above the button');
  });

  testWidgets('answers survive scrolling to the bottom and back', (tester) async {
    await _pump(tester, _Llm());
    for (final s in _open.take(3)) {
      await tester.ensureVisible(_card(s));
      await tester.tap(find.descendant(of: _card(s), matching: find.text('Learning')));
      await tester.pumpAndSettle();
    }
    final list = find.byType(Scrollable).first;
    await tester.fling(list, const Offset(0, -4000), 3000);
    await tester.pumpAndSettle();
    await tester.fling(list, const Offset(0, 4000), 3000);
    await tester.pumpAndSettle();
    for (final s in _open.take(3)) {
      expect(_selected(tester, s), {SkillDecision.learning}, reason: s);
    }
  });

  testWidgets('"I have it" without a line is flagged on the card itself, and nothing runs', (tester) async {
    final llm = _Llm();
    await _pump(tester, llm);
    await tester.ensureVisible(_card('Product Management'));
    await tester.tap(find.descendant(of: _card('Product Management'), matching: find.text('I have it')));
    await tester.pumpAndSettle();
    expect(find.textContaining('still needs a line'), findsOneWidget);
    final run = find.text('Tailor my CV & build prep');
    await tester.ensureVisible(run);
    await tester.tap(run);
    await tester.pumpAndSettle();
    expect(find.text("Add one line, or choose Learning or Don't have"), findsOneWidget);
    expect(llm.calls, isNot(contains('tailor_cv')));
  });

  testWidgets('#17: a failed cover letter still saves the tailored CV', (tester) async {
    final c = await _pump(tester, _Llm(failLetter: true));
    final run = find.text('Tailor my CV & build prep');
    await tester.ensureVisible(run);
    await tester.tap(run);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpAndSettle();
    final saved = await c.read(artifactsProvider.future);
    expect(saved, hasLength(1));
    expect(saved.single.applicationNote, isEmpty);
    expect(find.textContaining('ARTIFACT'), findsOneWidget);
  });
}
