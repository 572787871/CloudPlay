from pathlib import Path
import sys
import tarfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from restore import validate_members


class BackupSafetyTests(unittest.TestCase):
    def member(self,name,kind=tarfile.REGTYPE):
        entry=tarfile.TarInfo(name); entry.type=kind; return entry
    def test_normal_backup(self):
        validate_members([self.member('.env'),self.member('data/openlist/data.db'),self.member('private',tarfile.DIRTYPE)])
    def test_traversal(self):
        with self.assertRaises(ValueError): validate_members([self.member('data/../../etc/passwd')])
    def test_absolute(self):
        with self.assertRaises(ValueError): validate_members([self.member('/etc/shadow')])
    def test_symbolic_link(self):
        with self.assertRaises(ValueError): validate_members([self.member('data/link',tarfile.SYMTYPE)])
    def test_hard_link(self):
        with self.assertRaises(ValueError): validate_members([self.member('data/link',tarfile.LNKTYPE)])
    def test_device(self):
        with self.assertRaises(ValueError): validate_members([self.member('data/device',tarfile.CHRTYPE)])
    def test_unrelated_root(self):
        with self.assertRaises(ValueError): validate_members([self.member('etc/nginx/nginx.conf')])


if __name__=='__main__': unittest.main()
