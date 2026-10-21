# Draft issue for dart-lang/sdk (not filed; Grey files it)

Scripts and outputs: `packages/fhirant_server/tool/review_2026-10-17/
dart_sdk_framing/` (`repro.dart`, `headers.dart`); the full probe is
`smuggling_probe.dart` / `.tsv` beside it.

Open issues searched 2026-10-21 (`gh search issues --repo dart-lang/sdk`):
"Transfer-Encoding Content-Length smuggling", "request smuggling
HttpServer", "Content-Length Transfer-Encoding both". Found #46670, #52494
and #48822, all closed and all about responses received by the client. No
issue about the server side was found.

---

**Title:** HttpServer keeps the connection open after a request with both
Content-Length and Transfer-Encoding, and drops malformed requests without
a 400

**Dart SDK:** 3.13.0 (stable), linux_x64

**What happens**

1. A request with both `Content-Length` and `Transfer-Encoding: chunked` is
   framed by Transfer-Encoding, and the connection stays open. The bytes
   after the chunked body are then parsed and served as a second request.
   RFC 9112 section 6.1: "A server MAY reject a request that contains both
   Content-Length and Transfer-Encoding or process such a request in
   accordance with the Transfer-Encoding alone. Regardless, the server MUST
   close the connection after responding to such a request to avoid the
   potential attacks."
2. When a request has an invalid framing (Transfer-Encoding without chunked
   last, two different Content-Length values, whitespace before a field's
   colon), the server closes the socket and sends no response. RFC 9112
   requires a 400 first:
   - 6.3 item 4: "the server MUST respond with the 400 (Bad Request) status
     code and then close the connection."
   - 6.3 item 5: "the server MUST respond with a 400 (Bad Request) status
     code and then close the connection."
   - 5.1: "A server MUST reject, with a response status code of 400 (Bad
     Request), any received request message that contains whitespace
     between a header field name and colon."

In the source (`sdk/lib/_http/http_parser.dart`, 3.13.0), `_HttpParser`
sets `_contentLength = false` when it sees Transfer-Encoding and does not
touch `_persistentConnection`; `_reportHttpError` cancels the socket
subscription without writing a response. Related history, from comments on
#52494 and #48822: change 180485 made CL+TE an error as a security fix, and
change 327703 later dealt with responses carrying both. We have not read
either change.

**Reproduction** (plain dart:io, no packages)

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((req) async {
    await req.drain<void>();
    req.response.write('served ${req.uri}');
    await req.response.close();
  });
  const tail = 'GET /second HTTP/1.1\r\nHost: x\r\n\r\n';
  final cases = {
    'CL + TE: chunked': 'POST /first HTTP/1.1\r\nHost: x\r\n'
        'Content-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n$tail',
    'TE: gzip (chunked not final)': 'POST /first HTTP/1.1\r\nHost: x\r\n'
        'Transfer-Encoding: gzip\r\n\r\n$tail',
    'two Content-Length values': 'POST /first HTTP/1.1\r\nHost: x\r\n'
        'Content-Length: 2\r\nContent-Length: 40\r\n\r\n{}$tail',
    'space before colon': 'POST /first HTTP/1.1\r\nHost: x\r\n'
        'Content-Length : 2\r\n\r\n{}$tail',
  };
  for (final MapEntry(key: name, value: request) in cases.entries) {
    final socket = await Socket.connect('127.0.0.1', server.port);
    final got = StringBuffer();
    final done = Completer<bool>();
    socket
      ..listen(
        (b) => got.write(latin1.decode(b)),
        onDone: () => done.isCompleted ? null : done.complete(true),
      )
      ..add(latin1.encode(request));
    final closed = await done.future
        .timeout(const Duration(seconds: 3), onTimeout: () => false);
    socket.destroy();
    final statuses =
        RegExp(r'HTTP/1\.1 \d{3}').allMatches('$got').map((m) => m[0]).toList();
    stdout.writeln('$name: responses=$statuses closed=$closed '
        'second-served=${'$got'.contains('served /second')}');
  }
  await server.close(force: true);
}
```

Output on 3.13.0:

```
CL + TE: chunked: responses=[HTTP/1.1 200, HTTP/1.1 200] closed=false second-served=true
TE: gzip (chunked not final): responses=[] closed=true second-served=false
two Content-Length values: responses=[] closed=true second-served=false
space before colon: responses=[] closed=true second-served=false
```

**Expected:** the first case answers once and closes the connection (it
may answer 400). The other three answer 400, then close.

**Why it matters:** behind a front end that frames by Content-Length, the
first case is the classic CL.TE request-smuggling shape, and an
application cannot work around it. For the first request above, the
handler sees `content-length=null transfer-encoding=chunked
contentLength=-1 persistentConnection=true` (measured on 3.13.0): exactly
what an ordinary chunked request looks like, so it cannot know to close
the connection.
