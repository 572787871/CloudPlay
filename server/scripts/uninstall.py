#!/usr/bin/env python3
"""Remove only this project. Preserve downloads and credentials by default."""
import argparse
from pathlib import Path
import shutil
from common import BASE, MARKER, compose, credentials, run


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--purge-data',action='store_true',help='永久删除本项目下载数据及凭据')
    parser.add_argument('--confirm-domain',default='')
    args = parser.parse_args()
    domain = credentials()['server_url'].split('://',1)[1]
    if args.purge_data and args.confirm_domain != domain:
        raise RuntimeError('清空数据必须显式传入 --confirm-domain '+domain)
    compose('down','--remove-orphans')
    config = Path('/etc/nginx/conf.d/cloudplay.conf')
    if config.exists() and config.read_text().startswith(MARKER):
        config.unlink()
        previous = BASE/'private/previous-nginx.conf'
        legacy = Path('/etc/nginx/conf.d/vps-downloads.conf')
        if previous.exists() and not legacy.exists(): legacy.write_text(previous.read_text())
        run(['nginx','-t'])
        run(['systemctl','reload','nginx'])
    cron = Path('/etc/cron.d/cloudplay-cert')
    if cron.exists() and cron.read_text().startswith(MARKER): cron.unlink()
    if args.purge_data:
        for name in ('data','private','config/Caddyfile','.env'):
            p = BASE/name
            if p.is_dir(): shutil.rmtree(p)
            else: p.unlink(missing_ok=True)
        print('CloudPlay 专用数据已永久删除；备份目录及共享 Docker 保留。')
    else:
        print('服务已卸载；下载数据、配置、凭据和备份均保留。')


if __name__ == '__main__': main()
