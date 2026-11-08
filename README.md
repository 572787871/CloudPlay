# CloudPlay

面向个人的原生 iOS 私人云盘与离线下载项目。免费组件采用 **OpenList、Aria2、Caddy**，服务器为 Oracle Cloud ARM64。仅处理自己有权下载、存储和播放的资源。

服务器与原生 iOS MVP 已完成。SwiftUI 云盘、Aria2 下载、AVPlayer/VLCKit 播放、文件管理、后台传输与播放历史均使用真实接口。iOS arm64 已编译并生成供个人签名的未签名 IPA，ARM 和 Intel 模拟器各 16 项测试通过。真机和 iOS 27 尚未实测。

[下载 IPA、源码和测试日志](https://github.com/572787871/CloudPlay/releases/latest)

- [iOS 安装、构建与已知限制](docs/IOS.md)
- [服务器部署、运维与安全说明](server/README.md)
- [逐项真实测试记录](docs/TEST_RESULTS.md)
- [分阶段完成情况](docs/PHASES.md)
- [已核验 API 与来源](docs/API.md)

服务器端下载不会占用手机完整视频的存储。在线播放仍需要手机缓冲，主动下载到 iPhone 才会保存完整文件。本版提供已完成文件的 HTTP Range 播放；未完成 BT 文件的边下边播尚未实现。

第三方组件许可证归各自项目所有：[OpenList（AGPL-3.0）](https://github.com/OpenListTeam/OpenList)、[Aria2（GPL-2.0-or-later，详见上游 COPYING）](https://github.com/aria2/aria2)、[Caddy（Apache-2.0）](https://github.com/caddyserver/caddy)。iOS 集成未修改的 MobileVLCKit 3.7.5（LGPL-2.1），随源码及 App 提供许可证和重新链接说明。完整源码公开，服务器组件使用各自官方镜像及对应开源构建来源。
