#!/usr/bin/env python3
"""Find catch blocks that answer one status for the client's input AND the
server's own work.

For each `try { ... } catch (...) { ... }` in lib/src (a plain `catch`, no
`on Type`), record: does the try block parse client input (readAsString,
jsonDecode, fromJson, fromJsonString, Uri.splitQueryString)? does it call
the store (dbInterface., db., fhirDao, dbService)? what status does the
catch answer (statusCode: N, Response(N, Response.ok, 4xx helper names)?

A "mixed" site is one where the try does both and the catch answers with
one status. The create and patch handlers were that shape (PR #3): a store
failure came back as the client's 400.

Writes one TSV row per site as it goes.
"""
import pathlib
import re
import sys

PARSE = re.compile(r"readAsString|jsonDecode|fromJson(String)?\(|splitQueryString|base64Decode|loadYaml")
STORE = re.compile(r"\bdbInterface\.|\bdb\.|fhirDao|dbService\.|\.saveResource|\.search\(|getResource\b")
STATUS = re.compile(r"statusCode:\s*(\d{3})|Response\(\s*(\d{3})|Response\.(ok|notFound|forbidden|badRequest|internalServerError)|_validationErrorResponse|_errorResponse\(|_outcome\(\s*(\d{3})|unauthorized\(|forbidden\(")

def blocks(src):
    """Yield (line, try_body, catch_head, catch_body) for plain catch blocks."""
    i = 0
    while True:
        m = re.search(r"\btry\s*\{", src[i:])
        if not m:
            return
        start = i + m.end()
        depth, j = 1, start
        while depth and j < len(src):
            depth += {'{': 1, '}': -1}.get(src[j], 0)
            j += 1
        try_body = src[start:j-1]
        rest = src[j:]
        # skip `on X catch` clauses, look for a plain catch or the end
        k = 0
        catch = None
        while True:
            m2 = re.match(r"\s*(on\s+[\w.<>?]+\s*(catch\s*\([^)]*\))?|catch\s*\([^)]*\))\s*\{", rest[k:])
            if not m2:
                break
            head = m2.group(1)
            bstart = k + m2.end()
            depth, b = 1, bstart
            while depth and b < len(rest):
                depth += {'{': 1, '}': -1}.get(rest[b], 0)
                b += 1
            body = rest[bstart:b-1]
            if head.startswith('catch'):
                catch = (head, body)
            k = b
        if catch:
            line = src[:start].count('\n') + 1
            yield line, try_body, catch[0], catch[1]
        i = j

def main(out_path):
    out = pathlib.Path(out_path); out.parent.mkdir(parents=True, exist_ok=True)
    fh = out.open('w')
    fh.write('file\tline\ttry_parses\ttry_stores\tcatch_answers\tmixed\n'); fh.flush()
    mixed = 0
    for f in sorted(pathlib.Path('lib/src').rglob('*.dart')):
        src = f.read_text()
        for line, tb, ch, cb in blocks(src):
            parses = bool(PARSE.search(tb)); stores = bool(STORE.search(tb))
            st = STATUS.search(cb)
            answers = st.group(0) if st else ('rethrow' if 'rethrow' in cb else 'none')
            is_mixed = parses and stores and st is not None
            mixed += is_mixed
            fh.write(f'{f}\t{line}\t{parses}\t{stores}\t{answers}\t{is_mixed}\n'); fh.flush()
    print(f'mixed sites: {mixed}', flush=True)

if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
