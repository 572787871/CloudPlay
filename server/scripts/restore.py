#!/usr/bin/env python3
"""Restore to an empty installation only; reject traversal, links and devices."""
import argparse
from pathlib import Path, PurePosixPath
import tarfile
from common import BASE


def validate_members(members):
    for member in members:
        path = PurePosixPath(member.name)
        if path.is_absolute() or '..' in path.parts or member.issym() or member.islnk() or member.isdev():
            raise ValueError('不安全的备份成员')
        if not path.parts or path.parts[0] not in ('.env','private','data'):
            raise ValueError('备份包含非 CloudPlay 数据')
        if not (member.isdir() or member.isfile()):
            raise ValueError('备份包含不支持的特殊文件')


def main():
    parser = argparse.ArgumentParser(description='恢复到空目录；不会覆盖正在运行的服务')
    parser.add_argument('archive',type=Path)
    args = parser.parse_args()
    if any((BASE/name).exists() for name in ('data','private','.env')):
        raise RuntimeError('目标已有数据；请先停止并将原 data/private/.env 移至其他安全目录')
    with tarfile.open(args.archive) as archive:
        members = archive.getmembers()
        validate_members(members)
        archive.extractall(BASE,members=members)
    for path in (BASE/'private', BASE/'.env'):
        path.chmod(0o700 if path.is_dir() else 0o600)
    print('数据已恢复。先核对 .env 中 UID、域名与下载目录，再运行安装脚本。')


if __name__ == '__main__': main()
