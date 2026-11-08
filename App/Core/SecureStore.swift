import Foundation
import Security

enum SecureStore {
    private static let service = "CloudPlay.ServerCredentials"
    static func load(_ id: UUID) throws -> ServerCredentials {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service, kSecAttrAccount as String:id.uuidString,
            kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return ServerCredentials() }
        guard status == errSecSuccess, let data = result as? Data else { throw CloudError.message("无法读取 Keychain，请解锁手机后重试。") }
        return try JSONDecoder().decode(ServerCredentials.self, from:data)
    }
    static func save(_ value: ServerCredentials, id: UUID) throws {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service, kSecAttrAccount as String:id.uuidString]
        let data = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [kSecValueData as String:data,
            kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CloudError.message("Keychain 保存失败（\(status)）。") }
    }
    static func delete(_ id: UUID) { SecItemDelete([kSecClass as String:kSecClassGenericPassword,
        kSecAttrService as String:service,kSecAttrAccount as String:id.uuidString] as CFDictionary) }
}

enum LocalFiles {
    static func directory(_ name: String = "") -> URL {
        let base = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CloudPlay",isDirectory:true)
        let url = name.isEmpty ? base : base.appendingPathComponent(name,isDirectory:true)
        try? FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        var mutable = url; try? mutable.setResourceValues(resource)
        return url
    }
    static var documents: URL {
        let url = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        try? FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        return url
    }
    static func read<T: Decodable>(_ name: String, fallback: T) -> T {
        guard let data = try? Data(contentsOf:directory().appendingPathComponent(name)) else { return fallback }
        return (try? JSONDecoder().decode(T.self,from:data)) ?? fallback
    }
    static func write<T: Encodable>(_ value: T, name: String) throws {
        try JSONEncoder().encode(value).write(to:directory().appendingPathComponent(name),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
}
