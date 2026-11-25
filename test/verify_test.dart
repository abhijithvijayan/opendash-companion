import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/adb/adb_api.g.dart';
import 'package:opendash_companion/releases/verify.dart';

const pin = '25f012a33b86ab2365b480b594998a131fa8e0edc3768c9e258440f98d4ba7ee';
ApkInfo info({String pkg = 'in.abhijithvijayan.opendash', String cert = pin}) =>
    ApkInfo(packageName: pkg, versionName: '0.2.1', versionCode: 2041, certSha256: [cert]);

void main() {
  test('downloaded, all matching → Official', () {
    expect(verifyApk(fileSha256: 'aa', expectedSha256: 'aa', info: info(), pinnedCert: pin, expectedPackage: 'in.abhijithvijayan.opendash'),
        isA<Official>());
  });
  test('downloaded, checksum mismatch → Rejected', () {
    expect(verifyApk(fileSha256: 'aa', expectedSha256: 'bb', info: info(), pinnedCert: pin, expectedPackage: 'in.abhijithvijayan.opendash'),
        isA<Rejected>());
  });
  test('downloaded, other cert → Rejected', () {
    expect(verifyApk(fileSha256: 'aa', expectedSha256: 'aa', info: info(cert: 'ff'), pinnedCert: pin, expectedPackage: 'in.abhijithvijayan.opendash'),
        isA<Rejected>());
  });
  test('not an app → Rejected', () {
    expect(verifyApk(fileSha256: 'aa', info: null, pinnedCert: pin, expectedPackage: 'in.abhijithvijayan.opendash'), isA<Rejected>());
  });
  test('picked file, other package → Rejected', () {
    expect(verifyApk(fileSha256: 'aa', info: info(pkg: 'com.x'), pinnedCert: pin, expectedPackage: 'in.abhijithvijayan.opendash'),
        isA<Rejected>());
  });
  test('picked file, other cert → Unofficial', () {
    expect(verifyApk(fileSha256: 'aa', info: info(cert: 'ff'), pinnedCert: pin, expectedPackage: 'in.abhijithvijayan.opendash'),
        isA<Unofficial>());
  });
  test('picked file, official cert → Official', () {
    expect(verifyApk(fileSha256: 'aa', info: info(), pinnedCert: pin, expectedPackage: 'in.abhijithvijayan.opendash'), isA<Official>());
  });
  test('empty pin never matches', () {
    expect(verifyApk(fileSha256: 'aa', expectedSha256: 'aa', info: info(cert: ''), pinnedCert: '', expectedPackage: 'in.abhijithvijayan.opendash'),
        isA<Rejected>());
  });
  test('sha256OfFile', () async {
    final f = File('${(await Directory.systemTemp.createTemp()).path}/a')..writeAsStringSync('abc');
    expect(await sha256OfFile(f.path), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
}
