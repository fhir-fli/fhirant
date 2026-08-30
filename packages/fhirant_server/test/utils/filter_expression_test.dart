import 'package:fhirant_server/src/utils/filter_expression.dart';
import 'package:test/test.dart';

/// The cases come from R4 3.1.3 itself, including every worked example on the
/// page, so this pins the published syntax rather than what the parser
/// happens to accept.
void main() {
  group('the examples in R4 3.1.3.1', () {
    test('name co "pet"', () {
      final filter = parseFilter('name co "pet"') as FilterComparison;
      expect(filter.path.map((s) => s.name), ['name']);
      expect(filter.operator, FilterOperator.co);
      expect(filter.value, 'pet');
    });

    test('given eq "peter" and birthdate ge 2014-10-10', () {
      final filter = parseFilter('given eq "peter" and birthdate ge 2014-10-10')
          as FilterLogical;
      expect(filter.isAnd, isTrue);
      final left = filter.left as FilterComparison;
      expect(left.path.single.name, 'given');
      expect(left.value, 'peter');
      final right = filter.right as FilterComparison;
      expect(right.path.single.name, 'birthdate');
      expect(right.operator, FilterOperator.ge);
      expect(right.value, '2014-10-10');
    });

    test('code eq http://loinc.org|1234-5 keeps the system and the code', () {
      final filter =
          parseFilter('code eq http://loinc.org|1234-5') as FilterComparison;
      expect(filter.value, 'http://loinc.org|1234-5');
    });

    test('subject.name co "pet" chains by name', () {
      final filter = parseFilter('subject.name co "pet"') as FilterComparison;
      expect(filter.path.map((s) => s.name), ['subject', 'name']);
      expect(filter.path.every((s) => s.filter == null), isTrue);
    });

    test('related[type eq "has-component"].target pr true', () {
      final filter =
          parseFilter('related[type eq "has-component"].target pr true')
              as FilterComparison;
      expect(filter.path.map((s) => s.name), ['related', 'target']);
      expect(filter.operator, FilterOperator.pr);
      expect(filter.value, 'true');

      final sub = filter.path.first.filter! as FilterComparison;
      expect(sub.path.single.name, 'type');
      expect(sub.operator, FilterOperator.eq);
      expect(sub.value, 'has-component');
    });

    test('related[type eq has-component].target re Observation/4', () {
      final filter =
          parseFilter('related[type eq has-component].target re Observation/4')
              as FilterComparison;
      expect(filter.operator, FilterOperator.re);
      expect(filter.value, 'Observation/4');
      // Unquoted inside brackets: a token may hold anything but whitespace,
      // ']' and ')', so the bracket still closes the sub-filter.
      expect(
        (filter.path.first.filter! as FilterComparison).value,
        'has-component',
      );
    });
  });

  group('logical structure', () {
    test('and/or associate left to right with no precedence', () {
      // 3.1.3.1: "Logical expressions are evaluated left to right, with no
      // precedence between and and or." So this is ((a or b) and c), which is
      // NOT what boolean precedence would give.
      final filter =
          parseFilter('a eq 1 or b eq 2 and c eq 3') as FilterLogical;
      expect(filter.isAnd, isTrue);
      expect((filter.right as FilterComparison).path.single.name, 'c');

      final left = filter.left as FilterLogical;
      expect(left.isAnd, isFalse);
      expect((left.left as FilterComparison).path.single.name, 'a');
      expect((left.right as FilterComparison).path.single.name, 'b');
    });

    test('parentheses override the left-to-right grouping', () {
      final filter =
          parseFilter('a eq 1 or (b eq 2 and c eq 3)') as FilterLogical;
      expect(filter.isAnd, isFalse);
      expect((filter.right as FilterLogical).isAnd, isTrue);
    });

    test('not(...) negates the whole parenthesised filter', () {
      final filter = parseFilter('not(a eq 1 or b eq 2)') as FilterNot;
      expect((filter.operand as FilterLogical).isAnd, isFalse);
    });

    test('a parameter may be called "not"', () {
      // The grammar only gives "not" meaning in front of a parenthesis.
      final filter = parseFilter('not eq true') as FilterComparison;
      expect(filter.path.single.name, 'not');
      expect(filter.value, 'true');
    });

    test('nested parentheses', () {
      final filter = parseFilter('((a eq 1) and (b eq 2))') as FilterLogical;
      expect(filter.isAnd, isTrue);
    });
  });

  group('values', () {
    test('a quoted string may hold spaces, ) and ]', () {
      final filter =
          parseFilter('name eq "Clinic (North) [main]"') as FilterComparison;
      expect(filter.value, 'Clinic (North) [main]');
    });

    test('escapes inside a quoted string', () {
      final filter = parseFilter(r'name eq "a\"b\\c\tdé"') as FilterComparison;
      expect(filter.value, 'a"b\\c\tdé');
    });

    test('a token ends at whitespace, ] or )', () {
      final filter = parseFilter('(code eq abc)') as FilterComparison;
      expect(filter.value, 'abc');
    });

    test('a date value keeps its punctuation', () {
      final filter =
          parseFilter('date ge 2014-10-10T12:00:00+01:00') as FilterComparison;
      expect(filter.value, '2014-10-10T12:00:00+01:00');
    });
  });

  group('operators', () {
    test('every operator in the 3.1.3.2 table parses', () {
      const tokens = [
        'eq', 'ne', 'co', 'sw', 'ew', 'gt', 'lt', 'ge', 'le', //
        'ap', 'sa', 'eb', 'pr', 'po', 'ss', 'sb', 'in', 'ni', 're',
      ];
      expect(tokens.length, 19);
      for (final token in tokens) {
        final filter = parseFilter('x $token y') as FilterComparison;
        expect(filter.operator.token, token, reason: token);
      }
    });

    test('operators are matched case-insensitively', () {
      // The table itself prints "Co" for the contains row.
      expect(
        (parseFilter('name Co "pet"') as FilterComparison).operator,
        FilterOperator.co,
      );
    });

    test('an unknown operator is refused, and says where', () {
      expect(
        () => parseFilter('name like "pet"'),
        throwsA(
          isA<FilterParseException>()
              .having((e) => e.message, 'message', contains('like'))
              .having((e) => e.offset, 'offset', 5),
        ),
      );
    });
  });

  group('malformed input', () {
    test('a missing value', () {
      expect(
        () => parseFilter('name eq'),
        throwsA(isA<FilterParseException>()),
      );
    });

    test('an unclosed parenthesis', () {
      expect(
        () => parseFilter('(name eq "x"'),
        throwsA(isA<FilterParseException>()),
      );
    });

    test('an unclosed bracket', () {
      expect(
        () => parseFilter('related[type eq x.target pr true'),
        throwsA(isA<FilterParseException>()),
      );
    });

    test('an unterminated string', () {
      expect(
        () => parseFilter('name eq "pet'),
        throwsA(isA<FilterParseException>()),
      );
    });

    test('trailing rubbish after a complete filter', () {
      expect(
        () => parseFilter('name eq "pet" rubbish'),
        throwsA(isA<FilterParseException>()),
      );
    });

    test('an empty filter', () {
      expect(() => parseFilter(''), throwsA(isA<FilterParseException>()));
    });
  });
}
