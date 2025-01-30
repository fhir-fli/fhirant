import 'package:fhirant/fhirant.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DbService().initialize();
  runApp(const MyApp());
}
