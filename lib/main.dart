import 'package:fhirant/fhirant.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbService = DbService();
  await dbService.initializeDatabase();
  runApp(const MyApp());
}
