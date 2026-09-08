import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// REVIEW-2026-09-06 finding 43: the app ships the R4B specification's
/// canonical resources (the same NDJSON set the CLI loads) and finds them in
/// its asset bundle, so `$validate` on the phone can resolve a base type or
/// a bound value set.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the spec NDJSON files are in the asset bundle', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final spec = manifest
        .listAssets()
        .where((a) => a.startsWith('assets/fhir_spec/'))
        .toList()
      ..sort();
    expect(spec, contains('assets/fhir_spec/profiles-resources.ndjson'));
    expect(spec, contains('assets/fhir_spec/valuesets.ndjson'));
    expect(spec, hasLength(9));
    final text =
        await rootBundle.loadString('assets/fhir_spec/search-parameters.ndjson');
    expect(text, startsWith('{"resourceType":"SearchParameter"'));
  });
}
