import 'models.dart';

/// Deterministic matching used for job pre-scoring, ATS scoring and the Truth Guard.
/// Runs on-device, free, with no AI call.
class TextMatch {
  static const Map<String, List<String>> _synonyms = {
    'javascript': ['js', 'ecmascript'],
    'typescript': ['ts'],
    'node.js': ['nodejs', 'node js', 'node'],
    'react': ['react.js', 'reactjs'],
    'react native': ['react-native'],
    'vue': ['vue.js', 'vuejs'],
    'next.js': ['nextjs', 'next js'],
    'postgresql': ['postgres', 'psql'],
    'kubernetes': ['k8s'],
    'ci/cd': ['cicd', 'ci cd', 'continuous integration', 'continuous delivery', 'continuous deployment'],
    'machine learning': ['ml'],
    'artificial intelligence': ['ai'],
    'large language models': ['llm', 'llms'],
    'natural language processing': ['nlp'],
    'computer vision': ['cv vision', 'opencv'],
    'amazon web services': ['aws'],
    'google cloud': ['gcp', 'google cloud platform'],
    'microsoft azure': ['azure'],
    'c#': ['csharp', 'c sharp'],
    'c++': ['cpp'],
    'golang': ['go lang'],
    'rest api': ['rest apis', 'restful', 'rest', 'restful apis', 'restful services'],
    'graphql': ['graph ql'],
    'user experience': ['ux'],
    'user interface': ['ui'],
    'search engine optimization': ['seo'],
    'customer relationship management': ['crm'],
    'product management': ['product manager'],
    'project management': ['project manager', 'pmp'],
    'agile': ['scrum', 'kanban'],
    'microsoft excel': ['excel', 'spreadsheets'],
    'power bi': ['powerbi'],
    'tensorflow': ['tf'],
    'pytorch': ['torch'],
    'robot operating system': ['ros', 'ros2'],
    'flutter': ['dart flutter'],
  };

  static final Map<String, String> _canonical = () {
    final m = <String, String>{};
    _synonyms.forEach((canon, alts) {
      m[canon] = canon;
      for (final a in alts) {
        m[a] = canon;
      }
    });
    return m;
  }();

  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[‐-―]'), '-')
      .replaceAll(RegExp(r"[^a-z0-9+#./\- ]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String canonical(String term) {
    final n = normalize(term);
    return _canonical[n] ?? n;
  }

  /// All surface forms worth searching for a term.
  static List<String> variants(String term, [List<String> aliases = const []]) {
    final canon = canonical(term);
    final out = <String>{normalize(term), canon, ...aliases.map(normalize)};
    final alts = _synonyms[canon];
    if (alts != null) out.addAll(alts);
    // "React.js" also matches "react"; "Python 3" matches "python".
    final stripped = canon.replaceAll(RegExp(r'\.js$'), '').replaceAll(RegExp(r'\s+\d+(\.\d+)?$'), '');
    if (stripped.length > 1) out.add(stripped);
    out.removeWhere((v) => v.isEmpty || (v.length < 2 && v != 'c' && v != 'r'));
    return out.toList();
  }

  static bool containsTerm(String haystackNormalized, String variant) {
    if (variant.isEmpty) return false;
    final escaped = RegExp.escape(variant);
    // Word boundaries that tolerate symbols like c++, c#, .net, ci/cd.
    return RegExp('(^|[^a-z0-9+#])$escaped(?![a-z0-9+#])').hasMatch(haystackNormalized);
  }

  static bool mentions(String textNormalized, String term, [List<String> aliases = const []]) =>
      variants(term, aliases).any((v) => containsTerm(textNormalized, v));

  // ---------------------------------------------------------------- job pre-scoring

  /// Cheap 0-100 relevance score of a job against the profile (no AI).
  static ({double score, List<String> matched}) scoreJob(MasterProfile profile, Opportunity job, List<String> keywords) {
    final jd = normalize('${job.title} ${job.description}');
    final title = normalize(job.title);
    final skills = <String>{...profile.skills, for (final r in profile.roles) ...r.skills, for (final p in profile.projects) ...p.skills}
        .where((s) => s.trim().length > 1)
        .toList();
    final matched = <String>[];
    for (final s in skills) {
      if (mentions(jd, s)) matched.add(s);
    }
    final skillPart = skills.isEmpty ? 0.0 : (matched.length / (skills.length.clamp(1, 12))).clamp(0.0, 1.0);
    final kw = [...keywords, ...profile.targetRoles, profile.headline].where((k) => k.trim().isNotEmpty);
    var titlePart = 0.0;
    for (final k in kw) {
      final words = normalize(k).split(' ').where((w) => w.length > 2).toList();
      if (words.isEmpty) continue;
      final hit = words.where((w) => title.contains(w)).length / words.length;
      if (hit > titlePart) titlePart = hit;
    }
    final score = (skillPart * 70 + titlePart * 30).clamp(0, 100).toDouble();
    return (score: score, matched: matched);
  }

  // ---------------------------------------------------------------- requirement coverage

  static bool profileHas(MasterProfile profile, Requirement r) => mentions(normalize(profile.truthCorpus), r.skill, r.aliases);

  /// ATS-style keyword coverage score (0-100). MUST requirements count double.
  static double atsScore(String cvText, List<Requirement> reqs, {List<String> keywords = const []}) {
    if (reqs.isEmpty) return 0;
    final text = normalize(cvText);
    var total = 0.0, hit = 0.0;
    for (final r in reqs) {
      final w = r.importance == Importance.must ? 2.0 : 1.0;
      total += w;
      if (mentions(text, r.skill, r.aliases)) hit += w;
    }
    var kwTotal = 0, kwHit = 0;
    for (final k in keywords.take(15)) {
      kwTotal++;
      if (text.contains(normalize(k))) kwHit++;
    }
    final coverage = hit / total;
    final kwCoverage = kwTotal == 0 ? coverage : kwHit / kwTotal;
    // 80% requirement coverage, 10% phrase mirroring, 10% structure (single-column, parseable — always true for our export).
    return ((coverage * 0.8 + kwCoverage * 0.1 + 0.1) * 100).clamp(0, 100).toDouble();
  }

  // ---------------------------------------------------------------- truth guard

  /// Returns JD requirement terms that appear in [text] but are not supported by the
  /// candidate's own statements ([truth]). Used to flag/strip invented claims.
  static List<String> unsupportedClaims(String text, String truth, List<Requirement> reqs) {
    final t = normalize(text);
    final src = normalize(truth);
    final out = <String>[];
    for (final r in reqs) {
      if (mentions(t, r.skill, r.aliases) && !mentions(src, r.skill, r.aliases)) out.add(r.skill);
    }
    return out;
  }

  /// Numbers/percentages in [text] that never appear in [truth] (invented metrics).
  static List<String> unsupportedNumbers(String text, String truth) {
    final nums = RegExp(r'\d[\d,.]*\s?%?').allMatches(text).map((m) => m.group(0)!.trim().replaceAll(RegExp(r'[.,]$'), ''));
    final src = truth.replaceAll(' ', '');
    return nums.where((n) => n.isNotEmpty && !src.contains(n.replaceAll(' ', ''))).toSet().toList();
  }
}
