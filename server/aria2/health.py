"""Authenticated local RPC health check. Do not log config, tokens or responses."""
import json
from pathlib import Path
import sys
from urllib.request import Request, build_opener, ProxyHandler

try:
    settings = dict(line.split('=', 1) for line in Path('/config/aria2.conf').read_text().splitlines()
                    if '=' in line and not line.startswith('#'))
    payload = {'jsonrpc': '2.0', 'id': 'health', 'method': 'aria2.getVersion',
               'params': ['token:' + settings['rpc-secret']]}
    request = Request('http://127.0.0.1:6800/jsonrpc', json.dumps(payload).encode(),
                      {'Content-Type': 'application/json'})
    with build_opener(ProxyHandler({})).open(request, timeout=5) as response:
        result = json.load(response)
    sys.exit(0 if result.get('result', {}).get('version') else 1)
except Exception:
    sys.exit(1)
