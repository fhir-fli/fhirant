import 'package:fhirant/src/screens/administration_screen.dart';
import 'package:fhirant/src/services/server_service.dart';
import 'package:fhirant/src/state/server_state.dart';
import 'package:fhirant_server/fhirant_server.dart' show DeviceConsole;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The way into the Administration section, in Secure mode only: in
/// Experimentation mode authentication is off and there are no accounts.
class AdministrationCard extends StatelessWidget {
  const AdministrationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ServerState>();
    if (state.devMode) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        key: const Key('open-administration'),
        leading: const Icon(Icons.admin_panel_settings),
        title: const Text('Administration'),
        subtitle: const Text(
          'Accounts: create, approve passwords, reset, switch off',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AdministrationScreen(
              openConsole: () async => DeviceConsole(
                state.db,
                jwtSecret: await loadJwtSecret(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
