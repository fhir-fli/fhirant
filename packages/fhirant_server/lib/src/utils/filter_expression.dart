/// The `_filter` search parameter's expression tree, and its parser.
///
/// R4 3.1.3 defines the syntax, and this follows that page rather than any
/// summary of it:
///
/// ```text
/// filter        = paramExp / logExp / ("not") "(" filter ")"
/// logExp        = filter ("and" / "or" filter)+
/// paramExp      = paramPath SP compareOp SP compValue
/// compValue     = string / numberOrDate / token
/// paramPath     = paramName (("[" filter "]") "." paramPath)
/// ```
///
/// Two rules from that page shape the parser and are easy to get wrong:
///
/// - **"Logical expressions are evaluated left to right, with no precedence
///   between `and` and `or`."** So `a eq 1 or b eq 2 and c eq 3` groups as
///   `((a eq 1 or b eq 2) and c eq 3)`, which is NOT what a reader used to
///   boolean algebra expects, and is why the spec adds "if there is ambiguity,
///   use parentheses to be explicit".
/// - **A string and a token differ only in what characters they may hold.**
///   "The only difference between a 'string' value and a 'token' value is that
///   a string can contain spaces and ')' and ']'. There is otherwise no
///   significant difference between them." So the tree keeps the value, not
///   the quoting.
library;

/// The comparison operators of R4 3.1.3.2, in the order the table gives them.
enum FilterOperator {
  /// an item in the set has an equal value
  eq,

  /// an item in the set has an unequal value
  ne,

  /// an item in the set contains this value
  co,

  /// an item in the set starts with this value
  sw,

  /// an item in the set ends with this value
  ew,

  /// a value in the set is greater than the given value
  gt,

  /// a value in the set is less than the given value
  lt,

  /// a value in the set is greater than or equal to the given value
  ge,

  /// a value in the set is less than or equal to the given value
  le,

  /// a value in the set is approximately the same as this value
  ap,

  /// the value starts after the specified value
  sa,

  /// the value ends before the specified value
  eb,

  /// the set is empty or not (value is false or true)
  pr,

  /// an implied date period in the set overlaps the implied period in the value
  po,

  /// the value subsumes a concept in the set
  ss,

  /// the value is subsumed by a concept in the set
  sb,

  /// one of the concepts is in the nominated value set by URI
  isIn,

  /// none of the concepts are in the nominated value set by URI
  ni,

  /// one of the references in the set points to the given URL
  re;

  /// The token as it is written in a filter, which for [isIn] is `in`.
  String get token => this == FilterOperator.isIn ? 'in' : name;

  /// The operator [token] names, or null when it names none.
  static FilterOperator? parse(String token) {
    final lower = token.toLowerCase();
    if (lower == 'in') return FilterOperator.isIn;
    for (final op in FilterOperator.values) {
      if (op.name == lower) return op;
    }
    return null;
  }
}

/// A node of a parsed `_filter`.
sealed class FilterExpression {
  const FilterExpression();
}

/// `paramPath SP compareOp SP compValue` — one test against one path.
class FilterComparison extends FilterExpression {
  /// Creates a comparison of [path] against [value] using [operator].
  const FilterComparison(this.path, this.operator, this.value);

  /// The path being tested, one segment per `.`.
  final List<FilterPathSegment> path;

  /// The comparison to make.
  final FilterOperator operator;

  /// The value, with any JSON string quoting already removed.
  final String value;

  @override
  String toString() => '${path.join('.')} ${operator.token} $value';
}

/// `x and y` or `x or y`.
///
/// Built left-associatively with no precedence, per 3.1.3.1.
class FilterLogical extends FilterExpression {
  /// Creates `left <and|or> right`.
  const FilterLogical(this.left, this.isAnd, this.right);

  /// The expression on the left.
  final FilterExpression left;

  /// True for `and`, false for `or`.
  final bool isAnd;

  /// The expression on the right.
  final FilterExpression right;

  @override
  String toString() => '($left ${isAnd ? 'and' : 'or'} $right)';
}

/// `not(filter)`.
class FilterNot extends FilterExpression {
  /// Creates the negation of [operand].
  const FilterNot(this.operand);

  /// The expression being negated.
  final FilterExpression operand;

  @override
  String toString() => 'not($operand)';
}

/// One `name` or `name[filter]` step of a path.
class FilterPathSegment {
  /// Creates a path segment naming [name], optionally filtered by [filter].
  const FilterPathSegment(this.name, [this.filter]);

  /// The search parameter name for this step.
  final String name;

  /// The sub-filter in square brackets, when the step carries one.
  final FilterExpression? filter;

  @override
  String toString() => filter == null ? name : '$name[$filter]';
}

/// Thrown when a `_filter` value cannot be parsed.
///
/// Carries [offset] so a caller can point at where it gave up; R4 3.1.1.4.4
/// asks for "a clear error message" and a position is the clearest part.
class FilterParseException implements Exception {
  /// Creates a parse failure describing [message] at [offset] in [input].
  const FilterParseException(this.message, this.offset, this.input);

  /// What went wrong.
  final String message;

  /// The character offset in [input] where parsing stopped.
  final int offset;

  /// The expression that failed to parse.
  final String input;

  @override
  String toString() => 'Invalid _filter at offset $offset: $message';
}

/// Parses the `_filter` expression in [input].
///
/// Throws [FilterParseException] when [input] is not a filter.
FilterExpression parseFilter(String input) => _FilterParser(input).parse();

class _FilterParser {
  _FilterParser(this.input);

  final String input;
  int pos = 0;

  FilterExpression parse() {
    final expression = _parseFilter();
    _skipSpace();
    if (pos < input.length) {
      throw FilterParseException(
        'unexpected "${input.substring(pos)}"',
        pos,
        input,
      );
    }
    return expression;
  }

  /// One filter, then any `and`/`or` continuations.
  ///
  /// Left-associative with no precedence: the spec says these are "evaluated
  /// left to right", so `a or b and c` is `(a or b) and c`.
  FilterExpression _parseFilter() {
    var expression = _parseTerm();
    while (true) {
      final save = pos;
      _skipSpace();
      final word = _peekWord();
      if (word == 'and' || word == 'or') {
        pos += word!.length;
        final right = _parseTerm();
        expression = FilterLogical(expression, word == 'and', right);
      } else {
        pos = save;
        return expression;
      }
    }
  }

  /// `not(filter)`, `(filter)`, or a comparison.
  FilterExpression _parseTerm() {
    _skipSpace();
    final word = _peekWord();
    if (word == 'not') {
      final save = pos;
      pos += word!.length;
      _skipSpace();
      if (pos < input.length && input[pos] == '(') {
        return FilterNot(_parseParenthesised());
      }
      // "not" is only an operator in front of a parenthesis. Anywhere else it
      // is an ordinary parameter name, so give the characters back.
      pos = save;
    }
    if (pos < input.length && input[pos] == '(') {
      return _parseParenthesised();
    }
    return _parseComparison();
  }

  FilterExpression _parseParenthesised() {
    _expect('(');
    final inner = _parseFilter();
    _skipSpace();
    _expect(')');
    return inner;
  }

  FilterComparison _parseComparison() {
    final path = _parsePath();
    _skipSpace();
    final opStart = pos;
    final opToken = _readWhile((c) => !_isSpace(c));
    if (opToken.isEmpty) {
      throw FilterParseException('expected an operator', opStart, input);
    }
    final operator = FilterOperator.parse(opToken);
    if (operator == null) {
      throw FilterParseException(
        '"$opToken" is not one of the operators in R4 3.1.3.2',
        opStart,
        input,
      );
    }
    _skipSpace();
    final value = _parseValue();
    return FilterComparison(path, operator, value);
  }

  List<FilterPathSegment> _parsePath() {
    final segments = <FilterPathSegment>[];
    while (true) {
      _skipSpace();
      final nameStart = pos;
      final name = _readName();
      if (name.isEmpty) {
        throw FilterParseException(
          'expected a search parameter name',
          nameStart,
          input,
        );
      }
      FilterExpression? sub;
      if (pos < input.length && input[pos] == '[') {
        pos++;
        sub = _parseFilter();
        _skipSpace();
        _expect(']');
      }
      segments.add(FilterPathSegment(name, sub));
      if (pos < input.length && input[pos] == '.') {
        pos++;
        continue;
      }
      return segments;
    }
  }

  /// `string / numberOrDate / token`.
  ///
  /// A token is "any sequence of non-whitespace characters ... except ']' and
  /// ')'", which is what lets a sub-filter and a parenthesis close around an
  /// unquoted value.
  String _parseValue() {
    if (pos >= input.length) {
      throw FilterParseException('expected a value', pos, input);
    }
    if (input[pos] == '"') {
      return _parseQuotedString();
    }
    final start = pos;
    final token = _readWhile((c) => !_isSpace(c) && c != ']' && c != ')');
    if (token.isEmpty) {
      throw FilterParseException('expected a value', start, input);
    }
    return token;
  }

  String _parseQuotedString() {
    final start = pos;
    pos++; // the opening quote
    final buffer = StringBuffer();
    while (pos < input.length) {
      final char = input[pos];
      if (char == r'\') {
        pos++;
        if (pos >= input.length) {
          throw FilterParseException('unterminated escape', start, input);
        }
        final escaped = input[pos];
        final decoded = _decodeEscape(escaped);
        buffer.write(decoded);
        pos++;
        continue;
      }
      if (char == '"') {
        pos++;
        return buffer.toString();
      }
      buffer.write(char);
      pos++;
    }
    throw FilterParseException('unterminated string', start, input);
  }

  /// The character a JSON escape stands for, `\uXXXX` included.
  String _decodeEscape(String escaped) {
    switch (escaped) {
      case 'n':
        return '\n';
      case 't':
        return '\t';
      case 'r':
        return '\r';
      case 'b':
        return '\b';
      case 'f':
        return '\f';
      case '/':
        return '/';
      case '"':
        return '"';
      case r'\':
        return r'\';
      case 'u':
        return _readUnicodeEscape();
      default:
        throw FilterParseException(
          'unknown escape "\\$escaped"',
          pos,
          input,
        );
    }
  }

  String _readUnicodeEscape() {
    if (pos + 4 >= input.length) {
      throw FilterParseException(r'truncated \u escape', pos, input);
    }
    final hex = input.substring(pos + 1, pos + 5);
    final code = int.tryParse(hex, radix: 16);
    if (code == null) {
      throw FilterParseException('"\\u$hex" is not hexadecimal', pos, input);
    }
    pos += 4;
    return String.fromCharCode(code);
  }

  /// `paramName = nameCharStart (nameChar)*`, so `_` or a letter, then
  /// letters, digits, `_` and `-`.
  String _readName() {
    if (pos >= input.length) return '';
    final first = input[pos];
    if (!(first == '_' || _isAlpha(first))) return '';
    return _readWhile(
      (c) => c == '_' || c == '-' || _isAlpha(c) || _isDigit(c),
    );
  }

  String? _peekWord() {
    final save = pos;
    final word = _readWhile(_isAlpha);
    pos = save;
    return word.isEmpty ? null : word.toLowerCase();
  }

  String _readWhile(bool Function(String) test) {
    final start = pos;
    while (pos < input.length && test(input[pos])) {
      pos++;
    }
    return input.substring(start, pos);
  }

  void _skipSpace() {
    while (pos < input.length && _isSpace(input[pos])) {
      pos++;
    }
  }

  void _expect(String char) {
    if (pos >= input.length || input[pos] != char) {
      throw FilterParseException('expected "$char"', pos, input);
    }
    pos++;
  }

  static bool _isSpace(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r';

  static bool _isAlpha(String c) =>
      (c.codeUnitAt(0) >= 0x41 && c.codeUnitAt(0) <= 0x5A) ||
      (c.codeUnitAt(0) >= 0x61 && c.codeUnitAt(0) <= 0x7A);

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
}
