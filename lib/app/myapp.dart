import 'package:fhirant/app/app.dart';
import 'package:flutter/material.dart';

/// MyApp
class MyApp extends StatelessWidget {
  /// MyApp
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FHIR ANT',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const Scaffold(body: SafeArea(child: PrimaryScreen())),
    );
  }
}
