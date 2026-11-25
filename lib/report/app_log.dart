import 'dart:io';

/// This app's own record of what it did: connections, every step of every
/// operation, and what went wrong. It stays on the phone; the rider shares it
/// with a bug report if they choose. Capped, so it never grows without bound.
class AppLog {
  AppLog(this.file, {this.maxBytes = 256 * 1024, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final File file;
  final int maxBytes;
  final DateTime Function() _now;

  void add(String line) {
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('${_now().toUtc().toIso8601String()} $line\n', mode: FileMode.append, flush: true);
      if (file.lengthSync() > maxBytes) _trim();
    } on FileSystemException {
      // A log that can't be written must never break what it records.
    }
  }

  /// Keeps the newest half, starting on a whole line.
  void _trim() {
    final text = file.readAsStringSync();
    var cut = text.length - maxBytes ~/ 2;
    final nl = text.indexOf('\n', cut);
    cut = nl < 0 ? cut : nl + 1;
    file.writeAsStringSync(text.substring(cut), flush: true);
  }

  String read() {
    try {
      return file.existsSync() ? file.readAsStringSync() : '';
    } on FileSystemException {
      return '';
    }
  }
}
