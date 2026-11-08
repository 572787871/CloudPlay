# CloudPlay iOS 使用和构建

## 安装与连接

1. GitHub Actions → CloudPlay iOS 未签名 IPA → 最新成功运行 → 下载 `CloudPlay-unsigned-IPA`。IPA **未经签名**，须使用自己的 Apple 开发者身份签名 App 与 Share 扩展后安装。免费个人签名的有效期和扩展支持取决于 Apple 与签名工具，不能保证永久安装。
2. 首次打开 → 设置 → 添加服务器。填写 HTTPS OpenList 地址、普通账号密码、Aria2 HTTPS RPC 地址、RPC Secret 及 RPC 额外认证账号密码。可分别测试云盘与下载器，再保存。支持多个服务器。
3. 也可在手机安全导入第一阶段交付的 `CloudPlay-手机连接信息.json`；这是含凭据的私人文件，不应放入 Git、Actions 或公开链接。保存后删除手机接收目录里的原始配置文件。凭据存入 Keychain，服务器列表文件仅保存非机密元数据。
4. 云盘页可浏览 OpenList 本地目录及已挂载网盘，点击视频播放。第三方网盘须在 OpenList 管理页面使用该版本支持的驱动配置，未做无凭据的虚构联调。

## 离线下载

下载 → + → 添加 magnet、HTTP/HTTPS/FTP 或导入 torrent。目录默认 `/downloads`，对应 OpenList `/下载`。手机没有下载整部影片。元数据磁力的后续文件任务与导入的 torrent 默认暂停，以便在任务详情选择文件，再继续下载。Aria2 1.37 不支持纯 BT v2 磁力。速度、ETA、连接数来自真实 RPC；速度为零不会显示虚构剩余时间。

已完成视频可在任务详情播放，也会显示在云盘下载目录。移除下载任务保留已有服务器文件，物理删除使用云盘页。正在下载的文件请先暂停或移除任务；OpenList 文件管理不能自动感知所有 Aria2 文件锁，不能一边改名/移动一边下载。本版不开放未完成 BT 视频边下边播，Aria2 并不是原项目的验证分片 Range 调度引擎。

## 上传、文件管理与分享

- 云盘右上菜单支持文件上传、新建文件夹、排序和多选；长按可下载、分享临时 URL、复制、移动、重命名、删除。搜索依赖 OpenList 服务端索引；当前搜索最多 100 项，排序作用于已加载项目。
- 上传使用文件型后台 URLSession；进度来自系统传输回调，失败最多自动尝试 3 次，重新进入 App 可触发到期重试，列表也可手动重试。iOS 控制后台调度；用户强制结束 App 可能停止传输，需要重新打开，不保证无限后台运行。暂存上传会占用手机空间。
- 下载到手机保存在「文件 → 我的 iPhone → CloudPlay → 下载」。取消任务不删除 VPS 原文件；移除下载记录也不删除手机已保存的文件。
- 分享扩展通过系统「存储到文件」导入，**请选择我的 iPhone → CloudPlay**，再打开 CloudPlay 处理。这样不依赖收费开发者能力 App Groups，但不是一键唤起；也可直接用文件导入按钮。支持文本磁力、torrent、视频等文件。
- 分享链接是短期下载授权，接收者在失效前可访问；不要公开敏感文件链接。视频播放重新获取原始链接，系统播放器失败可回退 VLCKit，兼容播放器可手动刷新链接，自动错误重试有次数上限。

## 播放

AVPlayer 优先处理 MP4/MOV，MKV 等走 MobileVLCKit 3.7.5。系统播放器使用原生拖动和音轨/字幕菜单；兼容播放器提供倍速、音轨、内嵌/外挂字幕及延迟。横竖屏由系统方向控制。实际硬解能力取决于设备、编码、容器与 SDK，不承诺所有格式均能硬解。兼容播放器可关闭硬件解码重试。

进度和历史采用播放器真实时间；未准备好时显示加载或明确错误。播放历史最多 200 项，离线任务历史最多 500 项；可清除。手机实测仍需用户签名后的 iPhone 完成，CI 单元测试不能替代设备播放。

## 本地编译

需要 macOS、支持 iOS 17+ 的 Xcode、Ruby CocoaPods。仓库提供实际 `.xcodeproj`。执行：

```sh
pod install
open CloudPlay.xcworkspace
```

选择 CloudPlay Scheme，配置自己的 Bundle ID 和 Team（App 与 Share 扩展一起修改）。运行测试：

```sh
xcodebuild test -workspace CloudPlay.xcworkspace -scheme CloudPlay -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild build -workspace CloudPlay.xcworkspace -scheme CloudPlay -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/Device CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
python3 Scripts/package_ipa.py build/Device/Build/Products/Release-iphoneos/CloudPlay.app build/CloudPlay-unsigned.ipa
```

模拟器名称以本机实际安装为准。`Scripts/generate_project.rb` 是工程重建工具，已有工程需显式传 `--regenerate`，之后重新 `pod install`。打包脚本检查真机平台、arm64、扩展及第三方依赖，失败就停止；不会把模拟器 App 当作 IPA。

MobileVLCKit 固定真实 CocoaPods 版本 3.7.5；完整 LGPL 2.1 声明随 App 和源码提供。公开 App 源码及构建脚本可用于修改 LGPL 库后重新链接，详见 `App/Resources/ThirdPartyNotices.txt`。升级 SDK 后须重新验证其 API 与架构，不能直接拿主分支 4.0 API 套入 3.x 二进制。


## 可选真实 VPS 联调测试

`LiveIntegrationTests` 使用隔离普通账号执行真实文件操作、并发 Range 与 HTTPS MP4 播放 Seek。临时账号的 `base_path` 必须限制到专用测试目录，目录内放入 `Tests/Fixtures/generated.mp4`；不得使用管理员或个人文件目录。GitHub Secrets 仅配置 `CLOUDPLAY_TEST_USER` 和 `CLOUDPLAY_TEST_PASSWORD`；通过 Apple 的 `TEST_RUNNER_` 环境传递机制传入 XCTest，不作为构建参数或写进 App。没有临时账号时这 2 项测试明确跳过，其余离线测试照常执行。测试结束应删除账号、隔离目录与这两个 Secrets；不得把跳过记为联调通过。
