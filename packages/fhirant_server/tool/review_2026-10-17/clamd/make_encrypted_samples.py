"""Writes the files encrypted_samples.sh scans: each kind of
password-protected file a client could attach, beside its unprotected twin.

  plain.zip / encrypted.zip     zip, then `zip -P` (traditional encryption)
  plain.pdf / user_pw.pdf       PDF, then one that needs a password to open
  owner_only.pdf                PDF with only an owner password: opens with
                                no password, restricts printing or editing
  plain.docx / encrypted.docx   Word document, then password-protected
                                (msoffcrypto-tool, ECMA-376 agile encryption)

Needs pypdf and msoffcrypto-tool (a throwaway venv; see encrypted_samples.sh).

Run: python3 -I make_encrypted_samples.py <out dir>
"""
import io
import os
import subprocess
import sys
import zipfile

from msoffcrypto.format.ooxml import OOXMLFile
from pypdf import PdfWriter

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
text = b'A clinic letter. Nothing in it but text.\n'


def path(name):
    return os.path.join(out, name)


with open(path('letter.txt'), 'wb') as f:
    f.write(text)
for name, extra in (('plain.zip', []), ('encrypted.zip', ['-P', 'secret'])):
    if os.path.exists(path(name)):
        os.remove(path(name))
    subprocess.run(['zip', '-q', '-j', *extra, path(name), path('letter.txt')],
                   check=True)


def pdf(name, user=None, owner=None):
    w = PdfWriter()
    w.add_blank_page(width=200, height=200)
    if user is not None or owner is not None:
        w.encrypt(user_password=user or '', owner_password=owner,
                  algorithm='AES-256')
    with open(path(name), 'wb') as f:
        w.write(f)


pdf('plain.pdf')
pdf('user_pw.pdf', user='secret', owner='secret-owner')
pdf('owner_only.pdf', user='', owner='secret-owner')

docx = io.BytesIO()
with zipfile.ZipFile(docx, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml',
               '<?xml version="1.0" encoding="UTF-8"?>'
               '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
               'content-types"><Default Extension="rels" ContentType="'
               'application/vnd.openxmlformats-package.relationships+xml"/>'
               '<Default Extension="xml" ContentType="application/xml"/>'
               '<Override PartName="/word/document.xml" ContentType="'
               'application/vnd.openxmlformats-officedocument.'
               'wordprocessingml.document.main+xml"/></Types>')
    z.writestr('_rels/.rels',
               '<?xml version="1.0" encoding="UTF-8"?>'
               '<Relationships xmlns="http://schemas.openxmlformats.org/'
               'package/2006/relationships"><Relationship Id="rId1" Type="'
               'http://schemas.openxmlformats.org/officeDocument/2006/'
               'relationships/officeDocument" Target="word/document.xml"/>'
               '</Relationships>')
    z.writestr('word/document.xml',
               '<?xml version="1.0" encoding="UTF-8"?>'
               '<w:document xmlns:w="http://schemas.openxmlformats.org/'
               'wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>'
               'A clinic letter.</w:t></w:r></w:p></w:body></w:document>')
with open(path('plain.docx'), 'wb') as f:
    f.write(docx.getvalue())
docx.seek(0)
office = OOXMLFile(docx)
with open(path('encrypted.docx'), 'wb') as f:
    office.encrypt('secret', f)

for name in sorted(os.listdir(out)):
    print(name, os.path.getsize(path(name)), flush=True)
