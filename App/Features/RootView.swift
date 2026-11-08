import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    var body: some View {
        TabView(selection:$tab) {
            NavigationStack { FilesView(path:"/") }.id(store.selectedID).tabItem { Label("云盘",systemImage:"externaldrive.fill.badge.icloud") }.tag(0)
            NavigationStack { DownloadsView(active:tab==1 && phase == .active) }.tabItem { Label("下载",systemImage:"arrow.down.circle") }.tag(1)
            NavigationStack { HistoryView() }.tabItem { Label("播放",systemImage:"play.rectangle") }.tag(2)
            NavigationStack { SettingsView() }.tabItem { Label("设置",systemImage:"gearshape") }.tag(3)
        }
        .tint(.cyan)
        .onAppear { if store.profiles.isEmpty { tab=3 } }
        .onChange(of:phase) { _, value in
            if value == .active { store.scanInbox(); Task { await store.retryTransfers() } }
        }
        .task { store.scanInbox(); await store.retryTransfers() }
        .fullScreenCover(item:$store.playback) { request in PlayerView(request:request) }
        .sheet(isPresented:Binding(get:{ store.incomingLink != nil || store.incomingTorrent != nil || store.connectionImport != nil || store.incomingUpload != nil },set:{ if !$0 { clearImport() } })) {
            if let config=store.connectionImport { ProfileEditor(imported:config) }
            else if let url=store.incomingUpload { UploadPrompt(url:url) }
            else { AddDownloadView(prefill:store.incomingLink ?? "",torrent:store.incomingTorrent) }
        }
        .alert("提示",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error=nil}})) { Button("知道了") { store.error=nil } } message: { Text(store.error ?? "") }
    }
    private func clearImport() {
        if let file=store.incomingTorrent { try? FileManager.default.removeItem(at:file) }
        if let file=store.incomingUpload { try? FileManager.default.removeItem(at:file) }
        store.incomingLink=nil; store.incomingTorrent=nil; store.incomingUpload=nil; store.connectionImport=nil
    }
}

struct ServerMenu: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Menu {
            ForEach(store.profiles) { profile in Button(profile.name) { store.select(profile.id) } }
        } label: { Label(store.selected?.name ?? "未配置",systemImage:"server.rack").font(.subheadline).lineLimit(1) }
        .disabled(store.profiles.isEmpty)
    }
}
struct EmptyCloud: View {
    let title: String
    let detail: String
    var body: some View { ContentUnavailableView(title,systemImage:"cloud",description:Text(detail)) }
}
struct UploadPrompt: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var folder="/下载"
    var body: some View {
        NavigationStack {
            Form {
                Section("上传到服务器") { Text(url.lastPathComponent); TextField("目标目录",text:$folder).textInputAutocapitalization(.never); Text("文件会先暂存到手机，再由系统安排后台上传；系统强制终止 App 后需重新打开。这个操作不会添加 BT 下载任务。").font(.footnote).foregroundStyle(.secondary) }
                Button("开始上传") { Task { await store.upload(url,destination:folder); dismiss() } }.disabled(store.selected==nil)
            }.navigationTitle("导入文件").toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } } }
                .onAppear { folder=store.selected?.downloadMountPath ?? "/下载" }
        }
    }
}
