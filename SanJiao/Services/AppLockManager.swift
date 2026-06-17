import SwiftUI
import LocalAuthentication

/// 应用锁：开启后，App 进入后台再回前台（及冷启动）需要 Face ID / Touch ID / 设备密码解锁。
/// 纯本地，不依赖网络；与青羽的隐私定位一致。
@Observable
final class AppLockManager {
    static let enabledKey = "app_lock_enabled"

    /// 本次是否已解锁（运行时状态，被 ContentView 观察以决定是否盖锁屏）
    var isUnlocked: Bool
    /// 正在弹系统认证框，避免重复触发
    private(set) var isAuthenticating = false

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    init() {
        // 冷启动：开了应用锁就先锁住
        isUnlocked = !UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// 设置页开关。开/关都不立即锁住当前会话——锁在下次回到前台时生效。
    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        isUnlocked = true
    }

    /// App 进入后台：开了锁就标记为需重新解锁。
    func lockOnBackground() {
        if isEnabled { isUnlocked = false }
    }

    /// 触发系统认证（生物识别失败回退到设备密码）。
    func authenticate() {
        guard isEnabled, !isUnlocked, !isAuthenticating else { return }
        let context = LAContext()
        context.localizedFallbackTitle = String(localized: "输入手机密码")
        var error: NSError?
        // .deviceOwnerAuthentication = 生物识别，失败/不可用时回退设备密码
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: &error) else {
            // 设备本身没设密码 → 无法认证，放行，避免把用户永久锁在门外
            isUnlocked = true
            return
        }
        isAuthenticating = true
        context.evaluatePolicy(policy, localizedReason: String(localized: "解锁青羽记账")) { success, _ in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                if success {
                    withAnimation(.easeOut(duration: 0.25)) { self.isUnlocked = true }
                }
            }
        }
    }
}

/// 锁屏遮罩——盖住全部内容，认证通过才揭开。
struct AppLockView: View {
    @Environment(AppLockManager.self) private var lock

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.appAccent.opacity(0.12))
                        .frame(width: 92, height: 92)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(Color.appAccent)
                }
                Text("青羽记账已锁定")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                Button { lock.authenticate() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                        Text("解锁")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color.appAccent))
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { lock.authenticate() }
    }
}
