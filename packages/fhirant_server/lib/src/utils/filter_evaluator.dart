import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/filter_expression.dart';

/// Thrown when a `_filter` cannot be answered by this server's index.
///
/// R4 3.1.1.4.4 is the model for the response: a request the server cannot
/// honour is refused with "a clear error message", not answered with a result
/// set that quietly means something else. A `_filter` that returned the rows
/// matching a *different* operator would be a wrong answer, not a limitation.
class FilterNotSupported implements Exception {
  /// Creates a refusal explaining [message].
  const FilterNotSupported(this.message);

  /// What could not be answered, in terms the client can act on.
  final String message;

  @override
  String toString() => message;
}

/// Runs a parsed `_filter` against the database and returns matching ids.
///
/// Every leaf becomes an ordinary search — the same parser, index and
/// semantics the REST endpoint uses — and the logical operators combine the
/// id sets. Reimplementing parameter semantics beside the search engine is how
/// a `_filter` result stops meaning what the same query means without it.
class FilterEvaluator {
  /// Evaluates filters against [db] for [resourceType].
  FilterEvaluator(this.db, this.resourceType);

  /// The database searched.
  final FhirAntDb db;

  /// The type being searched, which decides each parameter's declared type.
  final fhir.R4ResourceType resourceType;

  /// The ids matching [expression].
  Future<Set<String>> evaluate(FilterExpression expression) async {
    switch (expression) {
      case FilterComparison():
        return _comparison(expression);
      case FilterLogical(:final left, :final isAnd, :final right):
        final leftIds = await evaluate(left);
        final rightIds = await evaluate(right);
        return isAnd
            ? leftIds.intersection(rightIds)
            : (leftIds..addAll(rightIds));
      case FilterNot(:final operand):
        final all = await _allIds();
        return all.difference(await evaluate(operand));
    }
  }

  Future<Set<String>> _comparison(FilterComparison comparison) async {
    if (comparison.path.any((segment) => segment.filter != null)) {
      // `related[type eq has-component].target` asks for two conditions on the
      // SAME element. Our index stores `related-type` and `related-target` as
      // separate rows with nothing tying them together, so ANDing them would
      // also match a resource where two DIFFERENT components satisfied the two
      // halves. That is a wrong answer, so it is refused instead.
      throw const FilterNotSupported(
        'A _filter path with a [sub-filter] is not supported: this server '
        'indexes the parameters inside the brackets separately, so it cannot '
        'tell whether they hold of the same element.',
      );
    }

    final name = comparison.path.map((segment) => segment.name).join('.');
    final root = comparison.path.first.name;
    // The common parameters — _id, _lastUpdated, _tag, _profile, _security and
    // the rest of R4 3.1.1.4.1 — are published against `Resource` and
    // `DomainResource`, not against each type, so a filter naming one has to
    // fall back to those tables.
    final definition = searchParameterTypes[resourceType.toString()]?[root] ??
        searchParameterTypes['DomainResource']?[root] ??
        searchParameterTypes['Resource']?[root];
    if (definition == null) {
      throw FilterNotSupported(
        '"$root" is not a search parameter of $resourceType.',
      );
    }
    // A chain is resolved by the search engine, which reads the target type's
    // parameters. The operator, though, is checked against the ROOT
    // parameter's declared type, which for a chain is always `reference`.
    final type = comparison.path.length > 1 ? 'reference' : definition.type;

    final key = _key(name, comparison, type);
    final value = _value(comparison, type, definition.comparators);

    final matches = await db.search(
      resourceType: resourceType,
      searchParameters: {
        key: [value],
      },
    );
    return matches
        .map((resource) => resource.id?.valueString)
        .whereType<String>()
        .toSet();
  }

  /// The search key, which is the parameter name plus a modifier where the
  /// operator maps onto one.
  String _key(String name, FilterComparison comparison, String type) {
    switch (comparison.operator) {
      case FilterOperator.co:
        if (type != 'string') {
          throw FilterNotSupported(
            '"co" on a $type parameter is not supported. R4 3.1.3.2 defines it '
            'for string, number and date; this server can answer it for '
            'string, through the :contains modifier.',
          );
        }
        return '$name:contains';
      case FilterOperator.pr:
        return '$name:missing';
      case FilterOperator.isIn:
        _requireToken(type, 'in');
        return '$name:in';
      case FilterOperator.ni:
        _requireToken(type, 'ni');
        return '$name:not-in';
      case FilterOperator.eq:
        if (type == 'string') {
          // 3.1.3.2 for a string eq: "Character sequence is the same (case
          // insensitive)". The default string search is starts-with, and
          // :exact is case AND accent sensitive, so neither answers this.
          throw const FilterNotSupported(
            '"eq" on a string parameter is not supported. It means the whole '
            'value, compared case-insensitively; this server offers '
            'starts-with (sw) and :exact, and neither is that comparison.',
          );
        }
        return name;
      case FilterOperator.sw:
        if (type != 'string') {
          throw FilterNotSupported('"sw" is defined for string, not $type.');
        }
        // R4 3.1.1.4.8: a string search matches a value that "equals or starts
        // with the supplied parameter value", which is what sw asks for.
        return name;
      case FilterOperator.re:
        if (type != 'reference') {
          throw FilterNotSupported('"re" is defined for reference, not $type.');
        }
        return name;
      case FilterOperator.gt:
      case FilterOperator.lt:
      case FilterOperator.ge:
      case FilterOperator.le:
      case FilterOperator.sa:
      case FilterOperator.eb:
      case FilterOperator.ap:
        return name;
      case FilterOperator.ne:
        // "An item in the set has an unequal value" is not the complement of
        // eq: a resource carrying both A and B satisfies `eq A` AND `ne A`.
        // Subtracting the eq set would drop it, which is a wrong answer.
        throw const FilterNotSupported(
          '"ne" is not supported. It asks whether ANY value in the set '
          'differs, which is not the complement of "eq" for a repeating '
          'element, and this index cannot express it.',
        );
      case FilterOperator.ew:
        throw const FilterNotSupported(
          '"ew" (ends with) is not supported: this server has no ends-with '
          'modifier.',
        );
      case FilterOperator.po:
        throw const FilterNotSupported(
          '"po" (period overlap) is not supported.',
        );
      case FilterOperator.ss:
      case FilterOperator.sb:
        throw FilterNotSupported(
          '"${comparison.operator.token}" (subsumption) is not supported.',
        );
    }
  }

  /// The search value, with a comparator prefix where the operator is one.
  String _value(
    FilterComparison comparison,
    String type,
    List<String> comparators,
  ) {
    const prefixed = {
      FilterOperator.gt,
      FilterOperator.lt,
      FilterOperator.ge,
      FilterOperator.le,
      FilterOperator.sa,
      FilterOperator.eb,
      FilterOperator.ap,
    };
    if (!prefixed.contains(comparison.operator)) {
      if (comparison.operator == FilterOperator.pr) {
        // `pr true` asks for a non-empty set, which is :missing=false.
        final present = comparison.value.toLowerCase() == 'true';
        return present ? 'false' : 'true';
      }
      return comparison.value;
    }
    final token = comparison.operator.token;
    if (!comparators.contains(token)) {
      final declared = comparators.isEmpty ? 'none' : comparators.join(', ');
      throw FilterNotSupported(
        '"$token" is not a comparator of this parameter. Its published '
        'definition declares: $declared.',
      );
    }
    return '$token${comparison.value}';
  }

  void _requireToken(String type, String token) {
    if (type != 'token') {
      throw FilterNotSupported('"$token" is defined for token, not $type.');
    }
  }

  /// Every id of this resource type, needed to complement a `not(...)`.
  Future<Set<String>> _allIds() async {
    final all = await db.search(
      resourceType: resourceType,
      searchParameters: const {},
    );
    return all
        .map((resource) => resource.id?.valueString)
        .whereType<String>()
        .toSet();
  }
}
