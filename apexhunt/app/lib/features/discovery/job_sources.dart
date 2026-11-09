import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/gateway.dart';
import '../../core/models.dart';
import '../../core/storage.dart';

/// Official/public job APIs. Every listing links back to its source as their terms require.
abstract class JobSource {
  String get name;
  Future<List<Opportunity>> search(String query, MissionConfig config);
}

final _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 30),
  headers: {'User-Agent': 'ApexHuntAI/1.0 (+job discovery; links back to source)'},
));

String _clean(String? html) => (html ?? '')
    .replaceAll(RegExp(r'<(br|/p|/li|/h\d)[^>]*>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
    .trim();

/// #14 stopgap until discovery moves behind the gateway: keeps each phone inside the free job APIs'
/// published limits by caching each response on the device and reusing it until it expires.
/// A failed refresh falls back to the last good copy.
class FeedCache {
  FeedCache([this._store, DateTime Function()? now]) : _now = now ?? DateTime.now;
  final LocalStore? _store;
  final DateTime Function() _now;
  final _memory = <String, (DateTime, List<Map>)>{};

  /// Remotive asks for "max. 4 times a day" and blocks more than 2 requests a minute.
  static const remotiveTtl = Duration(hours: 6);

  /// Jobicy: "Do not schedule automated polling more frequently than once per hour" (their API README).
  static const jobicyTtl = Duration(hours: 1);

  /// If a refresh fails, an older copy is shown only while it's younger than this, so very old
  /// listings never look fresh after a long outage.
  static const maxStale = Duration(days: 3);

  /// FNV-1a 64-bit: a stable file name for any key, including non-ASCII text.
  static String _hash(String key) {
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final b in utf8.encode(key)) {
      h = ((h ^ BigInt.from(b)) * prime) & mask;
    }
    return h.toRadixString(16).padLeft(16, '0');
  }

  Future<List<Map>> get(String key, Duration ttl, Future<List<Map>> Function() fetch) async {
    final file = 'feeds/${_hash(key)}.json';
    var hit = _memory[key];
    if (hit == null && _store != null) {
      final j = await _store.readJson(file);
      final at = j is Map ? DateTime.tryParse('${j['at']}') : null;
      if (at != null && j is Map && j['items'] is List) hit = (at, (j['items'] as List).whereType<Map>().toList());
    }
    if (hit != null && _now().difference(hit.$1) < ttl) return hit.$2;
    try {
      final items = await fetch();
      final at = _now();
      _memory[key] = (at, items);
      await _store?.writeJson(file, {'at': at.toIso8601String(), 'items': items});
      return items;
    } catch (_) {
      if (hit != null && _now().difference(hit.$1) < maxStale) return hit.$2;
      rethrow;
    }
  }
}

/// Does a listing's title, tags or category mention any word of [query]? (Feeds searched on the phone.)
bool _mentions(String query, Iterable<Object?> fields) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
  if (words.isEmpty) return true;
  final hay = fields.map((f) => f is List ? f.join(' ') : '${f ?? ''}').join(' ').toLowerCase();
  return words.any(hay.contains);
}

String _id(String source, Object? ext) => '$source:${ext ?? DateTime.now().microsecondsSinceEpoch}';

dynamic _json(dynamic data) => data is String ? jsonDecode(data) : data;

String _commitment(String raw) {
  final t = raw.toLowerCase();
  if (t.contains('part')) return 'PART_TIME';
  if (t.contains('contract') || t.contains('freelance')) return 'CONTRACT';
  if (t.contains('intern')) return 'INTERNSHIP';
  if (t.contains('full')) return 'FULL_TIME';
  return '';
}

/// Remotive's free feed is small (it returned 12 jobs in total, whatever the search, in Nov 2026), so it's
/// fetched whole at most every 6 hours and searched on the phone: one request per mission at most.
class RemotiveSource implements JobSource {
  RemotiveSource([FeedCache? cache, this._fetch]) : _cache = cache ?? FeedCache();
  final FeedCache _cache;
  final Future<List<Map>> Function()? _fetch;

  @override
  String get name => 'Remotive';

  static Future<List<Map>> _download() async {
    final r = await _dio.get('https://remotive.com/api/remote-jobs');
    return (_json(r.data)['jobs'] as List? ?? []).whereType<Map>().toList();
  }

  @override
  Future<List<Opportunity>> search(String query, MissionConfig config) async {
    final jobs = (await _cache.get('remotive', FeedCache.remotiveTtl, _fetch ?? _download)).where((j) => _mentions(query, [j['title'], j['tags'], j['category']]));
    return jobs
        .map((j) => Opportunity(
              id: _id(name, j['id']),
              source: name,
              title: '${j['title'] ?? ''}',
              company: '${j['company_name'] ?? ''}',
              location: '${j['candidate_required_location'] ?? 'Remote'}',
              url: '${j['url'] ?? ''}',
              description: _clean('${j['description'] ?? ''}'),
              salary: '${j['salary'] ?? ''}',
              postedAt: '${j['publication_date'] ?? ''}',
              remote: true,
              employmentType: _commitment('${j['job_type'] ?? ''}'),
            ))
        .toList();
  }
}

/// Jobicy asks for no more than one automated poll an hour, so each region's newest 100 jobs are fetched
/// at most hourly with no keyword and searched on the phone: at most 3 requests an hour, however many
/// keywords a mission has.
class JobicySource implements JobSource {
  JobicySource([FeedCache? cache, this._fetch]) : _cache = cache ?? FeedCache();
  final FeedCache _cache;
  final Future<List<Map>> Function(String? geo)? _fetch;

  static Future<List<Map>> _download(String? geo) async {
    final r = await _dio.get('https://jobicy.com/api/v2/remote-jobs', queryParameters: {'count': 100, 'geo': ?geo});
    return (_json(r.data)['jobs'] as List? ?? []).whereType<Map>().toList();
  }

  @override
  String get name => 'Jobicy';
  static const _geo = {'US': 'usa', 'GB': 'uk', 'DE': 'germany', 'CA': 'canada', 'AU': 'australia', 'IN': 'apac', 'AE': 'emea', 'FR': 'france', 'NL': 'netherlands', 'ES': 'spain'};

  @override
  Future<List<Opportunity>> search(String query, MissionConfig config) async {
    final geos = config.countries.map((c) => _geo[c]).whereType<String>().toSet();
    final results = <Opportunity>[];
    for (final String? geo in geos.isEmpty ? <String?>[null] : geos.take(3)) {
      final feed = await _cache.get('jobicy_${geo ?? 'all'}', FeedCache.jobicyTtl, () => (_fetch ?? _download)(geo));
      for (final j in feed.where((j) => _mentions(query, [j['jobTitle'], j['jobIndustry'], j['jobExcerpt']]))) {
        final type = j['jobType'] is List ? (j['jobType'] as List).join(' ') : '${j['jobType'] ?? ''}';
        final sal = j['salaryMin'] != null ? '${j['salaryMin']}–${j['salaryMax'] ?? ''} ${j['salaryCurrency'] ?? ''}'.trim() : '';
        results.add(Opportunity(
          id: _id(name, j['id']),
          source: name,
          title: _clean('${j['jobTitle'] ?? ''}'),
          company: '${j['companyName'] ?? ''}',
          location: '${j['jobGeo'] ?? 'Remote'}',
          url: '${j['url'] ?? ''}',
          description: _clean('${j['jobDescription'] ?? j['jobExcerpt'] ?? ''}'),
          salary: sal,
          postedAt: '${j['pubDate'] ?? ''}',
          remote: true,
          employmentType: _commitment(type),
        ));
      }
    }
    return results;
  }
}

class RemoteOkSource implements JobSource {
  @override
  String get name => 'Remote OK';
  @override
  Future<List<Opportunity>> search(String query, MissionConfig config) async {
    final tag = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
    final r = await _dio.get('https://remoteok.com/api', queryParameters: {'tag': tag});
    final list = (_json(r.data) as List? ?? []).whereType<Map>().where((j) => j['id'] != null);
    return list.map((j) {
      final sal = (j['salary_min'] is num && (j['salary_min'] as num) > 0) ? '\$${j['salary_min']}–\$${j['salary_max']}' : '';
      return Opportunity(
        id: _id(name, j['id']),
        source: name,
        title: '${j['position'] ?? ''}',
        company: '${j['company'] ?? ''}',
        location: '${(j['location'] ?? '').toString().isEmpty ? 'Remote' : j['location']}',
        url: '${j['url'] ?? ''}',
        description: _clean('${j['description'] ?? ''}'),
        salary: sal,
        postedAt: '${j['date'] ?? ''}',
        remote: true,
        employmentType: 'FULL_TIME',
      );
    }).toList();
  }
}

class ArbeitnowSource implements JobSource {
  @override
  String get name => 'Arbeitnow';
  @override
  Future<List<Opportunity>> search(String query, MissionConfig config) async {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    final out = <Opportunity>[];
    for (var page = 1; page <= 2; page++) {
      final r = await _dio.get('https://www.arbeitnow.com/api/job-board-api', queryParameters: {'page': page});
      for (final j in (_json(r.data)['data'] as List? ?? []).whereType<Map>()) {
        final hay = '${j['title']} ${(j['tags'] as List?)?.join(' ')}'.toLowerCase();
        if (words.isNotEmpty && !words.any(hay.contains)) continue;
        out.add(Opportunity(
          id: _id(name, j['slug']),
          source: name,
          title: '${j['title'] ?? ''}',
          company: '${j['company_name'] ?? ''}',
          location: '${j['location'] ?? ''}',
          country: 'DE',
          url: '${j['url'] ?? ''}',
          description: _clean('${j['description'] ?? ''}'),
          postedAt: j['created_at'] is num ? DateTime.fromMillisecondsSinceEpoch((j['created_at'] as num).toInt() * 1000).toIso8601String() : '',
          remote: j['remote'] == true,
          employmentType: _commitment((j['job_types'] as List?)?.join(' ') ?? ''),
        ));
      }
    }
    return out;
  }
}

/// Company career boards (Greenhouse / Lever) the user chooses to watch, e.g. "greenhouse:stripe".
class CompanyBoardsSource implements JobSource {
  @override
  String get name => 'Company boards';
  @override
  Future<List<Opportunity>> search(String query, MissionConfig config) async {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    final out = <Opportunity>[];
    for (final raw in config.watchedCompanies.take(15)) {
      final parts = raw.split(':');
      final kind = parts.length > 1 ? parts.first.toLowerCase() : 'greenhouse';
      final slug = parts.last.trim().toLowerCase();
      try {
        if (kind == 'lever') {
          final r = await _dio.get('https://api.lever.co/v0/postings/$slug', queryParameters: {'mode': 'json'});
          for (final j in (_json(r.data) as List? ?? []).whereType<Map>()) {
            final title = '${j['text'] ?? ''}';
            if (words.isNotEmpty && !words.any(title.toLowerCase().contains)) continue;
            final cats = j['categories'] as Map? ?? {};
            out.add(Opportunity(
              id: _id('Lever', j['id']),
              source: 'Lever · $slug',
              title: title,
              company: slug,
              location: '${cats['location'] ?? ''}',
              url: '${j['hostedUrl'] ?? ''}',
              description: '${j['descriptionPlain'] ?? ''}\n${(j['lists'] as List? ?? []).whereType<Map>().map((l) => '${l['text']}\n${_clean('${l['content']}')}').join('\n')}'.trim(),
              remote: '${cats['location']} ${j['workplaceType']}'.toLowerCase().contains('remote'),
              employmentType: _commitment('${cats['commitment'] ?? ''}'),
            ));
          }
        } else {
          final r = await _dio.get('https://boards-api.greenhouse.io/v1/boards/$slug/jobs', queryParameters: {'content': 'true'});
          for (final j in (_json(r.data)['jobs'] as List? ?? []).whereType<Map>()) {
            final title = '${j['title'] ?? ''}';
            if (words.isNotEmpty && !words.any(title.toLowerCase().contains)) continue;
            final loc = '${(j['location'] as Map?)?['name'] ?? ''}';
            out.add(Opportunity(
              id: _id('Greenhouse', j['id']),
              source: 'Greenhouse · $slug',
              title: title,
              company: slug,
              location: loc,
              url: '${j['absolute_url'] ?? ''}',
              description: _clean(_clean('${j['content'] ?? ''}')),
              postedAt: '${j['updated_at'] ?? ''}',
              remote: loc.toLowerCase().contains('remote'),
            ));
          }
        }
      } catch (_) {
        // A misspelled board shouldn't break the whole mission.
      }
    }
    return out;
  }
}

/// Freelancer.com public active-projects API (freelance mode).
class FreelancerSource implements JobSource {
  @override
  String get name => 'Freelancer.com';
  @override
  Future<List<Opportunity>> search(String query, MissionConfig config) async {
    final r = await _dio.get('https://www.freelancer.com/api/projects/0.1/projects/active/', queryParameters: {
      'query': query,
      'limit': 30,
      'full_description': 'true',
      'job_details': 'true',
      'sort_field': 'time_updated',
    });
    final projects = ((_json(r.data)['result'] as Map?)?['projects'] as List? ?? []).whereType<Map>();
    return projects.map((p) {
      final budget = p['budget'] as Map? ?? {};
      final cur = (p['currency'] as Map?)?['code'] ?? 'USD';
      final type = p['type'] == 'hourly' ? 'HOURLY' : 'FIXED_PRICE';
      final skills = (p['jobs'] as List? ?? []).whereType<Map>().map((j) => j['name']).join(', ');
      return Opportunity(
        id: _id(name, p['id']),
        source: name,
        title: '${p['title'] ?? ''}',
        company: 'Freelancer.com client',
        location: 'Remote',
        url: 'https://www.freelancer.com/projects/${p['seo_url'] ?? p['id']}',
        description: '${p['description'] ?? p['preview_description'] ?? ''}${skills.isEmpty ? '' : '\n\nSkills: $skills'}',
        salary: budget['minimum'] != null ? '$cur ${budget['minimum']}–${budget['maximum'] ?? ''}${type == 'HOURLY' ? '/hr' : ''}' : '',
        postedAt: p['time_submitted'] is num ? DateTime.fromMillisecondsSinceEpoch((p['time_submitted'] as num).toInt() * 1000).toIso8601String() : '',
        remote: true,
        employmentType: type,
        kind: MissionMode.freelance,
      );
    }).toList();
  }
}

/// Adzuna + Jooble via the gateway (keys stay server-side). Needs sign-in.
class GatewaySource implements JobSource {
  GatewaySource(this.api);
  final GatewayApi api;
  @override
  String get name => 'Adzuna & Jooble';
  @override
  Future<List<Opportunity>> search(String query, MissionConfig config) async {
    final countries = config.countries.where((c) => c != 'REMOTE').toList();
    return api.searchJobs(query, countries.isEmpty ? ['US'] : countries);
  }
}

// ---------------------------------------------------------------------------- country filtering

const countryNames = {
  'REMOTE': 'Worldwide Remote', 'US': 'USA', 'GB': 'UK', 'AE': 'UAE', 'DE': 'Germany', 'IN': 'India', 'CA': 'Canada',
  'AU': 'Australia', 'SG': 'Singapore', 'NL': 'Netherlands', 'FR': 'France', 'SA': 'Saudi Arabia', 'QA': 'Qatar',
  'IE': 'Ireland', 'NZ': 'New Zealand', 'ZA': 'South Africa', 'ES': 'Spain', 'PL': 'Poland', 'CH': 'Switzerland',
  'BR': 'Brazil', 'MX': 'Mexico', 'JP': 'Japan', 'MY': 'Malaysia', 'PH': 'Philippines', 'PK': 'Pakistan',
  'BD': 'Bangladesh', 'NG': 'Nigeria', 'KE': 'Kenya', 'EG': 'Egypt', 'IT': 'Italy', 'AT': 'Austria', 'BE': 'Belgium',
};

const countryFlags = {
  'REMOTE': '🌐', 'US': '🇺🇸', 'GB': '🇬🇧', 'AE': '🇦🇪', 'DE': '🇩🇪', 'IN': '🇮🇳', 'CA': '🇨🇦', 'AU': '🇦🇺', 'SG': '🇸🇬',
  'NL': '🇳🇱', 'FR': '🇫🇷', 'SA': '🇸🇦', 'QA': '🇶🇦', 'IE': '🇮🇪', 'NZ': '🇳🇿', 'ZA': '🇿🇦', 'ES': '🇪🇸', 'PL': '🇵🇱',
  'CH': '🇨🇭', 'BR': '🇧🇷', 'MX': '🇲🇽', 'JP': '🇯🇵', 'MY': '🇲🇾', 'PH': '🇵🇭', 'PK': '🇵🇰', 'BD': '🇧🇩', 'NG': '🇳🇬',
  'KE': '🇰🇪', 'EG': '🇪🇬', 'IT': '🇮🇹', 'AT': '🇦🇹', 'BE': '🇧🇪',
};

/// Whole-word terms that place a listing in a country: names, short forms and big cities that are
/// unambiguous. Never two-letter codes: in free text "IN", "CA", "DE", "SA" are US states or Australian
/// states, and "in", "at", "be" are ordinary words (#13). Countries not listed here match on their name.
const _countryTerms = <String, List<String>>{
  'US': [
    'united states',
    'united states of america',
    'usa',
    'u.s.',
    'u.s.a.',
    'us only',
    'us based',
    'in the us',
    'within the us',
    'us time zone',
    'us time zones',
    'us timezone',
    'us timezones',
    'us residents',
    'us citizens',
  ],
  'GB': ['united kingdom', 'uk', 'u.k.', 'great britain', 'britain', 'england', 'scotland', 'wales', 'northern ireland', 'london', 'manchester', 'edinburgh'],
  'AE': ['united arab emirates', 'uae', 'u.a.e.', 'emirates', 'dubai', 'abu dhabi', 'sharjah'],
  'DE': ['germany', 'deutschland', 'berlin', 'munich', 'münchen', 'hamburg', 'frankfurt'],
  'IN': ['india', 'bengaluru', 'bangalore', 'mumbai', 'delhi', 'new delhi', 'hyderabad', 'pune', 'chennai', 'gurugram', 'gurgaon', 'noida', 'kolkata'],
  'CA': ['canada', 'toronto', 'montreal', 'montréal', 'ottawa', 'calgary'],
  'AU': ['australia', 'sydney', 'brisbane', 'canberra'],
  'SA': ['saudi arabia', 'ksa', 'riyadh', 'jeddah'],
  'NL': ['netherlands', 'amsterdam', 'rotterdam'],
  'SG': ['singapore'],
};

/// Places elsewhere whose names contain a country term ("New South Wales" is in Australia, not Wales).
const _notCountry = <String, List<String>>{
  'GB': ['new south wales', 'new england'],
  'MX': ['new mexico'],
  'IE': ['northern ireland'],
};

const _regions = {
  'europe': ['GB', 'DE', 'NL', 'FR', 'IE', 'ES', 'PL', 'CH', 'IT', 'AT', 'BE'],
  'eu': ['DE', 'NL', 'FR', 'IE', 'ES', 'PL', 'IT', 'AT', 'BE'],
  'european union': ['DE', 'NL', 'FR', 'IE', 'ES', 'PL', 'IT', 'AT', 'BE'],
  'emea': ['GB', 'DE', 'NL', 'FR', 'IE', 'ES', 'PL', 'CH', 'IT', 'AT', 'BE', 'AE', 'SA', 'QA', 'ZA', 'NG', 'KE', 'EG'],
  'middle east': ['AE', 'SA', 'QA'],
  'gcc': ['AE', 'SA', 'QA'],
  'apac': ['IN', 'AU', 'SG', 'NZ', 'JP', 'MY', 'PH', 'PK', 'BD'],
  'asia': ['IN', 'SG', 'JP', 'MY', 'PH', 'PK', 'BD'],
  'americas': ['US', 'CA', 'BR', 'MX'],
  'north america': ['US', 'CA'],
  'latam': ['BR', 'MX'],
  'latin america': ['BR', 'MX'],
  'africa': ['ZA', 'NG', 'KE', 'EG'],
};

bool _hasWord(String text, String term) => RegExp('(?<![a-z0-9])${RegExp.escape(term)}(?![a-z0-9])').hasMatch(text);

String _normalizeLocation(String s) => s.toLowerCase().replaceAll(RegExp(r'[-_/|(),;:]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Countries a free-text location names, directly or through a region ("Remote, Europe").
Set<String> countriesIn(String location) {
  final loc = _normalizeLocation(location);
  if (loc.isEmpty) return {};
  final out = <String>{};
  for (final code in {...countryNames.keys, ..._countryTerms.keys}) {
    if (code == 'REMOTE') continue;
    var text = loc;
    for (final x in _notCountry[code] ?? const <String>[]) {
      text = text.replaceAll(x, ' ');
    }
    final terms = _countryTerms[code] ?? [(countryNames[code] ?? '').toLowerCase()];
    if (terms.any((t) => t.isNotEmpty && _hasWord(text, t))) out.add(code);
  }
  // An uppercase "US" ("Remote - US", "US") is the country; lowercase "us" is usually the pronoun.
  if (RegExp(r'(?<![A-Za-z])US(?![A-Za-z])').hasMatch(location)) out.add('US');
  for (final e in _regions.entries) {
    if (_hasWord(loc, e.key)) out.addAll(e.value);
  }
  return out;
}

/// Whether a listing is open to a candidate targeting [countries].
bool matchesCountries(Opportunity o, List<String> countries) {
  if (countries.isEmpty || o.kind == MissionMode.freelance) return true;
  final code = o.country.trim().toUpperCase();
  if (code.isNotEmpty && countries.contains(code)) return true;
  final named = countriesIn(o.location);
  final loc = _normalizeLocation(o.location);
  // "Anywhere in the US" names a country, so it is not worldwide.
  final worldwide =
      named.isEmpty && code.isEmpty && (loc.isEmpty || loc == 'remote' || const ['worldwide', 'anywhere', 'global', 'globally'].any((w) => _hasWord(loc, w)));
  if (o.remote && worldwide) return true;
  return countries.any((c) => c != 'REMOTE' && named.contains(c));
}

bool matchesCommitment(Opportunity o, List<String> commitments) {
  if (commitments.isEmpty || o.employmentType.isEmpty) return true;
  if (o.kind == MissionMode.freelance) {
    return commitments.contains(o.employmentType) || !commitments.any((c) => c == 'HOURLY' || c == 'FIXED_PRICE');
  }
  return commitments.contains(o.employmentType);
}
