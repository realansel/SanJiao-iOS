import SwiftUI

struct PrivacyStatementView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Hero
                VStack(alignment: .leading, spacing: 8) {
                    Text("🔒")
                        .font(.system(size: 44))
                    Text("我们的隐私承诺")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.appPrimary)
                        .tracking(-0.5)
                    Text("青羽记账不需要你的任何隐私数据")
                        .font(.system(size: 14))
                        .foregroundStyle(.appSecondary)
                }
                .padding(.top, 8)
                .padding(.bottom, 8)

                privacyItem(
                    icon: "iphone",
                    title: String(localized: "数据只在设备上"),
                    body: String(localized: "所有账单存储在设备本地，青羽没有服务器。开启 iCloud 备份后，数据随系统备份加密存储，由你的系统设置控制。")
                )
                privacyItem(
                    icon: "lock.shield",
                    title: String(localized: "设备级加密"),
                    body: String(localized: "账单数据库始终以密文存储，启用了 iOS 最高文件保护等级。锁屏后解密密钥从内存清除，需设置锁屏密码方可生效。")
                )
                privacyItem(
                    icon: "waveform",
                    title: String(localized: "语音转写，本机优先"),
                    body: String(localized: "支持的机型在设备端离线转写，音频不离开手机；较旧机型会经 Apple 语音服务处理。首次使用时 iOS 会弹出系统授权提示（含 Apple 的标准说明）。青羽自身从不存储、上传或分析你的音频。")
                )
                privacyItem(
                    icon: "nosign",
                    title: String(localized: "无广告，无追踪"),
                    body: String(localized: "不含任何广告或第三方追踪 SDK，仅使用 Apple 系统框架。不收集、不分析任何使用行为。")
                )
                privacyItem(
                    icon: "creditcard",
                    title: String(localized: "一次买断"),
                    body: String(localized: "青羽通过一次性购买收费，收入与你的数据无关，没有任何动机收集或变现它。")
                )

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.appBg)
        .navigationTitle("安全与隐私")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func privacyItem(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.appAccent)
                .frame(width: 36, height: 36)
                .background(Color.appAccentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appPrimary)
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(.appSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
