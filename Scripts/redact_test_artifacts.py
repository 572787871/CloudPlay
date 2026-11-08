#!/usr/bin/env python3
"""Publish text evidence and screenshots, without XCTest environment archives."""
import os
from pathlib import Path
import re

def redact(text,values):
    for value in values:
        if value:text=text.replace(value,'<redacted>')
    return re.sub(r'([?&](?:sign|token|access_token)=)[^\s&"<>]+',r'\1<redacted>',text)

def main():
    values=[os.environ.get('CLOUDPLAY_REDACT_USER',''),os.environ.get('CLOUDPLAY_REDACT_PASSWORD','')]
    for root in (Path('build/logs'),Path('build/screenshots')):
        if not root.exists():continue
        for path in root.rglob('*'):
            if not path.is_file():continue
            if path.suffix.lower() in ('.log','.json','.txt'):
                path.write_text(redact(path.read_text(errors='replace'),values))
            elif root.name=='screenshots' and path.suffix.lower()!='.png':path.unlink()

if __name__=='__main__':main()
