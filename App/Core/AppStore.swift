import Foundation
import SwiftUI
import AVFoundation

@MainActor final class AppStore: ObservableObject {
    @Published var profiles: [ServerProfile] = LocalFiles.read("servers.json",fallback:[])
    @Published var selectedID: UUID?
    @Published var error: String?
    @Published var playback: PlaybackRequest?
    @Published var playbackHistory: [PlaybackRecord] = LocalFiles.read("playback.json",fallback:[])
    @Published var taskHistory: [TaskRecord] = LocalFiles.read("task-history.json",fallback:[])
    @Published var incomingLink: String?
    @Published var incomingTorrent: URL?
    @Published var connectionImport: ConnectionImport?
    @Published var incomingUpload: URL?
    let transfers = TransferManager()
    private var clients: [UUID:OpenListClient] = [:]
    init() {
        if let saved = UserDefaults.standard.string(forKey:"selectedServer").flatMap(UUID.init(uuidString:)), profiles.contains(where:{$0.id==saved}) { selectedID = saved }
        else { selectedID = profiles.first?.id }
    }
    var selected: ServerProfile? { profiles.first { $0.id == selectedID } }
    var cellular: Bool { UserDefaults.standard.object(forKey:"cellular") as? Bool ?? true }
    func select(_ id: UUID) { selectedID = id; UserDefaults.standard.set(id.uuidString,forKey:"selectedServer") }
    func client(_ profile: ServerProfile) throws -> OpenListClient {
        if let cached = clients[profile.id] { return cached }
        let client = OpenListClient(profile:profile,credentials:try SecureStore.load(profile.id))
        clients[profile.id] = client; return client
    }
    func client() throws -> OpenListClient {
        guard let p = selected else { throw CloudError.message("请先在设置中添加服务器。") }; return try client(p)
    }
    func rpc(_ profile: ServerProfile? = nil) throws -> Aria2Client {
        guard let p = profile ?? selected else { throw CloudError.message("请先配置服务器。") }
        return Aria2Client(profile:p,credentials:try SecureStore.load(p.id))
    }
    func save(profile: ServerProfile, credentials: ServerCredentials) throws {
        try SecureStore.save(credentials,id:profile.id)
        if let i = profiles.firstIndex(where:{$0.id == profile.id}) { profiles[i] = profile } else { profiles.append(profile) }
        clients[profile.id] = nil
        try LocalFiles.write(profiles,name:"servers.json"); select(profile.id)
    }
    func removeProfile(_ profile: ServerProfile) {
        guard !transfers.items.contains(where:{$0.serverID==profile.id && $0.taskID != nil}) else { error = "请先完成或取消该服务器的文件传输。"; return }
        profiles.removeAll { $0.id == profile.id }; clients[profile.id] = nil; SecureStore.delete(profile.id)
        try? LocalFiles.write(profiles,name:"servers.json")
        selectedID = profiles.first?.id
    }
    func play(path: String, name: String, profile: ServerProfile? = nil, resume: Double? = nil) {
        guard let p = profile ?? selected else { error = "请先添加服务器。"; return }
        let previous = playbackHistory.first { $0.serverID == p.id && $0.path == path }
        playback = PlaybackRequest(profile:p,path:path,name:name,resume:resume ?? previous?.seconds ?? 0)
    }
    func record(_ request: PlaybackRequest, seconds: Double, duration: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        playbackHistory.removeAll { $0.serverID==request.profile.id && $0.path==request.path }
        playbackHistory.insert(PlaybackRecord(serverID:request.profile.id,path:request.path,name:request.name,seconds:seconds,duration:duration.isFinite ? duration : 0,updatedAt:Date()),at:0)
        playbackHistory = Array(playbackHistory.prefix(200)); try? LocalFiles.write(playbackHistory,name:"playback.json")
    }
    func recordTasks(_ tasks: [DownloadTask], profile: ServerProfile) {
        for item in tasks where item.status=="complete" || item.status=="error" {
            taskHistory.removeAll { $0.serverID==profile.id && $0.gid==item.gid }
            taskHistory.append(TaskRecord(serverID:profile.id,gid:item.gid,name:item.title,state:item.stateText,completed:item.completed,total:item.total,updatedAt:Date()))
        }
        taskHistory = Array(taskHistory.sorted {$0.updatedAt > $1.updatedAt}.prefix(500))
        try? LocalFiles.write(taskHistory,name:"task-history.json")
    }
    func handle(_ url: URL) {
        do {
            if url.scheme=="cloudplay", let link=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="url"})?.value { incomingLink=try InputValidation.downloadLink(link); return }
            if !url.isFileURL { incomingLink=try InputValidation.downloadLink(url.absoluteString); return }
            let scoped=url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let ext=url.pathExtension.lowercased()
            if ext=="json" {
                let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                guard size<65536 else { throw CloudError.message("连接配置文件过大。") }
                connectionImport=try JSONDecoder().decode(ConnectionImport.self,from:Data(contentsOf:url))
            } else if ["txt","magnet"].contains(ext) {
                let text=try String(contentsOf:url,encoding:.utf8)
                incomingLink=try InputValidation.downloadLink(text)
            } else {
                let target=LocalFiles.directory("Imports").appendingPathComponent(UUID().uuidString+"-"+url.lastPathComponent)
                try FileManager.default.copyItem(at:url,to:target)
                if ext=="torrent" { incomingTorrent=target } else { incomingUpload=target }
            }
        } catch { self.error=CloudError.friendly(error) }
    }
    func scanInbox() {
        guard incomingLink==nil, incomingTorrent==nil, incomingUpload==nil, connectionImport==nil else { return }
        let entries=(try? FileManager.default.contentsOfDirectory(at:LocalFiles.documents,includingPropertiesForKeys:[.isRegularFileKey],options:[.skipsHiddenFiles])) ?? []
        guard let file=entries.first(where:{ (try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true }) else { return }
        handle(file)
        // Staging succeeds before the received document is removed; keep failures for recovery.
        if incomingLink != nil || incomingTorrent != nil || incomingUpload != nil || connectionImport != nil { try? FileManager.default.removeItem(at:file) }
    }
    func upload(_ url: URL, destination: String) async {
        do {
            guard let profile=selected else { throw CloudError.message("请先配置服务器。") }
            let manager=transfers
            let record=try await Task.detached { try manager.addUpload(url,profile:profile,destination:destination) }.value
            await transfers.start(record,client:try client(profile),cellular:cellular)
        } catch { self.error=CloudError.friendly(error) }
    }
    func download(path: String, name: String) async {
        do {
            guard let profile=selected else { throw CloudError.message("请先配置服务器。") }
            let record=transfers.addDownload(profile:profile,path:path,name:name)
            await transfers.start(record,client:try client(profile),cellular:cellular)
        } catch { self.error=CloudError.friendly(error) }
    }
    func retryTransfers() async {
        for profile in profiles {
            for item in transfers.retryable(serverID:profile.id) {
                do { await transfers.start(item,client:try client(profile),cellular:cellular) } catch { self.error=CloudError.friendly(error) }
            }
        }
    }
}
