import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

/// Why a file's bytes may not be stored under the type it declares, or
/// `null` when they may (OWASP ASVS 5.0.0 V5.2.2: "Verify that when the
/// application accepts a file, either on its own or within an archive such
/// as a zip file, it checks if the file extension matches an expected file
/// extension and validates that the contents correspond to the type
/// represented by the extension"; asvs-5.0.json, read 2026-10-21).
///
/// [declared] is the file's own type (Binary.contentType,
/// Attachment.contentType, Signature.sigFormat), or `null` where its element
/// has no place for one (an extension's or a parameter's valueBase64Binary)
/// or left it out. Then the type is the one the bytes show, by the WHATWG
/// MIME Sniffing Standard's rules for a resource with an unknown type
/// (§7.1, with its sniff-scriptable flag set, so HTML is recognised and
/// refused; read 2026-10-21), and it must be one on the list as well.
String? fileTypeRefusal(String? declared, Uint8List bytes) {
  if (declared == null) {
    final sniffed = _sniff(bytes);
    if (sniffed == null || !_checks.containsKey(sniffed)) {
      return 'declares no type, and its bytes are not a type this server '
          'stores (${_listed()})';
    }
    return _checks[sniffed]!(bytes) ? null : _mismatch(sniffed);
  }
  final type = _MediaType.parse(declared);
  final check = type == null ? null : _checks[type.essence];
  if (type == null || check == null) {
    return 'is declared $declared, which this server does not store '
        '(${_listed()})';
  }
  final charset = type.charset;
  if (charset != null &&
      _text.contains(type.essence) &&
      !const {'utf-8', 'us-ascii'}.contains(charset)) {
    return 'is declared $declared; this server stores text only as UTF-8';
  }
  return check(bytes) ? null : _mismatch(type.essence);
}

String _mismatch(String type) => 'is not $type: its bytes do not match the '
    'type';

String _listed() => 'it stores ${_checks.keys.join(', ')}';

/// The types a file may have here, each with the check its bytes must pass.
///
/// The list is what the published examples carry as files
/// (tool/review_2026-10-17/content_type_census.tsv: the 3,022 R4B examples,
/// US Core 3.1.0 and every package in ~/.fhir/packages), what Signature's
/// definition names (R4B profiles-types.json, Signature.sigFormat:
/// "application/signature+xml for X ML DigSig, application/jose for JWS,
/// and image/* for a graphical image of a signature"), and what fhirant
/// itself reads (JSON Patch in a Bundle's Binary; CQL and ELM in
/// Library.content). HTML and XHTML files are left off, as Grey decided
/// 2026-10-21, because they can carry script; so are office documents and
/// archives, until someone needs one.
///
/// The image, audio and PDF checks are the byte patterns of the WHATWG MIME
/// Sniffing Standard (§6.1 image, §6.2 audio, §7.1 PDF).
final Map<String, bool Function(Uint8List)> _checks = {
  'application/pdf': (b) => _starts(b, const [0x25, 0x50, 0x44, 0x46, 0x2D]),
  'image/jpeg': (b) => _starts(b, const [0xFF, 0xD8, 0xFF]),
  'image/png': (b) =>
      _starts(b, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
  'image/gif': (b) =>
      _starts(b, const [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
      _starts(b, const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]),
  'audio/mpeg': (b) => _starts(b, const [0x49, 0x44, 0x33]) || _mp3Header(b),
  'text/plain': _isText,
  'text/cql': _isText,
  'application/json': _isJson,
  'application/elm+json': _isJson,
  'application/json-patch+json': _isJson,
  'application/xml': _isXml,
  'application/elm+xml': _isXml,
  'application/signature+xml': _isXml,
  'application/jose': _isJwsCompact,
};

/// The types whose bytes are text, for the charset rule.
const _text = {
  'text/plain',
  'text/cql',
  'application/json',
  'application/elm+json',
  'application/json-patch+json',
  'application/xml',
  'application/elm+xml',
  'application/signature+xml',
  'application/jose',
};

bool _starts(Uint8List b, List<int> pattern) {
  if (b.length < pattern.length) return false;
  for (var i = 0; i < pattern.length; i++) {
    if (b[i] != pattern[i]) return false;
  }
  return true;
}

/// WHATWG MIME Sniffing §6.2.3, "match an mp3 header" at the first byte: a
/// frame sync, an MPEG layer III frame, and a bit rate and sample rate that
/// are not the reserved values. The section's next step (a second header
/// one frame on) is not taken: as written it compares the frame size with
/// `s - length`, which is negative at the first frame, so no file would
/// pass.
bool _mp3Header(Uint8List b) {
  if (b.length < 4) return false;
  if (b[0] != 0xFF || b[1] & 0xE0 != 0xE0) return false;
  final layer = (b[1] & 0x06) >> 1;
  if (layer != 1) return false; // 4 - layer is 3: layer III
  if ((b[2] & 0xF0) >> 4 == 15) return false;
  if ((b[2] & 0x0C) >> 2 == 3) return false;
  return true;
}

/// UTF-8 with no binary data byte (WHATWG MIME Sniffing §3: 0x00-0x08,
/// 0x0B, 0x0E-0x1A, 0x1C-0x1F), and not HTML by §7.1's scriptable patterns:
/// a file called text that a browser would read as a page is refused.
bool _isText(Uint8List b) {
  for (final byte in b) {
    if (_isBinaryDataByte(byte)) return false;
  }
  try {
    utf8.decode(b);
  } on FormatException {
    return false;
  }
  return !_looksLikeHtml(b);
}

bool _isBinaryDataByte(int byte) =>
    byte <= 0x08 ||
    byte == 0x0B ||
    (byte >= 0x0E && byte <= 0x1A) ||
    (byte >= 0x1C && byte <= 0x1F);

bool _isJson(Uint8List b) {
  if (!_isText(b)) return false;
  try {
    jsonDecode(utf8.decode(b));
    return true;
  } on FormatException {
    return false;
  }
}

bool _isXml(Uint8List b) {
  if (!_isText(b)) return false;
  try {
    XmlDocument.parse(utf8.decode(b));
    return true;
  } on XmlException {
    return false;
  }
}

/// RFC 7515 §7.1, JWS Compact Serialization: three BASE64URL parts joined by
/// periods; the payload may be empty (Appendix F, detached content). §9.2.1
/// registers application/jose for this form.
bool _isJwsCompact(Uint8List b) {
  if (!_isText(b)) return false;
  return _jwsCompact.hasMatch(utf8.decode(b).trim());
}

final _jwsCompact = RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+$');

/// WHATWG MIME Sniffing §7.1's scriptable rows: after any leading whitespace
/// byte, `<!DOCTYPE HTML`, one of the listed tag names (case-insensitive)
/// or `<!--`, followed by a tag-terminating byte (space or `>`).
bool _looksLikeHtml(Uint8List b) {
  var i = 0;
  while (i < b.length && _isWhitespaceByte(b[i])) {
    i++;
  }
  final rest = latin1
      .decode(b.sublist(i, b.length < i + 16 ? b.length : i + 16))
      .toUpperCase();
  for (final opener in _htmlOpeners) {
    if (rest.length > opener.length &&
        rest.startsWith(opener) &&
        _isTagTerminating(rest.codeUnitAt(opener.length))) {
      return true;
    }
  }
  return false;
}

const _htmlOpeners = [
  '<!DOCTYPE HTML',
  '<HTML',
  '<HEAD',
  '<SCRIPT',
  '<IFRAME',
  '<H1',
  '<DIV',
  '<FONT',
  '<TABLE',
  '<A',
  '<STYLE',
  '<TITLE',
  '<B',
  '<BODY',
  '<BR',
  '<P',
  '<!--',
];

/// WHATWG MIME Sniffing §3.
bool _isWhitespaceByte(int b) =>
    b == 0x09 || b == 0x0A || b == 0x0C || b == 0x0D || b == 0x20;

/// WHATWG MIME Sniffing §3: 0x20 (SP) or 0x3E (">").
bool _isTagTerminating(int b) => b == 0x20 || b == 0x3E;

/// The type the bytes of an undeclared file show, by WHATWG MIME Sniffing
/// §7.1 with the sniff-scriptable flag set: HTML (refused), XML, PDF, the
/// image and audio patterns, and text when there is no binary data byte.
/// `null` for anything else.
String? _sniff(Uint8List b) {
  if (_looksLikeHtml(b)) return 'text/html';
  var i = 0;
  while (i < b.length && _isWhitespaceByte(b[i])) {
    i++;
  }
  const xmlDeclaration = [0x3C, 0x3F, 0x78, 0x6D, 0x6C]; // "<?xml"
  if (_starts(Uint8List.sublistView(b, i), xmlDeclaration)) {
    return 'application/xml';
  }
  for (final type in const [
    'application/pdf',
    'image/gif',
    'image/png',
    'image/jpeg',
    'audio/mpeg',
  ]) {
    if (_checks[type]!(b)) return type;
  }
  if (!b.any(_isBinaryDataByte)) return 'text/plain';
  return null;
}

/// A media type split as RFC 9110 §8.3.1 writes it: `type/subtype` and
/// `;`-separated parameters, the type and parameter names case-insensitive.
class _MediaType {
  _MediaType(this.essence, this.charset);

  final String essence;
  final String? charset;

  static _MediaType? parse(String value) {
    final parts = value.split(';');
    final essence = parts.first.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$').hasMatch(essence)) {
      return null;
    }
    String? charset;
    for (final p in parts.skip(1)) {
      final eq = p.indexOf('=');
      if (eq < 0) continue;
      if (p.substring(0, eq).trim().toLowerCase() == 'charset') {
        charset = p.substring(eq + 1).trim().replaceAll('"', '').toLowerCase();
      }
    }
    return _MediaType(essence, charset);
  }
}
