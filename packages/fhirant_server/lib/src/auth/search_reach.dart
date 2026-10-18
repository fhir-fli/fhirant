import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:fhirant_server/src/utils/filter_expression.dart';

/// The resource types, other than the one searched, whose index a search's
/// criteria read: the targets of chained parameters (typed or not, every
/// hop), of `_has` (nested ones too), and of chains inside `_filter`.
///
/// R4B security.html 6.1.0.5.1 (hl7.org/fhir/R4B/security.html, read whole
/// 2026-10-17, verbatim): "Chained search provides the ability to disclose
/// information on related resources. A security implementation must
/// consider whether a client has the permission to access the resource
/// being searched on, as well as the chained resource(s)". A chain is a
/// question about the chained type: `Observation?subject:Patient.family=X`
/// answers whether a patient named X exists, and which results are theirs.
/// Measured 2026-10-17 (REVIEW-2026-10-17 finding 6): with
/// `user/Observation.rs` only, that search answered 2.
///
/// The candidate types follow the engine (fhir_db `_chainCondition`): a
/// typed chain names its type; an untyped one reaches the reference's
/// declared targets that define the chained parameter, through the store's
/// own lookup, which includes uploaded SearchParameters.
Set<String> typesReachedBy(
  FhirAntDb db,
  String resourceType,
  Map<String, List<String>> query,
) {
  final reached = <String>{};
  for (final MapEntry(:key, :value) in query.entries) {
    if (key == '_filter') {
      for (final v in value) {
        try {
          _filterChains(parseFilter(v), (chain) {
            reached.addAll(_chainTargets(db, resourceType, chain));
          });
        } on FilterParseException {
          // The search refuses the filter itself; nothing is read.
        }
      }
      continue;
    }
    if (key.startsWith('_has:')) {
      for (final v in value) {
        for (var has = HasParameter.parse(key, v);
            has != null;
            has = has.nested) {
          reached
            ..add(has.targetType)
            ..addAll(_chainTargets(db, has.targetType, has.searchParam));
        }
      }
      continue;
    }
    reached.addAll(_chainTargets(db, resourceType, key));
  }
  return reached..remove(resourceType);
}

/// The types among [typesReachedBy] that [principal] may not search, in
/// name order; empty when it may search them all (or there is no
/// principal: authentication is off).
List<String> unsearchableTypesReachedBy(
  Principal? principal,
  FhirAntDb db,
  String resourceType,
  Map<String, List<String>> query,
) {
  if (principal == null) return const [];
  return [
    for (final type in typesReachedBy(db, resourceType, query))
      if (authorizeRequest(principal, 'GET', '/$type') != null) type,
  ]..sort();
}

/// The words a refusal carries: which types the criteria reach that the
/// caller's scopes do not cover.
String unsearchableTypesMessage(List<String> types) =>
    'The search criteria read ${types.join(', ')} (by chain, _has or '
    '_filter), which this token may not search.';

/// The types the chained key [key] on [type] reaches, every hop.
Set<String> _chainTargets(FhirAntDb db, String type, String key) {
  final parsed = SearchQueryKey.parse(key);
  final chain = parsed.chain;
  if (chain == null) return const {};
  final declared = db.fhirDao.lookupDefinition(type, parsed.name);
  if (declared == null || declared.type != 'reference') return const {};
  final next = SearchQueryKey.parse(chain);
  final constraint = parsed.modifier;
  // An untyped hop: the engine ORs every type that defines the chained
  // parameter, but its join keeps only the rows this reference points at,
  // which are the parameter's declared targets (SearchParameter.target).
  // Counting every type would refuse a token for types no row can reach.
  // A definition that declares no targets keeps the engine's whole set.
  final reachable = declared.targets.isEmpty
      ? [for (final t in fhir.R4ResourceType.values) '$t']
      : declared.targets;
  final candidates = constraint != null
      ? {constraint}
      : {
          for (final t in reachable)
            if (db.fhirDao.lookupDefinition(t, next.name) != null) t,
        };
  return {
    ...candidates,
    for (final c in candidates) ..._chainTargets(db, c, chain),
  };
}

/// Calls [onChain] with the dotted key of every comparison in [expression]
/// whose path has more than one segment (`subject.name`), the shape the
/// filter evaluator hands the store as a chained key.
void _filterChains(
  FilterExpression expression,
  void Function(String chain) onChain,
) {
  switch (expression) {
    case FilterComparison(:final path):
      if (path.length > 1) onChain(path.map((s) => s.name).join('.'));
    case FilterLogical(:final left, :final right):
      _filterChains(left, onChain);
      _filterChains(right, onChain);
    case FilterNot(:final operand):
      _filterChains(operand, onChain);
  }
}
