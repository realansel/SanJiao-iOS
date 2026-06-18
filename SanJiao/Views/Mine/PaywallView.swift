import SwiftUI
import SwiftData

struct PaywallView: View {
    @Environment(UnlockManager.self) private var unlock
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    private var trialText: String? {
        if case .trial(let days) = unlock.state {
            return String(format: String(localized: "试用期还剩 %d 天"), days)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── 关闭按钮 ──────────────────────────────────────────────
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.appSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.appSeparator)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            // ── 品牌图标 + 试用徽章 + 标题 ─────────────────────────────
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient.accentGradient)
                    .frame(width: 78, height: 78)
                    .shadow(color: Color.appAccent.opacity(0.28), radius: 14, y: 6)
                Image("FeatherGlyph")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
            }
            .padding(.top, 8)

            if let trialText {
                Text(trialText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.appAccent)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Color.appAccentSoft))
                    .padding(.top, 18)
            } else {
                Text("试用期已结束")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.appSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Color.appSeparator))
                    .padding(.top, 18)
            }

            Text("解锁完整版青羽")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(.appPrimary)
                .tracking(-0.5)
                .padding(.top, 12)

            Group {
                if transactions.count > 0 {
                    Text("你已记录 \(transactions.count) 笔 —— 继续看清自己的消费")
                } else {
                    Text("花得明白，才能活得更自在")
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(.appSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 36)
            .padding(.top, 6)

            // ── 卖点列表（先读理由）────────────────────────────────────
            VStack(spacing: 0) {
                featureRow(icon: "checkmark.seal.fill",
                           color: .appAccent,
                           title: String(localized: "买断制，一次付费永久使用"),
                           subtitle: String(localized: "没有订阅，没有月费"))
                Divider().padding(.leading, 52)
                featureRow(icon: "lock.shield.fill",
                           color: Color(hex: "34C759"),
                           title: String(localized: "数据只存在你的手机里"),
                           subtitle: String(localized: "不上传，不追踪，iOS 硬件加密保护"))
                Divider().padding(.leading, 52)
                featureRow(icon: "nosign",
                           color: Color(hex: "FF9F0A"),
                           title: String(localized: "零广告，零追踪"),
                           subtitle: String(localized: "没有任何第三方 SDK 或用户行为分析"))
            }
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            .padding(.top, 26)

            if let err = unlock.purchaseError {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "FF3B30"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
            }

            // 留白收在这里——把购买按钮压到底部拇指热区
            Spacer(minLength: 24)

            // ── 购买按钮（读完理由再要钱）──────────────────────────────
            Button {
                Task { await unlock.purchase() }
            } label: {
                Group {
                    if unlock.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 8) {
                            Text("立即解锁").font(.system(size: 17, weight: .semibold))
                            Text("·").opacity(0.5)
                            Text(unlock.product?.displayPrice ?? "¥25").font(.system(size: 17, weight: .semibold))
                        }
                    }
                }
                .foregroundStyle(.white)
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .background(LinearGradient.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Color.appAccent.opacity(0.22), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(unlock.isPurchasing)
            .padding(.horizontal, 24)

            Text("一次买断 · 永久使用 · 无订阅")
                .font(.system(size: 12))
                .foregroundStyle(.appTertiary)
                .padding(.top, 10)

            // ── 恢复购买 + 隐私政策 ────────────────────────────────────
            HStack(spacing: 16) {
                Button {
                    Task { await unlock.restore() }
                } label: {
                    if unlock.isRestoring {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("恢复购买").font(.system(size: 14)).foregroundStyle(.appSecondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(unlock.isRestoring)

                Text("·").foregroundStyle(.appTertiary)

                Link(destination: URL(string: "https://realansel.github.io/qingyu-site/privacy.html")!) {
                    Text("隐私政策").font(.system(size: 14)).foregroundStyle(.appSecondary)
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .background(Color.appBg.ignoresSafeArea())
        .onChange(of: unlock.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    @ViewBuilder
    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.appSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
