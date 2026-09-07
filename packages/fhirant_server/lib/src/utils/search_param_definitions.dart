/// Which resource types carry which operations, for the CapabilityStatement.
///
/// The search parameters and the _include/_revinclude declarations come from
/// the generated `searchParameterTypes` in fhir_r4_db (metadata_handler.dart);
/// this used to hold hand-typed lists of both for a few types.
class SearchParamDefinitions {
  SearchParamDefinitions._();

  static const Set<String> everythingTypes = {
    'Patient',
    'Encounter',
    'Practitioner',
    'RelatedPerson',
    'Device',
  };

  /// Resource types that support $export.
  static const Set<String> exportTypes = {'Patient', 'Group'};

  /// Resource types that support $document.
  static const Set<String> documentTypes = {'Composition'};

  /// Resource types that support $validate-code.
  static const Set<String> validateCodeTypes = {'CodeSystem', 'ValueSet'};

  /// Resource types that support $lookup.
  static const Set<String> lookupTypes = {'CodeSystem'};

  /// Resource types that support $expand.
  static const Set<String> expandTypes = {'ValueSet'};

  /// Resource types that support $subsumes.
  static const Set<String> subsumesTypes = {'CodeSystem'};

  /// Resource types that support $translate.
  static const Set<String> translateTypes = {'ConceptMap'};

  /// Resource types that support $preferred-id.
  static const Set<String> preferredIdTypes = {'NamingSystem'};
}
