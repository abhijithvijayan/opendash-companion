import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opendash_companion/releases/release.dart';

const _latest = 'https://api.github.com/repos/abhijithvijayan/opendash/releases/latest';

Map<String, Object?> _github({bool withJson = true, bool withApk = true}) => {
      'tag_name': 'v0.2.1',
      'html_url': 'https://github.com/abhijithvijayan/opendash/releases/tag/v0.2.1',
      'published_at': '2026-11-24T10:00:00Z',
      'body': 'Faster gauges.\n\n- Fixes the clock.',
      'assets': [
        if (withJson) {'name': 'opendash-release.json', 'browser_download_url': 'https://dl/opendash-release.json'},
        if (withApk) {'name': 'opendash-0.2.1.apk', 'browser_download_url': 'https://dl/opendash-0.2.1.apk'},
      ],
    };

const _json = {'version': '0.2.1', 'build': 2041, 'apk': 'opendash-0.2.1.apk', 'sha256': 'ABCDEF0123', 'git_sha': 'x', 'min_build': 0};

MockClient _client({Map<String, Object?>? github, int status = 200, List<http.Request>? seen}) => MockClient((req) async {
      seen?.add(req);
      if (req.url.toString() == _latest) return http.Response(jsonEncode(github ?? _github()), status);
      if (req.url.toString() == 'https://dl/opendash-release.json') return http.Response(jsonEncode(_json), 200);
      return http.Response('nope', 404);
    });

void main() {
  test('finds the release from its json asset', () async {
    final seen = <http.Request>[];
    final r = await fetchLatest(_client(seen: seen), repo: 'abhijithvijayan/opendash', jsonAsset: 'opendash-release.json');
    final rel = (r as ReleaseFound).release;
    expect(rel.version, '0.2.1');
    expect(rel.build, 2041);
    expect(rel.sha256, 'abcdef0123');
    expect(rel.apkUrl, 'https://dl/opendash-0.2.1.apk');
    expect(rel.apkName, 'opendash-0.2.1.apk');
    expect(rel.notes, 'Faster gauges.\n\n- Fixes the clock.');
    expect(rel.published, '2026-11-24');
    expect(seen.first.headers['User-Agent'], 'OpenDashCompanion');
    expect(seen.first.url.query, isEmpty);
  });

  test('missing assets → ReleaseMissing', () async {
    expect(await fetchLatest(_client(github: _github(withJson: false)), repo: 'abhijithvijayan/opendash', jsonAsset: 'opendash-release.json'),
        isA<ReleaseMissing>());
    expect(await fetchLatest(_client(github: _github(withApk: false)), repo: 'abhijithvijayan/opendash', jsonAsset: 'opendash-release.json'),
        isA<ReleaseMissing>());
  });

  test('no releases (404) → ReleaseMissing', () async {
    expect(await fetchLatest(_client(status: 404), repo: 'abhijithvijayan/opendash', jsonAsset: 'opendash-release.json'), isA<ReleaseMissing>());
  });

  test('fetch failure is a CheckFailed, not a throw', () async {
    final offline = MockClient((_) async => throw const SocketException('Failed host lookup'));
    expect(await fetchLatest(offline, repo: 'abhijithvijayan/opendash', jsonAsset: 'opendash-release.json'), isA<CheckFailed>());
    expect(await fetchLatest(_client(status: 403), repo: 'abhijithvijayan/opendash', jsonAsset: 'opendash-release.json'), isA<CheckFailed>());
  });

  test('Windows line endings in the notes are normalised', () async {
    final g = _github()..['body'] = 'One.\r\n\r\n- Two.';
    final rel = ((await fetchLatest(_client(github: g), repo: 'abhijithvijayan/opendash', jsonAsset: 'opendash-release.json')) as ReleaseFound).release;
    expect(rel.notes, 'One.\n\n- Two.');
  });

  test('notes are capped', () async {
    final g = _github()..['body'] = 'x' * 20000;
    final rel = ((await fetchLatest(_client(github: g), repo: 'abhijithvijayan/opendash', jsonAsset: 'opendash-release.json')) as ReleaseFound).release;
    expect(rel.notes.length, 8000);
  });

  group('offerUpdate', () {
    const rel = Release(version: '0.2.1', build: 2041, sha256: 'a', apkUrl: 'u', apkName: 'n');
    test('nothing installed → offered', () => expect(offerUpdate(rel, installedBuild: null), isTrue));
    test('newer → offered', () => expect(offerUpdate(rel, installedBuild: 2040), isTrue));
    test('same → not offered', () => expect(offerUpdate(rel, installedBuild: 2041), isFalse));
    test('skipped → not offered', () => expect(offerUpdate(rel, installedBuild: 2000, skippedBuild: 2041), isFalse));
  });

  test('download writes the file and reports progress', () async {
    final dir = await Directory.systemTemp.createTemp('dl');
    final client = MockClient((req) async => http.Response.bytes(List.filled(1000, 7), 200, headers: {'content-length': '1000'}));
    final progress = <int>[];
    const rel = Release(version: '0.2.1', build: 2041, sha256: 'a', apkUrl: 'https://dl/opendash-0.2.1.apk', apkName: 'opendash-0.2.1.apk');
    final path = await download(client, rel, dir, (sent, total) => progress.add(sent));
    expect(File(path).lengthSync(), 1000);
    expect(path.endsWith('opendash-0.2.1.apk'), isTrue);
    expect(progress.last, 1000);
  });

  test('a download that stops sending times out instead of hanging', () async {
    final dir = await Directory.systemTemp.createTemp('dl');
    final stalled = StreamController<List<int>>();
    final client = MockClient.streaming((req, body) async {
      stalled.add([1, 2, 3]);
      return http.StreamedResponse(stalled.stream, 200, contentLength: 1000);
    });
    const rel = Release(version: '0.2.1', build: 2041, sha256: 'a', apkUrl: 'https://dl/x.apk', apkName: 'x.apk');
    await expectLater(download(client, rel, dir, (_, _) {}, idleTimeout: const Duration(milliseconds: 100)), throwsA(isA<TimeoutException>()));
  });
}
