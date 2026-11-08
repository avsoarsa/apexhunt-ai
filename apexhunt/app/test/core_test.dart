import 'dart:convert';

import 'package:apexhunt_ai/core/ai/llm.dart';
import 'package:apexhunt_ai/core/models.dart';
import 'package:apexhunt_ai/core/text_match.dart';
import 'package:apexhunt_ai/features/discovery/job_sources.dart';
import 'package:apexhunt_ai/features/tailor/tailor_engine.dart';
import 'package:apexhunt_ai/features/vault/cv_documents.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

MasterProfile _profile() => MasterProfile(
      contact: Contact(name: 'Sk Arif Majid', email: 'sk@example.com', location: 'Hyderabad, India'),
      headline: 'Robotics & AI Developer',
      roles: [
        WorkRole(
          id: 'r1',
          company: 'Soham AI',
          title: 'AI/Robotics Developer',
          start: '2025-01',
          bullets: ['Built ROS2 navigation for a smart retail cart used in 12 stores', 'Wrote Python services for restocking robots'],
          skills: ['ROS2', 'Python', 'Docker'],
        ),
        WorkRole(id: 'r2', company: 'Jukshio', title: 'Assistant Developer', start: '2023-06', end: '2024-12', bullets: ['Integrated face recognition into a smart desk']),
      ],
      skills: ['Python', 'ROS2', 'Docker', 'Computer Vision', 'Flutter'],
      education: [Education(institution: 'JNTU', degree: 'B.Tech', year: '2023')],
    );

JdAnalysis _jd() => JdAnalysis(title: 'Robotics Engineer', requirements: [
      Requirement(skill: 'Python'),
      Requirement(skill: 'ROS2'),
      Requirement(skill: 'Kubernetes', aliases: ['k8s']),
      Requirement(skill: 'C++', importance: Importance.nice),
    ]);

void main() {
  group('TextMatch', () {
    test('canonical synonyms', () {
      expect(TextMatch.canonical('k8s'), 'kubernetes');
      expect(TextMatch.canonical('NodeJS'), 'node.js');
      expect(TextMatch.mentions(TextMatch.normalize('Experience with Postgres and REST'), 'PostgreSQL'), isTrue);
    });

    test('symbol-safe word boundaries', () {
      final t = TextMatch.normalize('Strong C++ and C# skills; not Java');
      expect(TextMatch.mentions(t, 'C++'), isTrue);
      expect(TextMatch.mentions(t, 'C#'), isTrue);
      expect(TextMatch.mentions(t, 'JavaScript'), isFalse);
      expect(TextMatch.mentions(TextMatch.normalize('javascript developer'), 'Java'), isFalse);
    });

    test('ATS score weights must-haves', () {
      final reqs = _jd().requirements;
      final low = TextMatch.atsScore('Python developer', reqs);
      final high = TextMatch.atsScore('Python, ROS2, Kubernetes, C++', reqs);
      expect(high, greaterThan(low));
      expect(high, closeTo(100, 0.01));
    });

    test('unsupported numbers are detected', () {
      expect(TextMatch.unsupportedNumbers('Cut latency by 42% across 12 stores', 'used in 12 stores'), ['42%']);
    });
  });

  group('Truth Guard', () {
    test('initial decisions split matched vs gaps', () {
      final d = TailorEngine.initialDecisions(_profile(), _jd());
      expect(d['Python'], SkillDecision.matched);
      expect(d['Kubernetes'], SkillDecision.gap);
    });

    test('reverts bullets with invented skills or metrics and drops fake skills', () {
      final p = _profile();
      final cv = TailoredCv(
        headline: 'Robotics Engineer (ROS2, Kubernetes)',
        summary: 'Robotics developer shipping ROS2 systems. Scaled fleets with Kubernetes to 99.9% uptime.',
        skills: ['ROS2', 'Python', 'Kubernetes'],
        roles: [
          TailoredRole(roleId: 'r1', bullets: [
            TailoredBullet(text: 'Engineered ROS2 navigation for a smart retail cart deployed in 12 stores', original: 'Built ROS2 navigation for a smart retail cart used in 12 stores'),
            TailoredBullet(text: 'Orchestrated robot services on Kubernetes, cutting downtime 40%', original: 'Wrote Python services for restocking robots'),
            TailoredBullet(text: 'Invented bullet with C++ and no source', original: ''),
          ]),
          TailoredRole(roleId: 'fake-role', bullets: [TailoredBullet(text: 'CTO at Google')]),
        ],
      );
      TailorEngine.applyTruthGuard(cv, p, _jd());

      expect(cv.roles.map((r) => r.roleId), ['r1', 'r2'], reason: 'only real roles survive, missing roles restored');
      final b = cv.roles.first.bullets;
      expect(b[0].flags, isEmpty);
      expect(b[0].enabled, isTrue);
      expect(b[1].text, 'Wrote Python services for restocking robots', reason: 'reverted to original');
      expect(b[1].flags.join(), contains('Kubernetes'));
      expect(b[2].enabled, isFalse, reason: 'no truthful original to fall back to');
      expect(cv.skills, isNot(contains('Kubernetes')));
      expect(cv.skillFlags, contains('Kubernetes'));
      expect(cv.summary, 'Robotics developer shipping ROS2 systems.');
      expect(cv.headline, 'Robotics & AI Developer');
    });

    test('user-confirmed evidence counts as truth', () {
      final p = _profile()..evidence.add(SkillEvidence(skill: 'Kubernetes', context: 'Ran k3s cluster for robot fleet simulations'));
      expect(TailorEngine.initialDecisions(p, _jd())['Kubernetes'], SkillDecision.matched);
    });
  });

  group('Documents', () {
    test('DOCX is a valid single-column package with anchors intact', () {
      final p = _profile();
      final cv = TailoredCv(headline: 'Robotics Engineer', summary: 'ROS2 developer.', skills: ['ROS2', 'Python'], roles: [
        TailoredRole(roleId: 'r1', bullets: [TailoredBullet(text: 'Built ROS2 navigation <fast> & safe'), TailoredBullet(text: 'hidden', enabled: false)]),
      ]);
      final bytes = CvDocxBuilder.build(CvDocument(profile: p, cv: cv));
      final zip = ZipDecoder().decodeBytes(bytes);
      final xml = utf8.decode(zip.findFile('word/document.xml')!.content as List<int>);
      expect(xml, contains('Soham AI'));
      expect(xml, contains('&lt;fast&gt; &amp; safe'));
      expect(xml, isNot(contains('hidden')));
      expect(xml, isNot(contains('<w:tbl')), reason: 'no tables (ATS rule)');
    });

    test('deterministic file name', () {
      final doc = CvDocument(profile: _profile(), cv: TailoredCv());
      final o = Opportunity(id: 'x', source: 's', title: 'Senior Robotics Engineer (ROS)', company: 'Acme Robotics, Inc.');
      expect(doc.fileStem(o), 'Sk_Majid_Acme_Robotics_Inc_Senior_Robotics_Engineer_ROS');
    });
  });

  group('Discovery', () {
    test('country matching', () {
      Opportunity o(String loc, {bool remote = true}) => Opportunity(id: '1', source: 's', title: 't', location: loc, remote: remote);
      expect(matchesCountries(o('Worldwide'), ['REMOTE']), isTrue);
      expect(matchesCountries(o('USA Only'), ['IN']), isFalse);
      expect(matchesCountries(o('Europe'), ['DE']), isTrue);
      expect(matchesCountries(o('Dubai, UAE', remote: false), ['AE']), isTrue);
    });

    test('job pre-score rewards skill + title overlap', () {
      final p = _profile();
      final good = Opportunity(id: '1', source: 's', title: 'Robotics Developer', description: 'Python, ROS2, Docker, computer vision');
      final bad = Opportunity(id: '2', source: 's', title: 'Accountant', description: 'Excel and audits');
      expect(TextMatch.scoreJob(p, good, ['Robotics Developer']).score, greaterThan(TextMatch.scoreJob(p, bad, ['Robotics Developer']).score + 40));
    });
  });

  group('Models & JSON', () {
    test('profile round-trips', () {
      final p = _profile();
      final back = MasterProfile.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(back.roles.first.id, 'r1');
      expect(back.roles.first.bullets.length, 2);
    });

    test('parseJsonObject handles fenced and chatty replies', () {
      expect(parseJsonObject('```json\n{"a": 1}\n```')['a'], 1);
      expect(parseJsonObject('Sure! Here it is: {"b": [1,2]} hope that helps')['b'], [1, 2]);
      expect(() => parseJsonObject('no json'), throwsA(isA<LlmException>()));
    });
  });
}
