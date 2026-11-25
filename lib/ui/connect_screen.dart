import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../adb/adb.dart';
import '../discovery/scan.dart';
import '../flows.dart';
import '../state/providers.dart';
import 'about_screen.dart';
import 'manual_key_screen.dart';
import 'scooter_screen.dart';
import 'sealed_screen.dart';
import 'update_notices.dart';
import 'widgets.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _address = TextEditingController();
  StreamSubscription<FoundHost>? _scan;
  final _found = <FoundHost>[];
  bool _scanning = false;

  @override
  void dispose() {
    _scan?.cancel();
    _address.dispose();
    super.dispose();
  }

  void _connect(String host) {
    if (host.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    _address.text = host;
    ref.read(connectionProvider.notifier).connect(host);
  }

  void _toggleScan() {
    if (_scanning) {
      _scan?.cancel();
      setState(() => _scanning = false);
      return;
    }
    setState(() {
      _found.clear();
      _scanning = true;
    });
    _scan = scan().listen(
      (h) => setState(() => _found.add(h)),
      onDone: () => mounted ? setState(() => _scanning = false) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The only place that moves between Connect, Set up access and the
    // scooter: one owner, so no two screens pop each other's routes.
    ref.listen(connectionProvider, (prev, next) {
      final nav = Navigator.of(context);
      if (next.connected && !(prev?.connected ?? false)) {
        _scan?.cancel();
        setState(() => _scanning = false);
        nav.popUntil((r) => r.isFirst);
        nav.push(MaterialPageRoute(builder: (_) => const ScooterScreen()));
      } else if (next.outcome == ConnectOutcome.unauthorized && prev?.outcome != ConnectOutcome.unauthorized) {
        nav.popUntil((r) => r.isFirst);
        final host = next.host!;
        nav.push(MaterialPageRoute(
          builder: (_) => accessFallbackFor(next.provision) == AccessFallback.sealed
              ? SealedScreen(host: host)
              : ManualKeyScreen(host: host),
        ));
      }
    });
    final conn = ref.watch(connectionProvider);
    final recents = ref.watch(recentsProvider);
    final known = ref.watch(knownBuildProvider);
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final failed = conn.outcome == ConnectOutcome.unreachable && !conn.busy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenDash Companion'),
        actions: [
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(openDashReleaseProvider);
          ref.invalidate(companionReleaseProvider);
          await ref.read(openDashReleaseProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text('Connect to your scooter', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            const SizedBox(height: 6),
            Text("Put the phone on the same Wi-Fi as the scooter, or on the scooter's hotspot, or share the phone's hotspot with it.",
                style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
            if (known != null) OpenDashUpdateNotice(installedBuild: known),
            const CompanionUpdateNotice(),
            const SizedBox(height: 20),
            TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.go,
              onSubmitted: _connect,
              decoration: const InputDecoration(hintText: 'Scooter address, e.g. 192.168.1.42', prefixIcon: Icon(Icons.lan_outlined)),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: conn.busy ? null : () => _connect(_address.text),
              child: conn.busy
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.onSurfaceVariant)),
                      const SizedBox(width: 12),
                      Text('Connecting to ${conn.host}…'),
                    ])
                  : const Text('Connect'),
            ),
            if (failed) ...[
              const SizedBox(height: 12),
              Notice(
                icon: Icons.wifi_off_rounded,
                color: cs.error,
                title: "Couldn't reach ${conn.host}",
                body: conn.error ?? 'Check the address, and that the phone and the scooter are on the same network.',
              ),
            ],
            if (recents.isNotEmpty) ...[
              const SectionLabel('Recent'),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (final (i, r) in recents.indexed) ...[
                    if (i > 0) const Divider(indent: 56),
                    ListTile(
                      leading: Icon(Icons.history_rounded, color: cs.onSurfaceVariant),
                      title: Text(r.host),
                      subtitle: Text(switch (r.build) { null => 'Not connected yet', 0 => 'No OpenDash', final b => 'OpenDash build $b' }),
                      trailing: IconButton(
                        tooltip: 'Forget',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => ref.read(recentsProvider.notifier).forget(r.host),
                      ),
                      onTap: conn.busy ? null : () => _connect(r.host),
                    ),
                  ],
                ]),
              ),
            ],
            SectionLabel(
              'Nearby',
              trailing: TextButton.icon(
                onPressed: conn.busy ? null : _toggleScan,
                icon: _scanning
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.radar_rounded, size: 20),
                label: Text(_scanning ? 'Stop' : 'Scan'),
              ),
            ),
            if (_found.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _scanning ? 'Looking for devices with adb open…' : 'Scan looks for devices on your networks that accept adb.',
                  style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (final (i, h) in _found.indexed) ...[
                    if (i > 0) const Divider(indent: 56),
                    ListTile(
                      leading: Icon(h.diagnostics ? Icons.electric_scooter_rounded : Icons.devices_other_rounded,
                          color: h.diagnostics ? cs.primary : cs.onSurfaceVariant),
                      title: Text(h.host),
                      subtitle: Text(h.diagnostics ? 'Ola head unit' : 'adb device'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: conn.busy ? null : () => _connect(h.host),
                    ),
                  ],
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
