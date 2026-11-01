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
    if (!_checks[sniffed]!(bytes)) return _mismatch(sniffed);
    return _imageRefusal(sniffed, bytes);
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
  if (!check(bytes)) return _mismatch(type.essence);
  return _imageRefusal(type.essence, bytes);
}

/// The most pixels an image may have here (OWASP ASVS 5.0.0 V5.2.6, level 3:
/// "Verify that the application rejects uploaded images with a pixel size
/// larger than the maximum allowed, to prevent pixel flood attacks"; read in
/// OWASP/ASVS v5.0.0 0x14-V5-File-Handling.md, 2026-11-01). ASVS sets no
/// number. This is Pillow's `MAX_IMAGE_PIXELS`, "around a quarter gigabyte
/// for a 24-bit (3 bpp) image", above which Pillow warns that the image
/// "could be decompression bomb DOS attack" (and refuses at twice it;
/// python-pillow/Pillow src/PIL/Image.py, read 2026-11-01). fhirant never
/// decodes an image; a client that downloads one may.
const int maxImagePixels = 1024 * 1024 * 1024 ~/ 4 ~/ 3;

/// Why the image [type] in [bytes] may not be stored, or `null`: one whose
/// size its header does not give, or larger than [maxImagePixels]. Only the
/// headers are read, never the pixels. Anything but PNG, JPEG and GIF is
/// `null`.
String? _imageRefusal(String type, Uint8List bytes) {
  final List<(int, int)>? sizes;
  switch (type) {
    case 'image/png':
      sizes = _pngSize(bytes);
    case 'image/gif':
      sizes = _gifSizes(bytes);
    case 'image/jpeg':
      sizes = _jpegSizes(bytes);
    default:
      return null;
  }
  if (sizes == null || sizes.isEmpty) {
    return 'is $type, but its size could not be read from its header';
  }
  for (final (width, height) in sizes) {
    if (width * height > maxImagePixels) {
      return 'is a $width x $height $type image, ${width * height} pixels, '
          'more than the $maxImagePixels this server stores';
    }
  }
  return null;
}

/// W3C PNG (Third Edition) 11.2.1: "The IHDR chunk shall be the first chunk
/// in the PNG datastream", its Width and Height four-byte unsigned integers
/// at offsets 16 and 20 (after the 8-byte signature and the chunk's length
/// and type), and "Zero is an invalid value."
List<(int, int)>? _pngSize(Uint8List b) {
  if (b.length < 24) return null;
  const ihdr = [0x49, 0x48, 0x44, 0x52];
  for (var i = 0; i < 4; i++) {
    if (b[12 + i] != ihdr[i]) return null;
  }
  final data = ByteData.sublistView(b);
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  if (width == 0 || height == 0) return null;
  return [(width, height)];
}

/// GIF89a (W3C spec-gif89a.txt): the Logical Screen Descriptor's width and
/// height (§18, little-endian at offsets 6 and 8), and every Image
/// Descriptor's (§20, separator 0x2C) up to the Trailer (§27, 0x3B). A
/// colour table is "3 x 2^(Size of Global Color Table+1)" bytes; extensions
/// (§23, 0x21) and image data (§22) are data sub-blocks ended by a
/// zero-length block (§16).
List<(int, int)>? _gifSizes(Uint8List b) {
  if (b.length < 13) return null;
  int u16(int at) => b[at] | b[at + 1] << 8;
  final sizes = [(u16(6), u16(8))];
  var i = 13;
  if (b[10] & 0x80 != 0) i += 3 * (1 << ((b[10] & 0x07) + 1));
  bool skipSubBlocks() {
    while (i < b.length) {
      final size = b[i++];
      if (size == 0) return true;
      i += size;
    }
    return false;
  }

  while (i < b.length) {
    final block = b[i++];
    if (block == 0x3B) return sizes;
    if (block == 0x21) {
      i++; // the extension's label
      if (!skipSubBlocks()) return null;
    } else if (block == 0x2C) {
      if (i + 9 > b.length) return null;
      sizes.add((u16(i + 4), u16(i + 6)));
      final flags = b[i + 8];
      i += 9;
      if (flags & 0x80 != 0) i += 3 * (1 << ((flags & 0x07) + 1));
      i++; // LZW Minimum Code Size
      if (!skipSubBlocks()) return null;
    } else {
      return null;
    }
  }
  return null;
}

/// ITU-T T.81 (W3C itu-t81.pdf): the frame header of every Start Of Frame
/// marker (Table B.1: X'FFC0'-X'FFCF' but DHT C4, JPG C8 and DAC CC) and of
/// DHP (X'FFDE', hierarchical), whose Y ("Number of lines") and X ("Number
/// of samples per line") follow Lf and P (B.2.2, Figure B.3). "Value 0
/// indicates that the number of lines shall be defined by the DNL marker",
/// which a header alone cannot bound, so it is not read. Markers without a
/// length (SOI, EOI, RSTm, TEM) are stepped over, and the entropy-coded data
/// after a scan header up to the next marker that is not X'FF00' stuffing or
/// RSTm.
List<(int, int)>? _jpegSizes(Uint8List b) {
  final sizes = <(int, int)>[];
  int u16(int at) => b[at] << 8 | b[at + 1];
  var i = 2; // after SOI
  while (i + 1 < b.length) {
    if (b[i] != 0xFF) return null;
    var marker = b[i + 1];
    while (marker == 0xFF && i + 2 < b.length) {
      i++; // fill bytes (B.1.1.2)
      marker = b[i + 1];
    }
    i += 2;
    if (marker == 0xD9) return sizes; // EOI
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) continue;
    if (i + 2 > b.length) return null;
    final length = u16(i);
    final isFrame = (marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC) ||
        marker == 0xDE;
    if (isFrame) {
      if (i + 7 > b.length) return null;
      final lines = u16(i + 3);
      final samples = u16(i + 5);
      if (lines == 0 || samples == 0) return null;
      sizes.add((samples, lines));
    }
    i += length;
    if (marker == 0xDA) {
      // SOS: entropy-coded data runs to the next real marker.
      while (i + 1 < b.length &&
          !(b[i] == 0xFF &&
              b[i + 1] != 0x00 &&
              !(b[i + 1] >= 0xD0 && b[i + 1] <= 0xD7))) {
        i++;
      }
    }
  }
  return sizes.isEmpty ? null : sizes;
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
