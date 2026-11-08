# 实际测试记录

日期：2026-11-05。只记录实际执行结果，不把 CI 配置视为已经运行。

环境：Ubuntu 20.04.6、aarch64、Docker 26.1.3、Compose v2.35.1。独立目录 `/opt/cloudplay/server`，线上入口 `https://cl.520123.xyz`。

## 已完成

- 本地 Python 编译检查、逐个 Shell 语法检查、备份路径安全 **7 项单元测试通过**。
- 实际拉取 OpenList v4.2.9、Caddy 2.11.8、Debian 13-slim，并检查架构为 ARM64。
- Aria2 在该 VPS 实际构建为 1.37.0，软件包为 Debian `1.37.0+debian-3`；镜像与运行进程均为真实产物。
- Caddy 经 ACME HTTP-01 成功取得该域名证书，nginx 使用同一独立证书，端到端校验保持启用；未修改共享泛域名证书。
- **29 项真实接口验收通过**：HTTPS、RPC 额外认证拒绝、RPC 缺失 Secret 拒绝、Aria2 版本/BT 特性、禁用默认 RPC 路径、匿名云盘拒绝、普通用户权限、目录浏览、真实驱动列表、共享卷创建目录、上传并验证内容、重命名、移动、复制、索引搜索、HTTPS 临时下载链接与 1 小时签名有效期、随机 Range 206、HEAD、越界 416、WebDAV 207、添加并暂停任务、恢复 HTTP 下载并完成、SHA-256 内容校验、下载完成后云盘可见、自生成 torrent 导入与 Piece 校验、未完成任务重启恢复且保留暂停状态、上传限速与不持续做种、清理自有验收目录。
- BT 测试数据完全自生成，下载走 HTTPS Web Seed；没有冒充公网 Peer 联调。
- 实际配置备份完成，包权限 600；在隔离临时目录恢复，核对凭据逐字节一致及 SQLite `integrity_check=ok`，未覆盖生产数据。
- 实际执行默认保留数据卸载，核对容器和专用网络移除、数据与凭据保留、旧站点入口恢复；随后重新部署成功。其他 3 个容器 ID 和运行状态未变。
- Docker 自启动状态为 `enabled`，容器采用 `unless-stopped`。没有为了测试而重启共享 VPS 整机。

## 遇到并修复的问题

- Compose 内联 tmpfs 的逗号曾被 YAML 解析为第二个挂载，Docker 报 `invalid mount path: 'mode=1777'`；已改成完整引号字符串并实际启动验证。
- 非 root Aria2 不能读取 COPY 后为 600 的健康脚本；已通过 Dockerfile `COPY --chmod=644` 修复并重新构建。
- nginx 上游默认证书深度过低报 `certificate chain too long`；显式设置验证深度 4，保留证书验证。
- Aria2 对缺失 Secret 的 JSON-RPC 返回 HTTP 400 与 JSON error；验收现同时检查两层错误，未把正常安全拒绝当服务故障。
- 查询到新发布 Caddy v2.11.9，但实际 `docker pull caddy:2.11.9` 返回 `manifest unknown`，未使用虚构镜像。最终使用已实际拉取、验证和联调的 v2.11.8；镜像就绪后可审核升级。

## 日志

- 工作区 `build/logs/stage1-install.log`：真实部署输出。
- 工作区 `build/logs/stage1-verify.log`：29 项验收输出。
- 工作区 `build/logs/stage1-operations.log`：备份、隔离恢复、卸载和重装输出。
- 工作区 `build/logs/aria2-build.log`：真实 Docker 构建日志。
- VPS `server/logs/`：拉取/构建和最后一次失败原因；日志目录不提交源码仓库。

## 未完成 / 未执行

- iOS Xcode 工程、iOS 编译、未签名 IPA、真机、字幕/音轨、后台 URLSession 与分享扩展：属于阶段 2–5，当前未宣称完成。
- 第三方网盘真实授权和读写：没有凭据，只有运行版本驱动列表验证。
- 公网 magnet 元数据获取、Peer 性能与移动网络视频播放：未实测，不能承诺某条磁力可用或提速。
- 整台 VPS 重启、OCI 控制台规则和免费配额核对：未执行；不影响已有服务。
- GitHub Actions 配置已创建，尚未发布新仓库或触发工作流。


## 2026-11-08 客户端开发与复测

- 新增原生 iOS 源码、Xcode 工程与单元/UI 测试，Linux 本机无 Xcode，未把静态检查当作 iOS 编译。GitHub macOS CI 已触发，最终结果将在完成后补录。
- 服务端 GitHub ARM64 CI 实际通过：7 项 Python 安全单元测试、3 个 ARM64 镜像拉取与架构断言、Aria2 镜像构建并运行真实版本检查。运行：https://github.com/572787871/CloudPlay/actions/runs/42482403449 。
- VPS 复测：22 项认证、普通账号权限、驱动清单、文件 CRUD/复制/搜索、签名有效期、Range/HEAD/WebDAV 检查通过。使用自生成内容，SHA 内容检查由上传/复制的实际字节断言完成。
- 原有手机账号登录返回业务码 401，管理员账号正常。为避免擅自重置账号，临时创建权限等同的普通验收账号，复测结束删除。VPS 已有 1 个用户下载任务，因此本轮不重复重启/下载恢复测试，保留第一阶段的对应证据。
- 未执行：签名后 iPhone 安装、真机 MP4/MKV 播放与随机 Seek、真实外部网盘授权、公共磁力 Peer 速度、整台 VPS 重启、实际蜂窝切换和后台系统终止测试。
