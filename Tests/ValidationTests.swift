import XCTest
@testable import CloudPlay

final class ValidationTests: XCTestCase {
    func testValidMagnet() throws {
        let link="magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
        XCTAssertEqual(try InputValidation.downloadLink("  "+link+"\n"),link)
    }
    func testInvalidAndV2OnlyMagnets() {
        XCTAssertThrowsError(try InputValidation.downloadLink("magnet:?xt=urn:btih:broken"))
        XCTAssertThrowsError(try InputValidation.downloadLink("magnet:?xt=urn:btmh:1220abcd"))
        XCTAssertThrowsError(try InputValidation.downloadLink("file:///etc/passwd"))
    }
    func testServerRejectsEmbeddedSecretsAndHTTP() {
        XCTAssertThrowsError(try InputValidation.httpsURL("http://example.org"))
        XCTAssertThrowsError(try InputValidation.httpsURL("https://user:secret@example.org"))
        XCTAssertThrowsError(try InputValidation.httpsURL("https://example.org?token=secret"))
    }
    func testPathAndRenameProtection() throws {
        XCTAssertEqual(try InputValidation.path("/下载/影片/"),"/下载/影片")
        XCTAssertThrowsError(try InputValidation.path("/下载/../config"))
        XCTAssertThrowsError(try InputValidation.name("../other"))
        XCTAssertThrowsError(try InputValidation.name("bad\nname"))
        XCTAssertEqual(InputValidation.joined("/","中文.mp4"),"/中文.mp4")
    }
    func testEngineProgressUsesRealLengthsAndUnknownETA() throws {
        let task=try JSONDecoder().decode(DownloadTask.self,from:Data(#"{"gid":"1234","status":"active","totalLength":"1000","completedLength":"125","downloadSpeed":"0"}"#.utf8))
        XCTAssertEqual(task.progress,0.125,accuracy:0.0001)
        XCTAssertEqual(task.eta,"未知")
    }
    func testMissingOptionalFileMetadata() throws {
        let file=try JSONDecoder().decode(CloudFile.self,from:Data(#"{"name":"影片.mkv"}"#.utf8))
        XCTAssertTrue(file.isVideo);XCTAssertEqual(file.size,0)
    }
    func completedTask(_ path: String, dir: String? = nil) throws -> DownloadTask {
        var value: [String:Any] = ["gid":"test", "status":"complete", "files":[[
            "index":"1", "path":path, "length":"100", "completedLength":"100", "selected":"true"]]]
        value["dir"] = dir
        return try JSONDecoder().decode(DownloadTask.self,from:JSONSerialization.data(withJSONObject:value))
    }
    var locationProfile: ServerProfile { ServerProfile(name:"路径测试",serverURL:URL(string:"https://example.org")!,rpcURL:URL(string:"https://example.org/rpc")!) }
    func testNativeTaskLocationPreservesDirectoryAndUnicode() throws {
        let task = try completedTask("/downloads/电影/中文 #1.mkv")
        XCTAssertEqual(DownloadFileLocation.candidates(file:task.files![0],task:task,profile:locationProfile),["/下载/电影/中文 #1.mkv"])
    }
    func testWebTaskLocationAndCompletedTransferFallback() throws {
        let root = DownloadFileLocation.webRoot + "/3bc0c5fa-78ee-4322-ad37-3e5a979984c3"
        let task = try completedTask(root+"/影片/video.mp4", dir:root)
        XCTAssertEqual(task.dir,root)
        XCTAssertEqual(DownloadFileLocation.candidates(file:task.files![0],task:task,profile:locationProfile),[
            "/下载/网页离线/3bc0c5fa-78ee-4322-ad37-3e5a979984c3/影片/video.mp4", "/下载/影片/video.mp4"])
    }
    func testTaskLocationRejectsTraversalUnknownRootsAndPrefixCollisions() throws {
        for path in ["/downloads-other/video.mp4", "/downloads/../secret.mp4", "/downloads/./video.mp4", "/etc/video.mp4", DownloadFileLocation.webRoot+"/not-a-task/video.mp4"] {
            let task = try completedTask(path)
            XCTAssertEqual(DownloadFileLocation.candidates(file:task.files![0],task:task,profile:locationProfile),[],path)
        }
    }
    func testIncompleteUnselectedAndMetadataFilesCannotPlay() throws {
        var task = try completedTask("/downloads/video.mp4")
        task.status = "active"
        XCTAssertTrue(DownloadFileLocation.candidates(file:task.files![0],task:task,profile:locationProfile).isEmpty)
        task.status = "complete"; task.files![0].completedLength = "99"
        XCTAssertTrue(DownloadFileLocation.candidates(file:task.files![0],task:task,profile:locationProfile).isEmpty)
        task.files![0].completedLength = "100"; task.files![0].selected = "false"
        XCTAssertTrue(DownloadFileLocation.candidates(file:task.files![0],task:task,profile:locationProfile).isEmpty)
        task.files![0].selected = "true"; task.followedBy = ["real-video-gid"]
        XCTAssertTrue(task.isMetadata); XCTAssertEqual(task.stateText,"元数据已获取")
        XCTAssertTrue(DownloadFileLocation.candidates(file:task.files![0],task:task,profile:locationProfile).isEmpty)
    }

}
