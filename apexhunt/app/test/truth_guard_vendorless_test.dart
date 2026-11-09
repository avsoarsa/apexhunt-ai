import 'package:apexhunt_ai/core/models.dart';
import 'package:apexhunt_ai/features/tailor/tailor_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Review of ec8b196 (B). Vendor-less names ("lambda" for "AWS Lambda") are now used as evidence,
/// so ordinary words in a CV count as proof of a product the candidate never used.
/// These fail on 2e9b552 and should pass once vendor-less names are used for claims only
/// (or accepted as evidence only from structured skills lists).
MasterProfile _profile() => MasterProfile(
      contact: Contact(name: 'Arjun Rao'),
      headline: 'Java Developer',
      rawText: 'Arjun Rao\nJava Developer, LoanWorks (2020 - Present)\n'
          '- Refactored payment rules with Java lambda expressions.\n'
          '- Gave stakeholders access to weekly loan reports.\n'
          '- Improved team dynamics during the platform migration.\n'
          '- Set up build pipelines in Jenkins.',
      roles: [
        WorkRole(id: 'r1', company: 'LoanWorks', title: 'Java Developer', start: '2020-01', bullets: [
          'Refactored payment rules with Java lambda expressions.',
          'Gave stakeholders access to weekly loan reports.',
          'Improved team dynamics during the platform migration.',
          'Set up build pipelines in Jenkins.',
        ], skills: ['Java', 'Jenkins']),
      ],
      skills: ['Java', 'Jenkins'],
    );

JdAnalysis _jd(List<String> skills) => JdAnalysis(title: 'Cloud Engineer', requirements: [for (final s in skills) Requirement(skill: s)]);

void main() {
  test('ordinary words are not evidence for vendor products', () {
    final d = TailorEngine.initialDecisions(_profile(), _jd(['AWS Lambda', 'Microsoft Access', 'Microsoft Dynamics', 'Azure Pipelines']));
    expect(d['AWS Lambda'], SkillDecision.gap, reason: 'Java "lambda expressions" are not AWS Lambda');
    expect(d['Microsoft Access'], SkillDecision.gap, reason: '"gave stakeholders access" is not MS Access');
    expect(d['Microsoft Dynamics'], SkillDecision.gap, reason: '"team dynamics" is not Microsoft Dynamics');
    expect(d['Azure Pipelines'], SkillDecision.gap, reason: 'Jenkins "build pipelines" are not Azure Pipelines');
  });

  test('an AWS Lambda claim built on "lambda expressions" is removed', () {
    final p = _profile();
    final cv = TailoredCv(headline: 'Java Developer', skills: ['Java'], roles: [
      TailoredRole(roleId: 'r1', bullets: [
        TailoredBullet(text: 'Built serverless loan APIs on AWS Lambda.', original: 'Refactored payment rules with Java lambda expressions.'),
      ]),
    ]);
    TailorEngine.applyTruthGuard(cv, p, _jd(['AWS Lambda']));
    expect(TailorEngine.tailoredCvText(p, cv), isNot(contains('AWS Lambda')));
  });
}
