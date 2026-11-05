"""CloudPlay operations helpers. Credentials and response bodies are never logged."""
import base64
import json
import os
from pathlib import Path
import subprocess
from urllib.request import Request, build_opener, ProxyHandler

BASE = Path(__file__).resolve().parents[1]
DOMAIN = 'cl.520123.xyz'
MARKER = '# Managed by CloudPlay'


def run(args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, **kwargs)
    if result.returncode:
        detail = result.stderr[-4000:]
        source = BASE/'private/connection.json'
        if source.exists():
            for key,value in json.loads(source.read_text()).items():
                if 'password' in key or 'secret' in key:
                    detail = detail.replace(value,'<redacted>')
        (BASE/'logs').mkdir(mode=0o700,exist_ok=True)
        write_private(BASE/'logs/last-operation-error.log',detail)
        raise RuntimeError('命令执行失败：' + args[0] + '（退出码 ' + str(result.returncode)
                           + '），原因见 logs/last-operation-error.log')
    return result.stdout


def compose(*args):
    return run(['docker', 'compose', '--project-directory', str(BASE), '-f',
                str(BASE/'docker-compose.yml'), *args])


def write_private(path, text, uid=None, gid=None):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as output:
        output.write(text)
    path.chmod(0o600)
    if uid is not None:
        os.chown(path, uid, gid)


def credentials():
    return json.loads((BASE/'private/connection.json').read_text())


def container_ip(service):
    cid = compose('ps', '-q', service).strip()
    if not cid:
        raise RuntimeError('服务未运行：' + service)
    details = json.loads(run(['docker', 'inspect', cid]))[0]
    return next(iter(details['NetworkSettings']['Networks'].values()))['IPAddress']


def request(url, payload=None, headers=None, method=None, raw=False):
    if payload is not None and not isinstance(payload, bytes):
        payload = json.dumps(payload, ensure_ascii=False).encode()
        headers = {'Content-Type': 'application/json', **(headers or {})}
    req = Request(url, data=payload, headers=headers or {}, method=method)
    # These helpers operate on this VPS's own private Docker subnet.
    with build_opener(ProxyHandler({})).open(req, timeout=30) as response:
        body = response.read()
        return body if raw else json.loads(body)


class OpenList:
    def __init__(self, base=None):
        self.base = base or 'http://' + container_ip('openlist') + ':5244'
        self.token = ''

    def call(self, endpoint, payload=None, method=None):
        result = request(self.base + endpoint, payload,
                         {'Authorization': self.token} if self.token else {}, method)
        if result.get('code') != 200:
            raise RuntimeError('OpenList 接口失败：' + endpoint + '，状态 ' + str(result.get('code')))
        return result.get('data')

    def login(self, username, password):
        self.token = self.call('/api/auth/login', {'username': username, 'password': password})['token']


def rpc(method, params=None):
    secret = credentials()['aria2_secret']
    result = request('http://' + container_ip('aria2') + ':6800/jsonrpc',
                     {'jsonrpc': '2.0', 'id': 'cloudplay', 'method': 'aria2.'+method,
                      'params': ['token:'+secret, *(params or [])]})
    if 'error' in result:
        raise RuntimeError('Aria2 接口失败：' + method + '，代码 ' + str(result['error'].get('code')))
    return result['result']


def basic_header(username, password):
    return 'Basic ' + base64.b64encode((username+':'+password).encode()).decode()
