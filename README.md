# CloudPlay

面向个人的原生 iOS 私人云盘与离线下载项目。免费组件采用 **OpenList、Aria2、Caddy**，服务器为 Oracle Cloud ARM64。仅处理自己有权下载、存储和播放的资源。

当前优先交付第一阶段服务器。没有使用模拟任务、模拟进度或第三方磁力缓存；不把服务器配置文件冒充完成的 iOS App。

- [服务器部署、运维与安全说明](server/README.md)
- [逐项真实测试记录](docs/TEST_RESULTS.md)
- [分阶段完成情况](docs/PHASES.md)
- [已核验 API 与来源](docs/API.md)

服务器端下载不会占用手机完整视频的存储。后续在线播放仍需要手机缓冲，主动下载到 iPhone 才会保存完整文件。下载中的 BT 视频播放属于后续实验功能，第一阶段仅开放已存在文件的 Range 读取能力。

第三方组件许可证归各自项目所有：[OpenList（AGPL-3.0）](https://github.com/OpenListTeam/OpenList)、[Aria2（GPL-2.0-or-later，详见上游 COPYING）](https://github.com/aria2/aria2)、[Caddy（Apache-2.0）](https://github.com/caddyserver/caddy)。目前不分发这些组件修改版或 iOS 播放器二进制；如后续分发，必须随产物保留许可证并履行相应源码义务。
