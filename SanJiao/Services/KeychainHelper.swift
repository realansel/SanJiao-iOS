import Foundation
import Security

/// Minimal Keychain wrapper.
/// Data survives app uninstall/reinstall — unlike UserDefaults.
enum KeychainHelper {

    // MARK: - Public API

    static func saveDate(_ date: Date, key: String) {
        var ti = date.timeIntervalSinceReferenceDate
        let data = Data(bytes: &ti, count: MemoryLayout<Double>.size)
        write(data, key: key)
    }

    static func loadDate(key: String) -> Date? {
        guard let data = read(key: key),
              data.count == MemoryLayout<Double>.size else { return nil }
        let ti = data.withUnsafeBytes { $0.load(as: Double.self) }
        return Date(timeIntervalSinceReferenceDate: ti)
    }

    static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: "app.qingyu.ios"
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Private

    private static func write(_ data: Data, key: String) {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key,
            kSecAttrService:      "app.qingyu.ios",
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func read(key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrAccount:  key,
            kSecAttrService:  "app.qingyu.ios",
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
