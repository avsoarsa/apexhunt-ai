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
    // Product names distinctive enough to count without the vendor, even in free text. Short forms that
    // are ordinary words ("lambda", "access", "dynamics", "pipelines", "glue") must NOT be added here.
    'apache kafka': ['kafka'],
    'apache cassandra': ['cassandra'],
    'apache hadoop': ['hadoop'],
    'google bigquery': ['bigquery', 'big query'],
    'google firebase': ['firebase'],
    'amazon s3': ['aws s3', 's3'],
    'amazon dynamodb': ['aws dynamodb', 'dynamodb'],
    'amazon redshift': ['aws redshift', 'redshift'],
    'microsoft power bi': ['power bi', 'powerbi'],
    'google cloud': ['gcp', 'google cloud platform'],
    'microsoft azure': ['azure'],
    'c#': ['csharp', 'c sharp'],
    'c++': ['cpp'],
    'go': ['golang', 'go lang'],
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

  // ---------------------------------------------------------------- evidence (strict) vs claims (broad)
  //
  // Evidence = proof the candidate really has a skill. It comes only from the profile, never from
  // AI-written aliases, and ambiguous names (Go, C, R…) need a skills-list entry or a disambiguated form.
  // Claims = what the AI wrote in generated text. Detection is deliberately broad so nothing slips past.

  /// Skill names that are also ordinary words ("go live", "C-level", "R&D", "express interest").
  /// In free text they only count when written in an unambiguous form.
  static const Map<String, List<String>> _ambiguous = {
    'go': ['golang', 'go lang', 'go language', 'go programming', 'go developer', 'go engineer'],
    'c': ['c programming', 'c language', 'ansi c', 'embedded c', 'c/c++', 'c and c++', 'c99', 'c11'],
    'r': ['r programming', 'r language', 'rstudio', 'r studio', 'tidyverse', 'ggplot2'],
    'swift': ['swiftui', 'swift language', 'swift programming', 'ios swift', 'swift/ios'],
    'rust': ['rust language', 'rust programming', 'rustlang', 'rust developer'],
    'dart': ['dart language', 'dart programming', 'flutter/dart', 'dart/flutter'],
    'express': ['express.js', 'expressjs', 'express framework', 'node/express'],
    'spring': ['spring boot', 'spring framework', 'spring mvc', 'spring cloud'],
    'ruby': ['ruby on rails', 'ruby language', 'ruby programming', 'rails framework', 'rails developer', 'rails api'],
    'unity': ['unity3d', 'unity engine', 'unity game', 'unity developer', 'c# unity'],
    'microsoft excel': ['microsoft excel', 'ms excel', 'excel vba', 'advanced excel', 'excel macros', 'excel pivot tables'],
  };

  /// Structured skill entries the candidate stated (skills list, per-role/project tools, check-in confirmations).
  /// Keys include vendor-less names, so a listed "Lambda" matches "AWS Lambda" and vice versa.
  static Set<String> _statedSkills(MasterProfile p) => {
        for (final s in p.skills) ...nameKeys(s),
        for (final r in p.roles) for (final s in r.skills) ...nameKeys(s),
        for (final pr in p.projects) for (final s in pr.skills) ...nameKeys(s),
        for (final e in p.evidence) ...nameKeys(e.skill),
        for (final c in p.certifications) ...nameKeys(c),
      };

  /// Free text the candidate wrote (bullets, summary, raw CV, check-in contexts).
  static String _statedText(MasterProfile p) => normalize(p.truthCorpus);

  static const _vendorPrefixes = ['apache', 'amazon', 'aws', 'google', 'microsoft', 'azure'];

  /// Vendor-less remainders too generic to stand for the product ("Google Cloud" is not "cloud").
  static const _genericNames = {
    'cloud', 'cloud platform', 'web services', 'services', 'platform', 'analytics', 'ads', 'sheets', 'docs', 'drive',
    'functions', 'teams', 'office', 'search', 'maps', 'storage', 'database', 'data', 'security', 'devops', 'ai', 'ml',
    'api', 'apis', 'console', 'workspace', 'mail', 'forms', 'word', 'project', 'cloud functions', 'cloud storage',
  };

  /// A skill's full names: "Amazon Web Services (AWS)" → [Amazon Web Services, AWS]. No vendor stripping.
  /// These are the only names that count as evidence in free text.
  static List<String> fullNames(String term) {
    final t = term.trim();
    final paren = RegExp(r'^(.*?)\s*\(([^)]+)\)\s*$').firstMatch(t);
    final base = paren == null ? [t] : [paren.group(1)!.trim(), paren.group(2)!.trim()];
    return [for (final b in base) if (b.isNotEmpty) b];
  }

  /// Every name a skill goes by: its full names plus vendor-less forms ("AWS Lambda" → [AWS Lambda, lambda]).
  /// Used to catch claims in generated text and to compare structured skills lists, never as free-text
  /// evidence: "lambda expressions" or "gave stakeholders access" prove nothing about AWS Lambda or MS Access.
  static List<String> names(String term) {
    final out = <String>{};
    for (final b in fullNames(term)) {
      out.add(b);
      final n = normalize(b);
      for (final v in _vendorPrefixes) {
        if (n.startsWith('$v ')) {
          final rest = n.substring(v.length + 1).trim();
          if (rest.length >= 2 && !_genericNames.contains(rest)) out.add(rest);
        }
      }
    }
    return out.toList();
  }

  /// Canonical keys for all of a skill's names (for comparing user answers and skills lists).
  static Set<String> nameKeys(String term) => names(term).map(canonical).toSet();

  static List<String>? _strictForms(String term) => _ambiguous[canonical(term)] ?? _ambiguous[normalize(term)];

  /// Strict match in free text: full names only (no vendor-less forms, no AI aliases);
  /// ambiguous names need a disambiguated form.
  static bool mentionsStrict(String textNormalized, String term) {
    for (final n in fullNames(term)) {
      final strict = _strictForms(n);
      final forms = strict ?? variants(n);
      if (forms.any((v) => containsTerm(textNormalized, v))) return true;
    }
    return false;
  }

  /// Does the profile prove this skill? (skill check-in, skills list, Truth Guard)
  /// For many checks against one profile, build a [ProfileEvidence] once instead.
  static bool hasEvidence(MasterProfile p, String skill) => ProfileEvidence(p).has(skill);

  static bool profileHas(MasterProfile profile, Requirement r) => hasEvidence(profile, r.skill);

  /// Surface forms that count as the generated text *claiming* a requirement. Deliberately broad:
  /// every name (incl. vendor-less "kafka"), built-in synonyms, and the AI's aliases, except an alias
  /// that is a separate skill the user really has (e.g. "Node.js" listed as an alias of "AWS Lambda").
  static Set<String> claimForms(Requirement r, MasterProfile profile, {ProfileEvidence? evidence}) {
    final ev = evidence ?? ProfileEvidence(profile);
    return {
      for (final n in names(r.skill)) ...variants(n),
      for (final a in r.aliases)
        if (a.trim().length >= 2 && !ev.has(a)) ...[for (final n in names(a)) ...variants(n)],
    };
  }

  /// Does normalized [textNormalized] claim the requirement [r]?
  static bool claims(String textNormalized, Requirement r, MasterProfile profile, {ProfileEvidence? evidence}) =>
      claimForms(r, profile, evidence: evidence).any((v) => containsTerm(textNormalized, v));

  /// JD requirements the generated [text] claims but the profile can't back up.
  static List<String> unsupportedClaims(String text, MasterProfile profile, List<Requirement> reqs) {
    final t = normalize(text);
    final ev = ProfileEvidence(profile);
    return [
      for (final r in reqs)
        if (claims(t, r, profile, evidence: ev) && !ev.has(r.skill)) r.skill,
    ];
  }

  /// Is [skill] covered by a CV? Counts the CV's skills list exactly and its text strictly.
  static bool covers(String cvTextNormalized, String skill, {List<String> skills = const []}) =>
      nameKeys(skill).intersection(skills.expand(nameKeys).toSet()).isNotEmpty || mentionsStrict(cvTextNormalized, skill);

  // ---------------------------------------------------------------- ATS score

  /// ATS-style keyword coverage score (0-100). MUST requirements count double.
  /// Pass the CV's [skills] list so listed skills count even when their name is ambiguous (e.g. "Go").
  static double atsScore(String cvText, List<Requirement> reqs, {List<String> keywords = const [], List<String> skills = const []}) {
    if (reqs.isEmpty) return 0;
    final text = normalize(cvText);
    var total = 0.0, hit = 0.0;
    for (final r in reqs) {
      final w = r.importance == Importance.must ? 2.0 : 1.0;
      total += w;
      if (covers(text, r.skill, skills: skills)) hit += w;
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

  // ---------------------------------------------------------------- numbers

  // Whole number tokens only: "8" is NOT found inside "98765", and digits glued to letters
  // ("ROS2", "EC2", "Web3") are part of a name, not a metric.
  static final _numberToken = RegExp(r'(?<![A-Za-z0-9.,])\d+(?:[.,]\d+)*(?:\s?%|[kKmM](?![A-Za-z]))?');

  // Number words are checked too, so "ten years" can't slip past where "10 years" wouldn't.
  // "one" is left out: it is far more often a pronoun ("one of the…") than a metric.
  static const Map<String, String> _numberWords = {
    'two': '2', 'three': '3', 'four': '4', 'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
    'ten': '10', 'eleven': '11', 'twelve': '12', 'thirteen': '13', 'fourteen': '14', 'fifteen': '15',
    'sixteen': '16', 'seventeen': '17', 'eighteen': '18', 'nineteen': '19', 'twenty': '20', 'thirty': '30',
    'forty': '40', 'fifty': '50', 'sixty': '60', 'seventy': '70', 'eighty': '80', 'ninety': '90',
    'hundred': '100', 'thousand': '1000', 'million': '1000000', 'billion': '1000000000', 'dozen': '12',
  };
  static final _numberWord = RegExp('\\b(${_numberWords.keys.join('|')})\\b', caseSensitive: false);

  /// Canonical value: "1,000" == "1000", "25 %" == "25%", "10K" == "10000", "2M" == "2000000".
  static String _numberValue(String surface) {
    var s = surface.replaceAll(' ', '').replaceAll(',', '').toLowerCase();
    var mult = 1.0;
    if (s.endsWith('k')) {
      mult = 1e3;
      s = s.substring(0, s.length - 1);
    } else if (s.endsWith('m')) {
      mult = 1e6;
      s = s.substring(0, s.length - 1);
    }
    final pct = s.endsWith('%');
    if (pct) s = s.substring(0, s.length - 1);
    final v = double.tryParse(s);
    if (v == null) return s;
    final n = v * mult;
    final txt = n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
    return pct ? '$txt%' : txt;
  }

  /// Strips digits that are identifiers, not achievements: phone numbers (+91 98765 43210, 10-digit
  /// mobiles) and the month part of dates (2021-03, 03/2021), so "3 cities" can't borrow a month.
  static String _numberEvidence(String truth) => truth
      .replaceAll(RegExp(r'\+\d[\d\s().-]{7,}\d'), ' ')
      .replaceAll(RegExp(r'(?<!\d)\d{10}(?!\d)'), ' ')
      .replaceAllMapped(RegExp(r'(?<!\d)((?:19|20)\d{2})[/.-]\d{1,2}(?!\d)'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'(?<!\d)\d{1,2}[/.-]((?:19|20)\d{2})(?!\d)'), (m) => m.group(1)!);

  static List<({String surface, String value})> _numbers(String text) => [
        for (final m in _numberToken.allMatches(text)) (surface: m.group(0)!, value: _numberValue(m.group(0)!)),
        for (final m in _numberWord.allMatches(text)) (surface: m.group(0)!, value: _numberWords[m.group(0)!.toLowerCase()]!),
      ];

  /// Numbers in [text] that the candidate never wrote (as whole tokens) in [truth].
  /// A percentage is backed by the same percentage or the bare number, and vice versa.
  static List<String> unsupportedNumbers(String text, String truth) {
    final known = <String>{};
    for (final n in _numbers(_numberEvidence(truth))) {
      known.add(n.value);
      known.add(n.value.replaceAll('%', ''));
    }
    final out = <String>[];
    for (final n in _numbers(text)) {
      final ok = known.contains(n.value) || known.contains(n.value.replaceAll('%', ''));
      if (!ok && !out.contains(n.surface)) out.add(n.surface);
    }
    return out;
  }
}

/// What one profile proves, computed once: its structured skill keys and its normalised free text.
/// Build one per check-in or guard run; the profile must not change while it's in use.
class ProfileEvidence {
  ProfileEvidence(MasterProfile p)
      : _skills = TextMatch._statedSkills(p),
        _text = TextMatch._statedText(p);

  final Set<String> _skills;
  final String _text;
  final _memo = <String, bool>{};

  /// Structured lists match on any name (incl. vendor-less); free text only on full names.
  bool has(String skill) => _memo.putIfAbsent(
        skill,
        () => TextMatch.nameKeys(skill).intersection(_skills).isNotEmpty || TextMatch.mentionsStrict(_text, skill),
      );
}
