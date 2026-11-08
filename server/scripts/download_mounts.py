#!/usr/bin/env python3
"""Expose the two actual shared download roots; never relocate files or restart downloads."""
import json
from common import OpenList, credentials

MOUNTS = {'/下载': '/downloads', '/下载/网页离线': '/opt/openlist/data/temp/aria2'}


def ensure_download_mounts(api):
    storages = api.call('/api/admin/storage/list?page=1&per_page=100')['content'] or []
    for mount, root in MOUNTS.items():
        existing = next((s for s in storages if s['mount_path'] == mount), None)
        if existing:
            addition = json.loads(existing.get('addition') or '{}')
            if existing['driver'] != 'Local' or addition.get('root_folder_path') != root:
                raise RuntimeError('已有同名挂载指向其他目录，拒绝覆盖：' + mount)
            continue
        api.call('/api/admin/storage/create', {
            'mount_path': mount, 'driver': 'Local',
            'addition': json.dumps({'root_folder_path': root, 'thumbnail': False,
                                    'show_hidden': False, 'mkdir_perm': '700'}),
            'cache_expiration': 0, 'enable_sign': True, 'web_proxy': True,
            'webdav_policy': 'native_proxy', 'proxy_range': True,
            'order_by': 'name', 'order_direction': 'asc', 'extract_folder': 'front'})
        print('已添加下载目录：' + mount, flush=True)


def main():
    p = credentials()
    api = OpenList()
    api.login(p['admin_username'], p['admin_password'])
    ensure_download_mounts(api)
    # Verify the ordinary iOS account can browse both mounts; never elevate its permissions.
    api.login(p['openlist_username'], p['openlist_password'])
    for mount in MOUNTS:
        api.call('/api/fs/list', {'path': mount, 'page': 1, 'per_page': 100, 'refresh': True})
    print('共享下载目录检查通过；原文件和 Aria2 任务均未移动。')


if __name__ == '__main__':
    main()
