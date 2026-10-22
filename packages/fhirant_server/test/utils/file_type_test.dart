import 'dart:convert';
import 'dart:typed_data';

import 'package:fhirant_server/src/utils/file_type.dart';
import 'package:test/test.dart';

/// Each listed type against bytes that are it and bytes that are not
/// (patterns: WHATWG MIME Sniffing §6.1, §6.2, §7.1, read 2026-10-21; JWS:
/// RFC 7515 §7.1).
void main() {
  Uint8List bytes(List<int> b) => Uint8List.fromList(b);
  Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));
  final pdf = text('%PDF-1.4\n');
  final png = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0]);
  final jpeg = bytes([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10]);
  final gif87 = text('GIF87a');
  final gif89 = text('GIF89a');
  final id3 = text('ID3\u0004');
  // Frame sync, MPEG-1 layer III, 128 kbit/s, 44.1 kHz.
  final mp3Frame = bytes([0xFF, 0xFB, 0x90, 0x00]);

  void accepts(String? type, Uint8List b) =>
      expect(fileTypeRefusal(type, b), isNull, reason: '$type');
  void refuses(String? type, Uint8List b, String says) =>
      expect(fileTypeRefusal(type, b), contains(says), reason: '$type');

  test('each binary type passes its own bytes and refuses another', () {
    final samples = {
      'application/pdf': pdf,
      'image/png': png,
      'image/jpeg': jpeg,
      'image/gif': gif89,
      'audio/mpeg': id3,
    };
    for (final MapEntry(key: type, value: own) in samples.entries) {
      accepts(type, own);
      for (final MapEntry(key: other, value: b) in samples.entries) {
        if (other != type) refuses(type, b, 'is not $type');
      }
    }
    accepts('image/gif', gif87);
    accepts('audio/mpeg', mp3Frame);
  });

  test('a signature cut short or one byte off is refused', () {
    refuses('image/jpeg', mp3Frame, 'is not'); // FF, then not D8 FF
    refuses('image/jpeg', bytes([0xFF, 0xD8]), 'is not');
    refuses('image/png', Uint8List.sublistView(png, 0, 7), 'is not');
    refuses('image/gif', text('GIF88a'), 'is not');
    refuses('application/pdf', text('%PDF'), 'is not');
    refuses('audio/mpeg', text('ID'), 'is not');
  });

  test('an MPEG frame that is not layer III, or uses a reserved rate', () {
    refuses('audio/mpeg', bytes([0xFF, 0xFD, 0x90, 0x00]), 'is not'); // II
    refuses('audio/mpeg', bytes([0xFF, 0xFB, 0xF0, 0x00]), 'is not'); // rate
    refuses('audio/mpeg', bytes([0xFF, 0xFB, 0x9C, 0x00]), 'is not'); // freq
  });

  test('text is UTF-8 with no binary data byte, and not a page', () {
    accepts('text/plain', text('Seen today. Température 38,2 °C.'));
    accepts('text/cql', text("library Example version '1.0'"));
    refuses('text/plain', bytes([0x61, 0x00, 0x62]), 'is not text/plain');
    refuses('text/plain', bytes([0xC3, 0x28]), 'is not text/plain');
    refuses('text/plain', text('\n\t<!DOCTYPE html>'), 'is not text/plain');
    refuses('text/plain', text('<p>Seen today</p>'), 'is not text/plain');
    refuses('text/plain', text('<!-- x -->'), 'is not text/plain');
    // "<PRE" is no row of §7.1's table, so text that starts with it stays
    // text.
    accepts('text/plain', text('<PRE>x'));
  });

  test('JSON and XML types parse', () {
    accepts('application/json', text('{"a": 1}'));
    accepts('application/json-patch+json', text('[]'));
    accepts('application/elm+json', text('{"library": {}}'));
    refuses('application/json', text('{"a": '), 'is not application/json');
    accepts('application/xml', text('<?xml version="1.0"?><a/>'));
    accepts('application/elm+xml', text('<library/>'));
    accepts('application/signature+xml', text('<Signature/>'));
    refuses('application/xml', text('<a>'), 'is not application/xml');
  });

  test('application/jose is a JWS in compact form', () {
    accepts('application/jose', text('eyJhbGciOiJFUzI1NiJ9.e30.c2ln'));
    accepts('application/jose', text('eyJhbGciOiJFUzI1NiJ9..c2ln'));
    refuses('application/jose', text('{"payload": "e30"}'), 'is not');
    refuses('application/jose', text('a.b'), 'is not');
  });

  test('the declared type is read as a media type', () {
    accepts('Image/PNG', png);
    accepts(' image/png ; name="scan.png"', png);
    accepts('text/plain; charset="utf-8"', text('x'));
    accepts('text/plain; charset=US-ASCII', text('x'));
    refuses('text/plain; charset=windows-1252', text('x'), 'only as UTF-8');
    refuses('png', png, 'which this server does not store');
    refuses('', png, 'which this server does not store');
  });

  test('types not on the list are refused, whatever the bytes', () {
    for (final type in const [
      'text/html',
      'application/xhtml+xml',
      'application/xhtml',
      'image/svg+xml',
      'application/zip',
      'application/octet-stream',
      'application/msword',
      'image/jpg',
      'application/dicom',
    ]) {
      refuses(type, text('x'), 'which this server does not store');
    }
  });

  test('an undeclared file is judged by what its bytes show', () {
    accepts(null, pdf);
    accepts(null, png);
    accepts(null, text('a note'));
    accepts(null, text('  <?xml version="1.0"?><a/>'));
    refuses(null, text('<?xml version="1.0"?><a>'), 'is not application/xml');
    refuses(null, text('<html>'), 'declares no type');
    refuses(null, bytes([0x50, 0x4B, 0x03, 0x04, 0x00]), 'declares no type');
  });
}
