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
                    Text("三秒·记一笔 不需要你的任何隐私数据")
                        .font(.system(size: 14))
                        .foregroundStyle(.appSecondary)
                }
                .padding(.top, 8)
                .padding(.bottom, 8)

                privacyItem(
                    icon: "iphone",
                    title: String(localized: "数据保存在你的设备上"),
                    body: String(localized: "所有账单数据由 SwiftData 存储在设备本地。悦笺没有服务器，不会将你的账单上传到任何地方。若你开启了 iCloud 备份，这些数据会随 iOS 系统备份一同加密存储——该过程由你的系统设置控制。")
                )
                privacyItem(
                    icon: "lock.shield",
                    title: String(localized: "设备级加密保护"),
                    body: String(localized: "账单数据库在磁盘上始终以密文存储，并启用了 iOS 最高的文件保护等级。设备锁屏后，解密密钥会从内存中清除，此时数据无法被读取——前提是你为设备设置了锁屏密码。")
                )
                privacyItem(
                    icon: "waveform",
                    title: String(localized: "语音转写优先在本机完成"),
                    body: String(localized: "使用语音记账时，支持的机型会在设备端完成转写，音频不会离开你的手机；较旧的机型会借助 Apple 的语音服务转写。无论哪种方式，悦笺都不会保存或上传音频。")
                )
                privacyItem(
                    icon: "nosign",
                    title: String(localized: "没有广告，没有追踪"),
                    body: String(localized: "悦笺不含任何广告、第三方分析工具或追踪 SDK，整个应用只使用 Apple 提供的系统框架。我们不收集、也不分析你的使用行为。")
                )
                privacyItem(
                    icon: "creditcard",
                    title: String(localized: "一次买断，不靠数据盈利"),
                    body: String(localized: "悦笺通过一次性购买收费。我们的收入与你的数据完全无关，因此没有任何动机去收集或变现它。")
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
