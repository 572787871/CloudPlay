#!/usr/bin/env python3
"""Idempotent ARM64 installer. Never installs unrelated software or resets existing accounts."""
import argparse
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import time
from pathlib import Path
from download_mounts import ensure_download_mounts
from common import BASE, MARKER, OpenList, compose, container_ip, run, write_private

IMAGES = {'OPENLIST_IMAGE': 'openlistteam/openlist:v4.2.9',
          'CADDY_IMAGE': 'caddy:2.11.8', 'DEBIAN_IMAGE': 'debian:13-slim'}
NGINX = Path('/etc/nginx/conf.d/cloudplay.conf')
LEGACY = Path('/etc/nginx/conf.d/vps-downloads.conf')


def bridge_config(domain, cert, key):
    return MARKER + f'''
server {{
    listen 80;
    server_name {domain};
    location /.well-known/acme-challenge/ {{
        proxy_pass http://127.0.0.1:18081;
        proxy_set_header Host {domain};
    }}
    location / {{ return 308 https://$host$request_uri; }}
}}
server {{
    listen 443 ssl http2;
    server_name {domain};
    ssl_certificate {cert};
    ssl_certificate_key {key};
    ssl_protocols TLSv1.2 TLSv1.3;
    access_log off;
    client_max_body_size 20g;
    location / {{
        proxy_pass https://127.0.0.1:18444;
        proxy_ssl_server_name on;
        proxy_ssl_name {domain};
        proxy_ssl_verify on;
        proxy_ssl_verify_depth 4;
        proxy_ssl_protocols TLSv1.2 TLSv1.3;
        proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
        proxy_set_header Host {domain};
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }}
}}
'''


def wait_for(fn, description, seconds=60):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            return fn()
        except (OSError, RuntimeError, ValueError):
            time.sleep(2)
    raise RuntimeError(description + '超时，请查看本项目专用日志')


def main():
    parser = argparse.ArgumentParser(description='CloudPlay ARM64 部署')
    parser.add_argument('--domain', default='cl.520123.xyz')
    parser.add_argument('--existing-nginx', action='store_true', help='保留现有 nginx 并增加本域名转发')
    parser.add_argument('--uid', type=int, default=10001)
    args = parser.parse_args()
    domain = args.domain.lower()
    if not re.fullmatch(r'[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?', domain) or '.' not in domain:
        raise RuntimeError('域名格式无效')
    if os.geteuid() != 0 or os.uname().machine not in ('aarch64', 'arm64'):
        raise RuntimeError('请在 ARM64 Linux 上以 root 或 sudo 执行')
    if args.uid < 1000:
        raise RuntimeError('容器必须使用非 root UID（至少 1000）')
    for executable in ('docker', 'openssl'):
        if not shutil.which(executable):
            raise RuntimeError('请先安装系统软件源提供的 ' + executable + '；详见 README')
    run(['docker', 'compose', 'version'])
    if shutil.disk_usage(BASE).free < 12*1024**3:
        raise RuntimeError('至少需要 12 GiB 空闲磁盘')
    socket.getaddrinfo(domain, 443)
    if (BASE/'data').exists() and not (BASE/'private/connection.json').exists():
        raise RuntimeError('已有数据但缺少原凭据，拒绝重置。请从备份恢复 private 与 .env')
    for folder in ('private', 'logs', 'backups', 'config'):
        (BASE/folder).mkdir(exist_ok=True)
        (BASE/folder).chmod(0o700)
    first = not (BASE/'private/connection.json').exists()
    if first:
        creds = {'server_url': 'https://'+domain, 'openlist_username': 'cloudplay',
                 'openlist_password': secrets.token_urlsafe(24),
                 'admin_username': 'admin', 'admin_password': secrets.token_urlsafe(24),
                 'aria2_rpc_url': 'https://'+domain+'/rpc', 'aria2_secret': secrets.token_urlsafe(32),
                 'rpc_username': 'cloudplay', 'rpc_password': secrets.token_urlsafe(24)}
        write_private(BASE/'private/connection.json', json.dumps(creds, ensure_ascii=False, indent=2))
    else:
        creds = json.loads((BASE/'private/connection.json').read_text())
        if creds['server_url'] != 'https://'+domain:
            raise RuntimeError('域名与已有配置不一致，拒绝覆盖')
    images = {}
    for variable, tag in IMAGES.items():
        log = BASE/'logs'/('pull-'+variable+'.log')
        with log.open('w') as output:
            result = subprocess.run(['docker', 'pull', '--platform', 'linux/arm64', tag],
                                    stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError('镜像拉取失败，详见 ' + str(log))
        detail = json.loads(run(['docker', 'image', 'inspect', tag]))[0]
        if detail['Architecture'] != 'arm64':
            raise RuntimeError('镜像架构不符：' + tag)
        images[variable] = detail['RepoDigests'][0]
        print('已验证 ARM64：'+tag, flush=True)
    if (BASE/'.env').exists():
        old_env = dict(line.split('=', 1) for line in (BASE/'.env').read_text().splitlines() if '=' in line)
        if old_env.get('APP_UID') != str(args.uid):
            raise RuntimeError('已有数据 UID 不同，请使用原 --uid；不会递归更改现有文件权限')
    env = {'DOMAIN': domain, 'APP_UID': str(args.uid), 'APP_GID': str(args.uid),
           'BT_PORT': '51425', **images}
    if args.existing_nginx:
        run(['nginx', '-t'])
        env.update(HTTP_BIND='127.0.0.1', HTTP_PORT='18081', HTTPS_BIND='127.0.0.1', HTTPS_PORT='18444')
        if NGINX.exists() and not NGINX.read_text().startswith(MARKER):
            raise RuntimeError('拒绝覆盖其他 nginx 配置')
    else:
        for port in (80, 443):
            with socket.socket() as sock:
                try:
                    sock.bind(('0.0.0.0', port))
                except OSError:
                    # An existing CloudPlay Caddy is allowed on a repeated run.
                    if not (BASE/'private/configured').exists():
                        raise RuntimeError('端口已占用：'+str(port)+'；可使用 --existing-nginx')
    write_private(BASE/'.env', '\n'.join(k+'='+v for k,v in env.items())+'\n')
    for folder in ('aria2', 'downloads', 'aria2-temp', 'openlist'):
        p = BASE/'data'/folder
        p.mkdir(parents=True, exist_ok=True)
        p.chmod(0o700)
        os.chown(p, args.uid, args.uid)
    for folder in ('caddy', 'caddy-config'):
        (BASE/'data'/folder).mkdir(parents=True, exist_ok=True)
        (BASE/'data'/folder).chmod(0o700)
    aria_config = BASE/'data/aria2/aria2.conf'
    if not aria_config.exists():
        write_private(aria_config, (BASE/'config/aria2.conf.template').read_text().replace(
            '__RPC_SECRET__', creds['aria2_secret']), args.uid, args.uid)
    session = BASE/'data/aria2/aria2.session'
    if not session.exists():
        write_private(session, '', args.uid, args.uid)
    # Generate Caddy's bcrypt via stdin; the password is absent from process arguments.
    bcrypt = run(['docker', 'run', '--rm', '-i', '--entrypoint', 'caddy', images['CADDY_IMAGE'],
                  'hash-password'], input=creds['rpc_password']+'\n').strip()
    caddy = (BASE/'config/Caddyfile.template').read_text().replace('__DOMAIN__', domain).replace(
        '__RPC_PASSWORD_HASH__', bcrypt)
    write_private(BASE/'config/Caddyfile', caddy)
    compose('config', '--quiet')
    with (BASE/'logs/aria2-build.log').open('w') as output:
        result = subprocess.run(['docker','compose','--project-directory',str(BASE),'-f',
                    str(BASE/'docker-compose.yml'),'build','aria2'],stdout=output,stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError('Aria2 构建失败：logs/aria2-build.log')
    architecture = json.loads(run(['docker','image','inspect','cloudplay/aria2:1.37-debian13-local']))[0]['Architecture']
    if architecture != 'arm64':
        raise RuntimeError('Aria2 构建产物不是 ARM64')
    compose('up','-d','aria2','openlist')
    api = OpenList()
    wait_for(lambda: api.call('/api/public/init_status'), 'OpenList 启动')
    config_file = BASE/'data/openlist/config.json'
    configuration = json.loads(config_file.read_text())
    configuration['site_url'] = 'https://'+domain
    configuration['tls_insecure_skip_verify'] = False
    configuration['max_concurrency'] = 16
    configuration['max_connections'] = 100
    configuration['cors'] = {'allow_origins':['https://'+domain],
                             'allow_methods':['*'],'allow_headers':['*']}
    configuration['log'].update(max_size=10,max_backups=3,max_age=7)
    for name in ('download','transfer','upload','copy','move'):
        configuration['tasks'][name].update(workers=2,max_retry=2,task_persistant=True)
    write_private(config_file,json.dumps(configuration,indent=2),args.uid,args.uid)
    compose('restart','openlist')
    wait_for(lambda: api.call('/api/public/init_status'),'OpenList 配置加载')
    if not (BASE/'private/configured').exists():
        initialized = api.call('/api/public/init_status')['initialized']
        if not initialized:
            api.call('/api/public/init/setup', {'username':'admin','password':creds['admin_password'],
                                               'site_title':'CloudPlay 私人云盘'})
        else:
            # This is only permitted for a new dedicated data directory before public ingress.
            compose('exec','-T','openlist','./openlist','admin','set',creds['admin_password'])
    api.login('admin', creds['admin_password'])
    users = api.call('/api/admin/user/list?page=1&per_page=100')['content']
    for user in users:
        if user['role'] == 1 and not user['disabled']:
            user['disabled'] = True
            api.call('/api/admin/user/update',user)
    if not any(u['username']==creds['openlist_username'] for u in users):
        api.call('/api/admin/user/create', {'username':creds['openlist_username'],
                 'password':creds['openlist_password'],'role':0,'base_path':'/',
                 'permission':0x73FE,'disabled':False})
    ensure_download_mounts(api)
    settings = api.call('/api/admin/setting/list')
    updates = {'site_title':'CloudPlay 私人云盘','aria2_uri':'http://aria2:6800/jsonrpc',
               'aria2_secret':creds['aria2_secret'],'search_index':'database','auto_update_index':'true',
               'link_expiration':'1','sign_all':'true'}
    changed = []
    for item in settings:
        if item['key'] in updates:
            item['value'] = updates[item['key']]
            changed.append(item)
    api.call('/api/admin/setting/save', changed)
    api.call('/api/admin/index/build', {})
    api.login(creds['openlist_username'],creds['openlist_password'])
    wait_for(lambda:api.call('/api/fs/list',{'path':'/下载','page':1,'per_page':100,'refresh':True}),
             '共享下载目录挂载')
    compose('run','--rm','--no-deps','caddy','caddy','validate','--config','/etc/caddy/Caddyfile')
    if args.existing_nginx:
        if LEGACY.exists():
            if not LEGACY.read_text().startswith('# Managed by VPS-Downloads'):
                raise RuntimeError('旧域名配置归属不明，未切换')
            backup = BASE/'private/previous-nginx.conf'
            if not backup.exists():
                write_private(backup, LEGACY.read_text())
            LEGACY.unlink()
        old = NGINX.read_text() if NGINX.exists() else None
        initial_cert = '/etc/nginx/ssl/520123.xyz/fullchain.pem'
        initial_key = '/etc/nginx/ssl/520123.xyz/privkey.pem'
        if old:
            initial_cert = re.search(r'ssl_certificate ([^;]+);',old).group(1)
            initial_key = re.search(r'ssl_certificate_key ([^;]+);',old).group(1)
        if not Path(initial_cert).exists() or not Path(initial_key).exists():
            raise RuntimeError('nginx 共存模式需要现有有效证书作为启动入口')
        NGINX.write_text(bridge_config(domain,initial_cert,initial_key))
        try:
            run(['nginx','-t'])
            run(['systemctl','reload','nginx'])
        except Exception:
            if old: NGINX.write_text(old)
            else: NGINX.unlink(missing_ok=True)
            if (BASE/'private/previous-nginx.conf').exists():
                LEGACY.write_text((BASE/'private/previous-nginx.conf').read_text())
            raise
    compose('up','-d','caddy')
    wait_for(lambda:compose('exec','-T','caddy','caddy','reload','--config','/etc/caddy/Caddyfile'),
             'Caddy 配置加载',seconds=30)
    write_private(BASE/'private/configured', 'CloudPlay owns only this Compose project and its dedicated nginx file.\n')
    print('CloudPlay 已启动；正在等待 Caddy 自动申请证书。',flush=True)
    def https_ready():
        body = run(['curl','--fail','--silent','--show-error','--max-time','8',
                    '--resolve',domain+':443:127.0.0.1','https://'+domain+'/healthz'])
        if body.strip() != 'CloudPlay': raise RuntimeError('HTTPS 尚未就绪')
        return True
    wait_for(https_ready,'HTTPS/ACME',seconds=180)
    if args.existing_nginx:
        certs = list((BASE/'data/caddy').glob('caddy/certificates/*/'+domain+'/'+domain+'.crt'))
        if not certs: raise RuntimeError('Caddy 证书文件未找到，未声明 HTTPS 部署完成')
        cert = certs[0]
        key = cert.with_suffix('.key')
        NGINX.write_text(bridge_config(domain,str(cert),str(key)))
        run(['nginx','-t'])
        run(['systemctl','reload','nginx'])
        wait_for(https_ready,'自有证书切换',seconds=30)
        hook = Path('/etc/cron.d/cloudplay-cert')
        hook.write_text(MARKER+'\n17 * * * * root /usr/bin/python3 '+str(BASE/'scripts/renew_nginx.py')+'\n')
        hook.chmod(0o644)
    print('第一阶段服务已部署：https://'+domain,flush=True)
    print('连接信息仅写入 private/connection.json，请勿提交或公开。',flush=True)
    print('运行 python3 scripts/verify.py 进行逐项接口和共享目录验证。',flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('部署未完成：'+str(error))
        raise SystemExit(1)
