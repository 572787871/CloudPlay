# 已核实的协议（OpenList v4.2.9 / Aria2 1.37）

接口来自固定版本的 [OpenList router.go](https://github.com/OpenListTeam/OpenList/blob/v4.2.9/server/router.go)、对应 `server/handles`、`drivers/local` 源码和 [Aria2 官方手册](https://aria2.github.io/manual/en/html/aria2c.html)。以执行验收的返回值为准，不假设所有第三方驱动具备写入或 Range 能力。

OpenList 响应包装为 `code/message/data`，HTTP 200 仍可能包含业务错误码。`Authorization` 传登录返回的 Token（不是擅自添加 `Bearer`）。

| 功能 | 方法和路径 | 请求 |
|---|---|---|
| 登录 | POST `/api/auth/login` | username、password、可选 otp_code |
| 当前账号 | GET `/api/me` | Authorization |
| 目录 | POST `/api/fs/list` | path、page、per_page、refresh |
| 文件信息及临时下载 URL | POST `/api/fs/get` | path、password |
| 新建目录 | POST `/api/fs/mkdir` | path |
| 重命名 | POST `/api/fs/rename` | path、name |
| 移动/复制 | POST `/api/fs/move`、`/api/fs/copy` | src_dir、dst_dir、names |
| 删除 | POST `/api/fs/remove` | dir、names |
| 上传 | PUT `/api/fs/put` | 原始文件 body；File-Path 为百分号编码的完整路径；As-Task:false |
| 搜索 | POST `/api/fs/search` | parent、keywords、scope、page、per_page、password；需启用索引 |
| WebDAV | `/dav/` | HTTP Basic；依账号权限控制 |
| 实际驱动列表 | GET `/api/admin/driver/names` | 管理员 Token；不向普通用户提供管理权限 |

文件 `/d/…?sign=…` 下载链接通过 `/api/fs/get` 获取，可能过期，应刷新链接并恢复读取。`Range: bytes=start-end`、HEAD、206/416 已纳入服务器验收，不能据此推断所有远程网盘链接也支持 Range。

Aria2 使用 HTTPS `/rpc`，先通过 Caddy Basic 认证，再在 JSON-RPC params 的第一项发送 `token:Secret`。支持 `aria2.getVersion`、`addUri`、`addTorrent`（base64 torrent）、`tellActive`、`tellWaiting`、`tellStopped`、`tellStatus`、`getFiles`、`pause`、`unpause`、`forceRemove`、`removeDownloadResult`、`changeOption`、`getGlobalStat`、`saveSession` 等官方方法。每次调用必须同时检查 HTTP 状态、JSON-RPC error 和业务状态。

任务删除 API 与删除下载文件不是一回事：Aria2 移除任务不会替客户端安全清理所有文件，后续客户端必须明确区分“移除任务”和“删除文件”。
