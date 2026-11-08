import 'dart:convert';

import '../../core/ai/llm.dart';
import '../../core/ai/prompts.dart';
import '../../core/models.dart';
import '../../core/text_match.dart';

/// The honest tailoring pipeline:
///   1. JD Auditor      — decompose the posting into requirements (AI)
///   2. Skill check-in  — user confirms what they really have (UI, no AI)
///   3. CV Tailor       — rewrite real experience in the job's language (AI)
///   4. Truth Guard     — strip any claim/number not backed by the profile (deterministic)
///   5. ATS scorer      — before/after keyword coverage (deterministic)
///   6. Prep Coach      — STAR stories, likely questions, honest gap plans (AI)
///   7. Cover letter / freelance proposal (AI)
class TailorEngine {
  TailorEngine(this.llm);
  final LlmClient llm;
  double spentUsd = 0;

  Future<Map<String, dynamic>> _json(String system, String user, {int maxTokens = 3500, String purpose = 'chat'}) async {
    final res = await llm.complete([ChatMsg.system(system), ChatMsg.user(user)], json: true, maxTokens: maxTokens, temperature: 0.3, purpose: purpose);
    spentUsd += res.chargedUsd;
    return parseJsonObject(res.content);
  }

  static String _clip(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;

  // ------------------------------------------------------------------ 1. JD audit

  Future<JdAnalysis> analyze(Opportunity o) async {
    final j = await _json(
      Prompts.analyzeJd,
      'POSTING (${o.kind == MissionMode.freelance ? 'freelance brief' : 'job'}):\nTitle: ${o.title}\nCompany/Client: ${o.company}\nLocation: ${o.location}\n\n"""\n${_clip(o.description, 14000)}\n"""',
      maxTokens: 2500,
      purpose: 'analyze_jd',
    );
    final a = JdAnalysis.fromJson(j);
    if (a.title.isEmpty) a.title = o.title;
    if (a.company.isEmpty) a.company = o.company;
    return a;
  }

  // ------------------------------------------------------------------ 2. initial decisions

  static Map<String, SkillDecision> initialDecisions(MasterProfile p, JdAnalysis a) {
    final learning = p.learning.map(TextMatch.canonical).toSet();
    return {
      for (final r in a.requirements)
        r.skill: TextMatch.hasEvidence(p, r.skill)
            ? SkillDecision.matched
            : learning.contains(TextMatch.canonical(r.skill))
                ? SkillDecision.learning
                : SkillDecision.gap,
    };
  }

  // ------------------------------------------------------------------ 3 + 4. tailor & guard

  Future<TailoredCv> tailor({required MasterProfile profile, required Opportunity opportunity, required JdAnalysis analysis, required Map<String, SkillDecision> decisions}) async {
    final confirmed = profile.evidence.map((e) => {'skill': e.skill, 'context': e.context, 'role_id': e.roleId}).toList();
    final learning = {
      ...profile.learning,
      ...decisions.entries.where((e) => e.value == SkillDecision.learning).map((e) => e.key),
    }.toList();
    final user = '''
CANDIDATE_PROFILE:
${jsonEncode(profile.toPromptJson())}

CONFIRMED_SKILLS (candidate's own statements):
${jsonEncode(confirmed)}

LEARNING (not yet experienced — never claim): ${jsonEncode(learning)}

JOB_ANALYSIS:
${jsonEncode(analysis.toJson())}

TARGET: ${opportunity.title} @ ${opportunity.company}''';
    final j = await _json(Prompts.tailorCv(freelance: opportunity.kind == MissionMode.freelance), user, maxTokens: 4000, purpose: 'tailor_cv');
    final cv = TailoredCv.fromJson(j);
    cv.learning = cv.learning.where((s) => learning.any((l) => TextMatch.canonical(l) == TextMatch.canonical(s))).toList();
    final notHeld = {
      for (final e in decisions.entries)
        if (e.value == SkillDecision.gap || e.value == SkillDecision.learning) TextMatch.canonical(e.key),
    };
    applyTruthGuard(cv, profile, analysis, notHeld: notHeld);
    return cv;
  }

  /// Deterministic safety net: anything the model wrote that the candidate never said is reverted or removed.
  ///
  /// [notHeld] = skills the user said they don't have (or are only learning) during check-in. They are
  /// treated as unsupported even if a word in the profile looks like them.
  static void applyTruthGuard(TailoredCv cv, MasterProfile profile, JdAnalysis analysis, {Set<String> notHeld = const {}}) {
    final truth = profile.truthCorpus;
    final reqs = analysis.requirements;
    bool held(String skill) => !notHeld.contains(TextMatch.canonical(skill)) && TextMatch.hasEvidence(profile, skill);
    List<String> badClaims(String text) {
      final t = TextMatch.normalize(text);
      return [for (final r in reqs) if (TextMatch.claims(t, r.skill) && !held(r.skill)) r.skill];
    }

    List<String> badNumbers(String text) => TextMatch.unsupportedNumbers(text, truth);

    // Lines the user really wrote: role/project bullets and check-in contexts (normalised → exact text).
    String key(String s) => TextMatch.normalize(s).replaceAll(RegExp(r'[.;:!]+$'), '').trim();
    final realLines = <String, String>{
      for (final r in profile.roles) for (final b in r.bullets) key(b): b,
      for (final pr in profile.projects) for (final b in pr.bullets) key(b): b,
      for (final e in profile.evidence) key(e.context): e.context,
    };
    Set<String> words(String s) => key(s).split(RegExp(r'[^a-z0-9+#]+')).where((w) => w.length > 2).toSet();
    String? realSource(String candidate) {
      if (candidate.trim().isEmpty) return null;
      final exact = realLines[key(candidate)];
      if (exact != null) return exact;
      final cw = words(candidate);
      if (cw.isEmpty) return null;
      for (final entry in realLines.entries) {
        final rw = words(entry.value);
        final inter = cw.intersection(rw).length;
        final union = cw.union(rw).length;
        if (union > 0 && inter / union >= 0.8) return entry.value; // same line, minor punctuation/wording drift
      }
      return null;
    }

    // Roles: keep only real role ids; fall back to original bullets for roles the model skipped.
    final byId = {for (final r in cv.roles) r.roleId: r};
    cv.roles = [
      for (final role in profile.roles)
        byId[role.id] ?? TailoredRole(roleId: role.id, bullets: role.bullets.map((b) => TailoredBullet(text: b, original: b, change: BulletChange.unchanged)).toList()),
    ];

    for (final role in cv.roles) {
      for (final b in role.bullets) {
        // The model fills in `original` itself, so verify it: only the user's real line may be shown as "Was:".
        b.original = realSource(b.original) ?? '';
        // A verbatim real line is true by definition (it may still contain an ambiguous word like "go live").
        if (realLines.containsKey(key(b.text))) {
          b.flags = [];
          continue;
        }
        final claims = badClaims(b.text);
        final numbers = badNumbers(b.text);
        if (claims.isEmpty && numbers.isEmpty) continue;
        b.flags = [
          ...claims.map((c) => 'Removed unsupported skill: $c'),
          ...numbers.map((n) => 'Removed number not in your CV: $n'),
        ];
        if (b.original.isNotEmpty) {
          b.text = b.original;
          b.change = BulletChange.unchanged;
        } else {
          b.enabled = false;
          b.flags.add('No matching line in your CV to fall back to');
        }
      }
      role.bullets.removeWhere((b) => b.text.trim().isEmpty);
    }

    // Skills list: only skills the candidate has actually stated (strict evidence).
    final kept = <String>[];
    for (final s in cv.skills) {
      if (held(s)) {
        kept.add(s);
      } else {
        cv.skillFlags.add(s);
      }
    }
    cv.skills = kept.toSet().toList();
    if (cv.skills.isEmpty) cv.skills = [for (final s in profile.skills) if (!notHeld.contains(TextMatch.canonical(s))) s];

    // Summary: drop any sentence with an unsupported claim or number.
    cv.summary = cv.summary
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((sentence) => badClaims(sentence).isEmpty && badNumbers(sentence).isEmpty)
        .join(' ')
        .trim();
    // Headline: skills and numbers are both checked; fall back to the user's own headline.
    if (badClaims(cv.headline).isNotEmpty || badNumbers(cv.headline).isNotEmpty) cv.headline = profile.headline;
    cv.projectIds = cv.projectIds.where((id) => profile.projects.any((p) => p.id == id)).toList();
  }

  // ------------------------------------------------------------------ 5. ATS text

  static String baseCvText(MasterProfile p) => [
        p.contact.name,
        p.headline,
        p.summary,
        p.skills.join(', '),
        for (final r in p.roles) ...[r.title, r.company, ...r.bullets],
        for (final pr in p.projects) ...[pr.name, pr.description, ...pr.bullets],
        for (final e in p.education) '${e.degree} ${e.institution}',
        ...p.certifications,
      ].join('\n');

  static String tailoredCvText(MasterProfile p, TailoredCv cv) => [
        p.contact.name,
        cv.headline,
        cv.summary,
        cv.skills.join(', '),
        for (final r in cv.roles) ...[
          p.roles.where((x) => x.id == r.roleId).map((x) => '${x.title} ${x.company}').join(),
          ...r.bullets.where((b) => b.enabled).map((b) => b.text),
        ],
        for (final pr in p.projects.where((x) => cv.projectIds.contains(x.id))) ...[pr.name, pr.description, ...pr.bullets],
        for (final e in p.education) '${e.degree} ${e.institution}',
        ...p.certifications,
      ].join('\n');

  // ------------------------------------------------------------------ 6. prep

  Future<PrepDossier> prep({required MasterProfile profile, required Opportunity opportunity, required JdAnalysis analysis, required TailoredCv cv, required Map<String, SkillDecision> decisions}) async {
    final gaps = decisions.entries.where((e) => e.value == SkillDecision.gap || e.value == SkillDecision.learning).map((e) => e.key).take(8).toList();
    final user = '''
CANDIDATE_PROFILE:
${jsonEncode(profile.toPromptJson())}

TAILORED_CV:
${jsonEncode(cv.toJson())}

JOB_ANALYSIS:
${jsonEncode(analysis.toJson())}

GAPS (the candidate does NOT have these yet): ${jsonEncode(gaps)}''';
    final j = await _json(Prompts.prepDossier(freelance: opportunity.kind == MissionMode.freelance), user, maxTokens: 6000, purpose: 'prep');
    return PrepDossier.fromJson(j);
  }

  // ------------------------------------------------------------------ 7. cover letter / proposal

  Future<String> applicationNote({required MasterProfile profile, required Opportunity opportunity, required JdAnalysis analysis, required TailoredCv cv, required Map<String, SkillDecision> decisions}) async {
    final freelance = opportunity.kind == MissionMode.freelance;
    final gaps = decisions.entries.where((e) => e.value == SkillDecision.gap).map((e) => e.key).toList();
    final user = '''
CANDIDATE_PROFILE:
${jsonEncode(profile.toPromptJson())}

TAILORED_CV:
${jsonEncode(cv.toJson())}

${freelance ? 'CLIENT_BRIEF' : 'JOB_POSTING'}:
${_clip(opportunity.description, 8000)}

JOB_ANALYSIS: ${jsonEncode(analysis.toJson())}
GAPS: ${jsonEncode(gaps)}
HOURLY_RATE_USD: ${profile.hourlyRateUsd}''';
    final j = await _json(freelance ? Prompts.freelanceProposal : Prompts.coverLetter, user, maxTokens: 2000, purpose: freelance ? 'proposal' : 'cover_letter');
    return '${j['proposal_markdown'] ?? j['letter_markdown'] ?? ''}'.trim();
  }
}
