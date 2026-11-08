import XCTest
import AVFoundation
@testable import CloudPlay

final class LiveIntegrationTests: XCTestCase {
    private func api() throws -> OpenListClient {
        let env=ProcessInfo.processInfo.environment
        guard let address=env["CLOUDPLAY_TEST_BASE"], let username=env["CLOUDPLAY_TEST_USER"], !username.isEmpty,
              let password=env["CLOUDPLAY_TEST_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("没有临时 VPS 测试账号；跳过真实服务器联调，不冒充已执行")
        }
        let profile=ServerProfile(name:"隔离联调",serverURL:try InputValidation.httpsURL(address),rpcURL:try InputValidation.httpsURL(address+"/rpc"))
        return OpenListClient(profile:profile,credentials:ServerCredentials(username:username,password:password),persistCredentials:false)
    }
    func testLiveOpenListFileOperationsAndConcurrentRanges() async throws {
        let client=try api();try await client.test()
        let folder="/接口验收-"+UUID().uuidString
        try await client.mutate("mkdir",values:["path":.string(folder)])
        addTeardownBlock { try await client.mutate("remove",values:["dir":.string("/"),"names":.array([.string(String(folder.dropFirst()))])]) }
        let content=Data((0..<4096).map {UInt8($0 % 256)})
        var request=try await client.uploadRequest(path:folder+"/上传.bin");request.httpBody=content
        let (uploaded,response)=try await URLSession.shared.data(for:request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
        XCTAssertEqual((try JSONSerialization.jsonObject(with:uploaded) as? [String:Any])?["code"] as? Int,200)
        try await client.mutate("rename",values:["path":.string(folder+"/上传.bin"),"name":.string("已改名.bin")])
        let page=try await client.list(folder);XCTAssertTrue(page.content?.contains {$0.name=="已改名.bin"} == true)
        let detail=try await client.detail(folder+"/已改名.bin")
        try await withThrowingTaskGroup(of:Void.self) { group in
            for start in [0,123,1024,4000] {
                group.addTask {
                    var req=URLRequest(url:detail.raw_url);req.setValue("bytes=\(start)-\(start+63)",forHTTPHeaderField:"Range")
                    let (bytes,response)=try await URLSession.shared.data(for:req)
                    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,206)
                    XCTAssertEqual(bytes,content.subdata(in:start..<(start+64)))
                }
            }
            try await group.waitForAll()
        }
    }
    @MainActor func testLiveHTTPSMP4PlaybackAndSeek() async throws {
        let client=try api();let file=try await client.detail("/generated.mp4")
        let item=AVPlayerItem(url:file.raw_url), player=AVPlayer()
        let ready=keyValueObservingExpectation(for:item,keyPath:"status",expectedValue:AVPlayerItem.Status.readyToPlay.rawValue)
        player.replaceCurrentItem(with:item)
        await fulfillment(of:[ready],timeout:30)
        XCTAssertEqual(item.status,.readyToPlay)
        let progress=expectation(description:"真实 HTTPS MP4 播放时间达到 0.5 秒")
        let token=player.addBoundaryTimeObserver(forTimes:[NSValue(time:CMTime(seconds:0.5,preferredTimescale:600))],queue:.main) {progress.fulfill()}
        defer {player.pause();player.removeTimeObserver(token)}
        player.play();await fulfillment(of:[progress],timeout:20)
        let seek=expectation(description:"真实 HTTPS Range Seek")
        player.seek(to:CMTime(seconds:4,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero) {finished in XCTAssertTrue(finished);seek.fulfill()}
        await fulfillment(of:[seek],timeout:15)
        XCTAssertEqual(player.currentTime().seconds,4,accuracy:0.5)
    }
}
