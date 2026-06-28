import SwiftUI
import SwiftData
import UserNotifications

@main
struct QingyuApp: App {
    @AppStorage("notification_enabled") private var notificationEnabled = false
    @AppStorage("notification_hour") private var notificationHour = 21
    @AppStorage("notification_minute") private var notificationMinute = 0
    @State private var appState = AppState()
    @State private var unlockManager = UnlockManager()
    @State private var appLock = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Transaction.self, Category.self, MerchantCategoryRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            // 给本地数据库设置 .complete 文件保护：设备锁屏后解密密钥被清出内存，数据真正不可读
            QingyuApp.applyCompleteFileProtection(storeURL: config.url)
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// 把 SwiftData 的 SQLite 存储（含 -wal / -shm）提升到 .complete 文件保护等级。
    ///
    /// iOS 默认等级是 completeUntilFirstUserAuthentication：开机首次解锁后，
    /// 解密密钥会常驻内存直到关机，之后再锁屏数据在技术上仍可被解密。
    /// .complete 则会在每次锁屏时清除密钥——锁屏即数据不可读。
    ///
    /// 每次启动都会重新应用一次（幂等操作），以覆盖 SQLite 可能重建的 -wal 文件。
    private static func applyCompleteFileProtection(storeURL: URL) {
        let fm = FileManager.default
        let base = storeURL.path
        let paths = [base, base + "-wal", base + "-shm"]
        for path in paths where fm.fileExists(atPath: path) {
            do {
                try fm.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: path
                )
            } catch {
                #if DEBUG
                print("⚠️ 文件保护等级设置失败: \(path) — \(error)")
                #endif
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(unlockManager)
                .environment(appLock)
                .onAppear {
                    Category.seedDefaultCategories(context: sharedModelContainer.mainContext)
                    appState.checkOnboarding()
                    // Restore an already-authorized reminder without showing a permission prompt.
                    NotificationManager.restoreReminderIfAuthorized(enabled: notificationEnabled, hour: notificationHour, minute: notificationMinute)
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                appLock.lockOnBackground()                 // 退后台→标记需重新解锁
            case .active:
                appLock.authenticate()                     // 回前台→自动唤起认证
                Task { await unlockManager.refreshEntitlements() }  // 回前台→重新核对购买(促销码等)
            default:
                break
            }
        }
    }
}
