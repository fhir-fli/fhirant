import 'package:fhirant/fhirant.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupSqlCipher();
  final dbService = DbService();
  await dbService.initialize();
  runApp(const MyApp());
}
