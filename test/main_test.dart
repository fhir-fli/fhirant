// // ignore_for_file: unnecessary_lambdas

// import 'package:fhirant/fhirant.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:mocktail/mocktail.dart';

// // Create a mock class for DbService
// class MockDbService extends Mock implements DbService {}

// void main() {
//   testWidgets('DbService is initialized correctly', (tester) async {
//     final mockDbService = MockDbService();

//     // Mock the initialize method to do nothing
//     // (or simulate successful initialization)
//     when(() => mockDbService.initialize()).thenAnswer((_) async {});

//     // Pass the mock DbService to MyApp (or inject it as needed)
//     await tester.pumpWidget(
//       const MaterialApp(
//         home: MyApp(), // Adjust if you have an injection mechanism
//       ),
//     );

//     // Verify that initialize was called on the DbService
//     verify(() => mockDbService.initialize()).called(1);
//   });

//   testWidgets('App initializes and renders MyApp widget', (tester) async {
//     // Set up mockDbService as done in previous tests
//     final mockDbService = MockDbService();
//     when(() => mockDbService.initialize()).thenAnswer((_) async {});

//     // Run the app with the mock DbService
//     await tester.pumpWidget(
//       const MaterialApp(
//         home: MyApp(), // Adjust if you have an injection mechanism
//       ),
//     );

//     // Verify the MyApp widget is rendered
//     expect(find.byType(MyApp), findsOneWidget);
//   });

//   testWidgets('Error during DbService initialization '
//       'should not crash the app', (tester) async {
//     final mockDbService = MockDbService();

//     // Mock initialize to throw an error
//     when(
//       () => mockDbService.initialize(),
//     ).thenThrow(Exception('Initialization failed'));

//     // Run the app
//     await tester.pumpWidget(
//       const MaterialApp(
//         home: MyApp(), // Adjust if you have an injection mechanism
//       ),
//     );

//     // Verify that the error handling is done properly (e.g., Snackbar appears)
//     expect(find.byType(SnackBar), findsOneWidget);
//   });
// }
