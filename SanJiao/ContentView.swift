import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(UnlockManager.self) private var unlockManager
    @AppStorage("display_mode") private var displayModeRaw = DisplayMode.system.rawValue

    init() {
        // 一次性迁移旧的 dark_mode (Bool) → display_mode (String)
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "display_mode") == nil {
            if let old = defaults.object(forKey: "dark_mode") as? Bool {
                defaults.set(old ? DisplayMode.dark.rawValue : DisplayMode.light.rawValue,
                             forKey: "display_mode")
            }
            // 全新用户：保持默认 .system，无需写入
        }
    }

    var body: some View {
        @Bindable var state = appState
        ZStack {
            TabRootView()

            // Record sheet
            if appState.showRecordSheet {
                RecordSheet()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }

            // Success overlay
            if appState.showSuccessOverlay {
                SuccessOverlay()
                    .zIndex(20)
            }

            // Onboarding
            if appState.showOnboarding {
                OnboardingView()
                    .zIndex(30)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(DisplayMode(rawValue: displayModeRaw)?.colorScheme)
        .animation(.spring(duration: 0.4), value: appState.showRecordSheet)
        .animation(.easeInOut(duration: 0.5), value: appState.showOnboarding)
        .onAppear {
            appState.ensureBillManagementStartDate()
        }
        .sheet(isPresented: $state.showPaywall) {
            PaywallView()
                .environment(unlockManager)
        }
    }
}

// MARK: - Tab root
struct TabRootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        TabView(selection: $state.selectedTab) {
            TodayView()
                .tabItem { Label("记录", systemImage: "pencil") }
                .tag(Tab.today)

            BillView()
                .tabItem { Label("账单", systemImage: "doc.text") }
                .tag(Tab.bill)

            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar") }
                .tag(Tab.stats)

            MineView()
                .tabItem { Label("我的", systemImage: "person") }
                .tag(Tab.mine)
        }
        .tint(Color.appAccent)
    }
}
