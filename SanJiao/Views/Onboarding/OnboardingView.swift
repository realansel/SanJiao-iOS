import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var appeared = false
    @State private var previewAmounts = [128, 46, 299]
    private let pills = [String(localized: "导入账单开始"), String(localized: "自动整理分类"), String(localized: "数据仅存本机")]

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.appAccent.opacity(0.18),
                    Color(hex: "F7F7FC"),
                    Color.appBg
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 280, height: 280)
                .blur(radius: 52)
                .offset(x: 92, y: -260)

            VStack(spacing: 0) {
                Spacer(minLength: 42)

                VStack(spacing: 14) {
                    Text("青羽")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.appPrimary)
                        .tracking(-1)

                    Text("先导入账单，再慢慢开始。")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.appSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 26)

                VStack(alignment: .leading, spacing: 18) {
                    previewHeader

                    VStack(spacing: 12) {
                        ForEach(Array(previewAmounts.enumerated()), id: \.offset) { index, amount in
                            previewRow(
                                emoji: ["🍜", "☕️", "🧺"][index],
                                title: [String(localized: "餐饮"), String(localized: "咖啡"), String(localized: "日用")][index],
                                subtitle: [String(localized: "午饭"), String(localized: "下午补给"), String(localized: "顺手买点东西")][index],
                                amount: amount
                            )
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 22)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.white.opacity(0.84))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 18, y: 10)
                )
                .padding(.bottom, 40)

                FlowLayout(spacing: 8) {
                    ForEach(pills, id: \.self) { pill in
                        Text(pill)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.appSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(0.65))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .strokeBorder(Color.white.opacity(0.92), lineWidth: 1)
                                    )
                            )
                    }
                }
                .padding(.bottom, 34)

                Spacer()

                VStack(spacing: 12) {
                    Button(action: { appState.dismissOnboarding(startWithBillManagement: true) }) {
                        Text("导入账单开始")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(LinearGradient.accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: Color.appAccent.opacity(0.24), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)

                    Button(action: { appState.dismissOnboarding() }) {
                        Text("先看看")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.appPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 14)

                Text("导入后会自动整理分类，也会更快看到参考。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.appTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 26)
            }
            .padding(.horizontal, 28)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.easeOut(duration: 0.55), value: appeared)
        }
        .onAppear {
            appeared = true
        }
    }

    private var previewHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("打开后会看到")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.appSecondary)

            Text("账单会先被整理清楚。")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.appPrimary)

            Text("后面再慢慢看见自己的消费节奏。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.appSecondary)
                .lineSpacing(2)
        }
    }

    private func previewRow(emoji: String, title: String, subtitle: String, amount: Int) -> some View {
        HStack(spacing: 14) {
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: 36, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.appSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("-¥\(amount)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.appPrimary)
                Text("已整理")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.appAccent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color(hex: "F7F7FC"))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Simple flow layout for pills
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.reduce(0) { max($0, $1.sizeThatFits(.unspecified).height) } } + CGFloat(rows.count - 1) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.reduce(0) { max($0, $1.sizeThatFits(.unspecified).height) }
            let rowWidth = row.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width } + CGFloat(row.count - 1) * spacing
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var rowWidth: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity
        for view in subviews {
            let w = view.sizeThatFits(.unspecified).width
            if rowWidth + w + (rows.last!.isEmpty ? 0 : spacing) > maxWidth, !rows.last!.isEmpty {
                rows.append([view])
                rowWidth = w
            } else {
                rowWidth += w + (rows.last!.isEmpty ? 0 : spacing)
                rows[rows.count - 1].append(view)
            }
        }
        return rows
    }
}
