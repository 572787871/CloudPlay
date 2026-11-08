import Foundation

private struct Envelope<T: Decodable>: Decodable { let code: Int; let message: String?; let data: T? }
private struct Empty: Decodable {}
private struct LoginResult: Decodable { let token: String }

actor OpenListClient {
    let profile: ServerProfile
    private var credentials: ServerCredentials
    private let session: URLSession
    private let persistCredentials: Bool
    init(profile: ServerProfile, credentials: ServerCredentials, session: URLSession = .shared, persistCredentials: Bool = true) {
        self.profile = profile; self.credentials = credentials; self.session = session; self.persistCredentials = persistCredentials
    }
    private func endpoint(_ path: String) -> URL {
        let base = profile.serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn:"/"))
        return URL(string:base + path)!
    }
    func login() async throws {
        let result: LoginResult = try await perform("/api/auth/login",payload:["username":.string(credentials.username),"password":.string(credentials.password)],retry:false,authenticated:false)
        credentials.token = result.token
        if persistCredentials {
            var current = try SecureStore.load(profile.id)
            if current.username == credentials.username && current.password == credentials.password {
                current.token = result.token
                try SecureStore.save(current,id:profile.id)
            }
        }
    }
    private func perform<T: Decodable>(_ path: String, payload: [String:JSONValue]? = nil,
                                      retry: Bool = true, authenticated: Bool = true) async throws -> T {
        if authenticated && credentials.token.isEmpty { try await login() }
        var req = URLRequest(url:endpoint(path)); req.timeoutInterval = 45
        if let payload {
            req.httpMethod = "POST"; req.httpBody = try JSONEncoder().encode(payload)
            req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        }
        if authenticated { req.setValue(credentials.token,forHTTPHeaderField:"Authorization") }
        let (data,response) = try await session.data(for:req)
        guard let http = response as? HTTPURLResponse else { throw CloudError.message("服务器响应无效。") }
        let value = try? JSONDecoder().decode(Envelope<T>.self,from:data)
        if http.statusCode == 401 || value?.code == 401 {
            if retry && authenticated { try await login(); return try await perform(path,payload:payload,retry:false) }
            throw CloudError.authentication
        }
        if http.statusCode == 403 || value?.code == 403 { throw CloudError.permission }
        guard (200..<300).contains(http.statusCode) else { throw CloudError.server(http.statusCode) }
        guard let value else { throw CloudError.message("无法识别 OpenList 响应，请核对服务器地址。") }
        guard value.code == 200 else {
            if value.message?.localizedCaseInsensitiveContains("space") == true { throw CloudError.message("服务器存储空间不足。") }
            throw CloudError.server(value.code)
        }
        if let result = value.data { return result }
        if let empty = Empty() as? T { return empty }
        throw CloudError.message("服务器返回的数据不完整。")
    }
    func test() async throws { try await login(); let _: JSONValue = try await perform("/api/me") }
    func list(_ path: String, page: Int = 1) async throws -> FilePage {
        try await perform("/api/fs/list",payload:["path":.string(try InputValidation.path(path)),"page":.number(Double(page)),"per_page":.number(100),"refresh":.bool(true)])
    }
    func search(_ path: String, keyword: String) async throws -> FilePage {
        try await perform("/api/fs/search",payload:["parent":.string(path),"keywords":.string(keyword),"scope":.number(0),"page":.number(1),"per_page":.number(100),"password":.string("")])
    }
    func detail(_ path: String) async throws -> FileDetail { try await perform("/api/fs/get",payload:["path":.string(path),"password":.string("")]) }
    func mutate(_ action: String, values: [String:JSONValue]) async throws {
        guard ["mkdir","rename","move","copy","remove"].contains(action) else { throw CloudError.message("不支持的文件操作。") }
        let _: Empty = try await perform("/api/fs/"+action,payload:values)
    }
    func uploadRequest(path: String) async throws -> URLRequest {
        if credentials.token.isEmpty { try await login() }
        var req = URLRequest(url:endpoint("/api/fs/put")); req.httpMethod = "PUT"
        req.setValue(credentials.token,forHTTPHeaderField:"Authorization")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"/-._~"))
        req.setValue(path.addingPercentEncoding(withAllowedCharacters:allowed),forHTTPHeaderField:"File-Path")
        req.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type")
        req.setValue("false",forHTTPHeaderField:"As-Task")
        req.setValue("false",forHTTPHeaderField:"Overwrite")
        req.timeoutInterval = 120
        return req
    }
}

actor Aria2Client {
    let profile: ServerProfile
    let credentials: ServerCredentials
    let session: URLSession
    init(profile: ServerProfile, credentials: ServerCredentials, session: URLSession = .shared) {
        self.profile = profile; self.credentials = credentials; self.session = session
    }
    struct RPCRequest: Encodable { let jsonrpc = "2.0"; let id = UUID().uuidString; let method: String; let params: [JSONValue] }
    private struct RPCError: Decodable { let code: Int; let message: String? }
    private struct RPCResponse<T: Decodable>: Decodable { let result: T?; let error: RPCError? }
    func call<T: Decodable>(_ method: String, params: [JSONValue] = []) async throws -> T {
        var req = URLRequest(url:profile.rpcURL); req.httpMethod = "POST"; req.timeoutInterval = 30
        req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if !credentials.rpcUsername.isEmpty {
            req.setValue("Basic " + Data((credentials.rpcUsername+":"+credentials.rpcPassword).utf8).base64EncodedString(),forHTTPHeaderField:"Authorization")
        }
        req.httpBody = try JSONEncoder().encode(RPCRequest(method:"aria2."+method,params:[.string("token:"+credentials.rpcSecret)]+params))
        let (data,response) = try await session.data(for:req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if [401,403].contains(status) { throw CloudError.authentication }
        if let value = try? JSONDecoder().decode(RPCResponse<T>.self,from:data) {
            if let error = value.error {
                if error.code == 1 { throw CloudError.message("Aria2 拒绝请求，请检查 Secret、任务状态和参数。") }
                throw CloudError.message("Aria2 操作失败（\(error.code)）。")
            }
            if (200..<300).contains(status), let result = value.result { return result }
        }
        throw CloudError.server(status)
    }
    func test() async throws -> String {
        struct Version: Decodable { let version: String }
        let v: Version = try await call("getVersion"); return v.version
    }
    func tasks() async throws -> [DownloadTask] {
        async let active: [DownloadTask] = call("tellActive")
        async let waiting: [DownloadTask] = call("tellWaiting",params:[.number(0),.number(100)])
        async let stopped: [DownloadTask] = call("tellStopped",params:[.number(0),.number(100)])
        let all = try await active + waiting + stopped
        var seen = Set<String>(); return all.filter { seen.insert($0.gid).inserted }
    }
    func status(_ gid: String) async throws -> DownloadTask { try await call("tellStatus",params:[.string(gid)]) }
    func add(_ url: String, directory: String) async throws -> String {
        let link = try InputValidation.downloadLink(url)
        let options: [String:JSONValue] = ["dir":.string(try InputValidation.path(directory)),"pause-metadata":.string("true")]
        return try await call("addUri",params:[.array([.string(link)]),.object(options)])
    }
    func addTorrent(_ data: Data, directory: String) async throws -> String {
        guard !data.isEmpty, data.count <= 8*1024*1024 else { throw CloudError.message("torrent 文件为空或超过 8 MB。") }
        return try await call("addTorrent",params:[.string(data.base64EncodedString()),.array([]),
            .object(["dir":.string(try InputValidation.path(directory)),"pause":.string("true")])])
    }
    func action(_ action: String, gid: String) async throws {
        guard ["pause","unpause","forceRemove","removeDownloadResult"].contains(action) else { throw CloudError.message("无效的任务操作。") }
        let _: String = try await call(action,params:[.string(gid)])
    }
    func selectFiles(_ indexes: Set<String>, gid: String) async throws {
        guard !indexes.isEmpty else { throw CloudError.message("至少选择一个文件。") }
        let _: String = try await call("changeOption",params:[.string(gid),.object(["select-file":.string(indexes.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }.joined(separator:","))])])
    }
}
