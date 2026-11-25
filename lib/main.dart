import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adb/adb_api.g.dart';
import 'licenses.dart';
import 'report/app_log.dart';
import 'state/auto_send.dart';
import 'state/prefs.dart';
import 'state/providers.dart';
import 'ui/ack_screen.dart';
import 'ui/connect_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerLicenses();
  final prefs = Prefs(await SharedPreferences.getInstance());
  // The log lives with the app's files: the temp directory is wiped on every update.
  final log = AppLog(File('${await AdbHostApi().filesDir()}/logs/companion.log'));
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs), appLogProvider.overrideWithValue(log)],
    child: const CompanionApp(),
  ));
}

class CompanionApp extends ConsumerStatefulWidget {
  const CompanionApp({super.key});

  @override
  ConsumerState<CompanionApp> createState() => _CompanionAppState();
}

class _CompanionAppState extends ConsumerState<CompanionApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // "Check every time the app opens": coming back to it counts.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(openDashReleaseProvider);
      ref.invalidate(companionReleaseProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accepted = ref.watch(ackProvider);
    ref.listen(autoSendProvider, (_, _) {});
    return MaterialApp(
      title: 'OpenDash Companion',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      home: accepted ? const ConnectScreen() : const AckScreen(),
    );
  }
}
