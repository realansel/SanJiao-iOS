import SwiftUI

struct SuccessOverlay: View {
    @Environment(AppState.self) private var appState
    @State private var showBody = false
    @State private var showContent = false
    @State private var trendProgress: CGFloat = 0   // 趋势线 draw-on 进度 0→1
    @State private var pointShown = false           // 荧青数据点亮起
    @State private var pointPulse = false           // 数据点光晕呼吸

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.appAccentSoft
                    .opacity(0.48)
                    .ignoresSafeArea()

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                successBody(in: proxy.size)
                    .scaleEffect(showBody ? 1 : 0.92)
                    .opacity(showBody ? 1 : 0)
                    .offset(y: showBody ? 0 : 16)
            }
            .onAppear {
                showBody = false
                showContent = false
                trendProgress = 0
                pointShown = false
                pointPulse = false

                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    showBody = true
                }
                // 趋势线从左缓缓画到右端——记账行为"汇入数据"的隐喻
                withAnimation(.easeOut(duration: 0.7).delay(0.18)) {
                    trendProgress = 1
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                    showContent = true
                }
                // 线画完后，末端的荧青数据点弹出亮起
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.82)) {
                    pointShown = true
                }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(0.95)) {
                    pointPulse = true
                }
            }
        }
    }

    private func successBody(in size: CGSize) -> some View {
        let cardWidth = min(size.width * 0.66, 280)
        let chartHeight: CGFloat = 56

        return VStack(spacing: 16) {
            VStack(spacing: 10) {
                // 趋势线 + 荧青数据点——画的是最近 7 天累计笔数的真实折线，
                // 末端那个荧青点就是"刚记下的第 N 笔"落在你账本成长曲线的顶端
                GeometryReader { geo in
                    let rect = CGRect(origin: .zero, size: geo.size)
                    let end = trendChartPoints(appState.successTrendPoints, in: rect).last
                        ?? CGPoint(x: geo.size.width * 0.90, y: geo.size.height * 0.16)
                    ZStack {
                        TrendLineShape(values: appState.successTrendPoints)
                            .trim(from: 0, to: trendProgress)
                            .stroke(
                                Color.appTeal,
                                style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                            )

                        // 光晕
                        Circle()
                            .fill(Color.appTeal.opacity(0.18))
                            .frame(width: 24, height: 24)
                            .scaleEffect(pointPulse ? 1.3 : 0.85)
                            .opacity(pointShown ? 1 : 0)
                            .position(end)

                        // 实心数据点
                        Circle()
                            .fill(Color.appTeal)
                            .frame(width: 10, height: 10)
                            .scaleEffect(pointShown ? 1 : 0.2)
                            .opacity(pointShown ? 1 : 0)
                            .position(end)
                    }
                }
                .frame(height: chartHeight)
                .padding(.top, 4)

                Text(appState.successAmount)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.appPrimary)
                    .tracking(-1)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                if !appState.successCategoryLine.isEmpty {
                    Text(appState.successCategoryLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.appSecondary)
                }

                // 累计——荧青，强调"积累属于自己的账本"
                if !appState.successAccumulation.isEmpty {
                    Text(appState.successAccumulation)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.appTeal)
                        .padding(.top, 2)
                }

                // 智能洞察——次级灰，按需出现（里程碑 / 日均对比 / 累计）
                if !appState.successInsight.isEmpty {
                    Text(appState.successInsight)
                        .font(.system(size: 12))
                        .foregroundStyle(.appTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.top, 1)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 20)
            .frame(width: cardWidth)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.appAccent.opacity(0.16), radius: 22, y: 12)

            HStack(spacing: 10) {
                Button {
                    appState.dismissSuccessOverlay(openRecordSheet: true)
                } label: {
                    Text("再记一笔")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.appAccentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    appState.dismissSuccessOverlay()
                } label: {
                    Text("完成")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.appAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .frame(width: cardWidth)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 10)
        }
    }
}

/// 把「累计笔数」序列映射成图表坐标点。归一化填满图表高度，所以哪怕基数大、
/// 窗口内只长几笔也能看出爬升；退化情况（无历史 / 全平）回退到一条好看的固定上扬线。
/// Shape 和数据点位置共用此函数，保证末端圆点正好落在折线终点。
private func trendChartPoints(_ values: [Double], in rect: CGRect) -> [CGPoint] {
    let leftInset: CGFloat = 0.04, rightInset: CGFloat = 0.90
    let topInset: CGFloat = 0.16, bottomInset: CGFloat = 0.88
    func pt(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * fx, y: rect.minY + rect.height * fy)
    }
    let minV = values.min() ?? 0
    let maxV = values.max() ?? 0
    let span = maxV - minV
    guard values.count >= 2, span > 0.0001 else {
        return [
            pt(leftInset, bottomInset),
            pt((leftInset + rightInset) / 2, (topInset + bottomInset) / 2),
            pt(rightInset, topInset)
        ]
    }
    let n = values.count
    return values.enumerated().map { i, v in
        let fx = leftInset + (rightInset - leftInset) * CGFloat(i) / CGFloat(n - 1)
        let norm = CGFloat((v - minV) / span)
        let fy = bottomInset - (bottomInset - topInset) * norm
        return pt(fx, fy)
    }
}

/// 账本成长折线——吃最近 7 天累计笔数，可被 .trim 驱动 draw-on 动画。
private struct TrendLineShape: Shape {
    var values: [Double]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = trendChartPoints(values, in: rect)
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}
