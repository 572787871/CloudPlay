import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from download_mounts import MOUNTS, ensure_download_mounts


class API:
    def __init__(self, storages=None):
        self.storages = storages or []
        self.creates = []
    def call(self, path, payload=None):
        if path.startswith('/api/admin/storage/list'):
            return {'content': self.storages}
        assert path == '/api/admin/storage/create'
        self.creates.append(payload)
        self.storages.append(payload)


class DownloadMountTests(unittest.TestCase):
    def test_only_dedicated_shared_roots_are_exposed(self):
        api = API()
        ensure_download_mounts(api)
        self.assertEqual(len(api.creates), 2)
        for storage in api.creates:
            self.assertEqual(json.loads(storage['addition'])['root_folder_path'], MOUNTS[storage['mount_path']])
            self.assertTrue(storage['enable_sign'])
            self.assertTrue(storage['proxy_range'])
            self.assertTrue(storage['web_proxy'])
    def test_repeated_runs_do_not_change_existing_mounts(self):
        api = API()
        ensure_download_mounts(api)
        ensure_download_mounts(api)
        self.assertEqual(len(api.creates), 2)
    def test_conflicting_mount_is_never_overwritten(self):
        api = API([{'mount_path':'/下载', 'driver':'Local', 'addition':json.dumps({'root_folder_path':'/other'})}])
        with self.assertRaises(RuntimeError): ensure_download_mounts(api)
        self.assertEqual(api.creates, [])
    def test_nonlocal_mount_is_never_overwritten(self):
        api = API([{'mount_path':'/下载', 'driver':'S3', 'addition':'{}'}])
        with self.assertRaises(RuntimeError): ensure_download_mounts(api)
        self.assertEqual(api.creates, [])


if __name__ == '__main__': unittest.main()
