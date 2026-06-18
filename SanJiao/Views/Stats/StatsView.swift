import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var scrollOffset: CGFloat = 0
    @State private var showMonthPicker = false
    private let collapseThreshold: CGFloat = 80

    private var isCollapsed: Bool { scrollOffset > collapseThreshold }

    private var isCurrentMonth: Bool {
        let now = Date()
        let cal = Calendar.current
        return appState.statsMonthYear == cal.component(.year, from: now) &&
               appState.statsMonthMo == cal.component(.month, from: now)
    }

    private var isCurrentYear: Bool {
        appState.statsYear == Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        @Bindable var state = appState
        NavigationStack {
            GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // KVO 探针：零高度，放在内容最顶部，监听 UIScrollView 滚动
                        ScrollOffsetDetector(offset: $scrollOffset)
                            .frame(height: 0)

                        // 完整头部——随滚动自然移出屏幕；不再用 isCollapsed 改它的高度，
                        // 否则"滚动→高度塌缩→内容变短→回弹→头部复原"会形成抖动回弹环。
                        // 折叠后的紧凑控件交给导航栏的 compactStickyBar 呈现。
                        fullHeader

                        if allTransactions.isEmpty {
                            statsEmptyView(viewportHeight: viewport.size.height)
                        } else if appState.statsView == .month {
                            MonthStatsView(transactions: allTransactions)
                        } else {
                            YearStatsView(transactions: allTransactions)
                        }

                        Text("数据仅存储在本设备  ·  私密安全")
                            .font(.system(size: 10))
                            .foregroundStyle(.appTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .padding(.bottom, 12)
                    }
                }
                .onAppear { scrollToPendingTarget(using: proxy) }
                .onChange(of: appState.pendingStatsScrollTarget) { _, _ in
                    scrollToPendingTarget(using: proxy)
                }
                .onChange(of: appState.statsView) { _, _ in
                    scrollToPendingTarget(using: proxy)
                }
            }
            }
            .background(Color.appBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarBackground(isCollapsed ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                if isCollapsed {
                    ToolbarItem(placement: .principal) {
                        compactStickyBar
                    }
                }
            }
            .sheet(isPresented: $showMonthPicker) {
                MonthPickerSheet(
                    year: $state.statsMonthYear,
                    month: $state.statsMonthMo,
                    availableMonths: YearMonth.availableMonths(from: allTransactions)
                )
                .presentationDetents([.height(330)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Full header（顶部，未滚动时显示）

    @ViewBuilder private var fullHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "统计"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.appPrimary)
                    .tracking(-0.5)
                Spacer()
                modeSegmented
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)

            if !allTransactions.isEmpty {
                periodNavRow
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
    }

    /// 月/年模式段控（完整版）
    private var modeSegmented: some View {
        HStack(spacing: 0) {
            segBtn(label: String(localized: "月"), type: .month)
            segBtn(label: String(localized: "年"), type: .year)
        }
        .padding(2)
        .background(Color.appSeparator)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// 月/年导航行（完整版，根据模式自动切换）
    @ViewBuilder private var periodNavRow: some View {
        HStack(spacing: 10) {
            if appState.statsView == .month {
                monthChevron(systemName: "chevron.left", disabled: false) {
                    appState.changeStatsMonth(-1)
                }
                Button { showMonthPicker = true } label: {
                    HStack(spacing: 4) {
                        Text("\(String(appState.statsMonthYear))年\(appState.statsMonthMo)月")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.appPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.appTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                monthChevron(systemName: "chevron.right", disabled: isCurrentMonth) {
                    appState.changeStatsMonth(1)
                }
            } else {
                monthChevron(systemName: "chevron.left", disabled: false) {
                    appState.changeStatsYear(-1)
                }
                Text("\(String(appState.statsYear))年")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                monthChevron(systemName: "chevron.right", disabled: isCurrentYear) {
                    appState.changeStatsYear(1)
                }
            }
            Spacer()
        }
    }

    // MARK: - Compact sticky bar（滚动后塞进 nav bar）

    private var compactStickyBar: some View {
        HStack(spacing: 10) {
            // 期段导航（紧凑）
            HStack(spacing: 6) {
                if appState.statsView == .month {
                    compactChevron(systemName: "chevron.left", disabled: false) {
                        appState.changeStatsMonth(-1)
                    }
                    Button { showMonthPicker = true } label: {
                        HStack(spacing: 3) {
                            Text("\(String(appState.statsMonthYear))·\(appState.statsMonthMo)月")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.appPrimary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.appTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    compactChevron(systemName: "chevron.right", disabled: isCurrentMonth) {
                        appState.changeStatsMonth(1)
                    }
                } else {
                    compactChevron(systemName: "chevron.left", disabled: false) {
                        appState.changeStatsYear(-1)
                    }
                    Text("\(String(appState.statsYear))年")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.appPrimary)
                    compactChevron(systemName: "chevron.right", disabled: isCurrentYear) {
                        appState.changeStatsYear(1)
                    }
                }
            }
            Spacer(minLength: 4)
            // 紧凑模式段控
            HStack(spacing: 2) {
                compactSegBtn(label: String(localized: "月"), type: .month)
                compactSegBtn(label: String(localized: "年"), type: .year)
            }
            .padding(2)
            .background(Color.appSeparator)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    @ViewBuilder private func statsEmptyView(viewportHeight: CGFloat) -> some View {
        VStack(spacing: 10) {
            EmptyStateIcon(systemName: "chart.bar.xaxis")
                .padding(.bottom, 4)
            Text(String(localized: "还没有统计数据"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.appSecondary)
            Text(String(localized: "记录几笔账单后，这里会展示你的支出趋势与分布"))
                .font(.system(size: 13))
                .foregroundStyle(.appTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        // 下移到约 1/3 屏处，不再贴着头部漂在上方
        .padding(.top, max(viewportHeight * 0.22, 40))
        .padding(.bottom, 40)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func segBtn(label: String, type: StatsViewType) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(appState.statsView == type ? .appPrimary : .appSecondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 5)
            .background(appState.statsView == type ? Color.appCard : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: appState.statsView == type ? .black.opacity(0.12) : .clear, radius: 2, y: 1)
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { appState.statsView = type } }
    }

    @ViewBuilder
    private func compactSegBtn(label: String, type: StatsViewType) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(appState.statsView == type ? .appPrimary : .appSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(appState.statsView == type ? Color.appCard : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { appState.statsView = type } }
    }

    private func monthChevron(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(disabled ? .appTertiary.opacity(0.5) : .appSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func compactChevron(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? .appTertiary.opacity(0.5) : .appSecondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func scrollToPendingTarget(using proxy: ScrollViewProxy) {
        guard let target = appState.pendingStatsScrollTarget, appState.statsView == .month else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.28)) {
                proxy.scrollTo(target.rawValue, anchor: .top)
            }
            appState.pendingStatsScrollTarget = nil
        }
    }
}
