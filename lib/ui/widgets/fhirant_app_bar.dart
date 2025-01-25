import 'package:flutter/material.dart';

/// FhirantAppBar
class FhirantAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Constructor
  const FhirantAppBar(this.isServerRunning, {super.key});

  /// Server running status notifier
  final ValueNotifier<bool> isServerRunning;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Center(
        child: Image.asset(
          'assets/fhirant_logo.png',
          height: 78, // Adjust size as needed
        ),
      ),
      backgroundColor: Colors.indigo,
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: isServerRunning,
          builder: (context, running, child) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Icon(
                Icons.circle,
                color: running ? Colors.green : Colors.red,
                size: 16,
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
