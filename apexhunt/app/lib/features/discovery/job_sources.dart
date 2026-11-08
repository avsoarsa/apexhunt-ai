import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/gateway.dart';
import '../../core/models.dart';

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

class RemotiveSource implements JobSource {
  @override
  String get name => 'Remotive';
  @override
  Future<List<Opportunity>> search(String query, MissionConfig config) async {
    final r = await _dio.get('https://remotive.com/api/remote-jobs', queryParameters: {'search': query, 'limit': 40});
    final jobs = (_json(r.data)['jobs'] as List? ?? []).whereType<Map>();
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

class JobicySource implements JobSource {
  @override
  String get name => 'Jobicy';
  static const _geo = {'US': 'usa', 'GB': 'uk', 'DE': 'germany', 'CA': 'canada', 'AU': 'australia', 'IN': 'apac', 'AE': 'emea', 'FR': 'france', 'NL': 'netherlands', 'ES': 'spain'};

  @override
  Future<List<Opportunity>> search(String query, MissionConfig config) async {
    final tag = query.split(' ').first.toLowerCase();
    final geos = config.countries.map((c) => _geo[c]).whereType<String>().toSet();
    final results = <Opportunity>[];
    for (final geo in geos.isEmpty ? <String?>[null] : geos.take(3)) {
      final r = await _dio.get('https://jobicy.com/api/v2/remote-jobs', queryParameters: {'count': 40, 'tag': tag, 'geo': ?geo});
      for (final j in (_json(r.data)['jobs'] as List? ?? []).whereType<Map>()) {
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

const _regions = {
  'europe': ['GB', 'DE', 'NL', 'FR', 'IE', 'ES', 'PL', 'CH', 'IT', 'AT', 'BE'],
  'emea': ['GB', 'DE', 'NL', 'FR', 'IE', 'ES', 'PL', 'CH', 'IT', 'AT', 'BE', 'AE', 'SA', 'QA', 'ZA', 'NG', 'KE', 'EG'],
  'middle east': ['AE', 'SA', 'QA'],
  'apac': ['IN', 'AU', 'SG', 'NZ', 'JP', 'MY', 'PH', 'PK', 'BD'],
  'asia': ['IN', 'SG', 'JP', 'MY', 'PH', 'PK', 'BD'],
  'americas': ['US', 'CA', 'BR', 'MX'],
  'north america': ['US', 'CA'],
  'latam': ['BR', 'MX'],
  'africa': ['ZA', 'NG', 'KE', 'EG'],
};

/// Whether a listing is open to a candidate targeting [countries].
bool matchesCountries(Opportunity o, List<String> countries) {
  if (countries.isEmpty || o.kind == MissionMode.freelance) return true;
  final loc = '${o.location} ${o.country}'.toLowerCase();
  final worldwide = loc.contains('worldwide') || loc.contains('anywhere') || loc.contains('global') || loc.trim() == 'remote' || loc.trim().isEmpty;
  for (final c in countries) {
    if (c == 'REMOTE') {
      if (o.remote && worldwide) return true;
      continue;
    }
    if (o.country.toUpperCase() == c) return true;
    final name = (countryNames[c] ?? c).toLowerCase();
    if (loc.contains(name) || RegExp('\\b${c.toLowerCase()}\\b').hasMatch(loc)) return true;
    if (c == 'US' && (loc.contains('united states') || loc.contains('usa'))) return true;
    if (c == 'GB' && (loc.contains('united kingdom') || loc.contains('uk') || loc.contains('london'))) return true;
    if (c == 'AE' && (loc.contains('dubai') || loc.contains('abu dhabi') || loc.contains('emirates'))) return true;
    if (o.remote && worldwide) return true;
    for (final entry in _regions.entries) {
      if (loc.contains(entry.key) && entry.value.contains(c)) return true;
    }
  }
  return false;
}

bool matchesCommitment(Opportunity o, List<String> commitments) {
  if (commitments.isEmpty || o.employmentType.isEmpty) return true;
  if (o.kind == MissionMode.freelance) {
    return commitments.contains(o.employmentType) || !commitments.any((c) => c == 'HOURLY' || c == 'FIXED_PRICE');
  }
  return commitments.contains(o.employmentType);
}
