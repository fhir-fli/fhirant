// ignore_for_file: avoid_print

import 'dart:async';

import 'package:fhirant/app/app.dart';
import 'package:fhirant/app/initialize_service.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(App());
}
