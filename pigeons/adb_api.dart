import 'package:pigeon/pigeon.dart';

// The phone-side adb layer: Kotlin connects, runs a line, streams an install
// and inspects an APK. Every rule about what to run lives in Dart.
//
//   dart run pigeon --input pigeons/adb_api.dart
@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/adb/adb_api.g.dart',
  kotlinOut: 'android/app/src/main/kotlin/in/abhijithvijayan/opendash/companion/AdbApi.g.kt',
  kotlinOptions: KotlinOptions(package: '`in`.abhijithvijayan.opendash.companion', errorClassName: 'AdbApiError'),
  dartPackageName: 'opendash_companion',
))
class ConnectReply {
  ConnectReply(this.outcome, this.detail);

  /// 'ok', 'unauthorized' or 'unreachable'.
  String outcome;
  String? detail;
}

class ProvisionReply {
  ProvisionReply(this.outcome, this.detail);

  /// 'ok', 'unimplemented', 'unreachable' or 'failed'.
  String outcome;
  String? detail;
}

class ShellReply {
  ShellReply(this.output, this.exitCode);
  String output;
  int exitCode;
}

class ApkInfo {
  ApkInfo(this.packageName, this.versionName, this.versionCode, this.certSha256);
  String packageName;
  String versionName;
  int versionCode;
  List<String> certSha256;
}

@HostApi()
abstract class AdbHostApi {
  @async
  ConnectReply connect(String host, int port);

  /// Asks the scooter's gRPC service to accept this phone's adb key.
  @async
  ProvisionReply provision(String host);

  @async
  ShellReply shell(String command);

  /// Streams the APK to `cmd package install`. Answers the installer's text
  /// ("Success") or fails with it.
  @async
  String install(String apkPath, List<String> options);

  /// Copies a file to the head unit. Progress arrives as installProgress.
  @async
  void push(String localPath, String remotePath);

  /// Copies a file from the head unit to the phone.
  @async
  void pull(String remotePath, String localPath);

  void disconnect();

  /// This phone's adb public key, in the format `adb_keys` holds.
  String publicKey();

  ApkInfo? inspectApk(String path);

  /// Whether Android lets this app hand an APK to the phone's installer.
  bool canInstallOnPhone();
  void openInstallPermission();
  void installOnPhone(String apkPath);

  /// The app's private files directory, kept across updates.
  String filesDir();

  /// Opens Android's share sheet for a file in the app's cache.
  void shareFile(String path, String mimeType, String subject);
}

@FlutterApi()
abstract class AdbEvents {
  void installProgress(int sent, int total);
}
