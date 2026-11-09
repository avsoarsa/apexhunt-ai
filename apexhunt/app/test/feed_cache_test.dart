import 'package:apexhunt_ai/core/models.dart';
import 'package:apexhunt_ai/core/storage.dart';
import 'package:apexhunt_ai/features/discovery/job_sources.dart';
import 'package:flutter_test/flutter_test.dart';

/// #14 stopgap: each phone stays inside Remotive's limits (about 4 fetches a day, 2 a minute).
void main() {
  test('a feed is reused until it expires, then refreshed', () async {
    var now = DateTime(2026, 11, 10, 9);
    var calls = 0;
    final cache = FeedCache(LocalStore.memory(), () => now);
    Future<List<Map>> fetch() async => [
          {'n': ++calls},
        ];

    expect((await cache.get('remotive', FeedCache.remotiveTtl, fetch)).single['n'], 1);
    now = now.add(const Duration(hours: 5, minutes: 59));
    expect((await cache.get('remotive', FeedCache.remotiveTtl, fetch)).single['n'], 1, reason: 'still fresh');
    now = now.add(const Duration(minutes: 2));
    expect((await cache.get('remotive', FeedCache.remotiveTtl, fetch)).single['n'], 2, reason: 'expired after 6 hours');
    expect(calls, 2);
  });

  test('the cache survives an app restart through the local store', () async {
    final store = LocalStore.memory();
    final now = DateTime(2026, 11, 10, 9);
    var calls = 0;
    Future<List<Map>> fetch() async {
      calls++;
      return [
        {'title': 'Flutter Developer'},
      ];
    }

    await FeedCache(store, () => now).get('remotive', FeedCache.remotiveTtl, fetch);
    await FeedCache(store, () => now.add(const Duration(hours: 1))).get('remotive', FeedCache.remotiveTtl, fetch);
    expect(calls, 1, reason: 'a new FeedCache (app restart) reads the saved copy instead of calling again');
  });

  test('a failed refresh falls back to the last good copy', () async {
    var now = DateTime(2026, 11, 10, 9);
    final cache = FeedCache(LocalStore.memory(), () => now);
    await cache.get('remotive', FeedCache.remotiveTtl, () async => [
          {'title': 'Old'},
        ]);
    now = now.add(const Duration(hours: 7));
    final r = await cache.get('remotive', FeedCache.remotiveTtl, () async => throw Exception('429'));
    expect(r.single['title'], 'Old');
  });

  test('Remotive is downloaded once per mission, however many keywords', () async {
    var calls = 0;
    final source = RemotiveSource(FeedCache(LocalStore.memory()), () async {
      calls++;
      return [
        {'id': 1, 'title': 'Senior Flutter Developer', 'tags': ['dart'], 'category': 'Software Development', 'candidate_required_location': 'Worldwide'},
        {'id': 2, 'title': 'Customer Support Lead', 'tags': ['zendesk'], 'category': 'Customer Service', 'candidate_required_location': 'USA'},
      ];
    });
    final cfg = MissionConfig();
    final flutter = await source.search('Flutter Developer', cfg);
    final support = await source.search('Support Lead', cfg);
    await source.search('Dart', cfg);
    await source.search('Zendesk', cfg);
    expect(calls, 1);
    expect(flutter.map((o) => o.title), ['Senior Flutter Developer']);
    expect(support.map((o) => o.title), ['Customer Support Lead']);
    expect(flutter.single.source, 'Remotive', reason: 'attribution kept');
  });

  test('an uppercase "US" in the location is the US (B, review of #27)', () {
    Opportunity o(String loc) => Opportunity(id: '1', source: 's', title: 't', location: loc, remote: false);
    for (final loc in ['Remote - US', 'US', 'Remote (US)', 'USA', 'US Only', 'United States']) {
      expect(matchesCountries(o(loc), ['US']), isTrue, reason: loc);
    }
    expect(matchesCountries(o('Remote - US'), ['IN']), isFalse);
    expect(matchesCountries(o('Join us in Berlin'), ['US']), isFalse, reason: 'lowercase "us" is the pronoun');
  });
}
