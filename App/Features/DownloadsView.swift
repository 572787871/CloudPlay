import SwiftUI
import UniformTypeIdentifiers

struct DownloadsView: View {
    @EnvironmentObject private var store: AppStore
    let active: Bool
    @State private var tasks: [DownloadTask]=[]
    @State private var add=false
    @State private var mode=0
    @State private var message: String?
    var body: some View {
        VStack(spacing:0) {
            Picker("分类",selection:$mode) { Text("离线任务").tag(0); Text("文件传输").tag(1); Text("历史").tag(2) }.pickerStyle(.segmented).padding()
            if mode==0 {
                if store.selected==nil { EmptyCloud(title:"尚未配置服务器",detail:"请先在设置中添加 Aria2 RPC。") }
                else {
                    List {
                        if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
                        ForEach(tasks) { item in
                            NavigationLink { TaskDetailView(gid:item.gid) } label: {
                                VStack(alignment:.leading,spacing:8) {
                                    HStack { Text(item.title).lineLimit(2); Spacer(); Text(item.stateText).font(.caption).foregroundStyle(.secondary) }
                                    if item.total>0 { ProgressView(value:item.progress); Text("\(Format.bytes(item.completed)) / \(Format.bytes(item.total))").font(.caption) }
                                    else { Text("等待获取元数据和文件大小").font(.caption).foregroundStyle(.secondary) }
                                    Text("↓ \(Format.bytes(item.speed))/s · 连接 \(item.connections ?? "0") · 种子 \(item.numSeeders ?? "0") · 剩余 \(item.eta)").font(.caption2).foregroundStyle(.secondary)
                                }.padding(.vertical,5)
                            }
                            .swipeActions {
                                if item.status=="active" || item.status=="waiting" { Button("暂停") { action("pause",item) }.tint(.orange) }
                                if item.status=="paused" { Button("继续") { action("unpause",item) }.tint(.cyan) }
                            }
                        }
                        if tasks.isEmpty && message==nil { Text("暂无服务器任务，点击 + 添加链接或 torrent。").foregroundStyle(.secondary) }
                    }.refreshable { await refresh() }
                }
            } else if mode==1 { TransfersView(manager:store.transfers) }
            else {
                List(store.taskHistory.filter {$0.serverID==store.selectedID}) { record in
                    VStack(alignment:.leading) { Text(record.name).lineLimit(2); Text("\(record.state) · \(Format.bytes(record.completed)) · \(record.updatedAt.formatted())").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.navigationTitle("下载")
        .toolbar { ToolbarItem(placement:.topBarLeading) { ServerMenu() }; ToolbarItem(placement:.topBarTrailing) { Button { add=true } label: { Image(systemName:"plus") }.disabled(store.selected==nil) } }
        .sheet(isPresented:$add) { AddDownloadView() }
        .task(id:"\(active)-\(store.selectedID?.uuidString ?? "")") {
            guard active else { return }
            while !Task.isCancelled {
                await refresh(); await store.retryTransfers()
                do { try await Task.sleep(nanoseconds:2_000_000_000) } catch { return }
            }
        }
    }
    private func refresh() async {
        guard let profile=store.selected else { return }
        do { let result=try await store.rpc(profile).tasks(); guard !Task.isCancelled else {return}; tasks=result; store.recordTasks(result,profile:profile); message=nil }
        catch { if !Task.isCancelled { message=CloudError.friendly(error) } }
    }
    private func action(_ verb: String,_ item: DownloadTask) { Task { do { try await store.rpc().action(verb,gid:item.gid); await refresh() } catch { store.error=CloudError.friendly(error) } } }
}

struct AddDownloadView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var prefill=""
    var torrent: URL?
    @State private var link=""
    @State private var directory="/downloads"
    @State private var importing=false
    @State private var selectedTorrent: URL?
    @State private var busy=false
    @State private var error: String?
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section("服务器离线下载") {
                    TextField("magnet / HTTPS / HTTP / FTP",text:$link,axis:.vertical).lineLimit(3...6).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
                    PasteButton(payloadType:String.self) { values in link=values.first ?? "" }
                    TextField("服务器保存目录",text:$directory).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("从文件导入 torrent") { importing=true }
                    if let file=selectedTorrent { Label(file.lastPathComponent,systemImage:"doc") }
                }
                Section { Text("服务器独立下载，关闭 App 后仍继续。磁力的元数据任务完成后，后续文件任务会暂停，进入详情选择文件后继续。没有可用 Peer 的磁力可能一直等待。").font(.footnote).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.orange) }
                Button { submit() } label: { if busy { ProgressView() } else { Text("添加到服务器") } }.disabled(busy || store.selected==nil)
            }.navigationTitle("添加下载").toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } } }
                .onAppear { link=prefill; selectedTorrent=torrent; directory=store.selected?.aria2Directory ?? "/downloads" }
                .fileImporter(isPresented:$importing,allowedContentTypes:[UTType(filenameExtension:"torrent") ?? .data]) { result in if case .success(let url)=result { selectedTorrent=url } }
        }
    }
    private func submit() {
        focused=false; busy=true; error=nil
        Task {
            defer { busy=false }
            do {
                let target=try InputValidation.path(directory)
                let root=store.selected?.aria2Directory ?? "/downloads"
                guard target==root || target.hasPrefix(root+"/") else { throw CloudError.message("请将任务保存在已配置的共享下载目录内。") }
                let rpc=try store.rpc()
                if let file=selectedTorrent {
                    let scoped=file.startAccessingSecurityScopedResource(); defer { if scoped {file.stopAccessingSecurityScopedResource()} }
                    guard (try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 8*1024*1024 else { throw CloudError.message("torrent 文件超过 8 MB。") }
                    let data=try Data(contentsOf:file)
                    let _: String=try await rpc.addTorrent(data,directory:target)
                } else { let _: String=try await rpc.add(link,directory:target) }
                dismiss()
            } catch { self.error=CloudError.friendly(error) }
        }
    }
}

struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var phase
    let gid: String
    @State private var item: DownloadTask?
    @State private var selection=Set<String>()
    @State private var loaded=false
    @State private var confirm=false
    @State private var opening: String?
    @State private var message: String?
    var body: some View {
        List {
            if let item {
                Section {
                    Text(item.title).font(.headline)
                    Text("任务：\(item.gid)").font(.caption).textSelection(.enabled)
                    Text(item.stateText)
                    if item.total>0 { ProgressView(value:item.progress); Text("\(Format.bytes(item.completed)) / \(Format.bytes(item.total))") }
                    Text("↓ \(Format.bytes(item.speed))/s · 剩余 \(item.eta)").font(.caption)
                    if let code=item.errorCode, code != "0" { Text(code=="9" ? "服务器磁盘空间不足。" : "下载器错误代码：\(code)").foregroundStyle(.orange) }
                    HStack {
                        if item.status=="active" || item.status=="waiting" { Button("暂停") { act("pause") } }
                        if item.status=="paused" { Button("继续下载") { act("unpause") } }
                        Spacer(); Button("移除任务",role:.destructive) { confirm=true }
                    }
                }
                if let next=item.followedBy, !next.isEmpty { Section("元数据已获取") { ForEach(next,id:\.self) { nextID in NavigationLink("打开后续文件下载任务") { TaskDetailView(gid:nextID) } } } }
                if item.isMetadata {
                    Section { Text("此任务只获取 torrent 元数据，不是视频文件。请打开后续文件下载任务查看视频。").font(.footnote).foregroundStyle(.secondary) }
                } else {
                    Section(item.status == "complete" ? "已下载文件" : "文件选择") {
                        ForEach(item.files ?? []) { file in
                            if item.status == "complete" {
                                VStack(alignment:.leading,spacing:8) {
                                    fileLabel(file)
                                    if CloudFile(name:file.path).isVideo, file.selected == "true",
                                       Int64(file.completedLength) == Int64(file.length), (Int64(file.length) ?? 0) > 0 {
                                        Button { play(file,task:item) } label: {
                                            HStack { Label("播放视频",systemImage:"play.circle.fill"); if opening == file.index { ProgressView() } }
                                        }.disabled(opening != nil).buttonStyle(.borderless)
                                    }
                                }
                            } else {
                                Toggle(isOn:Binding(get:{selection.contains(file.index)},set:{if $0 {selection.insert(file.index)} else {selection.remove(file.index)}})) { fileLabel(file) }
                            }
                        }
                        if (item.files ?? []).isEmpty { Text("等待元数据。没有可用 Peer 时无法获取文件列表。").foregroundStyle(.secondary) }
                        if item.status != "complete" { Button("暂停并保存文件选择") { Task { do {
                            if item.status=="active" || item.status=="waiting" { try await store.rpc().action("pause",gid:gid) }
                            try await store.rpc().selectFiles(selection,gid:gid); await refresh()
                        } catch { message=CloudError.friendly(error) } } }.disabled(selection.isEmpty) }
                    }
                    if let profile=store.selected {
                        Section("云盘位置") {
                            NavigationLink("打开下载文件夹") { FilesView(path:profile.downloadMountPath) }
                            if (item.files ?? []).contains(where:{$0.path.hasPrefix(DownloadFileLocation.webRoot+"/")}) {
                                NavigationLink("打开网页离线文件夹") { FilesView(path:InputValidation.joined(profile.downloadMountPath,DownloadFileLocation.webFolder)) }
                                Text("网页任务可能先保存在临时目录。转存失败时可从“网页离线”进入任务目录；请勿移动或删除仍在下载、转存或做种的文件。").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else { ProgressView("正在读取任务状态…") }
            if let message { Text(message).foregroundStyle(.orange) }
        }.navigationTitle("任务详情")
        .task(id:phase) {
            guard phase == .active else {return}
            while !Task.isCancelled { await refresh(); do {try await Task.sleep(nanoseconds:2_000_000_000)} catch {return} }
        }
        .confirmationDialog("移除任务将停止服务器下载，已下载文件会保留。",isPresented:$confirm,titleVisibility:.visible) {
            Button("移除任务，保留文件",role:.destructive) { act(["complete","error","removed"].contains(item?.status ?? "") ? "removeDownloadResult" : "forceRemove") }
        }
    }
    private func fileLabel(_ file: TorrentFile) -> some View {
        VStack(alignment:.leading) {
            Text((file.path as NSString).lastPathComponent)
            Text(Format.bytes(Int64(file.length) ?? 0)).font(.caption).foregroundStyle(.secondary)
            if file.selected != "true" { Text("未选择下载").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func play(_ file: TorrentFile,task: DownloadTask) {
        guard let profile=store.selected else {return}
        opening=file.index; message=nil
        Task {
            defer {opening=nil}
            do {
                let path=try await store.client(profile).completedFilePath(file,task:task)
                guard store.selectedID == profile.id else {return}
                store.play(path:path,name:(file.path as NSString).lastPathComponent,profile:profile)
            } catch {message=CloudError.friendly(error)}
        }
    }
    private func act(_ action: String) { Task { do { try await store.rpc().action(action,gid:gid); if ["forceRemove","removeDownloadResult"].contains(action) { dismiss() } else { await refresh() } } catch {message=CloudError.friendly(error)} } }
    private func refresh() async {
        do { let value=try await store.rpc().status(gid); guard !Task.isCancelled else{return}; item=value; if !loaded && !(value.files ?? []).isEmpty { selection=Set((value.files ?? []).filter {$0.selected=="true"}.map(\.index)); loaded=true } }
        catch { if !Task.isCancelled {message=CloudError.friendly(error)} }
    }
}

struct TransfersView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var manager: TransferManager
    var body: some View {
        List {
            ForEach(manager.items) { item in
                VStack(alignment:.leading,spacing:6) {
                    Label(item.name,systemImage:item.upload ? "arrow.up.doc" : "arrow.down.doc")
                    Text(item.state).font(.caption).foregroundStyle(.secondary)
                    if item.total>0 { ProgressView(value:item.progress); Text("\(Format.bytes(item.completed)) / \(Format.bytes(item.total))").font(.caption) }
                    if let failure=item.failure { Text(failure).font(.caption).foregroundStyle(.orange) }
                    HStack {
                        if item.taskID != nil { Button("取消") { manager.cancel(item) } }
                        if item.taskID==nil && item.state != "已完成" { Button("重试") { Task {
                            guard let profile=store.profiles.first(where:{$0.id==item.serverID}) else{return}
                            do { await manager.start(manager.prepareRetry(item),client:try store.client(profile),cellular:store.cellular) } catch {store.error=CloudError.friendly(error)}
                        } } }
                        if !item.upload && item.state=="已完成", let path=item.localPath { ShareLink(item:URL(fileURLWithPath:path)) { Text("打开或分享文件") } }
                    }.buttonStyle(.borderless)
                }.padding(.vertical,4)
                .swipeActions { if item.taskID==nil { Button("移除记录",role:.destructive) {manager.remove(item)} } }
            }
            if manager.items.isEmpty { Text("暂无手机文件传输。可在云盘中上传文件，或选择下载到 iPhone。").foregroundStyle(.secondary) }
        }
    }
}
