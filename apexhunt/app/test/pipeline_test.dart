import 'dart:convert';
import 'dart:io';

import 'package:apexhunt_ai/core/ai/llm.dart';
import 'package:apexhunt_ai/core/app_state.dart';
import 'package:apexhunt_ai/core/models.dart';
import 'package:apexhunt_ai/core/storage.dart';
import 'package:apexhunt_ai/core/text_match.dart';
import 'package:apexhunt_ai/core/theme.dart';
import 'package:apexhunt_ai/features/discovery/mission_controller.dart';
import 'package:apexhunt_ai/features/tailor/tailor_engine.dart';
import 'package:apexhunt_ai/features/tailor/tailor_screen.dart';
import 'package:apexhunt_ai/features/vault/cv_documents.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Scripted model: answers each pipeline node with canned JSON, and deliberately
/// tries to sneak an unclaimed skill (Kafka) and an invented metric into the CV.
class ScriptedLlm implements LlmClient {
  final calls = <String>[];
  @override
  String get label => 'Scripted';

  @override
  Future<LlmResult> complete(List<ChatMsg> messages, {bool json = false, int maxTokens = 3000, double temperature = 0.4, String purpose = 'chat'}) async {
    calls.add(purpose);
    final user = messages.last.content;
    String out;
    switch (purpose) {
      case 'analyze_jd':
        out = jsonEncode({
          'title': 'Senior Backend Engineer',
          'company': 'Fintech Co',
          'summary': 'Payments APIs on Node.js.',
          'requirements': [
            {'skill': 'Node.js', 'importance': 'MUST'},
            {'skill': 'PostgreSQL', 'importance': 'MUST'},
            {'skill': 'Kafka', 'importance': 'MUST', 'evidence': 'event streaming with Kafka'},
            {'skill': 'Redis', 'importance': 'NICE'},
            {'skill': 'AWS', 'importance': 'NICE'},
          ],
          'keywords': ['payment APIs'],
        });
      case 'tailor_cv':
        final profile = jsonDecode(RegExp(r'CANDIDATE_PROFILE:\n(.*)\n\nCONFIRMED_SKILLS', dotAll: true).firstMatch(user)!.group(1)!);
        final roleId = (profile['roles'] as List).first['id'];
        out = jsonEncode({
          'headline': 'Backend Engineer · Node.js & PostgreSQL',
          'summary': 'Backend engineer building payment APIs in Node.js. Built Kafka pipelines at scale.',
          'skills': ['Node.js', 'PostgreSQL', 'Redis', 'Kafka'],
          'roles': [
            {
              'role_id': roleId,
              'bullets': [
                {'text': 'Built RESTful payment APIs in Node.js for order processing.', 'original': 'Built REST APIs in Node.js for order processing.', 'change': 'REPHRASED', 'keywords': ['Node.js']},
                {'text': 'Migrated order events to Kafka, cutting latency by 40%.', 'original': 'Maintained PostgreSQL schemas and reduced query latency by 25%.', 'change': 'REPHRASED'},
                {'text': 'Cached hot order lookups in Redis for the checkout service.', 'original': 'Cached order lookups in Redis.', 'change': 'FROM_USER_CONTEXT', 'keywords': ['Redis']},
              ],
            },
          ],
          'learning': ['Kafka'],
          'metric_prompts': [
            {'role_id': roleId, 'bullet': 'Built RESTful payment APIs', 'question': 'How many orders per day?'},
          ],
        });
      case 'prep':
        out = jsonEncode({
          'pitch_60s': 'I build payment APIs.',
          'star_stories': [
            {'title': 'Latency', 'requirement': 'PostgreSQL', 'source': 'Backend Engineer @ TechNova', 'situation': 's', 'task': 't', 'action': 'a', 'result': 'r'},
          ],
          'likely_questions': [
            {'question': 'Idempotency?', 'why_they_ask': 'payments', 'answer_outline': 'keys'},
          ],
          'gap_plans': [
            {'skill': 'Kafka', 'mental_model': 'log', 'how_to_answer_honestly': 'Not yet in production…', 'learn_in_48h': ['run locally'], 'vocabulary': ['partition'], 'practice_task': 'build a pipeline'},
          ],
          'questions_to_ask': ['On-call?'],
        });
      case 'cover_letter':
        out = jsonEncode({'letter_markdown': 'Fintech Co needs fast payment APIs.'});
      default:
        out = '{}';
    }
    return LlmResult(content: '```json\n$out\n```', chargedUsd: 0.004);
  }
}

MasterProfile profile() => MasterProfile(
      contact: Contact(name: 'Alex Rivera', email: 'alex@example.com'),
      headline: 'Backend Engineer',
      roles: [
        WorkRole(id: 'r1', company: 'TechNova', title: 'Backend Engineer', start: '2023-02', bullets: [
          'Built REST APIs in Node.js for order processing.',
          'Maintained PostgreSQL schemas and reduced query latency by 25%.',
        ]),
      ],
      skills: ['Node.js', 'PostgreSQL'],
    );

Opportunity job() => Opportunity(
      id: 'Remotive:42',
      source: 'Remotive',
      title: 'Senior Backend Engineer',
      company: 'Fintech Co',
      description: 'We need Node.js, PostgreSQL and Kafka for payment APIs. Redis and AWS are a plus. ' * 3,
    );

void main() {
  test('full pipeline: audit → check-in → tailor → Truth Guard → ATS → prep → letter → PDF/DOCX', () async {
    final llm = ScriptedLlm();
    final engine = TailorEngine(llm);
    final p = profile()..evidence.add(SkillEvidence(skill: 'Redis', context: 'Cached order lookups in Redis.', roleId: 'r1'));
    final o = job();

    final a = await engine.analyze(o);
    final decisions = TailorEngine.initialDecisions(p, a);
    expect(decisions['Redis'], SkillDecision.matched, reason: 'confirmed during check-in');
    expect(decisions['Kafka'], SkillDecision.gap);
    decisions['Kafka'] = SkillDecision.learning;

    final cv = await engine.tailor(profile: p, opportunity: o, analysis: a, decisions: decisions);
    final bullets = cv.roles.single.bullets;
    expect(bullets[0].flags, isEmpty);
    expect(bullets[1].text, 'Maintained PostgreSQL schemas and reduced query latency by 25%.', reason: 'Kafka + 40% claim reverted to the real bullet');
    expect(bullets[1].flags.join(' '), allOf(contains('Kafka'), contains('40%')));
    expect(bullets[2].enabled, isTrue, reason: 'user-confirmed Redis context is truthful');
    expect(cv.skills, ['Node.js', 'PostgreSQL', 'Redis']);
    expect(cv.skillFlags, ['Kafka']);
    expect(cv.summary, 'Backend engineer building payment APIs in Node.js.');
    expect(cv.learning, ['Kafka'], reason: 'listed honestly as learning');

    final before = TextMatch.atsScore(TailorEngine.baseCvText(p), a.requirements, keywords: a.keywords);
    final after = TextMatch.atsScore(TailorEngine.tailoredCvText(p, cv), a.requirements, keywords: a.keywords);
    expect(after, greaterThan(before));

    final prep = await engine.prep(profile: p, opportunity: o, analysis: a, cv: cv, decisions: decisions);
    expect(prep.gaps.single.skill, 'Kafka');
    final note = await engine.applicationNote(profile: p, opportunity: o, analysis: a, cv: cv, decisions: decisions);
    expect(note, contains('Fintech Co'));
    expect(llm.calls, ['analyze_jd', 'tailor_cv', 'prep', 'cover_letter']);
    expect(engine.spentUsd, closeTo(0.016, 1e-9));

    // Documents: PDF must contain real, extractable text in reading order (ATS).
    final doc = CvDocument(profile: p, cv: cv);
    final pdf = await CvPdfBuilder.build(doc);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    final out = Directory.systemTemp.createTempSync('apexhunt');
    File('${out.path}/cv.pdf').writeAsBytesSync(pdf);
    File('${out.path}/cv.docx').writeAsBytesSync(CvDocxBuilder.build(doc));
    // ignore: avoid_print
    print('DOCS_WRITTEN ${out.path}');
  });

  testWidgets('Tailor screen: analyze, skill check-in, run pipeline, save artifact', (tester) async {
    final store = LocalStore.memory();
    await store.writeJson('profile.json', profile().toJson());
    await store.writeJson('pipeline.json', [job().toJson()]);
    final llm = ScriptedLlm();

    final router = GoRouter(initialLocation: '/tailor/${Uri.encodeComponent('Remotive:42')}', routes: [
      GoRoute(path: '/tailor/:id', builder: (_, s) => TailorScreen(opportunityId: Uri.decodeComponent(s.pathParameters['id']!))),
      GoRoute(path: '/artifact/:id', builder: (_, s) => Scaffold(body: Text('ARTIFACT ${s.pathParameters['id']}'))),
      GoRoute(path: '/settings', builder: (_, _) => const Scaffold(body: Text('SETTINGS'))),
    ]);
    final container = ProviderContainer(overrides: [
      localStoreProvider.overrideWithValue(store),
      aiServiceProvider.overrideWith((ref) => _FakeAi(ref, llm)),
    ]);
    addTearDown(container.dispose);
    await container.read(profileProvider.future);
    container.read(missionProvider);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: buildTheme(Brightness.dark), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Senior Backend Engineer'), findsWidgets);

    await tester.tap(find.text('Analyze requirements'));
    await tester.pumpAndSettle();
    expect(find.text('Skill check-in'), findsOneWidget);
    expect(find.text('Kafka'), findsOneWidget);

    // Mark Redis as "I have it" with real context; leave Kafka as a gap.
    // Open requirements render in JD order: Kafka, Redis, AWS → Redis is the 2nd segmented control.
    await tester.scrollUntilVisible(find.text('AWS'), 200, scrollable: find.byType(Scrollable).first);
    final iHaveIt = find.text('I have it').at(1);
    await tester.ensureVisible(iHaveIt);
    await tester.tap(iHaveIt);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Cached order lookups in Redis at TechNova.');
    await tester.pumpAndSettle();

    final run = find.text('Tailor my CV & build prep');
    await tester.scrollUntilVisible(run, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(run);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpAndSettle();

    final artifacts = await container.read(artifactsProvider.future);
    expect(artifacts, hasLength(1));
    final art = artifacts.single;
    expect(art.decisions['Redis'], SkillDecision.matched);
    expect(art.decisions['Kafka'], SkillDecision.gap);
    expect(art.prep.gaps.single.skill, 'Kafka');
    expect(art.applicationNote, isNotEmpty);
    expect(find.textContaining('ARTIFACT'), findsOneWidget, reason: 'navigated to the vault entry');

    final saved = container.read(profileProvider).value!;
    expect(saved.evidence.map((e) => e.skill), contains('Redis'), reason: 'confirmed skill persisted for next time');
  });
}

class _FakeAi extends AiService {
  _FakeAi(super.ref, this.llm);
  final LlmClient llm;
  @override
  Future<LlmClient> client({bool allowFreeByok = false}) async => llm;
}
