import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            Section {
                Label("随时继续观看",systemImage:"play.rectangle.fill").font(.title2.bold())
                Text("从云盘选择视频后，会记录真实播放位置。MP4 优先使用系统播放器，MKV 等格式使用兼容播放器。").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(store.playbackHistory) { item in
                Button {
                    guard let profile=store.profiles.first(where:{$0.id==item.serverID}) else {store.error="该历史对应的服务器已被删除。";return}
                    store.play(path:item.path,name:item.name,profile:profile,resume:item.seconds)
                } label: {
                    HStack {
                        Image(systemName:"play.circle.fill").font(.title).foregroundStyle(.cyan)
                        VStack(alignment:.leading) {
                            Text(item.name).lineLimit(2).foregroundStyle(.primary)
                            Text("\(Format.time(item.seconds)) / \(Format.time(item.duration))").font(.caption).foregroundStyle(.secondary)
                            Text(item.updatedAt.formatted()).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }.swipeActions { Button("删除记录",role:.destructive) { store.playbackHistory.removeAll {$0.id==item.id}; try? LocalFiles.write(store.playbackHistory,name:"playback.json") } }
            }
        }.navigationTitle("播放")
    }
}
