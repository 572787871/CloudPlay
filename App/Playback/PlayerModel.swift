import Foundation
import AVKit
import MobileVLCKit
import Combine

@MainActor final class PlayerModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    @Published var engine="系统"
    @Published var avPlayer: AVPlayer?
    let vlc=VLCMediaPlayer()
    @Published var seconds: Double=0
    @Published var duration: Double=0
    @Published var buffering=true
    @Published var playing=false
    @Published var failure: String?
    @Published var rate: Float=1
    @Published var audio: [Track]=[]
    @Published var subtitles: [Track]=[]
    var store: AppStore?
    var request: PlaybackRequest?
    private var observation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var observer: Any?
    private var loader: Task<Void,Never>?
    private var generation=UUID()
    private var pendingResume: Double=0
    private var pendingSubtitle: URL?
    private var refreshes=0
    private var saveTick: Double=0
    var hardware=true
    struct Track: Identifiable { let id: Int32; let name: String }
    override init() { super.init(); vlc.delegate=self }
    func configure(store: AppStore, request: PlaybackRequest) {
        self.store=store; self.request=request; seconds=request.resume
        engine=["mkv","avi","webm","ts","m2ts"].contains((request.name as NSString).pathExtension.lowercased()) ? "兼容" : "系统"
        open(at:request.resume)
    }
    func open(at position: Double) {
        loader?.cancel(); generation=UUID(); let ticket=generation
        releasePlayer(); failure=nil; buffering=true; playing=false
        loader=Task { [weak self] in
            guard let self, let store=self.store, let request=self.request else{return}
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
                let detail=try await store.client(request.profile).detail(request.path)
                guard !Task.isCancelled, ticket==self.generation else{return}
                self.pendingResume=position
                if self.engine=="系统" { self.startAV(detail.raw_url) } else { self.startVLC(detail.raw_url) }
            } catch { guard !Task.isCancelled else{return}; self.buffering=false; self.failure=CloudError.friendly(error) }
        }
    }
    private func startAV(_ url: URL) {
        let item=AVPlayerItem(url:url)
        let player=AVPlayer(playerItem:item); player.automaticallyWaitsToMinimizeStalling=true
        avPlayer=player
        observation=item.observe(\.status,options:[.new,.initial]) { [weak self] item,_ in
            let status=item.status
            Task { @MainActor [weak self] in
                guard let self, self.engine=="系统" else{return}
                if status == .failed { self.engine="兼容"; self.open(at:self.seconds) }
                if status == .readyToPlay {
                    if self.pendingResume>0 { self.seek(self.pendingResume); self.pendingResume=0 }
                    self.avPlayer?.playImmediately(atRate:self.rate)
                }
            }
        }
        controlObservation=player.observe(\.timeControlStatus,options:[.new]) { [weak self] player,_ in
            let state=player.timeControlStatus
            Task { @MainActor [weak self] in self?.buffering=state == .waitingToPlayAtSpecifiedRate; self?.playing=state == .playing }
        }
        observer=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:1,preferredTimescale:600),queue:.main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.engine=="系统" else{return}
                let actual=time.seconds
                if actual.isFinite && actual>=0 { self.seconds=actual }
                if let length=self.avPlayer?.currentItem?.duration.seconds, length.isFinite { self.duration=max(0,length) }
                self.periodicSave()
            }
        }
        player.play()
    }
    private func startVLC(_ url: URL) {
        let media=VLCMedia(url:url)
        media.addOption(":network-caching=1500")
        if !hardware { media.addOption(":avcodec-hw=none") }
        vlc.media=media; vlc.play(); vlc.rate=rate
    }
    func switchEngine(_ value: String) { guard engine != value else{return}; engine=value; open(at:seconds) }
    func toggle() {
        if engine=="系统" { if playing {avPlayer?.pause()} else {avPlayer?.playImmediately(atRate:rate)} }
        else { if vlc.isPlaying {vlc.pause()} else {vlc.play();vlc.rate=rate} }
    }
    func seek(_ value: Double) {
        let target=max(0, duration > 0 ? min(value,duration) : value)
        if engine=="系统" {
            avPlayer?.seek(to:CMTime(seconds:target,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)
        } else if vlc.isSeekable { vlc.time=VLCTime(int:Int32(min(target*1000,Double(Int32.max)))) }
    }
    func setRate(_ value: Float) { rate=value; if engine=="系统" {if playing {avPlayer?.rate=value}} else {vlc.rate=value} }
    func addSubtitle(_ source: URL) throws {
        let scope=source.startAccessingSecurityScopedResource();defer {if scope {source.stopAccessingSecurityScopedResource()}}
        guard (try source.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<10*1024*1024 else {throw CloudError.message("字幕文件超过 10 MB。")}
        let url=LocalFiles.directory("Subtitles").appendingPathComponent(UUID().uuidString+"-"+source.lastPathComponent)
        try FileManager.default.copyItem(at:source,to:url); pendingSubtitle=url
        if engine != "兼容" {engine="兼容";open(at:seconds)}
        else { _=vlc.addPlaybackSlave(url,type:.subtitle,enforce:true);pendingSubtitle=nil }
    }
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in self?.updateVLC() }
    }
    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in self?.updateVLC() }
    }
    private func updateVLC() {
        guard engine=="兼容" else{return}
        switch vlc.state {
        case .error:
            buffering=false
            if refreshes<2 { refreshes+=1; open(at:seconds) }
            else {failure="兼容播放器暂时无法读取视频。可刷新链接、关闭硬件解码重试，或检查网盘代理与 Range 支持。"}
            return
        case .opening,.buffering: buffering=true
        default: buffering=false
        }
        playing=vlc.isPlaying
        let actual=Double(vlc.time.intValue)/1000
        if actual>=0 && actual.isFinite {seconds=actual}
        duration=max(0,Double(vlc.media?.length.intValue ?? 0)/1000)
        if vlc.state == .playing {
            if pendingResume>0 && vlc.isSeekable { vlc.time=VLCTime(int:Int32(min(pendingResume*1000,Double(Int32.max)))); pendingResume=0 }
            if let file=pendingSubtitle { _=vlc.addPlaybackSlave(file,type:.subtitle,enforce:true);pendingSubtitle=nil }
        }
        let audioNames=vlc.audioTrackNames as? [String] ?? []
        let audioIDs=vlc.audioTrackIndexes as? [NSNumber] ?? []
        audio=zip(audioIDs,audioNames).map {Track(id:$0.0.int32Value,name:$0.1)}
        let names=vlc.videoSubTitlesNames as? [String] ?? []
        let ids=vlc.videoSubTitlesIndexes as? [NSNumber] ?? []
        subtitles=zip(ids,names).map {Track(id:$0.0.int32Value,name:$0.1)}
        periodicSave()
    }
    private func periodicSave() { if abs(seconds-saveTick)>=5 { saveTick=seconds; save() } }
    func save() { if let request {store?.record(request,seconds:seconds,duration:duration)} }
    private func releasePlayer() {
        if let observer, let avPlayer {avPlayer.removeTimeObserver(observer)}
        observer=nil; observation=nil;controlObservation=nil;avPlayer?.pause();avPlayer=nil
        vlc.stop();audio=[];subtitles=[]
    }
    func stop() {
        save();loader?.cancel();generation=UUID();releasePlayer();vlc.drawable=nil
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
}
