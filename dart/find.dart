import 'package:pocketbase/pocketbase.dart';

Future<void> main() async {
  final PocketBase pb = PocketBase('http://127.0.0.1:8090');

  // Authenticate
  await pb.admins.authWithPassword('grey@fhirfli.dev', '01 password');

  final resultList = await pb.collection('Observation').getOne('8dazsc6sbge4tgh');
  print(resultList.data);
  }
