#!/usr/bin/env python3
"""Real API smoke tests. Use only self-generated fixtures and clean up their own files."""
import hashlib
import base64
import json
from pathlib import Path
import time
import uuid
from urllib.error import HTTPError
from urllib.parse import quote, parse_qs, urlsplit
from common import BASE, OpenList, basic_header, credentials, request, rpc, compose


def check(condition, message):
    if not condition: raise RuntimeError(message)
    print('通过：'+message,flush=True)


def bencode(value):
    if isinstance(value,int): return b'i'+str(value).encode()+b'e'
    if isinstance(value,str): value=value.encode()
    if isinstance(value,bytes): return str(len(value)).encode()+b':'+value
    if isinstance(value,list): return b'l'+b''.join(bencode(v) for v in value)+b'e'
    if isinstance(value,dict):
        return b'd'+b''.join(bencode(k)+bencode(value[k]) for k in sorted(value))+b'e'
    raise TypeError('不支持的 Bencode 值')


def main(files_only=False):
    creds = credentials()
    public = creds['server_url']
    # TLS validation is enabled in urllib; no custom unverified context is used.
    check(request(public+'/healthz',raw=True)==b'CloudPlay','公网 HTTPS 与证书验证')
    payload = {'jsonrpc':'2.0','id':'verify','method':'aria2.getVersion','params':[]}
    try:
        request(public+'/rpc',payload)
        raise RuntimeError('RPC 额外认证未生效')
    except HTTPError as error:
        check(error.code==401,'RPC 无额外认证被拒绝')
    headers = {'Authorization':basic_header(creds['rpc_username'],creds['rpc_password'])}
    try:
        rejected = request(public+'/rpc',payload,headers)
    except HTTPError as error:
        if error.code not in (400,401,403): raise
        rejected = json.load(error)
    check('error' in rejected,'RPC 缺少 Aria2 Secret 被拒绝')
    payload['params'] = ['token:'+creds['aria2_secret']]
    version = request(public+'/rpc',payload,headers)['result']
    check('BitTorrent' in version['enabledFeatures'],'Aria2 真实版本与 BitTorrent 支持：'+version['version'])
    try:
        request(public+'/jsonrpc',payload)
        raise RuntimeError('未保护的 JSON-RPC 路由可访问')
    except HTTPError as error:
        check(error.code==404,'默认 JSON-RPC 路径已关闭')
    guest = request(public+'/api/fs/list',{'path':'/下载','page':1,'per_page':20})
    check(guest.get('code') in (401,403),'匿名云盘文件访问被拒绝')
    api = OpenList(public)
    api.login(creds['openlist_username'],creds['openlist_password'])
    check(api.call('/api/me')['role']==0,'手机账号为普通用户而非管理员')
    listing = api.call('/api/fs/list',{'path':'/下载','page':1,'per_page':100,'refresh':True})
    check(isinstance(listing.get('content'),list) or listing.get('content') is None,'共享下载目录可浏览')
    admin = OpenList(public)
    admin.login(creds['admin_username'],creds['admin_password'])
    drivers = admin.call('/api/admin/driver/names')
    check(bool(drivers),'获取运行版本真实支持的网盘驱动清单')
    name = 'CloudPlay验收-'+uuid.uuid4().hex[:10]
    folder = '/下载/'+name
    local = BASE/'data/downloads'/name
    gids = []
    try:
        api.call('/api/fs/mkdir',{'path':folder})
        check(local.is_dir(),'OpenList 创建目录反映到 Aria2 共享卷')
        source = bytes(range(256))*2048
        upload_headers = {'Authorization':api.token,'File-Path':quote(folder+'/源文件.bin',safe='/'),
                          'Content-Type':'application/octet-stream','As-Task':'false'}
        uploaded = request(public+'/api/fs/put',source,upload_headers,method='PUT')
        check(uploaded['code']==200 and (local/'源文件.bin').read_bytes()==source,'文件上传与内容校验')
        api.call('/api/fs/rename',{'path':folder+'/源文件.bin','name':'已重命名.bin'})
        check((local/'已重命名.bin').exists(),'文件重命名')
        api.call('/api/fs/mkdir',{'path':folder+'/子目录'})
        api.call('/api/fs/move',{'src_dir':folder,'dst_dir':folder+'/子目录','names':['已重命名.bin']})
        check((local/'子目录/已重命名.bin').exists(),'文件移动')
        api.call('/api/fs/copy',{'src_dir':folder+'/子目录','dst_dir':folder,'names':['已重命名.bin']})
        deadline=time.monotonic()+20
        while not (local/'已重命名.bin').exists() and time.monotonic()<deadline:time.sleep(0.5)
        check((local/'已重命名.bin').read_bytes()==source,'文件复制')
        admin.call('/api/admin/index/update',{'paths':[folder],'max_depth':5})
        deadline=time.monotonic()+20
        found=[]
        while time.monotonic()<deadline:
            results=api.call('/api/fs/search',{'parent':folder,'keywords':'已重命名','scope':0,'page':1,'per_page':100})
            found=results.get('content') or []
            if found:break
            time.sleep(0.5)
        check(bool(found),'数据库索引与文件搜索')
        info = api.call('/api/fs/get',{'path':folder+'/已重命名.bin','password':''})
        url = info['raw_url']
        check(url.startswith(public+'/'),'本地文件使用 HTTPS 临时播放链接')
        signature=parse_qs(urlsplit(url).query).get('sign',[''])[0]
        expires=int(signature.rsplit(':',1)[-1])
        check(0 < expires-time.time() <= 3700,'播放链接签名有效期为 1 小时')
        from urllib.request import Request, build_opener, ProxyHandler
        opener=build_opener(ProxyHandler({}))
        with opener.open(Request(url,headers={'Range':'bytes=123-321'}),timeout=20) as response:
            check(response.status==206 and response.read()==source[123:322],
                  'HTTP Range 206 与随机字节读取')
        with opener.open(Request(url,method='HEAD'),timeout=20) as response:
            check(int(response.headers['Content-Length'])==len(source),'HEAD 文件长度')
        try:
            opener.open(Request(url,headers={'Range':'bytes='+str(len(source)+1)+'-'}),timeout=20)
            raise RuntimeError('错误范围未被拒绝')
        except HTTPError as error:check(error.code==416,'HTTP Range 越界返回 416')
        dav_headers={'Authorization':basic_header(creds['openlist_username'],creds['openlist_password']),
                     'Depth':'1'}
        with opener.open(Request(public+'/dav/'+quote('下载/'+name+'/',safe='/'),
                                 headers=dav_headers,method='PROPFIND'),timeout=20) as response:
            check(response.status==207,'WebDAV 认证与目录浏览')
        if files_only:
            print('文件与 Range 复测完成；保留现有下载任务，不执行下载器重启测试。',flush=True)
            return
        gid = rpc('addUri',[[url],{'dir':'/downloads/'+name,'out':'离线下载.bin','pause':'true'}])
        gids.append(gid)
        check(rpc('tellStatus',[gid])['status']=='paused','真实离线任务添加与暂停')
        rpc('unpause',[gid])
        deadline=time.monotonic()+60
        while time.monotonic()<deadline:
            status=rpc('tellStatus',[gid])
            if status['status'] in ('complete','error'):break
            time.sleep(0.5)
        check(status['status']=='complete','Aria2 HTTPS 离线下载完成')
        check(hashlib.sha256((local/'离线下载.bin').read_bytes()).digest()==hashlib.sha256(source).digest(),
              '离线下载 SHA-256 内容校验')
        after=api.call('/api/fs/list',{'path':folder,'page':1,'per_page':100,'refresh':True})
        check(any(f['name']=='离线下载.bin' for f in after['content']),'下载完成自动出现在云盘目录')
        # A real BitTorrent engine test using our own bytes and an HTTPS web seed.
        # This proves torrent import and piece verification, not public peer availability.
        piece_length=128*1024
        metainfo=bencode({'info':{'name':'已重命名.bin','length':len(source),
                         'piece length':piece_length,
                         'pieces':b''.join(hashlib.sha1(source[i:i+piece_length]).digest()
                                          for i in range(0,len(source),piece_length))},
                          'url-list':[url]})
        torrent=rpc('addTorrent',[base64.b64encode(metainfo).decode(),[],
                                 {'dir':'/downloads/'+name+'/BT验收','seed-time':'0'}])
        gids.append(torrent)
        deadline=time.monotonic()+60
        while time.monotonic()<deadline:
            bt=rpc('tellStatus',[torrent])
            if bt['status'] in ('complete','error'):break
            time.sleep(0.5)
        check(bt['status']=='complete' and (local/'BT验收/已重命名.bin').read_bytes()==source,
              '自生成 torrent 导入与 Piece 校验（HTTPS Web Seed，不冒充公网 Peer）')
        # Paused, unfinished task persisted and restored, without relying on a real seed.
        resume = rpc('addUri',[[url],{'dir':'/downloads/'+name,'out':'恢复测试.bin','pause':'true'}])
        gids.append(resume)
        rpc('saveSession')
        compose('restart','aria2')
        deadline=time.monotonic()+30
        restored=None
        while time.monotonic()<deadline:
            try:
                restored=rpc('tellStatus',[resume])
                if restored:break
            except (OSError,RuntimeError):pass
            time.sleep(1)
        check(restored is not None and restored['gid']==resume and restored['status']=='paused','Aria2 容器重启后恢复未完成任务')
        options=rpc('getGlobalOption')
        check(float(options.get('seed-time','-1'))==0 and options.get('max-overall-upload-limit')=='65536',
              '不持续做种与 64 KiB/s 上传上限')
    finally:
        for gid in gids:
            try:
                state=rpc('tellStatus',[gid])['status']
                rpc('removeDownloadResult' if state in ('complete','error','removed') else 'forceRemove',[gid])
            except (OSError,RuntimeError):pass
        rpc('saveSession')
        if local.exists():
            api.call('/api/fs/remove',{'dir':'/下载','names':[name]})
        check(not local.exists(),'验收目录删除；不触及其他文件')
    print('验收完成。未执行 iPhone 真机、外部网盘凭据和公网磁力 Peer 实测。',flush=True)


if __name__ == '__main__':
    import argparse
    parser=argparse.ArgumentParser(description='使用自生成数据验收 CloudPlay')
    parser.add_argument('--files-only',action='store_true',help='服务器有用户任务时，仅验证认证、文件管理及 Range，不重启下载器')
    main(files_only=parser.parse_args().files_only)
