import 'package:apexhunt_ai/core/models.dart';
import 'package:apexhunt_ai/core/text_match.dart';
import 'package:apexhunt_ai/features/tailor/tailor_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adversarial Truth Guard cases from the QA pass (B).
///
/// Each test asserts the honest behaviour that CLAUDE.md promises. On main
/// (b46a08e) they fail: they reproduce the bypasses reported in the linked
/// issues, so whoever fixes the guard can make them green.
///
/// The profile is a realistic import: `rawText` holds the whole original CV,
/// including dates, a phone number and a PIN code, as a real upload does.
const _rawCv = '''Priya Sharma | +91 98765 43210 | priya@example.com | Hyderabad 500081
Backend Developer, Finlytics (Jan 2021 - Present)
- Built REST APIs in Node.js for loan processing.
- Helped the payments product go live in three cities.
- Presented sprint demos to C-level stakeholders.
Junior Developer, CodeNest (Jul 2019 - Dec 2020)
- Wrote SQL reports in PostgreSQL.
- Supported R&D experiments on credit scoring.
Education: B.Tech Computer Science, JNTU, 2019''';

MasterProfile _profile() => MasterProfile(
      contact: Contact(name: 'Priya Sharma', email: 'priya@example.com', phone: '+91 98765 43210', location: 'Hyderabad 500081'),
      headline: 'Backend Developer',
      rawText: _rawCv,
      roles: [
        WorkRole(id: 'r1', company: 'Finlytics', title: 'Backend Developer', start: '2021-01', bullets: [
          'Built REST APIs in Node.js for loan processing.',
          'Helped the payments product go live in three cities.',
          'Presented sprint demos to C-level stakeholders.',
        ], skills: ['Node.js']),
        WorkRole(id: 'r2', company: 'CodeNest', title: 'Junior Developer', start: '2019-07', end: '2020-12', bullets: [
          'Wrote SQL reports in PostgreSQL.',
          'Supported R&D experiments on credit scoring.',
        ], skills: ['PostgreSQL']),
      ],
      skills: ['Node.js', 'PostgreSQL', 'SQL'],
      education: [Education(institution: 'JNTU', degree: 'B.Tech', year: '2019')],
    );

JdAnalysis _jd(List<Requirement> reqs) => JdAnalysis(title: 'Backend Engineer', requirements: reqs);

/// Everything that would reach the exported CV.
String _exported(MasterProfile p, TailoredCv cv) => TailorEngine.tailoredCvText(p, cv);

void main() {
  group('Truth Guard: invented numbers', () {
    test('a number is unsupported even if its digits appear inside a date or phone number', () {
      expect(TextMatch.unsupportedNumbers('Led a team of 8 engineers', _rawCv), ['8'], reason: '"8" only appears inside 98765 and 500081');
      expect(TextMatch.unsupportedNumbers('10+ years of experience', _rawCv), ['10'], reason: '"10" only appears inside 43210');
    });

    test('invented experience and metrics are removed from summary and bullets', () {
      final p = _profile();
      final cv = TailoredCv(
        headline: 'Backend Developer',
        summary: 'Backend developer with 10+ years of experience leading a team of 8 engineers.',
        skills: ['Node.js'],
        roles: [
          TailoredRole(roleId: 'r1', bullets: [
            TailoredBullet(text: 'Built REST APIs in Node.js serving 50 banks and 2 million users.', original: 'Built REST APIs in Node.js for loan processing.'),
          ]),
        ],
      );
      TailorEngine.applyTruthGuard(cv, p, _jd([Requirement(skill: 'Node.js')]));
      final text = _exported(p, cv);
      for (final invented in ['10+ years', 'team of 8', '50 banks', '2 million']) {
        expect(text, isNot(contains(invented)));
      }
    });

    test('numbers in the headline are checked too', () {
      final p = _profile();
      final cv = TailoredCv(headline: 'Senior Backend Engineer | 12 years | 40% faster APIs', skills: ['Node.js']);
      TailorEngine.applyTruthGuard(cv, p, _jd([Requirement(skill: 'Node.js')]));
      expect(cv.headline, isNot(contains('12 years')));
      expect(cv.headline, isNot(contains('40%')));
    });
  });

  group('Truth Guard: what counts as evidence for a skill', () {
    test('ordinary words are not evidence for Go, C or R', () {
      final d = TailorEngine.initialDecisions(_profile(), _jd([Requirement(skill: 'Go'), Requirement(skill: 'C'), Requirement(skill: 'R')]));
      expect(d['Go'], SkillDecision.gap, reason: '"go live" is not Go experience');
      expect(d['C'], SkillDecision.gap, reason: '"C-level" is not C experience');
      expect(d['R'], SkillDecision.gap, reason: '"R&D" is not R experience');
    });

    test('a Go claim built on "go live" is removed', () {
      final p = _profile();
      final cv = TailoredCv(headline: 'Backend Developer', skills: ['Node.js', 'Go'], roles: [
        TailoredRole(roleId: 'r1', bullets: [
          TailoredBullet(text: 'Built loan-processing microservices in Go and Node.js.', original: 'Built REST APIs in Node.js for loan processing.'),
        ]),
      ]);
      TailorEngine.applyTruthGuard(cv, p, _jd([Requirement(skill: 'Go')]));
      expect(cv.skills, isNot(contains('Go')));
      expect(_exported(p, cv), isNot(contains('microservices in Go')));
    });

    test('aliases written by the AI cannot make a missing skill look supported', () {
      final p = _profile();
      final lambda = Requirement(skill: 'AWS Lambda', aliases: ['serverless', 'Node.js']);
      expect(TailorEngine.initialDecisions(p, _jd([lambda]))['AWS Lambda'], SkillDecision.gap);
      final cv = TailoredCv(headline: 'Backend Developer', skills: ['Node.js'], roles: [
        TailoredRole(roleId: 'r1', bullets: [
          TailoredBullet(text: 'Built serverless loan APIs on AWS Lambda with Node.js.', original: 'Built REST APIs in Node.js for loan processing.'),
        ]),
      ]);
      TailorEngine.applyTruthGuard(cv, p, _jd([lambda]));
      expect(_exported(p, cv), isNot(contains('AWS Lambda')));
    });
  });

  group('Truth Guard: reverting', () {
    test('a flagged bullet falls back to the real bullet, not to text the AI labelled "original"', () {
      final p = _profile();
      final cv = TailoredCv(headline: 'Backend Developer', skills: ['Node.js'], roles: [
        TailoredRole(roleId: 'r1', bullets: [
          TailoredBullet(text: 'Built Kafka pipelines for loan events.', original: 'Designed the event-driven architecture for all loan processing.'),
        ]),
      ]);
      TailorEngine.applyTruthGuard(cv, p, _jd([Requirement(skill: 'Kafka')]));
      expect(_exported(p, cv), isNot(contains('Designed the event-driven architecture')));
    });
  });
}
