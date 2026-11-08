import XCTest
@testable import CloudPlay

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int,Data))?
    override class func canInit(with request: URLRequest) -> Bool {true}
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
    override func startLoading() {
        do {
            guard let handler=Self.handler else {throw URLError(.badServerResponse)}
            let (status,data)=try handler(request)
            let response=HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch {client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading() {}
}

final class APITests: XCTestCase {
    func session() -> URLSession {let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[StubProtocol.self];return URLSession(configuration:c)}
    var profile: ServerProfile {ServerProfile(name:"接口测试",serverURL:URL(string:"https://unit.example")!,rpcURL:URL(string:"https://rpc.example/rpc")!)}
    func body(_ request: URLRequest) -> Data {
        if let data=request.httpBody {return data}
        guard let stream=request.httpBodyStream else{return Data()}
        stream.open();defer {stream.close()};var data=Data();var buffer=[UInt8](repeating:0,count:4096)
        while stream.hasBytesAvailable {let n=stream.read(&buffer,maxLength:buffer.count);if n<=0 {break};data.append(contentsOf:buffer.prefix(n))}
        return data
    }
    override func tearDown() {StubProtocol.handler=nil;super.tearDown()}
    func testRPCAuthenticationAndPayload() async throws {
        StubProtocol.handler={ request in
            XCTAssertEqual(request.url?.absoluteString,"https://rpc.example/rpc")
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Basic "+Data("rpc-user:rpc-password".utf8).base64EncodedString())
            let json=try JSONSerialization.jsonObject(with:self.body(request)) as! [String:Any]
            XCTAssertEqual(json["method"] as? String,"aria2.getVersion")
            XCTAssertEqual((json["params"] as? [String])?.first,"token:unit-secret")
            return (200,Data(#"{"jsonrpc":"2.0","id":"test","result":{"version":"1.37.0"}}"#.utf8))
        }
        let c=ServerCredentials(username:"u",password:"p",rpcSecret:"unit-secret",rpcUsername:"rpc-user",rpcPassword:"rpc-password")
        let version=try await Aria2Client(profile:profile,credentials:c,session:session()).test()
        XCTAssertEqual(version,"1.37.0")
    }
    func testRPC400BusinessErrorIsNotSuccess() async {
        StubProtocol.handler={ _ in (400,Data(#"{"jsonrpc":"2.0","id":"test","error":{"code":1,"message":"Unauthorized"}}"#.utf8)) }
        do {let _=try await Aria2Client(profile:profile,credentials:ServerCredentials(),session:session()).test();XCTFail("不得把拒绝请求当作成功")}
        catch {XCTAssertTrue(error is CloudError)}
    }
    func testOpenListRefreshesExpiredTokenExactlyOnce() async throws {
        var loginCount=0
        var listCount=0
        StubProtocol.handler={ request in
            if request.url?.path=="/api/auth/login" {loginCount+=1;return (200,Data(#"{"code":200,"data":{"token":"new-token"}}"#.utf8))}
            listCount+=1
            if listCount==1 {return (200,Data(#"{"code":401,"message":"expired"}"#.utf8))}
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"new-token")
            return (200,Data(#"{"code":200,"data":{"content":[{"name":"真实响应结构.mp4","size":12,"is_dir":false}],"total":1}}"#.utf8))
        }
        let credentials=ServerCredentials(username:"unit",password:"unit-password",token:"old-token")
        let api=OpenListClient(profile:profile,credentials:credentials,session:session(),persistCredentials:false)
        let result=try await api.list("/下载")
        XCTAssertEqual(loginCount,1);XCTAssertEqual(listCount,2);XCTAssertEqual(result.content?.first?.name,"真实响应结构.mp4")
    }
    func testOpenListPermissionCodeInsideHTTP200() async {
        StubProtocol.handler={ _ in (200,Data(#"{"code":403,"message":"denied"}"#.utf8)) }
        let api=OpenListClient(profile:profile,credentials:ServerCredentials(token:"token"),session:session(),persistCredentials:false)
        do {let _=try await api.list("/");XCTFail("权限错误未被处理")}
        catch {XCTAssertEqual(error.localizedDescription,CloudError.permission.localizedDescription)}
    }
}
