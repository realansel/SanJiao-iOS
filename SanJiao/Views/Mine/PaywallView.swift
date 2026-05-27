import SwiftUI
import SwiftData

struct PaywallView: View {
    @Environment(UnlockManager.self) private var unlock
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    var body: some View {
        VStack(spacing: 0) {
            // ── 关闭按钮 ──────────────────────────────────────────────────────
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.appSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.appSeparator)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ScrollView {
                VStack(spacing: 0) {
                    // ── 图标 ─────────────────────────────────────────────────
                    Text("☀️")
                        .font(.system(size: 52))
                        .padding(.top, 32)
                        .padding(.bottom, 16)

                    // ── 标题 ─────────────────────────────────────────────────
                    Group {
                        if case .trial(let days) = unlock.state {
                            Text("试用期还剩 \(days) 天")
                        } else {
                            Text("试用期已结束")
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.appSecondary)
                    .padding(.bottom, 10)

                    Text("解锁悦笺")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.appPrimary)
                        .tracking(-0.5)
                        .padding(.bottom, 6)

                    if transactions.count > 0 {
                        Text("你已记录了 \(transactions.count) 笔，继续了解你的消费")
                            .font(.system(size: 14))
                            .foregroundStyle(.appSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    } else {
                        Text("花得明白，才能活得更自在")
                            .font(.system(size: 14))
                            .foregroundStyle(.appSecondary)
                    }

                    // ── 购买按钮 ──────────────────────────────────────────────
                    Button {
                        Task { await unlock.purchase() }
                    } label: {
                        Group {
                            if unlock.isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                HStack(spacing: 6) {
                                    Text("解锁悦笺")
                                        .font(.system(size: 17, weight: .semibold))
                                    Text(unlock.product?.displayPrice ?? "¥25")
                                        .font(.system(size: 17, weight: .semibold))
                                        .opacity(0.85)
                                }
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(height: 58)
                        .frame(maxWidth: .infinity)
                        .background(LinearGradient.accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: Color.appAccent.opacity(0.2), radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                    .disabled(unlock.isPurchasing)
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 20)

                    // ── 卖点列表 ──────────────────────────────────────────────
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
                    .padding(.bottom, 24)

                    // ── 错误提示 ──────────────────────────────────────────────
                    if let err = unlock.purchaseError {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "FF3B30"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                    }

                    // ── 恢复购买 ──────────────────────────────────────────────
                    Button {
                        Task { await unlock.restore() }
                    } label: {
                        Group {
                            if unlock.isRestoring {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("恢复购买")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.appSecondary)
                                    .underline()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(unlock.isRestoring)
                    .padding(.bottom, 32)
                }
            }
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
