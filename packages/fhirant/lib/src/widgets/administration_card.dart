import 'package:fhirant/src/screens/administration_screen.dart';
import 'package:fhirant/src/services/server_service.dart';
import 'package:fhirant/src/state/server_state.dart';
import 'package:fhirant_server/fhirant_server.dart'
    show DeviceConsole, SyncJobs;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The way into the Administration section, in Secure mode only: in
/// Experimentation mode authentication is off and there are no accounts.
class AdministrationCard extends StatelessWidget {
  const AdministrationCard({super.key});

  /// The one record of the running sync in this app: every console the
  /// section opens shares it, so a sync outlives the sign-in that started
  /// it. The store's lease keeps it the only sync on the phone.
  static final SyncJobs syncJobs = SyncJobs();

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
          'Accounts, the apps allowed to sign in, and sync with another '
          'server',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AdministrationScreen(
              openConsole: () async => DeviceConsole(
                state.db,
                jwtSecret: await loadJwtSecret(),
                exportDir: await state.exportDir(),
                syncJobs: syncJobs,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
