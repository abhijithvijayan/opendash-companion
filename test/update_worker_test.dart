import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opendash_companion/releases/update_worker.dart';
import 'package:opendash_companion/state/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

MockClient _client({int build = 2041}) => MockClient((req) async {
      final u = req.url.toString();
      if (u == 'https://api.github.com/repos/abhijithvijayan/opendash/releases/latest') {
        return http.Response(
            jsonEncode({
              'assets': [
                {'name': 'opendash-release.json', 'browser_download_url': 'https://dl/o.json'},
                {'name': 'o.apk', 'browser_download_url': 'https://dl/o.apk'},
              ],
            }),
            200);
      }
      if (u == 'https://dl/o.json') {
        return http.Response(jsonEncode({'version': '0.2.1', 'build': build, 'apk': 'o.apk', 'sha256': 'ab'}), 200);
      }
      return http.Response('nope', 404);
    });

Future<Prefs> _prefs({bool notify = true}) async {
  SharedPreferences.setMockInitialValues({});
  final p = Prefs(await SharedPreferences.getInstance());
  await p.setRecents([const Recent('h', build: 2000)]);
  if (!notify) await p.setNotifyUpdates(false);
  return p;
}

void main() {
  test('notifies once for a newer release and records it', () async {
    final prefs = await _prefs();
    final sent = <String>[];
    expect(await runUpdateCheck(prefs: prefs, client: _client(), notify: (t, b) async => sent.add(t)), isTrue);
    expect(sent, ['OpenDash 0.2.1 is available']);
    expect(prefs.lastNotifiedOpenDash, 2041);
    await runUpdateCheck(prefs: prefs, client: _client(), notify: (t, b) async => sent.add(t));
    expect(sent.length, 1);
  });

  test('notifyUpdates=false never notifies', () async {
    final prefs = await _prefs(notify: false);
    final sent = <String>[];
    expect(await runUpdateCheck(prefs: prefs, client: _client(), notify: (t, b) async => sent.add(t)), isTrue);
    expect(sent, isEmpty);
  });

  test('not newer than installed does not notify', () async {
    final prefs = await _prefs();
    final sent = <String>[];
    await runUpdateCheck(prefs: prefs, client: _client(build: 2000), notify: (t, b) async => sent.add(t));
    expect(sent, isEmpty);
  });
}
