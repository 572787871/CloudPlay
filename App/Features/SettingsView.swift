import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var add=false
    @State private var importer=false
    @State private var editing: ServerProfile?
    @AppStorage("appearance") private var appearance="system"
    @AppStorage("cellular") private var cellular=true
    private static var notices: String {
        var sections=["ThirdPartyNotices"].compactMap { name in Bundle.main.url(forResource:name,withExtension:"txt").flatMap {try? String(contentsOf:$0,encoding:.utf8)} }
        if let url=Bundle.main.url(forResource:"PodsAcknowledgements",withExtension:"plist"),
           let data=try? Data(contentsOf:url), let object=try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],
           let entries=object["PreferenceSpecifiers"] as? [[String:Any]] {
            sections += entries.compactMap { entry in guard let text=entry["FooterText"] as? String else {return nil}; return ((entry["Title"] as? String) ?? "")+"\n"+text }
        } else if let url=Bundle.main.url(forResource:"LGPL-2.1",withExtension:"txt"), let text=try? String(contentsOf:url,encoding:.utf8) {sections.append(text)}
        return sections.joined(separator:"\n\n")
    }

    var body: some View {
        Form {
            if store.profiles.isEmpty {
                Section { Label("欢迎使用 CloudPlay",systemImage:"cloud.fill").font(.title2.bold()); Text("添加服务器，或导入私人的连接信息文件。账号与访问凭据会安全保存在此设备。").foregroundStyle(.secondary) }
            }
            Section("服务器") {
                ForEach(store.profiles) { profile in
                    HStack {
                        Button { store.select(profile.id) } label: {
                            VStack(alignment:.leading) { Text(profile.name); Text(profile.serverURL.host ?? "").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if store.selectedID==profile.id { Image(systemName:"checkmark.circle.fill").foregroundStyle(.cyan) }
                        Button { editing=profile } label: { Image(systemName:"pencil") }.buttonStyle(.borderless).accessibilityLabel("编辑服务器")
                    }
                    .swipeActions { Button("删除",role:.destructive) { store.removeProfile(profile) } }
                }
                Button("添加服务器",systemImage:"plus") { add=true }
                Button("导入连接信息 JSON",systemImage:"square.and.arrow.down") { importer=true }
            }
            Section("外观和网络") {
                Picker("外观",selection:$appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                Toggle("文件传输允许移动网络",isOn:$cellular)
                Text("该开关控制手机文件上传和下载。云端 Aria2 任务在 VPS 运行，关闭 App 不会停止服务器下载。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("网盘与服务器") {
                if let profile=store.selected { Link("打开 OpenList 管理页面",destination:profile.serverURL) }
                Text("用管理员账号在 OpenList 网页添加该版本实际支持的网盘驱动。挂载成功后会出现在云盘目录中，手机无需保存各网盘长期密钥。").font(.footnote).foregroundStyle(.secondary)
                Text("服务器磁盘、下载目录和 RPC 限速由 VPS 配置管理；本 App 不承诺绕过服务条款、网络限制或 iOS 后台限制。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("本机记录") {
                Button("清除播放历史",role:.destructive) { store.playbackHistory=[]; try? LocalFiles.write(store.playbackHistory,name:"playback.json") }
                Button("清除离线任务历史",role:.destructive) { store.taskHistory=[]; try? LocalFiles.write(store.taskHistory,name:"task-history.json") }
                Text("文件 App → 我的 iPhone → CloudPlay → 下载，可查看主动保存到手机的文件。取消传输不会删除 VPS 上的原文件。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("关于") { Text("CloudPlay 1.0"); NavigationLink("开源许可证与重新链接说明") { ScrollView { Text(Self.notices).font(.footnote).textSelection(.enabled).padding() }.navigationTitle("开源声明") }; Text("原生私人云盘 · Aria2 · OpenList · AVPlayer / VLCKit").font(.footnote); Text("仅访问自己有权使用的内容。BT Peer 可以观察服务器公网 IP，BT 通信并不匿名。").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("设置")
        .sheet(isPresented:$add) { ProfileEditor() }
        .sheet(item:$editing) { ProfileEditor(profile:$0) }
        .fileImporter(isPresented:$importer,allowedContentTypes:[.json]) { result in if case .success(let url)=result { store.handle(url) } }
    }
}

struct ProfileEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var profile: ServerProfile?
    var imported: ConnectionImport?
    @State private var id=UUID()
    @State private var name="私人云盘"
    @State private var address="https://cl.520123.xyz"
    @State private var rpcAddress="https://cl.520123.xyz/rpc"
    @State private var username=""
    @State private var password=""
    @State private var secret=""
    @State private var rpcUser=""
    @State private var rpcPassword=""
    @State private var mount="/下载"
    @State private var directory="/downloads"
    @State private var busy=false
    @State private var result: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") { TextField("名称",text:$name); TextField("HTTPS 服务器地址",text:$address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled() }
                Section("OpenList 登录") { TextField("用户名",text:$username).textInputAutocapitalization(.never).autocorrectionDisabled(); SecureField("密码",text:$password); Button("独立测试云盘连接") { test(rpc:false) } }
                Section("Aria2 JSON-RPC") {
                    TextField("HTTPS RPC 地址",text:$rpcAddress).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Aria2 RPC Secret",text:$secret)
                    TextField("额外认证用户名",text:$rpcUser).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("额外认证密码",text:$rpcPassword)
                    Button("独立测试下载器连接") { test(rpc:true) }
                }
                Section("共享目录映射") { TextField("OpenList 下载目录",text:$mount).textInputAutocapitalization(.never); TextField("Aria2 服务器目录",text:$directory).textInputAutocapitalization(.never); Text("此映射用于从已完成下载任务定位云盘文件。默认 /下载 ↔ /downloads。").font(.footnote).foregroundStyle(.secondary) }
                if busy { ProgressView("正在连接真实服务器…") }
                if let result { Text(result).font(.footnote).textSelection(.enabled) }
            }.navigationTitle(profile==nil ? "添加服务器" : "编辑服务器")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("保存") { save() }.disabled(busy) }
                }
                .task { load() }
        }
    }
    private func values() throws -> (ServerProfile,ServerCredentials) {
        guard !name.isEmpty, !username.isEmpty, !password.isEmpty else { throw CloudError.message("请填写名称、OpenList 用户名和密码。") }
        var p=ServerProfile(id:id,name:name,serverURL:try InputValidation.httpsURL(address),rpcURL:try InputValidation.httpsURL(rpcAddress))
        p.downloadMountPath=try InputValidation.path(mount); p.aria2Directory=try InputValidation.path(directory)
        return (p,ServerCredentials(username:username,password:password,rpcSecret:secret,rpcUsername:rpcUser,rpcPassword:rpcPassword))
    }
    private func load() {
        do {
            if let profile {
                id=profile.id; name=profile.name; address=profile.serverURL.absoluteString; rpcAddress=profile.rpcURL.absoluteString
                mount=profile.downloadMountPath; directory=profile.aria2Directory
                let c=try SecureStore.load(profile.id); username=c.username; password=c.password; secret=c.rpcSecret; rpcUser=c.rpcUsername; rpcPassword=c.rpcPassword
            } else if let imported {
                address=imported.server_url; username=imported.openlist_username; password=imported.openlist_password
                rpcAddress=imported.aria2_rpc_url; secret=imported.aria2_secret; rpcUser=imported.rpc_username ?? ""; rpcPassword=imported.rpc_password ?? ""
            }
        } catch { result=CloudError.friendly(error) }
    }
    private func save() {
        do { let (p,c)=try values(); try store.save(profile:p,credentials:c); dismiss() } catch { result=CloudError.friendly(error) }
    }
    private func test(rpc: Bool) {
        busy=true; result=nil
        Task {
            defer { busy=false }
            do {
                let (p,c)=try values()
                if rpc { let version=try await Aria2Client(profile:p,credentials:c).test(); result="下载器连接成功：Aria2 \(version)" }
                else { try await OpenListClient(profile:p,credentials:c,persistCredentials:false).test(); result="OpenList 登录和账号接口验证成功。" }
            } catch { result=CloudError.friendly(error) }
        }
    }
}
