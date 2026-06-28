import Foundation
import StoreKit
import Observation

// MARK: - UnlockState

enum UnlockState: Equatable {
    case trial(daysRemaining: Int)
    case unlocked
    case expired

    /// 试用中或已解锁时允许新增记录
    var canRecord: Bool {
        switch self {
        case .trial, .unlocked: return true
        case .expired:          return false
        }
    }

    var daysRemaining: Int? {
        if case .trial(let d) = self { return d }
        return nil
    }
}

// MARK: - UnlockManager

@Observable
final class UnlockManager {

    // ── 配置 ──────────────────────────────────────────────────────────────────
    /// 在 App Store Connect 里创建的非消耗型内购 Product ID，上线前替换此值
    static let productID = "app.qingyu.ios.unlock"
    static let trialDays = 7

    // ── State ─────────────────────────────────────────────────────────────────
    private(set) var state: UnlockState = .trial(daysRemaining: UnlockManager.trialDays)
    private(set) var product: Product?
    private(set) var isPurchasing  = false
    private(set) var isRestoring   = false
    private(set) var purchaseError: String?

    var canRecord:   Bool { state.canRecord }
    var isUnlocked:  Bool { if case .unlocked = state { return true }; return false }

    /// 试用剩余天数文案，仅 trial 状态下有值
    var trialBadgeText: String? {
        guard case .trial(let d) = state else { return nil }
        return d == 0 ? "今天是最后一天" : "试用期还剩 \(d) 天"
    }

    private var updatesTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        updatesTask = listenForTransactions()
        Task { await setup() }
    }

    deinit { updatesTask?.cancel() }

    /// 监听 App Store 侧到达的交易——促销码兑换、其它设备购买、Ask to Buy 批准等
    /// 都通过 Transaction.updates 推送进来，保证 app 运行中也能即时解锁。
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { continue }
                if case .verified(let tx) = result, tx.productID == Self.productID {
                    await tx.finish()
                    await MainActor.run { self.state = .unlocked }
                }
            }
        }
    }

    /// 回前台 / 兑换后重新核对权益——只升级到已解锁，不会把已解锁降级。
    @MainActor
    func refreshEntitlements() async {
        if await hasPurchased() { state = .unlocked }
    }

    // MARK: - Setup

    @MainActor
    func setup() async {
        if await hasPurchased() {
            state = .unlocked
        } else {
            state = computeTrialState()
        }
        await loadProduct()
    }

    // MARK: - Helpers

    private func hasPurchased() async -> Bool {
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == Self.productID {
                return true
            }
        }
        return false
    }

    private func computeTrialState() -> UnlockState {
        // 首次启动日期固化在 Keychain，卸载重装后仍保留
        let firstLaunch: Date
        if let stored = KeychainHelper.loadDate(key: "qingyu_first_launch") {
            firstLaunch = stored
        } else {
            firstLaunch = Date()
            KeychainHelper.saveDate(firstLaunch, key: "qingyu_first_launch")
        }

        let cal = Calendar.current
        let elapsed = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: firstLaunch),
            to: cal.startOfDay(for: Date())
        ).day ?? 0

        let remaining = max(0, Self.trialDays - elapsed)
        return remaining > 0 ? .trial(daysRemaining: remaining) : .expired
    }

    @MainActor
    private func loadProduct() async {
        guard let p = try? await Product.products(for: [Self.productID]).first else { return }
        product = p
    }

    // MARK: - Actions

    @MainActor
    func purchase() async {
        guard let product else {
            purchaseError = "暂时无法连接 App Store，请稍后再试"
            return
        }
        isPurchasing  = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let tx) = verification else {
                    purchaseError = "购买验证失败，请联系支持"
                    return
                }
                await tx.finish()
                state = .unlocked

            case .userCancelled:
                break

            case .pending:
                purchaseError = "购买待处理，可能需要家长批准"

            @unknown default:
                break
            }
        } catch {
            purchaseError = "购买失败，请检查网络后重试"
        }
    }

    // MARK: - DEBUG helpers (仅 Debug 构建可见，发布版本会被完全剔除)
    #if DEBUG
    /// 把首次启动日期重置为"今天"——试用从头再来 7 天
    @MainActor
    func debugResetTrial() {
        KeychainHelper.delete(key: "qingyu_first_launch")
        state = computeTrialState()
    }

    /// 把首次启动日期改为 N 天前——可一键测试"剩 1 天 / 已过期"等场景
    /// - 例如：daysAgo = 6 → 还剩 1 天；daysAgo = 7 → 已过期
    @MainActor
    func debugSetTrialStart(daysAgo: Int) {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        KeychainHelper.saveDate(date, key: "qingyu_first_launch")
        state = computeTrialState()
    }
    #endif

    @MainActor
    func restore() async {
        isRestoring   = true
        purchaseError = nil
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
        } catch {
            purchaseError = "恢复失败，请检查网络后重试"
        }
        if await hasPurchased() {
            state = .unlocked
        } else {
            purchaseError = "未找到可恢复的购买记录"
        }
    }
}
