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
}
