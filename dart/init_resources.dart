// Function to create or update a record
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart';
import 'package:pocketbase/pocketbase.dart';

Future<void> main() async {
  HttpOverrides.global = HttpOverridesImpl();

  final PocketBase pb = PocketBase('http://127.0.0.1:8090');

  try {
    await pb.admins.authWithPassword('grey@fhirfli.dev', '01 password');
    await uploadPatients(pb);
  } catch (e) {
    print(e);
  }
}

Future<void> uploadPatients(PocketBase pb) async {
  final dir = Directory('assets/mimic_iv');
  final List<FileSystemEntity> files = dir.listSync();
  for (final FileSystemEntity file in files) {
    if (file is File) {
      final List<String> lines = file.readAsLinesSync();
      for (final String line in lines) {
        final Resource resource = Resource.fromJsonString(line);
        await createOrUpdateResource(pb, resource);
      }
    }
  }
}

class HttpOverridesImpl extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

Future<Resource> createOrUpdateResource(
        PocketBase pb, Resource resource) async =>
    Resource.fromJson(
        await createOrUpdateRecord(pb, resource.prepareForUpload.toJson()));

Future<Map<String, dynamic>> createOrUpdateRecord(
    PocketBase pb, Map<String, dynamic> resourceMap) async {
  final Map<String, dynamic> body = resourceMapToBody(resourceMap);
  final String resourceType = resourceMap['resourceType'];
  try {
    final RecordModel recordModel =
        await pb.collection(resourceType.toLowerCase()).create(body: body);
    print(recordModel);
    if (recordModel.data['resource'] != null) {
      print('resource returned');
      return recordModel.data['resource'];
    } else {
      return _operationOutcomes('Error creating record');
    }
  } catch (e) {
    print('Error creating or updating record: $e');
    if (e is ClientException && e.statusCode == 404) {
      final RecordModel recordModel =
          await pb.collection(resourceType.toLowerCase()).create(body: body);
      if (recordModel.data['resource'] != null) {
        return recordModel.data['resource'];
      } else {
        return _operationOutcomes(e.toString());
      }
    } else {
      return _operationOutcomes(e.toString());
    }
  }
}

Map<String, dynamic> resourceMapToBody(Map<String, dynamic> resourceMap) => {
      "lastUpdated": resourceMap['meta']['lastUpdated'],
      "resource": resourceMap,
    };

Map<String, dynamic> _operationOutcomes(String error) => <String, dynamic>{
      'resourceType': 'OperationOutcome',
      'issue': <Map<String, dynamic>>[
        <String, dynamic>{
          'severity': 'error',
          'code': 'processing',
          'diagnostics': error,
        }
      ]
    };

extension PocketbaseId on Resource {
  static String generate() =>
      generateNewUuidString().replaceAll('-', '').substring(12, 27);

  Resource get newPocketbaseId {
    final Map<String, dynamic> json = this.toJson();
    json['id'] = generate();
    return Resource.fromJson(json);
  }

  Resource get newPocketbaseIdIfNoId =>
      this.id != null && this.id.toString().length == 15
          ? this
          : newPocketbaseId;

  Resource get prepareForUpload =>
      updateVersion(versionIdAsTime: true).newPocketbaseIdIfNoId;
}
