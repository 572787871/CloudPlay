#!/usr/bin/env python3
"""Consistent offline backup; media is opt-in to avoid unexpectedly filling disk."""
import argparse
from datetime import datetime, timezone
import os
import tarfile
from common import BASE, compose, rpc


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--include-downloads',action='store_true')
    args = parser.parse_args()
    outdir = BASE/'backups'
    outdir.mkdir(mode=0o700,exist_ok=True)
    target = outdir/('cloudplay-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'.tar.gz')
    rpc('saveSession')
    running = compose('ps','--services','--status','running').split()
    try:
        compose('stop')
        fd = os.open(target,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
        with os.fdopen(fd,'wb') as output, tarfile.open(fileobj=output,mode='w:gz') as archive:
            for name in ('.env','private','data/aria2','data/openlist','data/caddy','data/caddy-config'):
                if (BASE/name).exists(): archive.add(BASE/name,arcname=name,recursive=True)
            if args.include_downloads:
                for name in ('data/downloads','data/aria2-temp'):
                    archive.add(BASE/name,arcname=name,recursive=True)
    except Exception:
        target.unlink(missing_ok=True)
        raise
    finally:
        if running: compose('up','-d',*running)
    print(str(target))
    print('备份含密钥，请离机加密保存；'+('包含下载文件。' if args.include_downloads else '不包含下载文件，恢复任务还需保留原下载目录。'))


if __name__ == '__main__': main()
