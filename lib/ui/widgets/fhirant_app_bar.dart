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
          height: MediaQuery.of(context).size.height * 0.1,
          fit: BoxFit.contain,
        ),
      ),
      backgroundColor: Colors.indigo,
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: isServerRunning,
          builder: (context, running, child) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Tooltip(
                message: running ? 'Server Running' : 'Server Stopped',
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    Icons.circle,
                    key: ValueKey(running),
                    color: running ? Colors.green : Colors.red,
                    size: 16,
                  ),
                ),
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
