import Foundation
import Combine

struct FileTransfer: Codable, Identifiable {
    var id = UUID()
    var serverID: UUID
    var name: String
    var remotePath: String
    var localPath: String?
    var upload: Bool
    var state = "等待连接"
    var completed: Int64 = 0
    var total: Int64 = 0
    var attempts = 0
    var nextRetry: Date?
    var taskID: Int?
    var failure: String?
    var progress: Double { total > 0 ? min(1,Double(completed)/Double(total)) : 0 }
}

final class TransferManager: NSObject, ObservableObject, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "xyz.cloudplay.personal.background-transfers"
    @Published private(set) var items: [FileTransfer] = []
    private let lock = NSRecursiveLock()
    private var records: [FileTransfer] = []
    private var bodies: [Int:Data] = [:]
    private var savedDownloads: [Int:String] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier:Self.identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 24*3600
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        return URLSession(configuration:config,delegate:self,delegateQueue:queue)
    }()
    override init() {
        super.init()
        records = LocalFiles.read("transfers.json",fallback:[])
        items = records
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            let identifiers = Set(tasks.compactMap(\.taskDescription))
            self.lock.lock()
            for i in self.records.indices where (self.records[i].taskID != nil || self.records[i].state == "正在连接") && !identifiers.contains(self.records[i].id.uuidString) {
                self.records[i].taskID = nil
                self.records[i].state = "等待重试"
                self.records[i].nextRetry = Date()
            }
            self.persistLocked(); self.lock.unlock()
        }
    }
    private func persistLocked() {
        try? LocalFiles.write(records,name:"transfers.json")
        let snapshot = records
        DispatchQueue.main.async { self.items = snapshot }
    }
    private func update(_ id: UUID, _ edit: (inout FileTransfer)->Void) {
        lock.lock(); defer { lock.unlock() }
        guard let i = records.firstIndex(where:{ $0.id == id }) else { return }
        edit(&records[i]); persistLocked()
    }
    func addUpload(_ source: URL, profile: ServerProfile, destination: String) throws -> FileTransfer {
        let accessible = source.startAccessingSecurityScopedResource()
        defer { if accessible { source.stopAccessingSecurityScopedResource() } }
        let name = try InputValidation.name(source.lastPathComponent)
        let target = LocalFiles.directory("UploadQueue").appendingPathComponent(UUID().uuidString+"-"+name)
        try FileManager.default.copyItem(at:source,to:target)
        try? FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:target.path)
        let total = (try? target.resourceValues(forKeys:[.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let record = FileTransfer(serverID:profile.id,name:name,remotePath:InputValidation.joined(try InputValidation.path(destination),name),localPath:target.path,upload:true,total:total)
        lock.lock(); records.insert(record,at:0); persistLocked(); lock.unlock()
        return record
    }
    func addDownload(profile: ServerProfile, path: String, name: String) -> FileTransfer {
        let record = FileTransfer(serverID:profile.id,name:name,remotePath:path,upload:false)
        lock.lock(); records.insert(record,at:0); persistLocked(); lock.unlock()
        return record
    }
    private func claim(_ id: UUID) -> FileTransfer? {
        lock.lock(); defer { lock.unlock() }
        guard let i=records.firstIndex(where:{$0.id==id}), records[i].taskID==nil,
              !["正在连接","已完成","已取消"].contains(records[i].state) else { return nil }
        let previous=records[i]
        records[i].state="正在连接"; records[i].attempts += 1; persistLocked()
        return previous
    }
    func start(_ candidate: FileTransfer, client: OpenListClient, cellular: Bool) async {
        guard let record=claim(candidate.id) else { return }
        do {
            let task: URLSessionTask
            if record.upload {
                guard let local = record.localPath, FileManager.default.fileExists(atPath:local) else { throw CloudError.message("上传源文件已不存在。") }
                if record.attempts > 0 { try await client.login() }
                var request = try await client.uploadRequest(path:record.remotePath)
                request.allowsCellularAccess = cellular
                task = session.uploadTask(with:request,fromFile:URL(fileURLWithPath:local))
            } else {
                let detail = try await client.detail(record.remotePath)
                var request = URLRequest(url:detail.raw_url); request.allowsCellularAccess = cellular
                task = session.downloadTask(with:request)
            }
            task.taskDescription = record.id.uuidString
            update(record.id) { $0.taskID = task.taskIdentifier; $0.state = record.upload ? "正在上传" : "下载到手机"; $0.failure = nil; $0.nextRetry = nil }
            task.resume()
        } catch { fail(record.id,error:error) }
    }
    func retryable(serverID: UUID) -> [FileTransfer] {
        lock.lock(); defer { lock.unlock() }
        return records.filter { $0.serverID == serverID && $0.taskID == nil && $0.attempts < 3 && $0.state == "等待重试" && ($0.nextRetry ?? .distantPast) <= Date() }
    }
    func cancel(_ record: FileTransfer) {
        update(record.id) { $0.state = "已取消"; $0.nextRetry = nil; $0.taskID = nil }
        session.getAllTasks { tasks in tasks.filter { $0.taskDescription == record.id.uuidString }.forEach { $0.cancel() } }
        if record.upload, let path = record.localPath { try? FileManager.default.removeItem(atPath:path) }
    }
    func remove(_ record: FileTransfer) {
        if record.taskID != nil { cancel(record) }
        lock.lock(); records.removeAll { $0.id == record.id }; persistLocked(); lock.unlock()
    }
    func prepareRetry(_ record: FileTransfer) -> FileTransfer {
        var next = record; next.attempts = 0; next.taskID = nil
        update(record.id) { $0.attempts = 0; $0.failure = nil; $0.state = "等待重试" }
        return next
    }
    private func fail(_ id: UUID, error: Error) {
        update(id) {
            guard $0.state != "已取消" else { return }
            $0.taskID = nil; $0.failure = CloudError.friendly(error)
            $0.state = $0.attempts < 3 ? "等待重试" : "传输失败"
            $0.nextRetry = Date().addingTimeInterval($0.attempts <= 1 ? 30 : 120)
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        update(id) { $0.completed = totalBytesSent; $0.total = max(0,totalBytesExpectedToSend) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); defer { lock.unlock() }
        if (bodies[dataTask.taskIdentifier]?.count ?? 0) < 65536 { bodies[dataTask.taskIdentifier,default:Data()].append(data.prefix(65536)) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        update(id) { $0.completed = totalBytesWritten; $0.total = max(0,totalBytesExpectedToWrite) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { return }
        lock.lock(); defer { lock.unlock() }
        let name = records.first { $0.id.uuidString == downloadTask.taskDescription }?.name ?? "下载文件"
        let folder = LocalFiles.documents.appendingPathComponent("下载",isDirectory:true)
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let target = folder.appendingPathComponent(String(UUID().uuidString.prefix(8))+"-"+name)
        do { try FileManager.default.moveItem(at:location,to:target); savedDownloads[downloadTask.taskIdentifier] = target.path }
        catch { savedDownloads[downloadTask.taskIdentifier] = "" }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        if let error { fail(id,error:error); return }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { fail(id,error:status == 401 ? CloudError.authentication : CloudError.server(status)); return }
        lock.lock()
        let body = bodies.removeValue(forKey:task.taskIdentifier)
        let saved = savedDownloads.removeValue(forKey:task.taskIdentifier)
        let record = records.first { $0.id == id }
        lock.unlock()
        if record?.upload == true {
            guard let body, let object = try? JSONSerialization.jsonObject(with:body) as? [String:Any], let code = object["code"] as? Int, code == 200 else {
                fail(id,error:CloudError.message("服务器未确认上传成功，请检查权限和剩余空间。")); return
            }
        } else if saved == nil || saved?.isEmpty == true { fail(id,error:CloudError.message("手机文件保存失败，请检查可用空间。")); return }
        update(id) { $0.state = "已完成"; $0.taskID = nil; $0.completed = max($0.total,$0.completed); $0.nextRetry = nil; if let saved { $0.localPath = saved } }
        if record?.upload == true, let source = record?.localPath { try? FileManager.default.removeItem(atPath:source) }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { AppDelegate.backgroundCompletion?(); AppDelegate.backgroundCompletion = nil }
    }
}
