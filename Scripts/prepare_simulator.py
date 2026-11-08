#!/usr/bin/env python3
"""Select the newest installed iOS runtime and report real simulator boot errors."""
import json
from pathlib import Path
import re
import subprocess

def main():
    result=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))
    candidates=[]
    for runtime,devices in result['devices'].items():
        if 'iOS-' not in runtime:continue
        version=tuple(map(int,re.findall(r'\d+',runtime)))
        for device in devices:
            if device['name'].startswith('iPhone') and device.get('isAvailable',True):
                candidates.append((version,runtime,device))
    if not candidates:raise RuntimeError('Runner 未安装可用 iPhone 模拟器')
    _,runtime,device=max(candidates,key=lambda x:x[0])
    print('准备模拟器：'+device['name']+' / '+runtime,flush=True)
    if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',device['udid']],check=True,timeout=60)
    subprocess.run(['xcrun','simctl','bootstatus',device['udid'],'-b'],check=True,timeout=300)
    Path('build').mkdir(exist_ok=True)
    Path('build/simulator-id').write_text(device['udid'])
    print('模拟器已实际启动',flush=True)

if __name__=='__main__':main()
