import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @EnvironmentObject private var store: AppStore
    let path: String
    @State private var files: [CloudFile]=[]
    @State private var query=""
    @State private var loading=false
    @State private var page=1
    @State private var more=false
    @State private var selected=Set<String>()
    @State private var selecting=false
    @State private var sort="name"
    @State private var operation: String?
    @State private var text=""
    @State private var names: [String]=[]
    @State private var importer=false
    @State private var deleteConfirm=false
    @State private var share: ShareURL?
    @State private var details: CloudFile?
    private var sorted: [CloudFile] {
        files.sorted { a,b in
            if a.is_dir != b.is_dir { return a.is_dir }
            switch sort {
            case "size": return a.size > b.size
            case "modified": return (a.modified ?? "") > (b.modified ?? "")
            default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }
    var body: some View {
        Group {
            if store.selected==nil { EmptyCloud(title:"连接你的私人云盘",detail:"请在设置中添加服务器或导入手机连接信息。") }
            else {
                List {
                    if path=="/" { Section { Label(store.selected?.name ?? "",systemImage:"cloud.fill").font(.title2.bold()); Text("云端文件不占用手机完整文件空间；主动下载后会保存到文件 App。").font(.footnote).foregroundStyle(.secondary) } }
                    if !query.isEmpty { Text("服务器搜索结果").font(.caption).foregroundStyle(.secondary) }
                    ForEach(sorted) { file in row(file) }
                    if loading { HStack { Spacer(); ProgressView(); Spacer() } }
                    if files.isEmpty && !loading { Text(query.isEmpty ? "目录为空" : "没有搜索到文件；请检查服务器索引。").foregroundStyle(.secondary) }
                    if more && query.isEmpty { Button("加载更多") { Task { await load(next:true) } } }
                }
                .refreshable { await load() }
                .searchable(text:$query,prompt:"搜索云盘文件")
                .task(id:query) {
                    if !query.isEmpty { selecting=false; selected=[] }
                    if !query.isEmpty { try? await Task.sleep(nanoseconds:450_000_000) }
                    guard !Task.isCancelled else { return }; await load()
                }
            }
        }
        .navigationTitle(path=="/" ? "云盘" : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(path=="/" ? .large : .inline)
        .toolbar {
            ToolbarItem(placement:.topBarLeading) { if path=="/" { ServerMenu() } }
            ToolbarItemGroup(placement:.topBarTrailing) {
                if store.selected != nil {
                    if selecting {
                        Menu("操作") {
                            Button("移动所选") { begin("move",Array(selected)) }
                            Button("复制所选") { begin("copy",Array(selected)) }
                            Button("删除所选",role:.destructive) { names=Array(selected); deleteConfirm=true }
                        }.disabled(selected.isEmpty)
                    }
                    Menu {
                        Button(selecting ? "完成多选" : "多选文件") { selecting.toggle(); selected=[] }.disabled(!query.isEmpty)
                        Button("新建文件夹") { begin("mkdir",[]) }
                        Button("上传文件") { importer=true }
                        Picker("排序",selection:$sort) { Text("名称").tag("name"); Text("大小").tag("size"); Text("修改时间").tag("modified") }
                    } label: { Image(systemName:"ellipsis.circle") }
                }
            }
        }
        .alert(operationTitle,isPresented:Binding(get:{operation != nil},set:{if !$0 {operation=nil}})) {
            TextField(operation=="move" || operation=="copy" ? "目标目录（如 /下载）" : "名称",text:$text).textInputAutocapitalization(.never)
            Button("取消",role:.cancel) { operation=nil }
            Button("确定") { let action=operation; operation=nil; Task { await mutate(action) } }
        } message: { Text(operation=="move" || operation=="copy" ? "下载中的文件请先停止对应任务；异步复制需刷新目录查看结果。" : "") }
        .confirmationDialog("删除服务器上的文件？此操作可能无法撤销。",isPresented:$deleteConfirm,titleVisibility:.visible) {
            Button("删除 \(names.count) 项",role:.destructive) { Task { await mutate("remove") } }
        }
        .fileImporter(isPresented:$importer,allowedContentTypes:[.item],allowsMultipleSelection:true) { result in
            if case .success(let urls)=result { Task { for url in urls { await store.upload(url,destination:path=="/" ? (store.selected?.downloadMountPath ?? "/下载") : path) } } }
        }
        .sheet(item:$share) { value in ActivitySheet(items:[value.url]) }
        .sheet(item:$details) { file in
            NavigationStack {
                Form {
                    LabeledContent("名称",value:file.name)
                    LabeledContent("大小",value:Format.bytes(file.size))
                    LabeledContent("修改时间",value:file.modified ?? "未知")
                    Button("下载到 iPhone") { details=nil; Task { await store.download(path:InputValidation.joined(file.parent ?? path,file.name),name:file.name) } }
                }.navigationTitle("文件详情").toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { details=nil } } }
            }
        }
    }
    @ViewBuilder private func row(_ file: CloudFile) -> some View {
        let folder=file.parent ?? path
        let full=InputValidation.joined(folder,file.name)
        Group {
            if file.is_dir && !selecting {
                NavigationLink { FilesView(path:full) } label: { fileLabel(file) }
            } else {
                Button {
                    if selecting { if selected.contains(file.name) { selected.remove(file.name) } else { selected.insert(file.name) } }
                    else if file.isVideo { store.play(path:full,name:file.name) }
                    else { details=file }
                } label: { fileLabel(file) }.buttonStyle(.plain)
            }
        }
        .contextMenu {
            if file.isVideo { Button("播放") { store.play(path:full,name:file.name) } }
            if !file.is_dir {
                Button("下载到 iPhone") { Task { await store.download(path:full,name:file.name) } }
                Button("分享临时下载链接") { Task {
                    do { let detail=try await store.client().detail(full); share=ShareURL(url:detail.raw_url) }
                    catch { store.error=CloudError.friendly(error) }
                } }
            }
            if query.isEmpty {
                Button("重命名") { begin("rename",[file.name]); text=file.name }
                Button("移动") { begin("move",[file.name]) }
                Button("复制") { begin("copy",[file.name]) }
                Button("删除",role:.destructive) { names=[file.name]; deleteConfirm=true }
            }
        }
    }
    private func fileLabel(_ file: CloudFile) -> some View {
        HStack(spacing:12) {
            if selecting { Image(systemName:selected.contains(file.name) ? "checkmark.circle.fill" : "circle").foregroundStyle(.cyan) }
            Image(systemName:file.is_dir ? "folder.fill" : file.isVideo ? "play.rectangle.fill" : "doc.fill").font(.title2).foregroundStyle(file.is_dir ? Color.cyan : Color.secondary)
            VStack(alignment:.leading,spacing:3) {
                Text(file.name).lineLimit(2)
                Text(file.is_dir ? "文件夹" : Format.bytes(file.size)).font(.caption).foregroundStyle(.secondary)
                if let modified=file.modified { Text(String(modified.prefix(19)).replacingOccurrences(of:"T",with:" ")).font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer(minLength:0)
        }.contentShape(Rectangle())
    }
    private var operationTitle: String { ["mkdir":"新建文件夹","rename":"重命名","move":"移动到","copy":"复制到"][operation ?? ""] ?? "文件操作" }
    private func begin(_ action: String, _ values: [String]) { operation=action; names=values; text=(action=="move" || action=="copy") ? (store.selected?.downloadMountPath ?? "/下载") : "" }
    private func load(next: Bool = false) async {
        guard store.selected != nil else { return }
        loading=true; defer { loading=false }
        do {
            let targetPage=next ? page+1 : 1
            let result: FilePage
            if query.isEmpty { result=try await store.client().list(path,page:targetPage) }
            else { result=try await store.client().search(path,keyword:query) }
            guard !Task.isCancelled else { return }
            let incoming=result.content ?? []
            if next { files+=incoming } else { files=incoming; selected=[] }
            page=targetPage; more=query.isEmpty && incoming.count==100 && files.count < (result.total ?? Int.max)
        } catch { if !Task.isCancelled { store.error=CloudError.friendly(error) } }
    }
    private func mutate(_ action: String?) async {
        do {
            guard let action else { return }
            let payload: [String:JSONValue]
            switch action {
            case "mkdir": payload=["path":.string(InputValidation.joined(path,try InputValidation.name(text)))]
            case "rename": guard let name=names.first else { return }; payload=["path":.string(InputValidation.joined(path,name)),"name":.string(try InputValidation.name(text))]
            case "move","copy": payload=["src_dir":.string(path),"dst_dir":.string(try InputValidation.path(text)),"names":.array(names.map(JSONValue.string))]
            default: payload=["dir":.string(path),"names":.array(names.map(JSONValue.string))]
            }
            try await store.client().mutate(action,values:payload); await load()
        } catch { store.error=CloudError.friendly(error) }
    }
}

struct ShareURL: Identifiable { let id=UUID(); let url: URL }
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems:items,applicationActivities:nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController,context: Context) {}
}
