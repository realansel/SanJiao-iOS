import SwiftUI
import SwiftData
import UIKit
import UserNotifications

struct MineView: View {
    @Environment(AppState.self) private var appState
    @Environment(UnlockManager.self) private var unlockManager
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @AppStorage("notification_enabled") private var notificationEnabled = false
    @AppStorage("notification_hour") private var notificationHour = 21
    @AppStorage("notification_minute") private var notificationMinute = 0
    @AppStorage("display_mode") private var displayModeRaw = DisplayMode.system.rawValue
    private var displayMode: DisplayMode {
        DisplayMode(rawValue: displayModeRaw) ?? .system
    }
    @AppStorage(AppStorageKeys.billManagementStartDate) private var billManagementStartTimestamp = 0.0
    @Environment(\.openURL) private var openURL
    @State private var showBillManagement = false
    @State private var billManagementStartMode: BillManagementMode?
    @State private var navResetID = UUID()
    @State private var showFeedbackCopied = false

    private let feedbackEmail = "hello@qingzhang.app"
    /// App Store 数字 ID — 上架审核通过后从 App Store Connect 取到真实 ID 替换此处
    private let appStoreID = "0000000000"
    /// 直接打开 App Store 评分页（itms-apps 协议会唤起 App Store app，不会在 Safari 里弹出来）
    private var appStoreReviewURL: URL? {
        URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review")
    }

    // MARK: - Derived stats
    private var totalRecords: Int { transactions.count }

    /// Days elapsed since the user first started using bill management (inclusive). Minimum 1.
    private var recordingDays: Int {
        guard billManagementStartTimestamp > 0 else { return 1 }
        let firstDate = Date(timeIntervalSince1970: billManagementStartTimestamp)
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: firstDate),
            to: cal.startOfDay(for: Date())
        ).day ?? 0
        return days + 1
    }

    private var monthExpense: Double {
        let cal = Calendar.current
        let now = Date()
        return transactions.filter {
            let c = cal.dateComponents([.year, .month], from: $0.date)
            return c.year == cal.component(.year, from: now)
                && c.month == cal.component(.month, from: now)
                && $0.isExpense && !$0.isRefunded
        }.reduce(0) { $0 + $1.absoluteAmount }
    }

    /// Average seconds per record, based on stored recordDuration.
    /// Only counts records where duration > 0 (i.e. recorded with the current version).
    private var avgRecordTime: String {
        let durations = transactions.compactMap(\.recordDuration)
        guard !durations.isEmpty else { return "--" }
        let avg = durations.reduce(0, +) / Double(durations.count)
        return String(localized: "\(String(format: "%.1f", avg)) 秒")
    }

    private var reminderDateBinding: Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = notificationHour
                c.minute = notificationMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                notificationHour = c.hour ?? 21
                notificationMinute = c.minute ?? 0
                NotificationManager.scheduleDailyReminder(hour: notificationHour, minute: notificationMinute)
            }
        )
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    heroCard.padding(.top, 12)
                    settingsCard
                    #if DEBUG
                    debugTrialCard
                    #endif
                    Text("数据仅存储在本设备  ·  私密安全")
                        .font(.system(size: 10))
                        .foregroundStyle(.appTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 16)
            }
            .background(Color.appBg)
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showBillManagement) {
                BillImportView(startMode: billManagementStartMode)
            }
            .onChange(of: appState.pendingOpenBillManagement) { _, shouldOpen in
                guard shouldOpen else { return }
                switch appState.pendingBillManagementTarget {
                case .home:
                    billManagementStartMode = nil
                case .import:
                    billManagementStartMode = .import
                case .export:
                    billManagementStartMode = .export
                }
                showBillManagement = true
                appState.pendingOpenBillManagement = false
                appState.pendingBillManagementTarget = .home
            }
            .onChange(of: appState.selectedTab) { _, newTab in
                if newTab != .mine {
                    showBillManagement = false
                    billManagementStartMode = nil
                    navResetID = UUID()
                }
                // Re-sync notification toggle whenever Mine tab becomes active
                if newTab == .mine {
                    UNUserNotificationCenter.current().getNotificationSettings { settings in
                        DispatchQueue.main.async {
                            if notificationEnabled && settings.authorizationStatus == .denied {
                                notificationEnabled = false
                            }
                        }
                    }
                }
            }
        }
        .id(navResetID)
    }

    // MARK: - Hero card
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("你已进行账单管理")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .tracking(0.3)
                .padding(.bottom, 8)

            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("\(recordingDays)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(-2)
                Text(" 天")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(spacing: 8) {
                statCell(label: String(localized: "总记录"), value: String(localized: "\(totalRecords) 笔"))
                statCell(label: String(localized: "平均用时"), value: avgRecordTime)
                statCell(label: String(localized: "本月支出"), value: "¥\(Int(monthExpense).formatted())")
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(LinearGradient.accentGradient)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Settings cards
    private var settingsCard: some View {
        VStack(spacing: 12) {
            unlockCard
            dataCard
            notificationCard
            appearanceCard
            supportCard
        }
        .alert("邮箱已复制", isPresented: $showFeedbackCopied) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("已复制开发者邮箱 \(feedbackEmail)")
        }
    }

    // MARK: - Unlock status card

    @ViewBuilder
    private var unlockCard: some View {
        switch unlockManager.state {
        case .unlocked:
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.appAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("悦笺已解锁")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.appPrimary)
                    Text("买断制 · 永久使用 · 感谢支持 ☀️")
                        .font(.system(size: 12))
                        .foregroundStyle(.appSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.appAccent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))

        case .trial(let days):
            Button { appState.showPaywall = true } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.appAccent.opacity(0.2), lineWidth: 3)
                            .frame(width: 36, height: 36)
                        Circle()
                            .trim(from: 0, to: CGFloat(UnlockManager.trialDays - days) / CGFloat(UnlockManager.trialDays))
                            .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 36, height: 36)
                            .rotationEffect(.degrees(-90))
                        Text("\(days)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.appAccent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("试用期还剩 \(days) 天")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.appPrimary)
                        Text("点击了解解锁方式")
                            .font(.system(size: 12))
                            .foregroundStyle(.appSecondary)
                    }
                    Spacer()
                    Text("›")
                        .font(.system(size: 16))
                        .foregroundStyle(.appTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.appCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

        case .expired:
            Button { appState.showPaywall = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.appAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("试用已结束")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.appPrimary)
                        Text("解锁悦笺，继续记录你的消费")
                            .font(.system(size: 12))
                            .foregroundStyle(.appSecondary)
                    }
                    Spacer()
                    Text("解锁")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(LinearGradient.accentGradient)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.appCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    private var dataCard: some View {
        VStack(spacing: 0) {
            sectionHeader(String(localized: "数据"))
            Divider()
            NavigationLink(destination: BillImportView()) {
                settingsRow(icon: "📂", title: String(localized: "账单管理"), subtitle: String(localized: "导入第三方账单，或导出本地账单"))
            }
            .buttonStyle(.plain)
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var notificationCard: some View {
        VStack(spacing: 0) {
            sectionHeader(String(localized: "通知"))
            Divider()
            HStack(spacing: 14) {
                Text("⏰").font(.system(size: 20)).frame(width: 36, alignment: .center)
                Text("记账提醒")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.appPrimary)
                Spacer()
                if notificationEnabled {
                    DatePicker("", selection: reminderDateBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(Color.appAccent)
                        .padding(.trailing, 8)
                }
                Toggle("", isOn: $notificationEnabled)
                    .tint(Color.appAccent)
                    .labelsHidden()
                    .onChange(of: notificationEnabled) { _, newValue in
                        if newValue {
                            NotificationManager.requestAuthorizationIfNeeded(enabled: true, hour: notificationHour, minute: notificationMinute)
                        } else {
                            NotificationManager.cancelDailyReminder()
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var appearanceCard: some View {
        VStack(spacing: 0) {
            sectionHeader(String(localized: "外观"))
            Divider()
            NavigationLink(destination: DisplayModeView()) {
                settingsRow(icon: "🎨", title: String(localized: "显示模式"), subtitle: displayMode.label)
            }
            .buttonStyle(.plain)
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var supportCard: some View {
        VStack(spacing: 0) {
            sectionHeader(String(localized: "支持"))
            Divider()
            NavigationLink(destination: PrivacyStatementView()) {
                HStack(spacing: 14) {
                    Text("🔒").font(.system(size: 20)).frame(width: 36, alignment: .center)
                    Text("安全与隐私")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.appPrimary)
                    Spacer()
                    Text("›").font(.system(size: 16)).foregroundStyle(.appTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 66)
            Button {
                UIPasteboard.general.string = feedbackEmail
                showFeedbackCopied = true
                if let url = URL(string: "mailto:\(feedbackEmail)") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 14) {
                    Text("💌").font(.system(size: 20)).frame(width: 36, alignment: .center)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("意见反馈")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.appPrimary)
                        Text("有想法或遇到问题，欢迎直接告诉我")
                            .font(.system(size: 12))
                            .foregroundStyle(.appSecondary)
                    }
                    Spacer()
                    Text(feedbackEmail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.appAccent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 66)
            Button {
                if let url = appStoreReviewURL {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 14) {
                    Text("⭐").font(.system(size: 20)).frame(width: 36, alignment: .center)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("去 App Store 评分")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.appPrimary)
                        Text("如果它帮到了你，给个好评是最大的鼓励")
                            .font(.system(size: 12))
                            .foregroundStyle(.appSecondary)
                    }
                    Spacer()
                    Text("›").font(.system(size: 16)).foregroundStyle(.appTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.appTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Text(icon).font(.system(size: 20)).frame(width: 36, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.appPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.appSecondary)
            }
            Spacer()
            Text("›").font(.system(size: 16)).foregroundStyle(.appTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    #if DEBUG
    // MARK: - DEBUG 试用调试卡片
    private var debugTrialCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("DEBUG · 试用状态")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.appWarning)
                Spacer()
                Text(currentTrialDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.appSecondary)
            }
            HStack(spacing: 8) {
                debugBtn("重置 (7天)") {
                    Task { @MainActor in unlockManager.debugResetTrial() }
                }
                debugBtn("剩 1 天") {
                    Task { @MainActor in unlockManager.debugSetTrialStart(daysAgo: 6) }
                }
                debugBtn("已过期") {
                    Task { @MainActor in unlockManager.debugSetTrialStart(daysAgo: 7) }
                }
            }
        }
        .padding(14)
        .background(Color.appWarning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.appWarning.opacity(0.35), lineWidth: 1)
        )
    }

    private var currentTrialDescription: String {
        switch unlockManager.state {
        case .trial(let d): return "trial · 剩 \(d) 天"
        case .unlocked:     return "unlocked"
        case .expired:      return "expired"
        }
    }

    @ViewBuilder
    private func debugBtn(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.appPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.appCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
    #endif
}

// MARK: - 显示模式

enum DisplayMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .light:  return String(localized: "浅色")
        case .dark:   return String(localized: "深色")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

private struct DisplayModeView: View {
    @AppStorage("display_mode") private var displayModeRaw = DisplayMode.system.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(DisplayMode.allCases.enumerated()), id: \.element.id) { i, mode in
                    Button {
                        displayModeRaw = mode.rawValue
                    } label: {
                        HStack(spacing: 14) {
                            Text(mode.label)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.appPrimary)
                            Spacer()
                            if displayModeRaw == mode.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.appAccent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if i < DisplayMode.allCases.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Color.appBg)
        .navigationTitle("显示模式")
        .navigationBarTitleDisplayMode(.inline)
    }
}
