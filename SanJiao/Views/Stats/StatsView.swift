import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Header + toggle
                        HStack {
                            Text(String(localized: "统计"))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.appPrimary)
                                .tracking(-0.5)
                            Spacer()
                            // Segment control
                            HStack(spacing: 0) {
                                segBtn(label: String(localized: "月"), type: .month)
                                segBtn(label: String(localized: "年"), type: .year)
                            }
                            .padding(2)
                            .background(Color.appSeparator)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                        if allTransactions.isEmpty {
                            statsEmptyView
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
                .onAppear {
                    scrollToPendingTarget(using: proxy)
                }
                .onChange(of: appState.pendingStatsScrollTarget) { _, _ in
                    scrollToPendingTarget(using: proxy)
                }
                .onChange(of: appState.statsView) { _, _ in
                    scrollToPendingTarget(using: proxy)
                }
            }
            .background(Color.appBg)
            .navigationBarHidden(true)
        }
    }

    @ViewBuilder var statsEmptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.appTertiary)
                .opacity(0.7)
            Text(String(localized: "还没有统计数据"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.appSecondary)
            Text(String(localized: "记录几笔账单后，这里会展示你的支出趋势与分布"))
                .font(.system(size: 13))
                .foregroundStyle(.appTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
