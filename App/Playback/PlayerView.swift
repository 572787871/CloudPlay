import SwiftUI
import AVKit
import MobileVLCKit
import UniformTypeIdentifiers

struct PlayerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let request: PlaybackRequest
    @StateObject private var model=PlayerModel()
    @State private var slider: Double=0
    @State private var dragging=false
    @State private var subtitleImport=false
    @State private var delay: Double=0
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing:12) {
                HStack {
                    Button {model.stop();dismiss()} label:{Image(systemName:"xmark.circle.fill").font(.title)}.accessibilityLabel("关闭播放器")
                    Text(request.name).lineLimit(1).font(.headline)
                    Spacer(minLength:0)
                    Menu {
                        Button("系统播放器") {model.switchEngine("系统")}
                        Button("兼容播放器") {model.switchEngine("兼容")}
                        Button("刷新播放链接") {model.open(at:model.seconds)}
                        Button("关闭硬件解码重试") {model.hardware=false;model.switchEngine("兼容");model.open(at:model.seconds)}
                    } label:{Image(systemName:"ellipsis.circle").font(.title2)}
                }.padding(.horizontal)
                ZStack {
                    if model.engine=="系统", let player=model.avPlayer { NativePlayer(player:player) }
                    else { VLCVideo(player:model.vlc) }
                    if model.buffering { ProgressView("正在读取并缓冲视频…").padding().background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:18)) }
                    if let failure=model.failure {
                        VStack {Text(failure).multilineTextAlignment(.center);Button("重新连接") {model.open(at:model.seconds)}}.padding().background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:18)).padding()
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                if model.engine=="兼容" {
                    VStack(spacing:12) {
                        Slider(value:Binding(get:{dragging ? slider : min(model.seconds,max(model.duration,1))},set:{slider=$0}),in:0...max(model.duration,1),onEditingChanged:{ editing in dragging=editing;if !editing {model.seek(slider)} }).disabled(model.duration<=0 || !model.vlc.isSeekable)
                        HStack {Text(Format.time(model.seconds));Spacer();Text(Format.time(model.duration))}.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        HStack(spacing:32) {
                            Button {model.seek(model.seconds-15)} label:{Image(systemName:"gobackward.15")}
                            Button {model.toggle()} label:{Image(systemName:model.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size:46))}
                            Button {model.seek(model.seconds+15)} label:{Image(systemName:"goforward.15")}
                        }.font(.title)
                        HStack {
                            rateMenu
                            Spacer()
                            Menu("音轨") {ForEach(model.audio) {track in Button(track.name) {model.vlc.currentAudioTrackIndex=track.id}}}.disabled(model.audio.isEmpty)
                            Spacer()
                            Menu("字幕") {
                                ForEach(model.subtitles) {track in Button(track.name) {model.vlc.currentVideoSubTitleIndex=track.id}}
                                Button("导入外挂字幕") {subtitleImport=true}
                            }
                        }
                        HStack {Text("字幕延迟").font(.caption);Slider(value:$delay,in:-10...10,step:0.1).onChange(of:delay){_,v in model.vlc.currentVideoSubTitleDelay=Int(v*1_000_000)};Text(String(format:"%.1f 秒",delay)).font(.caption.monospacedDigit())}
                    }.padding(.horizontal)
                } else {
                    HStack {rateMenu;Spacer();Button("外挂字幕 / 兼容播放") {subtitleImport=true}}.padding(.horizontal)
                }
                Text("\(model.engine)播放器 · 支持设备旋转 · 播放位置实时保存").font(.caption2).foregroundStyle(.secondary).padding(.bottom,6)
            }.padding(.top,8)
        }.preferredColorScheme(.dark).foregroundStyle(.white)
        .onAppear {model.configure(store:store,request:request)}
        .onDisappear {model.stop()}
        .fileImporter(isPresented:$subtitleImport,allowedContentTypes:[.item]) {result in
            do {let file=try result.get();try model.addSubtitle(file)} catch {model.failure=CloudError.friendly(error)}
        }
    }
    private var rateMenu: some View {
        Menu("\(String(format:"%.2g",model.rate))×") { ForEach([Float(0.5),0.75,1,1.25,1.5,2],id:\.self) {value in Button("\(String(format:"%.2g",value))×") {model.setRate(value)} } }
    }
}

struct NativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let view=AVPlayerViewController();view.player=player;view.showsPlaybackControls=true
        view.allowsPictureInPicturePlayback=false
        return view
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController,context: Context) {uiViewController.player=player}
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController,coordinator:()) {uiViewController.player=nil}
}
struct VLCVideo: UIViewRepresentable {
    let player: VLCMediaPlayer
    func makeUIView(context: Context) -> UIView {let view=UIView();view.backgroundColor = .black;player.drawable=view;return view}
    func updateUIView(_ uiView: UIView,context: Context) {if player.drawable == nil {player.drawable=uiView}}
    static func dismantleUIView(_ uiView: UIView,coordinator:()) {}
}
