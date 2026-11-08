#!/usr/bin/env python3
"""Validate a real device .app and package it with embedded resources/frameworks."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import zipfile

def main():
    p=argparse.ArgumentParser();p.add_argument('app',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
    info=plistlib.loads((a.app/'Info.plist').read_bytes())
    assert info['CFBundlePackageType']=='APPL'
    assert 'iPhoneOS' in info.get('CFBundleSupportedPlatforms',[]),'不是 iOS 真机 App'
    executable=a.app/info['CFBundleExecutable']
    assert executable.is_file()
    arch=subprocess.check_output(['xcrun','lipo','-archs',str(executable)],text=True)
    assert 'arm64' in arch
    assert (a.app/'PlugIns/CloudPlayShare.appex').is_dir(),'缺少分享扩展'
    # MobileVLCKit may be statically linked. A dynamic dylib must resolve inside the app/system.
    dependencies=subprocess.check_output(['xcrun','otool','-L',str(executable)],text=True)
    for line in dependencies.splitlines()[1:]:
        name=line.strip().split(' ',1)[0]
        if name.startswith('@rpath/'):
            relative=name[len('@rpath/'):]
            assert (a.app/'Frameworks'/relative).exists(),'缺少动态库：'+relative
    for item in a.app.rglob('*'):
        if item.is_file() and (item.suffix=='.dylib' or item.parent.suffix=='.framework' and item.name==item.parent.stem):
            output=subprocess.check_output(['xcrun','lipo','-archs',str(item)],text=True)
            assert 'arm64' in output,'Framework 缺少 arm64：'+str(item)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    staging=a.output.parent/'IPA-Staging'
    if staging.exists():shutil.rmtree(staging)
    (staging/'Payload').mkdir(parents=True)
    shutil.copytree(a.app,staging/'Payload'/a.app.name,symlinks=True)
    subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent','Payload',str(a.output.resolve())],cwd=staging,check=True)
    with zipfile.ZipFile(a.output) as z:assert z.testzip() is None
    print('已验证 iPhoneOS/arm64、扩展和动态依赖并打包未签名 IPA：'+str(a.output))

if __name__=='__main__':main()
