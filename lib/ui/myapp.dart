import 'package:fhirant/fhirant.dart';
import 'package:flutter/material.dart';

/// MyApp
class MyApp extends StatelessWidget {
  /// MyApp
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FHIR ANT',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const Scaffold(body: SafeArea(child: HomeScreen())),
    );
  }
}
