#!/usr/bin/env python3
"""Reload nginx only when CloudPlay's Caddy-managed certificate changes."""
import hashlib
from pathlib import Path
from common import BASE, MARKER, credentials, run, write_private


def main():
    config = Path('/etc/nginx/conf.d/cloudplay.conf')
    if not config.exists() or not config.read_text().startswith(MARKER): return
    domain = credentials()['server_url'].split('://',1)[1]
    certs = list((BASE/'data/caddy').glob('caddy/certificates/*/'+domain+'/'+domain+'.crt'))
    if not certs: raise RuntimeError('CloudPlay 证书缺失')
    digest = hashlib.sha256(certs[0].read_bytes()).hexdigest()
    record = BASE/'private/nginx-cert-sha256'
    if record.exists() and record.read_text().strip() == digest: return
    run(['nginx','-t'])
    run(['systemctl','reload','nginx'])
    write_private(record, digest+'\n')


if __name__ == '__main__': main()
