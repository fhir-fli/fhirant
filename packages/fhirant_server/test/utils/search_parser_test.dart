import 'package:test/test.dart';
import 'package:fhirant_server/src/utils/search_parser.dart';

void main() {
  group('SearchParameterParser', () {
    test('parses simple search parameters', () {
      final queryParams = {
        'name': 'Smith',
        'gender': 'male',
      };

      final result = SearchParameterParser.parseQueryParameters(queryParams);

      expect(result['searchParams'], isNotNull);
      final searchParams = result['searchParams'] as Map<String, List<String>>;
      expect(searchParams['name'], equals(['Smith']));
      expect(searchParams['gender'], equals(['male']));
      expect(result['count'], isNull);
      expect(result['offset'], isNull);
    });

    test('parses pagination parameters', () {
      final queryParams = {
        '_count': '10',
        '_offset': '20',
      };

      final result = SearchParameterParser.parseQueryParameters(queryParams);

      expect(result['count'], equals(10));
      expect(result['offset'], equals(20));
      expect(result['searchParams'], isNull);
    });

    test('parses sort parameter', () {
      final queryParams = {
        '_sort': 'name,-date',
      };

      final result = SearchParameterParser.parseQueryParameters(queryParams);

      expect(result['sort'], equals(['name', '-date']));
    });

    test('parses comma-separated values (OR logic)', () {
      final queryParams = {
        'name': 'Smith,Jones,Brown',
      };

      final result = SearchParameterParser.parseQueryParameters(queryParams);

      final searchParams = result['searchParams'] as Map<String, List<String>>;
      expect(searchParams['name'], equals(['Smith', 'Jones', 'Brown']));
    });

    test('parses complex query with all parameter types', () {
      final queryParams = {
        'name': 'Smith',
        'gender': 'male,female',
        '_count': '25',
        '_offset': '50',
        '_sort': 'name,-birthDate',
        '_include': 'Patient:organization',
        '_summary': 'data',
      };

      final result = SearchParameterParser.parseQueryParameters(queryParams);

      final searchParams = result['searchParams'] as Map<String, List<String>>;
      expect(searchParams['name'], equals(['Smith']));
      expect(searchParams['gender'], equals(['male', 'female']));
      expect(result['count'], equals(25));
      expect(result['offset'], equals(50));
      expect(result['sort'], equals(['name', '-birthDate']));
      expect(result['include'], equals(['Patient:organization']));
      expect(result['summary'], equals('data'));
    });

    test('parses _include:iterate into separate list', () {
      final queryParams = {
        '_include': 'Patient:managingOrganization',
        '_include:iterate': 'Organization:partOf',
      };

      final result = SearchParameterParser.parseQueryParameters(queryParams);

      expect(result['include'], equals(['Patient:managingOrganization']));
      expect(result['includeIterate'], equals(['Organization:partOf']));
    });

    test('parses _revinclude:iterate into separate list', () {
      final queryParams = {
        '_revinclude': 'Encounter:subject',
        '_revinclude:iterate': 'Observation:encounter',
      };

      final result = SearchParameterParser.parseQueryParameters(queryParams);

      expect(result['revinclude'], equals(['Encounter:subject']));
      expect(result['revincludeIterate'], equals(['Observation:encounter']));
    });

    test('_include:iterate not treated as search parameter', () {
      final queryParams = {
        '_include:iterate': 'Organization:partOf',
      };

      expect(SearchParameterParser.hasSearchParameters(queryParams), isFalse);
    });

    test('hasSearchParameters returns true when search params exist', () {
      final queryParams = {
        'name': 'Smith',
        '_count': '10',
      };

      expect(SearchParameterParser.hasSearchParameters(queryParams), isTrue);
    });

    test('hasSearchParameters returns false when only special params exist', () {
      final queryParams = {
        '_count': '10',
        '_offset': '20',
        '_sort': 'name',
      };

      expect(SearchParameterParser.hasSearchParameters(queryParams), isFalse);
    });

    test('parses _has parameter', () {
      final queryParams = {
        '_has:Observation:patient:code': '1234',
      };

      final result = SearchParameterParser.parseQueryParameters(queryParams);

      expect(result['has'], isNotNull);
      final hasList = result['has'] as List;
      expect(hasList, hasLength(1));
      final hasParam = hasList[0];
      expect(hasParam.targetType, 'Observation');
      expect(hasParam.referenceParam, 'patient');
      expect(hasParam.searchParam, 'code');
      expect(hasParam.value, '1234');
    });

    test('parses multiple _has parameters', () {
      // Note: Dart Map doesn't support duplicate keys, but different _has params
      // have different keys
      final queryParams = {
        '_has:Observation:patient:code': '1234',
        '_has:Condition:patient:code': 'I10',
      };

      final result = SearchParameterParser.parseQueryParameters(queryParams);

      expect(result['has'], isNotNull);
      final hasList = result['has'] as List;
      expect(hasList, hasLength(2));
    });

    test('hasSearchParameters returns true for _has params', () {
      final queryParams = {
        '_has:Observation:patient:code': '1234',
        '_count': '10',
      };

      expect(SearchParameterParser.hasSearchParameters(queryParams), isTrue);
    });

    test('_has combined with regular search params', () {
      final queryParams = {
        '_has:Observation:patient:code': '1234',
        'name': 'Smith',
      };

      final result = SearchParameterParser.parseQueryParameters(queryParams);

      expect(result['has'], isNotNull);
      expect(result['searchParams'], isNotNull);
      final searchParams = result['searchParams'] as Map<String, List<String>>;
      expect(searchParams['name'], equals(['Smith']));
    });

    test('invalid _has format produces null (ignored)', () {
      final queryParams = {
        '_has:BadFormat': '1234', // only 1 segment
      };

      final result = SearchParameterParser.parseQueryParameters(queryParams);
      expect(result['has'], isNull);
    });
  });
}
