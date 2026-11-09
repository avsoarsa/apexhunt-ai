import 'package:apexhunt_ai/core/models.dart';
import 'package:apexhunt_ai/features/discovery/job_sources.dart';
import 'package:flutter_test/flutter_test.dart';

/// #13: two-letter codes and short words in free-text locations must not pick the wrong country.
Opportunity _o(String loc, {bool remote = true, String country = ''}) =>
    Opportunity(id: '1', source: 's', title: 't', location: loc, remote: remote, country: country);

void main() {
  test("B's table from #13: none of these match", () {
    final cases = {
      'Indianapolis, IN': 'IN',
      'Remote in US time zones': 'IN',
      'San Francisco, CA': 'CA',
      'Wilmington, DE': 'DE',
      'Adelaide, SA': 'SA',
      'Remote at a US company': 'AT',
      'Remote, must be based in the US': 'BE',
      'Ukraine (remote)': 'GB',
      'Milwaukee, WI': 'GB',
    };
    cases.forEach((loc, code) => expect(matchesCountries(_o(loc, remote: false), [code]), isFalse, reason: '$loc for $code'));
  });

  test('real locations still match', () {
    final cases = {
      'Bengaluru, India': 'IN',
      'Bangalore': 'IN',
      'Remote - India': 'IN',
      'London, UK': 'GB',
      'Manchester, United Kingdom': 'GB',
      'Belfast, Northern Ireland': 'GB',
      'Berlin, Germany': 'DE',
      'Toronto, ON, Canada': 'CA',
      'Dubai': 'AE',
      'Riyadh, KSA': 'SA',
      'Sydney, NSW, Australia': 'AU',
      'Remote (EU only)': 'DE',
      'San Francisco, CA, USA': 'US',
      'Anywhere in the U.S.': 'US',
      'Remote in US time zones': 'US',
    };
    cases.forEach((loc, code) => expect(matchesCountries(_o(loc, remote: false), [code]), isTrue, reason: '$loc for $code'));
  });

  test('look-alike places are not the country', () {
    expect(matchesCountries(_o('Newcastle, New South Wales', remote: false), ['GB']), isFalse);
    expect(matchesCountries(_o('Boston, New England', remote: false), ['GB']), isFalse);
    expect(matchesCountries(_o('Santa Fe, New Mexico', remote: false), ['MX']), isFalse);
    expect(matchesCountries(_o('Belfast, Northern Ireland', remote: false), ['IE']), isFalse);
  });

  test('worldwide remote is open to every country, but "anywhere in the US" is not', () {
    expect(matchesCountries(_o('Worldwide'), ['IN']), isTrue);
    expect(matchesCountries(_o('Remote'), ['REMOTE']), isTrue);
    expect(matchesCountries(_o('Anywhere'), ['DE']), isTrue);
    expect(matchesCountries(_o('Anywhere in the US'), ['IN']), isFalse);
    expect(matchesCountries(_o('Anywhere in the US'), ['REMOTE']), isFalse);
  });

  test("a source's own country code wins, and pins remote listings to that country", () {
    expect(matchesCountries(_o('Remote', country: 'DE'), ['DE']), isTrue);
    expect(matchesCountries(_o('Remote', country: 'DE'), ['IN']), isFalse, reason: 'Arbeitnow remote = remote within Germany');
  });

  test('freelance and empty selections are not filtered', () {
    expect(matchesCountries(Opportunity(id: '1', source: 's', title: 't', location: 'Indianapolis, IN', kind: MissionMode.freelance), ['IN']), isTrue);
    expect(matchesCountries(_o('Indianapolis, IN'), []), isTrue);
  });
}
