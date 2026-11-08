import Foundation

struct ServerProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var serverURL: URL
    var rpcURL: URL
    var downloadMountPath = "/下载"
    var aria2Directory = "/downloads"
}

struct ServerCredentials: Codable, Sendable {
    var username = ""
    var password = ""
    var token = ""
    var rpcSecret = ""
    var rpcUsername = ""
    var rpcPassword = ""
}

struct ConnectionImport: Decodable {
    let server_url: String
    let openlist_username: String
    let openlist_password: String
    let aria2_rpc_url: String
    let aria2_secret: String
    let rpc_username: String?
    let rpc_password: String?
}

enum CloudError: LocalizedError {
    case message(String)
    case authentication
    case permission
    case fileNotFound
    case server(Int)
    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        case .authentication: return "认证失败，请检查账号、密码或 RPC 凭据。"
        case .fileNotFound: return "文件尚未转存、已被移动或已删除，请到云盘确认文件位置。"
        case .permission: return "没有操作权限，请检查服务器账号权限。"
        case .server(let code): return "服务器返回错误（\(code)），请稍后重试。"
        }
    }
    static func friendly(_ error: Error) -> String {
        if let value = error as? CloudError { return value.localizedDescription }
        if let value = error as? URLError {
            switch value.code {
            case .notConnectedToInternet, .networkConnectionLost: return "网络连接已断开，请检查 Wi-Fi 或移动网络。"
            case .timedOut: return "连接超时，请检查服务器状态后重试。"
            case .secureConnectionFailed, .serverCertificateUntrusted: return "HTTPS 证书验证失败，请检查域名和证书。"
            case .cancelled: return "操作已取消。"
            default: return "无法连接服务器（\(value.errorCode)）。"
            }
        }
        if (error as NSError).domain == NSCocoaErrorDomain,
           (error as NSError).code == NSFileWriteOutOfSpaceError { return "手机存储空间不足。" }
        return "操作失败，请检查服务器状态、文件权限或可用空间后重试。"
    }
}

enum InputValidation {
    static func httpsURL(_ input: String) throws -> URL {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw CloudError.message("请输入不含账号密码或查询参数的 HTTPS 地址。")
        }
        return url
    }
    static func downloadLink(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: value), let scheme = parts.scheme?.lowercased() else {
            throw CloudError.message("下载链接格式无效。")
        }
        if scheme == "magnet" {
            let xt = parts.queryItems?.filter { $0.name.lowercased() == "xt" }.compactMap(\.value) ?? []
            let hashes = xt.filter { $0.lowercased().hasPrefix("urn:btih:") }.map { String($0.dropFirst(9)) }
            let valid = hashes.contains { hash in
                hash.range(of: "^(?:[0-9a-fA-F]{40}|[A-Za-z2-7]{32})$", options: .regularExpression) != nil
            }
            guard valid else { throw CloudError.message("此 Aria2 版本需要有效的 BT v1 Info Hash，纯 BT v2 磁力不受支持。") }
        } else {
            guard ["https", "http", "ftp"].contains(scheme), parts.host != nil,
                  parts.user == nil, parts.password == nil else {
                throw CloudError.message("仅支持 magnet、HTTP、HTTPS、FTP 链接；请勿在链接中嵌入密码。")
            }
        }
        return value
    }
    static func path(_ value: String) throws -> String {
        guard value.hasPrefix("/"), !value.contains("\0"),
              !value.split(separator: "/").contains("..") else { throw CloudError.message("请选择以 / 开头且不含 .. 的目录。") }
        return value == "/" ? value : value.trimmingCharacters(in: CharacterSet(charactersIn: "/")).withLeadingSlash
    }
    static func name(_ value: String) throws -> String {
        guard !value.isEmpty, value != ".", value != "..", !value.contains("/"),
              !value.contains("\0"), !value.contains("\n"), !value.contains("\r") else {
            throw CloudError.message("文件名不能为空或包含斜杠、换行及路径跳转。")
        }
        return value
    }
    static func joined(_ folder: String, _ name: String) -> String {
        (folder == "/" ? "" : folder) + "/" + name
    }
}
private extension String { var withLeadingSlash: String { "/" + self } }

struct CloudFile: Decodable, Identifiable, Hashable, Sendable {
    var name: String
    var size: Int64 = 0
    var is_dir: Bool = false
    var modified: String?
    var parent: String?
    var id: String { (parent ?? "") + "/" + name }
    var isVideo: Bool { ["mp4", "mkv", "mov", "m4v", "avi", "webm", "ts", "m2ts"].contains((name as NSString).pathExtension.lowercased()) }
    init(name: String, size: Int64 = 0, is_dir: Bool = false, modified: String? = nil, parent: String? = nil) {
        self.name = name; self.size = size; self.is_dir = is_dir; self.modified = modified; self.parent = parent
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        is_dir = try c.decodeIfPresent(Bool.self, forKey: .is_dir) ?? false
        modified = try c.decodeIfPresent(String.self, forKey: .modified)
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
    }
    enum CodingKeys: String, CodingKey { case name, size, is_dir, modified, parent }
}
struct FilePage: Decodable { var content: [CloudFile]?; var total: Int? }
struct FileDetail: Decodable { var raw_url: URL; var sign: String?; var size: Int64?; var is_dir: Bool? }

indirect enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
struct TorrentFile: Decodable, Identifiable, Sendable {
    var index: String
    var path: String
    var length: String
    var completedLength: String
    var selected: String
    var id: String { index }
}
struct DownloadTask: Decodable, Identifiable, Sendable {
    var gid: String
    var status: String
    var totalLength: String?
    var completedLength: String?
    var downloadSpeed: String?
    var uploadSpeed: String?
    var numSeeders: String?
    var connections: String?
    var files: [TorrentFile]?
    var followedBy: [String]?
    var dir: String?
    var bittorrent: BTInfo?
    var errorCode: String?
    var id: String { gid }
    var total: Int64 { Int64(totalLength ?? "") ?? 0 }
    var completed: Int64 { Int64(completedLength ?? "") ?? 0 }
    var speed: Int64 { Int64(downloadSpeed ?? "") ?? 0 }
    var progress: Double { total > 0 ? min(1, Double(completed) / Double(total)) : 0 }
    var title: String { bittorrent?.info?.name ?? files?.first.map { ($0.path as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 } ?? "正在获取元数据" }
    var isMetadata: Bool { !(followedBy ?? []).isEmpty || files?.first.map { ($0.path as NSString).lastPathComponent.hasPrefix("[METADATA]") } == true }
    var stateText: String {
        if isMetadata && status == "complete" { return "元数据已获取" }
        return ["active":"下载中", "waiting":"等待中", "paused":"已暂停", "error":"下载错误", "complete":"已完成", "removed":"已移除"][status] ?? status
    }
    var eta: String { speed > 0 && total > completed ? Format.time(Double(total-completed) / Double(speed)) : "未知" }
    struct BTInfo: Decodable, Sendable { var info: Info?; struct Info: Decodable, Sendable { var name: String? } }
}
struct PlaybackRecord: Codable, Identifiable {
    var id: String { serverID.uuidString + path }
    var serverID: UUID
    var path: String
    var name: String
    var seconds: Double
    var duration: Double
    var updatedAt: Date
}
struct TaskRecord: Codable, Identifiable {
    var id: String { serverID.uuidString + gid }
    var serverID: UUID
    var gid: String
    var name: String
    var state: String
    var completed: Int64
    var total: Int64
    var updatedAt: Date
}
struct PlaybackRequest: Identifiable {
    let id = UUID()
    let profile: ServerProfile
    let path: String
    let name: String
    var resume: Double = 0
}
enum Format {
    static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    static func time(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "--:--" }
        let v = Int(min(value, 359999))
        return String(format: "%d:%02d:%02d", v/3600, (v/60)%60, v%60)
    }
}

/// Maps Aria2 container paths to the configured OpenList mounts without guessing arbitrary system paths.
enum DownloadFileLocation {
    static let webRoot = "/opt/openlist/data/temp/aria2"
    static let webFolder = "网页离线"

    static func candidates(file: TorrentFile, task: DownloadTask, profile: ServerProfile) -> [String] {
        guard task.status == "complete", !task.isMetadata, file.selected == "true",
              let length = Int64(file.length), length > 0,
              Int64(file.completedLength) == length,
              let path = clean(file.path), let root = clean(profile.aria2Directory),
              let mount = clean(profile.downloadMountPath) else { return [] }
        if let suffix = relative(path, to: root) {
            return [InputValidation.joined(mount, suffix)]
        }
        guard let suffix = relative(path, to: webRoot) else { return [] }
        let parts = suffix.split(separator: "/")
        guard parts.count > 1, UUID(uuidString: String(parts[0])) != nil else { return [] }
        // OpenList may copy completed data to the default destination and remove its temporary source.
        // Only use that fallback when Aria2 confirms the exact per-task temporary directory.
        var values = [InputValidation.joined(InputValidation.joined(mount, webFolder), suffix)]
        if let directory = task.dir.flatMap(clean), directory == webRoot + "/" + String(parts[0]) {
            values.append(InputValidation.joined(mount, parts.dropFirst().joined(separator: "/")))
        }
        return values
    }

    private static func clean(_ value: String) -> String? {
        guard value.hasPrefix("/"), !value.contains("\0"), !value.contains("\n"), !value.contains("\r"),
              !value.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        let parts = value.split(separator: "/")
        return "/" + parts.joined(separator: "/")
    }
    private static func relative(_ path: String, to root: String) -> String? {
        let prefix = root == "/" ? "/" : root + "/"
        guard path.hasPrefix(prefix), path.count > prefix.count else { return nil }
        return String(path.dropFirst(prefix.count))
    }
}
