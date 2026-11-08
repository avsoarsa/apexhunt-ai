import 'package:apexhunt_ai/core/models.dart';
import 'package:apexhunt_ai/features/tailor/tailor_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Review of the Truth Guard fix in 7889ff2 (B). Each test states the honest behaviour;
/// they fail on 7889ff2 and should pass once the review points are addressed.
MasterProfile _profile() => MasterProfile(
      contact: Contact(name: 'Priya Sharma'),
      headline: 'Backend Developer',
      rawText: 'Priya Sharma\nBackend Developer, Finlytics (2021 - Present)\n'
          '- Built REST APIs in Node.js for loan processing.\n- Coached new analysts to excel in client reviews.',
      roles: [
        WorkRole(id: 'r1', company: 'Finlytics', title: 'Backend Developer', start: '2021-01', bullets: [
          'Built REST APIs in Node.js for loan processing.',
          'Coached new analysts to excel in client reviews.',
        ], skills: ['Node.js']),
      ],
      skills: ['Node.js'],
    );

JdAnalysis _jd(List<Requirement> reqs) => JdAnalysis(title: 'Backend Engineer', requirements: reqs);

TailoredCv _cvWith(String bullet) => TailoredCv(headline: 'Backend Developer', skills: ['Node.js'], roles: [
      TailoredRole(roleId: 'r1', bullets: [TailoredBullet(text: bullet, original: 'Built REST APIs in Node.js for loan processing.')]),
    ]);

void main() {
  group('Claim detection still sees short forms', () {
    test('"Kafka" is a claim of the requirement "Apache Kafka"', () {
      final p = _profile();
      final cv = _cvWith('Built Kafka pipelines for loan processing.');
      TailorEngine.applyTruthGuard(cv, p, _jd([Requirement(skill: 'Apache Kafka', aliases: ['Kafka'])]));
      expect(TailorEngine.tailoredCvText(p, cv), isNot(contains('Kafka')));
    });

    test('"AWS" is a claim of the requirement "Amazon Web Services (AWS)"', () {
      final p = _profile();
      final cv = _cvWith('Deployed the loan APIs on AWS.');
      TailorEngine.applyTruthGuard(cv, p, _jd([Requirement(skill: 'Amazon Web Services (AWS)', aliases: ['AWS'])]));
      expect(TailorEngine.tailoredCvText(p, cv), isNot(contains('on AWS')));
    });
  });

  group('Ambiguous names', () {
    test('"excel in client reviews" is not Excel evidence', () {
      expect(TailorEngine.initialDecisions(_profile(), _jd([Requirement(skill: 'Excel')]))['Excel'], SkillDecision.gap);
    });

    test('an Excel claim built on "excel in" is removed', () {
      final p = _profile();
      final cv = _cvWith('Built loan dashboards in Excel.');
      TailorEngine.applyTruthGuard(cv, p, _jd([Requirement(skill: 'Excel')]));
      expect(TailorEngine.tailoredCvText(p, cv), isNot(contains('dashboards in Excel')));
    });
  });
}
