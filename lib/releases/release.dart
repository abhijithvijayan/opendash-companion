import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const kUserAgent = 'OpenDashCompanion';
const _notesCap = 8000;

class Release {
  const Release({
    required this.version,
    required this.build,
    required this.sha256,
    required this.apkUrl,
    required this.apkName,
    this.notes = '',
    this.published = '',
    this.url = '',
  });

  final String version;
  final int build;
  final String sha256;
  final String apkUrl;
  final String apkName;
  final String notes;

  /// `YYYY-MM-DD`.
  final String published;
  final String url;
}

sealed class ReleaseCheck {
  const ReleaseCheck();
}

class ReleaseFound extends ReleaseCheck {
  const ReleaseFound(this.release);
  final Release release;
}

/// There is no usable release (none published, or its assets are missing).
class ReleaseMissing extends ReleaseCheck {
  const ReleaseMissing();
}

class CheckFailed extends ReleaseCheck {
  const CheckFailed(this.why);
  final String why;
}

const _headers = {'User-Agent': kUserAgent, 'Accept': 'application/vnd.github+json'};

Future<ReleaseCheck> fetchLatest(http.Client client, {required String repo, required String jsonAsset}) async {
  try {
    final res = await client
        .get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return const ReleaseMissing();
    if (res.statusCode != 200) return CheckFailed('GitHub answered ${res.statusCode}.');
    final gh = jsonDecode(res.body);
    if (gh is! Map) return const CheckFailed('GitHub sent something unexpected.');
    final assets = {
      for (final a in (gh['assets'] as List? ?? const []))
        if (a is Map && a['name'] is String && a['browser_download_url'] is String) a['name'] as String: a['browser_download_url'] as String,
    };
    final jsonUrl = assets[jsonAsset];
    if (jsonUrl == null) return const ReleaseMissing();
    final jr = await client.get(Uri.parse(jsonUrl), headers: {'User-Agent': kUserAgent}).timeout(const Duration(seconds: 20));
    if (jr.statusCode != 200) return CheckFailed('The release description could not be downloaded (${jr.statusCode}).');
    final j = jsonDecode(jr.body);
    if (j is! Map || j['build'] is! int || j['apk'] is! String || j['sha256'] is! String) return const ReleaseMissing();
    final apkUrl = assets[j['apk']];
    if (apkUrl == null) return const ReleaseMissing();
    final body = gh['body'] is String ? (gh['body'] as String).replaceAll('\r\n', '\n') : '';
    final published = gh['published_at'] is String ? gh['published_at'] as String : '';
    return ReleaseFound(Release(
      version: j['version'] is String ? j['version'] as String : '${j['build']}',
      build: j['build'] as int,
      sha256: (j['sha256'] as String).toLowerCase(),
      apkUrl: apkUrl,
      apkName: j['apk'] as String,
      notes: body.length > _notesCap ? body.substring(0, _notesCap) : body,
      published: published.length >= 10 ? published.substring(0, 10) : published,
      url: gh['html_url'] is String ? gh['html_url'] as String : '',
    ));
  } on TimeoutException {
    return const CheckFailed('GitHub did not answer in time.');
  } on SocketException {
    return const CheckFailed('No internet connection.');
  } on http.ClientException {
    return const CheckFailed('No internet connection.');
  } on FormatException {
    return const CheckFailed('GitHub sent something unexpected.');
  }
}

/// [min_build] is ignored: it bounds OpenDash's own updater, not an adb install.
bool offerUpdate(Release r, {required int? installedBuild, int skippedBuild = 0}) {
  if (installedBuild == null) return true;
  return r.build > installedBuild && r.build != skippedBuild;
}

/// Throws [TimeoutException] when nothing arrives for [idleTimeout]: a
/// hotspot whose upstream died keeps the socket open and sends nothing.
Future<String> download(http.Client client, Release r, Directory dir, void Function(int sent, int total) onProgress,
    {Duration idleTimeout = const Duration(seconds: 30)}) async {
  await dir.create(recursive: true);
  final req = http.Request('GET', Uri.parse(r.apkUrl))..headers['User-Agent'] = kUserAgent;
  final res = await client.send(req).timeout(idleTimeout);
  if (res.statusCode != 200) throw HttpException('Download failed (${res.statusCode}).');
  final total = res.contentLength ?? 0;
  final file = File('${dir.path}/${r.apkName.replaceAll('/', '_')}');
  final sink = file.openWrite();
  var sent = 0;
  try {
    await for (final chunk in res.stream.timeout(idleTimeout)) {
      sink.add(chunk);
      sent += chunk.length;
      onProgress(sent, total);
    }
  } finally {
    await sink.close();
  }
  return file.path;
}
