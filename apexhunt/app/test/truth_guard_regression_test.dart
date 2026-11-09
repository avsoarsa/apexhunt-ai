import 'package:apexhunt_ai/core/models.dart';
import 'package:apexhunt_ai/core/text_match.dart';
import 'package:apexhunt_ai/features/tailor/tailor_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the Truth Guard fixes to #9, #10 and #11 (A).
/// They pin behaviour the fixes introduced, so honest lines aren't caught as collateral damage.
MasterProfile _profile() => MasterProfile(
      contact: Contact(name: 'Priya Sharma', phone: '+91 98765 43210'),
      headline: 'Backend Developer',
      rawText: 'Priya Sharma +91 98765 43210\nBackend Developer, Finlytics 03/2021 - Present\nSkills: Golang, PostgreSQL',
      roles: [
        WorkRole(id: 'r1', company: 'Finlytics', title: 'Backend Developer', start: '2021-03', bullets: [
          'Helped the payments product go live in three cities.',
          'Cut report generation time by 1,000 ms using PostgreSQL indexes.',
        ]),
      ],
      skills: ['Golang', 'PostgreSQL'],
    );

JdAnalysis _jd(List<String> skills) => JdAnalysis(requirements: [for (final s in skills) Requirement(skill: s)]);

void main() {
  test('a skills-list "Golang" is evidence for a Go requirement', () {
    expect(TailorEngine.initialDecisions(_profile(), _jd(['Go']))['Go'], SkillDecision.matched);
  });

  test('a real bullet survives verbatim even when it contains an ambiguous word', () {
    final p = _profile()..skills.remove('Golang');
    final cv = TailoredCv(headline: 'Backend Developer', skills: ['PostgreSQL'], roles: [
      TailoredRole(roleId: 'r1', bullets: [TailoredBullet(text: 'Helped the payments product go live in three cities.', original: 'x')]),
    ]);
    TailorEngine.applyTruthGuard(cv, p, _jd(['Go']));
    final b = cv.roles.single.bullets.single;
    expect(b.enabled, isTrue);
    expect(b.flags, isEmpty);
    expect(b.original, isEmpty, reason: 'an unverifiable "original" is cleared, so the Vault never shows it as "Was:"');
  });

  test('number words are checked like digits, and stated words count as evidence', () {
    const truth = 'Helped the payments product go live in three cities.';
    expect(TextMatch.unsupportedNumbers('Launched in 3 cities', truth), isEmpty, reason: '"three" backs "3"');
    expect(TextMatch.unsupportedNumbers('Ten years of experience', truth), ['Ten']);
  });

  test('formatting variants of the same number are accepted', () {
    const truth = 'Cut report generation time by 1,000 ms; grew usage 25%.';
    expect(TextMatch.unsupportedNumbers('Saved 1000 ms per report and grew usage by 25 %', truth), isEmpty);
  });

  test('date months and phone digits are not evidence for metrics', () {
    final truth = _profile().rawText;
    expect(TextMatch.unsupportedNumbers('Shipped to 3 regions', truth), ['3'], reason: '"03/2021" is a date, not a metric');
    expect(TextMatch.unsupportedNumbers('91% test coverage', truth), ['91%'], reason: '+91 is a country code');
    expect(TextMatch.unsupportedNumbers('Backend developer since 2021', truth), isEmpty, reason: 'the year itself still counts');
  });

  test('digits inside names (ROS2, EC2) are not treated as metrics', () {
    expect(TextMatch.unsupportedNumbers('Built ROS2 nodes on AWS EC2', ''), isEmpty);
  });

  test('a skill the user un-ticked at check-in is removed even if the profile mentions it', () {
    final p = _profile();
    final cv = TailoredCv(headline: 'Go Backend Developer', skills: ['Golang', 'PostgreSQL'], roles: [
      TailoredRole(roleId: 'r1', bullets: [
        TailoredBullet(text: 'Built Go services for payments.', original: 'Helped the payments product go live in three cities.'),
      ]),
    ]);
    TailorEngine.applyTruthGuard(cv, p, _jd(['Go']), notHeld: {TextMatch.canonical('Go')});
    expect(cv.skills, ['PostgreSQL']);
    expect(cv.headline, 'Backend Developer');
    expect(cv.roles.single.bullets.single.text, 'Helped the payments product go live in three cities.');
  });

  test('"guard rails" in a profile is not evidence for Ruby', () {
    final p = _profile()..roles.first.bullets.add('Added guard rails to the deploy pipeline.');
    expect(TextMatch.hasEvidence(p, 'Ruby'), isFalse);
  });

  test('an AI alias the user really has does not flag an honest line', () {
    final p = _profile()..skills.add('Node.js');
    final req = Requirement(skill: 'AWS Lambda', aliases: ['Node.js']);
    expect(TextMatch.unsupportedClaims('Built REST APIs in Node.js.', p, [req]), isEmpty);
    expect(TextMatch.unsupportedClaims('Deployed serverless functions on AWS Lambda.', p, [req]), ['AWS Lambda']);
  });

  test('a listed "Microsoft Excel" is evidence for an Excel requirement', () {
    final p = _profile()..skills.add('Microsoft Excel');
    expect(TextMatch.hasEvidence(p, 'Excel'), isTrue);
  });

  // #23: vendor-less names are claims-only in free text; structured lists and curated synonyms still count.
  test('a distinctive short name in a bullet ("Kafka") is evidence for "Apache Kafka"', () {
    final p = _profile()..roles.first.bullets.add('Built Kafka consumers for payment events.');
    expect(TextMatch.hasEvidence(p, 'Apache Kafka'), isTrue);
  });

  test('a skills-list "Lambda" is evidence for "AWS Lambda", but a bullet word is not', () {
    expect(TextMatch.hasEvidence(_profile()..skills.add('Lambda'), 'AWS Lambda'), isTrue);
    expect(TextMatch.hasEvidence(_profile()..roles.first.bullets.add('Used Java lambda expressions.'), 'AWS Lambda'), isFalse);
  });

  test('the AI writing a bare vendor-less name is still caught as a claim', () {
    final p = _profile()..roles.first.bullets.add('Used Java lambda expressions.');
    expect(TextMatch.unsupportedClaims('Deployed the loan APIs to Lambda.', p, [Requirement(skill: 'AWS Lambda')]), ['AWS Lambda']);
  });

  test('ProfileEvidence gives the same answers as hasEvidence', () {
    final p = _profile()..skills.add('Microsoft Excel');
    final ev = ProfileEvidence(p);
    for (final s in ['Go', 'Excel', 'PostgreSQL', 'Ruby', 'AWS Lambda', 'Kafka']) {
      expect(ev.has(s), TextMatch.hasEvidence(p, s), reason: s);
    }
  });
}
