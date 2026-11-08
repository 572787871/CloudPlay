# CloudPlay 服务器（ARM64）

组件：OpenList v4.2.9、Debian 13 软件包 Aria2、Caddy 2.11.8。安装脚本实际拉取 `linux/arm64` 镜像并核对架构，把 OpenList、Caddy 和 Debian 固定到拉取时的摘要。Aria2 使用随项目提供的 Dockerfile 构建，不依赖不明来源二进制或修改版下载器。

当前 VPS 已检测为 Ubuntu 20.04.6 / aarch64，而不是假定的 Debian 13。容器采用独立用户 10001，保留宿主机系统、其他容器、SSH 与其他站点。不会安装飞牛 OS 或群晖系统。

## 一、准备

1. 将 `cl.520123.xyz` 的 A 记录指向自己的 VPS 公网 IPv4。只有配置了可用 IPv6 才添加 AAAA，避免 ACME 优先走不可达 IPv6。BT 使用 DNS 直连记录；不要通过不支持 BT 的 HTTP CDN 代理 BT 端口。
2. OCI 控制台的安全列表或 NSG 放行 TCP 80、443；可选放行 TCP/UDP 51425（BT 入站/DHT）。SSH 保持实际端口，当前为 57278，建议仅允许自己的管理地址。**不要放行 6800、5244 或 Docker 管理接口。** 未持有 OCI 控制台凭据时，本项目不会声称已修改安全列表。
3. 宿主机防火墙保持 SSH 和已有服务规则。使用 UFW 时先保留真实 SSH 端口，再放行 80/443 和需要的 51425；不要直接 `ufw reset`。Docker 发布端口可能绕过 UFW，Compose 因此根本不发布 RPC 与 OpenList 后端端口。
4. 推荐受支持的 Ubuntu/Debian，至少 12 GiB 空闲磁盘。当前 Ubuntu 20.04 的系统升级需另行安排维护，安装脚本不会自动升级发行版或中断其他服务。
5. 将本项目复制到 VPS，例如 `/opt/cloudplay`。以下命令从 `/opt/cloudplay/server` 执行。不要上传任何聊天记录、root 密码或旧项目凭据到 GitHub。

## 二、一键部署

端口 80/443 空闲的服务器：

```bash
cd /opt/cloudplay/server
sudo bash scripts/install.sh --domain cl.520123.xyz
sudo python3 scripts/verify.py
```

**当前这台已有 nginx 的 VPS 使用：**

```bash
cd /opt/cloudplay/server
sudo bash scripts/install.sh --domain cl.520123.xyz --existing-nginx
sudo python3 scripts/verify.py
```

脚本仅在缺少 Docker/Compose 时使用 Docker 官方签名 apt 源安装依赖，不执行第三方远程一键脚本。已有 Docker 不会被重装。若系统版本不再提供官方软件包，apt 会明确失败，脚本不伪造安装完成。

重复运行保留原凭据、下载数据、会话与 UID；不会递归修改已有文件权限。已有数据却丢失凭据时会停止，避免重置账号。默认 UID 10001；已有数据必须继续使用原 `--uid`。

nginx 共存模式：仅增加 `cloudplay.conf`，HTTP-01 验证转发给 Caddy 的 80 端口；Caddy 自动申请独立证书。证书就绪后 nginx 使用同一份 Caddy 证书，专用定时任务每小时检测证书变化并校验、重载 nginx。临时启动入口复用本机已有的有效泛域名证书，**不复制、不修改共享证书**。旧 VPS-Downloads 域名配置只在确认归属后备份到 `private/previous-nginx.conf`，旧容器和下载数据保留，卸载 CloudPlay 时可恢复旧入口。

安装日志：`logs/pull-*.log`、`logs/aria2-build.log`。`docker compose ps` 可查看真实健康状态。只有经过 HTTPS 验证后，安装脚本才输出部署成功。

## 三、连接和凭据

安装后查看本机文件：

```bash
sudo cat private/connection.json
```

此文件权限为 600，不会由 Web 服务器提供，已加入 `.gitignore`：

- `server_url`：OpenList 地址。
- `openlist_username` / `openlist_password`：给手机的普通用户，只管理挂载目录。
- `admin_username` / `admin_password`：添加网盘驱动等后台管理；不要给不可信客户端使用。
- `aria2_rpc_url`：`https://cl.520123.xyz/rpc`。
- `aria2_secret`：Aria2 JSON-RPC 的 `token:...`。
- `rpc_username` / `rpc_password`：Caddy HTTP Basic 额外认证，必须与 RPC Secret 同时配置。

不要把 Secret 拼进 URL、浏览器分享链接、日志或仓库。后续 iOS 将保存到 Keychain。当前可使用 OpenList 自带网页验证文件操作。

`/rpc` 只接受 POST。JSON-RPC 示例中 `RPC_SECRET` 和 Basic 认证应从受保护的本机配置读取，不要把真实值粘贴到公开示例：

```json
{"jsonrpc":"2.0","id":"cloudplay","method":"aria2.getVersion","params":["token:RPC_SECRET"]}
```

WebDAV 地址为 `https://cl.520123.xyz/dav/`，使用手机普通用户认证；`下载` 对应共享下载目录。

下载/播放签名有效期设为 1 小时。链接属于临时访问凭据，不要公开；长期播放时新建 Range 请求可能需要刷新签名，后续原生播放器会通过文件路径重新获取链接。

## 四、目录、下载与网盘

```text
server/
  data/aria2/          aria2.conf（含 Secret）、session、DHT
  data/downloads/      Aria2 和 OpenList 同一 /downloads 卷
  data/aria2-temp/     OpenList 内置离线任务的共享临时目录
  data/openlist/       SQLite、挂载驱动凭据、索引
  data/caddy/          自动 HTTPS 证书、ACME 账号
  private/            管理与手机连接信息、旧入口备份
  logs/               构建与拉取日志
  backups/            权限受限的备份包
```

直接添加 Aria2 任务时默认目录 `/downloads`，下载文件自然出现在 OpenList `/下载`，不必重复上传或转存。不下载未选中的完整视频来伪装边下边播。Aria2 不保证媒体索引位置或连续可播放分片，未完成文件即使显示出来也不承诺能播放；不要在下载期间重命名、移动或删除它，先在下载器中停止或移除相应任务。

默认同时下载 2 个任务，上传上限 64 KiB/s，`seed-time=0`，完成后不持续做种；下载过程中仍可能上传 BT 数据。免费软件不会替你保证 OCI 账单永远为零，请在 OCI 查看账号实际免费额度、出站流量和存储使用。项目不创建付费实例、付费磁盘或商业服务。

第三方网盘：使用管理员登录 OpenList 后，在存储管理中选择**本运行版本实际显示的驱动**，按对应官方驱动说明授权。支持挂载不代表支持所有写入、搜索、Range、字幕或免限制下载。没有真实云盘授权时不会声称已完成第三方云盘联调；账号和 Token 只保存在服务器 OpenList 数据中。客户端浏览挂载后的统一文件树，无需保存各云盘长期密钥。

服务器启用数据库搜索索引和自动更新。大型网盘索引可能消耗存储和 API 配额；可在 OpenList 后台限定索引路径与深度。

## 五、日常管理

```bash
sudo bash scripts/manage.sh status
sudo bash scripts/manage.sh start
sudo bash scripts/manage.sh stop
sudo bash scripts/manage.sh restart
sudo bash scripts/manage.sh logs aria2
sudo python3 scripts/verify.py
```

容器采用 `restart: unless-stopped`。正常运行的服务在 Docker 随系统启动后会恢复；手动 stop 的服务保持停止。Aria2 定期保存未完成任务，优雅停止时保存会话。极端断电可能丢失最后 30 秒的任务变更，磁盘中的 `.aria2` 控制文件与已下载数据保留。Aria2 原生会话不提供永久的已完成任务数据库；后续 App 播放/任务历史将独立持久化。

日志按 10 MB × 3 轮转；OpenList 文件日志同样限制。不要直接公开 OpenList 数据目录、Docker 日志或包含下载链接的诊断包。

## 六、备份、升级与恢复

```bash
# 短暂停止本项目以保证 SQLite 一致；不包含体积庞大的视频
sudo python3 scripts/backup.py
# 如确实需要备份视频且磁盘足够
sudo python3 scripts/backup.py --include-downloads
# 核对新版本后修改 install.py 中 IMAGES，再升级并重新验收
sudo bash scripts/upgrade.sh --existing-nginx --domain cl.520123.xyz
```

备份包含密钥和云盘授权，必须离机加密保存，不能上传公开仓库。默认备份未包含下载内容，恢复下载任务必须保留原 `data/downloads` 和临时数据。

恢复脚本只接受空的 `data/private` 目标，拒绝绝对路径、`..`、软硬链接和设备文件。先停止 CloudPlay，把原数据移到独立备份位置，再执行：

```bash
sudo python3 scripts/restore.py /安全目录/cloudplay-时间戳.tar.gz
sudo bash scripts/install.sh --existing-nginx --domain cl.520123.xyz
sudo python3 scripts/verify.py
```

凭据轮换：OpenList 管理员可修改普通用户密码；RPC Secret 修改 `data/aria2/aria2.conf` 后重启 Aria2，并更新 OpenList `aria2_secret` 设置及手机 Keychain。Basic 密码通过 `caddy hash-password` 生成新哈希写入 `config/Caddyfile`，再 `docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile`。同时更新仅本机的 `private/connection.json`，否则安装/验收脚本仍会读取旧凭据。不要使用安装脚本来强制重置已经手动改过的账号。

## 七、卸载

```bash
# 默认只停止并删除本项目容器和网络，保留数据及凭据，恢复旧入口
sudo python3 scripts/uninstall.py
# 永久删除本项目数据（备份目录仍保留），仅在确定后执行
sudo python3 scripts/uninstall.py --purge-data --confirm-domain cl.520123.xyz
```

不会卸载共享 Docker、清理其他镜像或修改其他域名。清理镜像需确认没有其他项目共用后手动处理，禁止 `docker system prune -a --volumes`。

## 八、验证范围

`verify.py` 会实际测试：HTTPS 证书、RPC 两层认证、匿名访问拒绝、普通用户权限、目录与共享卷、上传/下载内容、重命名、移动、复制、WebDAV、HTTP Range 206/416 与 HEAD、真实 Aria2 HTTP 下载、下载后云盘可见、暂停、恢复和容器重启后的任务恢复，并只清理自生成的验收目录。

独立单元测试：`python3 -m unittest discover -s tests -v`。CI 提供 ARM64 镜像拉取、Aria2 构建和脚本测试，但 CI 配置文件本身不代表已经执行成功。公网 BT Peer、第三方网盘授权、iPhone 字幕/音轨与后台传输需分别实测，详见根目录测试记录。

## 网页离线任务完成，但下载文件夹为空

OpenList 与 App 直接创建的 Aria2 任务保存位置不同：App 默认写入 `/downloads`，网页离线任务先写入 `/opt/openlist/data/temp/aria2/<任务 UUID>`，随后由 OpenList 转存到目标云盘目录。因此 Aria2 的“已完成”只表示下载完成，不保证网页的转存任务成功。

本版同时挂载：

| OpenList 云盘目录 | 容器内真实目录 |
| --- | --- |
| `/下载` | `/downloads` |
| `/下载/网页离线` | `/opt/openlist/data/temp/aria2` |

已有部署只需更新脚本并执行下列命令，不必重装、重启下载器或重新下载：

```bash
cd /opt/cloudplay/server
sudo python3 scripts/download_mounts.py
```

脚本幂等，只补充缺失挂载，不移动原文件；发现同名挂载指向其他存储时拒绝覆盖。使用现有普通 App 账号验证两个目录，不授予管理员权限。网页临时文件仍由 Aria2/OpenList 管理，**下载、转存、做种期间不要手动删除、移动、改名**。其中未完成的文件不能当作可播放的完整视频。

OpenList 4.2.9 网页若选择 `upload_download_stream`（直接上传下载流）处理磁力，会在转存时尝试 HTTP 读取 `magnet:`，出现 `failed to resolve host`。后续添加磁力请选普通“上传成功后删除临时文件”或“不删除临时文件”，不要选“直接上传下载流”。这属于网页逐任务策略，本项目没有修改上游镜像或擅自修改已运行任务的策略。“不删除”会保留临时副本，占用额外空间；确认转存完成、且下载器不再使用源文件后再清理。失败的旧任务可以先在 `/下载/网页离线/<任务 UUID>/…` 访问已下载内容，无须再次获取磁力。

CloudPlay 1.0.1 在已完成任务的每个视频文件下显示“播放视频”，核对实际文件长度后才打开。网页临时源已删除时，仅尝试默认 `/下载` 目标下保持相同目录结构的文件；如果网页另选了其他云盘或目录，请从云盘页打开实际目标，不猜测任意目录或扫描整台服务器。`[METADATA]` 项只是 torrent 元数据，详情会指向后续文件任务。
