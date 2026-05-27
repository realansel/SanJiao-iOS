import SwiftUI

struct SuccessOverlay: View {
    @Environment(AppState.self) private var appState
    @State private var showBody = false
    @State private var showContent = false
    @State private var pulse = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.appAccentSoft
                    .opacity(0.48)
                    .ignoresSafeArea()

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                successAura

                successBody(in: proxy.size)
                    .scaleEffect(showBody ? 1 : 0.9)
                    .opacity(showBody ? 1 : 0)
                    .offset(y: showBody ? 0 : 16)
            }
            .onAppear {
                showBody = false
                showContent = false
                pulse = false

                withAnimation(.easeOut(duration: 0.42)) {
                    showBody = true
                }
                withAnimation(.easeOut(duration: 0.52).delay(0.08)) {
                    showContent = true
                }
                withAnimation(.easeOut(duration: 2.6).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
    }

    private var successAura: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                ExactAppIconShape()
                    .stroke(
                        Color.white.opacity(index == 0 ? 0.18 : 0.1),
                        lineWidth: index == 0 ? 1.4 : 1
                    )
                    .frame(width: 184, height: 236)
                    .scaleEffect(pulse ? (index == 0 ? 1.55 : 1.85) : 0.92)
                    .opacity(pulse ? 0 : (index == 0 ? 0.28 : 0.16))
                    .blur(radius: pulse ? 2.2 : 0.4)
                    .animation(
                        .easeOut(duration: 2.6)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.72),
                        value: pulse
                    )
            }

            ExactAppIconShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "A79CF7").opacity(0.12),
                            Color(hex: "6155F1").opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 184, height: 236)
                .scaleEffect(pulse ? 1.22 : 1.03)
                .opacity(pulse ? 0.05 : 0.1)
                .blur(radius: 10)
                .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: pulse)
        }
        .blendMode(.plusLighter)
    }

    private func successBody(in size: CGSize) -> some View {
        let bodyWidth = min(size.width * 0.56, 238)
        let bodyHeight = bodyWidth * 1.28

        return VStack(spacing: 18) {
            ZStack {
                ExactAppIconShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "A99EF7"),
                                Color(hex: "7E73F0"),
                                Color(hex: "5A50EE")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                ExactAppIconShape()
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)

                VStack(spacing: 0) {
                    IconSmileShape()
                        .stroke(
                            Color.white.opacity(0.88),
                            style: StrokeStyle(lineWidth: max(bodyWidth * 0.032, 5), lineCap: .round)
                        )
                        .frame(width: bodyWidth * 0.46, height: bodyHeight * 0.1)
                        .padding(.top, bodyHeight * 0.19)
                        .scaleEffect(showContent ? 1 : 0.9)
                        .opacity(showContent ? 1 : 0)

                    Spacer(minLength: bodyHeight * 0.12)

                    Text(appState.successAmount)
                        .font(.system(size: bodyWidth * 0.16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .tracking(-1)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 6)

                    if !appState.successCategoryLine.isEmpty {
                        Text(appState.successCategoryLine)
                            .font(.system(size: bodyWidth * 0.062, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(.top, bodyHeight * 0.04)
                            .opacity(showContent ? 1 : 0)
                    }

                    Text("轻松记下")
                        .font(.system(size: bodyWidth * 0.072, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.96))
                        .padding(.top, bodyHeight * 0.055)
                        .opacity(showContent ? 1 : 0)

                    if !appState.successInsight.isEmpty {
                        Text(appState.successInsight)
                            .font(.system(size: bodyWidth * 0.055))
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, bodyWidth * 0.045)
                            .padding(.top, bodyHeight * 0.06)
                            .opacity(showContent ? 1 : 0)
                    } else if !appState.successElapsed.isEmpty {
                        Text(appState.successElapsed)
                            .font(.system(size: bodyWidth * 0.055, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.top, bodyHeight * 0.06)
                            .opacity(showContent ? 1 : 0)
                    }

                    Spacer(minLength: bodyHeight * 0.16)
                }
                .frame(width: bodyWidth * 0.9, height: bodyHeight)
            }
            .frame(width: bodyWidth, height: bodyHeight)
            .shadow(color: Color.appAccent.opacity(0.08), radius: 18, y: 10)

            HStack(spacing: 10) {
                Button {
                    appState.dismissSuccessOverlay(openRecordSheet: true)
                } label: {
                    Text("再记一笔")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.98))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.34))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.36), lineWidth: 1)
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    appState.dismissSuccessOverlay()
                } label: {
                    Text("完成")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.white.opacity(0.94))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .frame(width: min(size.width * 0.62, 272))
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 10)
        }
    }
}

private struct IconSmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.2))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.minY + rect.height * 0.2),
            control1: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY),
            control2: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.maxY)
        )
        return path
    }
}

private struct ExactAppIconShape: Shape {
    private let points: [CGPoint] = [
        CGPoint(x: 0.111639, y: 0.000000),
        CGPoint(x: 0.893112, y: 0.000000),
        CGPoint(x: 0.895487, y: 0.001842),
        CGPoint(x: 0.907363, y: 0.001842),
        CGPoint(x: 0.909739, y: 0.003683),
        CGPoint(x: 0.916865, y: 0.003683),
        CGPoint(x: 0.923990, y: 0.007366),
        CGPoint(x: 0.928741, y: 0.007366),
        CGPoint(x: 0.938242, y: 0.011050),
        CGPoint(x: 0.942993, y: 0.014733),
        CGPoint(x: 0.952494, y: 0.018416),
        CGPoint(x: 0.978622, y: 0.040516),
        CGPoint(x: 0.990499, y: 0.058932),
        CGPoint(x: 0.992874, y: 0.069982),
        CGPoint(x: 0.995249, y: 0.071823),
        CGPoint(x: 0.995249, y: 0.084715),
        CGPoint(x: 0.997625, y: 0.086556),
        CGPoint(x: 0.997625, y: 0.103131),
        CGPoint(x: 0.995249, y: 0.104972),
        CGPoint(x: 0.995249, y: 0.121547),
        CGPoint(x: 0.992874, y: 0.123389),
        CGPoint(x: 0.990499, y: 0.151013),
        CGPoint(x: 0.988124, y: 0.152855),
        CGPoint(x: 0.988124, y: 0.162063),
        CGPoint(x: 0.985748, y: 0.163904),
        CGPoint(x: 0.985748, y: 0.176796),
        CGPoint(x: 0.983373, y: 0.178637),
        CGPoint(x: 0.983373, y: 0.189687),
        CGPoint(x: 0.980998, y: 0.191529),
        CGPoint(x: 0.980998, y: 0.202578),
        CGPoint(x: 0.978622, y: 0.204420),
        CGPoint(x: 0.978622, y: 0.217311),
        CGPoint(x: 0.976247, y: 0.219153),
        CGPoint(x: 0.976247, y: 0.232044),
        CGPoint(x: 0.973872, y: 0.233886),
        CGPoint(x: 0.973872, y: 0.246777),
        CGPoint(x: 0.971496, y: 0.248619),
        CGPoint(x: 0.971496, y: 0.261510),
        CGPoint(x: 0.969121, y: 0.263352),
        CGPoint(x: 0.969121, y: 0.281768),
        CGPoint(x: 0.966746, y: 0.283610),
        CGPoint(x: 0.966746, y: 0.300184),
        CGPoint(x: 0.964371, y: 0.302026),
        CGPoint(x: 0.961995, y: 0.335175),
        CGPoint(x: 0.959620, y: 0.337017),
        CGPoint(x: 0.959620, y: 0.355433),
        CGPoint(x: 0.957245, y: 0.357274),
        CGPoint(x: 0.957245, y: 0.383057),
        CGPoint(x: 0.954869, y: 0.384899),
        CGPoint(x: 0.954869, y: 0.418048),
        CGPoint(x: 0.952494, y: 0.419890),
        CGPoint(x: 0.952494, y: 0.528545),
        CGPoint(x: 0.954869, y: 0.530387),
        CGPoint(x: 0.957245, y: 0.585635),
        CGPoint(x: 0.959620, y: 0.587477),
        CGPoint(x: 0.961995, y: 0.622468),
        CGPoint(x: 0.964371, y: 0.624309),
        CGPoint(x: 0.964371, y: 0.639042),
        CGPoint(x: 0.966746, y: 0.640884),
        CGPoint(x: 0.969121, y: 0.677716),
        CGPoint(x: 0.971496, y: 0.679558),
        CGPoint(x: 0.971496, y: 0.694291),
        CGPoint(x: 0.973872, y: 0.696133),
        CGPoint(x: 0.976247, y: 0.725599),
        CGPoint(x: 0.978622, y: 0.727440),
        CGPoint(x: 0.978622, y: 0.745856),
        CGPoint(x: 0.980998, y: 0.747698),
        CGPoint(x: 0.983373, y: 0.779006),
        CGPoint(x: 0.985748, y: 0.780847),
        CGPoint(x: 0.985748, y: 0.793738),
        CGPoint(x: 0.988124, y: 0.795580),
        CGPoint(x: 0.988124, y: 0.808471),
        CGPoint(x: 0.990499, y: 0.810313),
        CGPoint(x: 0.990499, y: 0.826888),
        CGPoint(x: 0.992874, y: 0.828729),
        CGPoint(x: 0.992874, y: 0.843462),
        CGPoint(x: 0.995249, y: 0.845304),
        CGPoint(x: 0.995249, y: 0.860037),
        CGPoint(x: 0.997625, y: 0.861878),
        CGPoint(x: 0.997625, y: 0.876611),
        CGPoint(x: 1.000000, y: 0.878453),
        CGPoint(x: 1.000000, y: 0.917127),
        CGPoint(x: 0.997625, y: 0.918969),
        CGPoint(x: 0.995249, y: 0.931860),
        CGPoint(x: 0.990499, y: 0.937385),
        CGPoint(x: 0.990499, y: 0.941068),
        CGPoint(x: 0.985748, y: 0.948435),
        CGPoint(x: 0.971496, y: 0.961326),
        CGPoint(x: 0.971496, y: 0.963168),
        CGPoint(x: 0.954869, y: 0.974217),
        CGPoint(x: 0.938242, y: 0.981584),
        CGPoint(x: 0.933492, y: 0.981584),
        CGPoint(x: 0.923990, y: 0.985267),
        CGPoint(x: 0.914489, y: 0.985267),
        CGPoint(x: 0.912114, y: 0.987109),
        CGPoint(x: 0.895487, y: 0.987109),
        CGPoint(x: 0.893112, y: 0.985267),
        CGPoint(x: 0.881235, y: 0.985267),
        CGPoint(x: 0.878860, y: 0.983425),
        CGPoint(x: 0.874109, y: 0.983425),
        CGPoint(x: 0.871734, y: 0.981584),
        CGPoint(x: 0.862233, y: 0.979742),
        CGPoint(x: 0.857482, y: 0.976059),
        CGPoint(x: 0.847981, y: 0.972376),
        CGPoint(x: 0.836105, y: 0.963168),
        CGPoint(x: 0.817102, y: 0.955801),
        CGPoint(x: 0.812352, y: 0.955801),
        CGPoint(x: 0.802850, y: 0.952118),
        CGPoint(x: 0.769596, y: 0.952118),
        CGPoint(x: 0.767221, y: 0.953959),
        CGPoint(x: 0.752969, y: 0.955801),
        CGPoint(x: 0.743468, y: 0.959484),
        CGPoint(x: 0.738717, y: 0.963168),
        CGPoint(x: 0.731591, y: 0.965009),
        CGPoint(x: 0.710214, y: 0.981584),
        CGPoint(x: 0.707838, y: 0.981584),
        CGPoint(x: 0.700713, y: 0.987109),
        CGPoint(x: 0.676960, y: 0.996317),
        CGPoint(x: 0.657957, y: 0.998158),
        CGPoint(x: 0.655582, y: 1.000000),
        CGPoint(x: 0.634204, y: 1.000000),
        CGPoint(x: 0.631829, y: 0.998158),
        CGPoint(x: 0.612827, y: 0.996317),
        CGPoint(x: 0.605701, y: 0.992634),
        CGPoint(x: 0.600950, y: 0.992634),
        CGPoint(x: 0.591449, y: 0.988950),
        CGPoint(x: 0.553444, y: 0.963168),
        CGPoint(x: 0.534442, y: 0.955801),
        CGPoint(x: 0.520190, y: 0.953959),
        CGPoint(x: 0.517815, y: 0.952118),
        CGPoint(x: 0.484561, y: 0.952118),
        CGPoint(x: 0.482185, y: 0.953959),
        CGPoint(x: 0.467933, y: 0.955801),
        CGPoint(x: 0.448931, y: 0.963168),
        CGPoint(x: 0.420428, y: 0.983425),
        CGPoint(x: 0.406176, y: 0.988950),
        CGPoint(x: 0.401425, y: 0.992634),
        CGPoint(x: 0.396675, y: 0.992634),
        CGPoint(x: 0.382423, y: 0.998158),
        CGPoint(x: 0.370546, y: 0.998158),
        CGPoint(x: 0.368171, y: 1.000000),
        CGPoint(x: 0.346793, y: 1.000000),
        CGPoint(x: 0.344418, y: 0.998158),
        CGPoint(x: 0.334917, y: 0.998158),
        CGPoint(x: 0.332542, y: 0.996317),
        CGPoint(x: 0.320665, y: 0.994475),
        CGPoint(x: 0.301663, y: 0.987109),
        CGPoint(x: 0.266033, y: 0.963168),
        CGPoint(x: 0.258907, y: 0.961326),
        CGPoint(x: 0.254157, y: 0.957643),
        CGPoint(x: 0.249406, y: 0.957643),
        CGPoint(x: 0.247031, y: 0.955801),
        CGPoint(x: 0.242280, y: 0.955801),
        CGPoint(x: 0.232779, y: 0.952118),
        CGPoint(x: 0.199525, y: 0.952118),
        CGPoint(x: 0.197150, y: 0.953959),
        CGPoint(x: 0.182898, y: 0.955801),
        CGPoint(x: 0.163895, y: 0.963168),
        CGPoint(x: 0.152019, y: 0.972376),
        CGPoint(x: 0.149644, y: 0.972376),
        CGPoint(x: 0.137767, y: 0.979742),
        CGPoint(x: 0.133017, y: 0.979742),
        CGPoint(x: 0.118765, y: 0.985267),
        CGPoint(x: 0.106888, y: 0.985267),
        CGPoint(x: 0.104513, y: 0.987109),
        CGPoint(x: 0.090261, y: 0.987109),
        CGPoint(x: 0.087886, y: 0.985267),
        CGPoint(x: 0.076010, y: 0.985267),
        CGPoint(x: 0.073634, y: 0.983425),
        CGPoint(x: 0.061758, y: 0.981584),
        CGPoint(x: 0.052257, y: 0.977901),
        CGPoint(x: 0.035629, y: 0.966851),
        CGPoint(x: 0.033254, y: 0.966851),
        CGPoint(x: 0.019002, y: 0.953959),
        CGPoint(x: 0.016627, y: 0.948435),
        CGPoint(x: 0.009501, y: 0.941068),
        CGPoint(x: 0.009501, y: 0.937385),
        CGPoint(x: 0.004751, y: 0.931860),
        CGPoint(x: 0.002375, y: 0.918969),
        CGPoint(x: 0.000000, y: 0.917127),
        CGPoint(x: 0.000000, y: 0.878453),
        CGPoint(x: 0.002375, y: 0.876611),
        CGPoint(x: 0.002375, y: 0.861878),
        CGPoint(x: 0.004751, y: 0.860037),
        CGPoint(x: 0.004751, y: 0.847145),
        CGPoint(x: 0.007126, y: 0.845304),
        CGPoint(x: 0.007126, y: 0.834254),
        CGPoint(x: 0.009501, y: 0.832413),
        CGPoint(x: 0.009501, y: 0.817680),
        CGPoint(x: 0.011876, y: 0.815838),
        CGPoint(x: 0.011876, y: 0.802947),
        CGPoint(x: 0.014252, y: 0.801105),
        CGPoint(x: 0.014252, y: 0.788214),
        CGPoint(x: 0.016627, y: 0.786372),
        CGPoint(x: 0.016627, y: 0.773481),
        CGPoint(x: 0.019002, y: 0.771639),
        CGPoint(x: 0.019002, y: 0.758748),
        CGPoint(x: 0.021378, y: 0.756906),
        CGPoint(x: 0.021378, y: 0.740331),
        CGPoint(x: 0.023753, y: 0.738490),
        CGPoint(x: 0.023753, y: 0.721915),
        CGPoint(x: 0.026128, y: 0.720074),
        CGPoint(x: 0.026128, y: 0.705341),
        CGPoint(x: 0.028504, y: 0.703499),
        CGPoint(x: 0.028504, y: 0.688766),
        CGPoint(x: 0.030879, y: 0.686924),
        CGPoint(x: 0.030879, y: 0.670350),
        CGPoint(x: 0.033254, y: 0.668508),
        CGPoint(x: 0.033254, y: 0.651934),
        CGPoint(x: 0.035629, y: 0.650092),
        CGPoint(x: 0.035629, y: 0.633517),
        CGPoint(x: 0.038005, y: 0.631676),
        CGPoint(x: 0.038005, y: 0.613260),
        CGPoint(x: 0.040380, y: 0.611418),
        CGPoint(x: 0.040380, y: 0.593002),
        CGPoint(x: 0.042755, y: 0.591160),
        CGPoint(x: 0.042755, y: 0.569061),
        CGPoint(x: 0.045131, y: 0.567219),
        CGPoint(x: 0.045131, y: 0.534070),
        CGPoint(x: 0.047506, y: 0.532228),
        CGPoint(x: 0.047506, y: 0.412523),
        CGPoint(x: 0.045131, y: 0.410681),
        CGPoint(x: 0.045131, y: 0.381215),
        CGPoint(x: 0.042755, y: 0.379374),
        CGPoint(x: 0.042755, y: 0.355433),
        CGPoint(x: 0.040380, y: 0.353591),
        CGPoint(x: 0.040380, y: 0.335175),
        CGPoint(x: 0.038005, y: 0.333333),
        CGPoint(x: 0.038005, y: 0.314917),
        CGPoint(x: 0.035629, y: 0.313076),
        CGPoint(x: 0.033254, y: 0.278085),
        CGPoint(x: 0.030879, y: 0.276243),
        CGPoint(x: 0.030879, y: 0.261510),
        CGPoint(x: 0.028504, y: 0.259669),
        CGPoint(x: 0.028504, y: 0.244936),
        CGPoint(x: 0.026128, y: 0.243094),
        CGPoint(x: 0.026128, y: 0.230203),
        CGPoint(x: 0.023753, y: 0.228361),
        CGPoint(x: 0.023753, y: 0.213628),
        CGPoint(x: 0.021378, y: 0.211786),
        CGPoint(x: 0.021378, y: 0.198895),
        CGPoint(x: 0.019002, y: 0.197053),
        CGPoint(x: 0.019002, y: 0.186004),
        CGPoint(x: 0.016627, y: 0.184162),
        CGPoint(x: 0.016627, y: 0.171271),
        CGPoint(x: 0.014252, y: 0.169429),
        CGPoint(x: 0.014252, y: 0.158379),
        CGPoint(x: 0.011876, y: 0.156538),
        CGPoint(x: 0.011876, y: 0.147330),
        CGPoint(x: 0.009501, y: 0.145488),
        CGPoint(x: 0.009501, y: 0.132597),
        CGPoint(x: 0.007126, y: 0.130755),
        CGPoint(x: 0.007126, y: 0.119705),
        CGPoint(x: 0.004751, y: 0.117864),
        CGPoint(x: 0.004751, y: 0.101289),
        CGPoint(x: 0.002375, y: 0.099448),
        CGPoint(x: 0.002375, y: 0.088398),
        CGPoint(x: 0.004751, y: 0.086556),
        CGPoint(x: 0.004751, y: 0.073665),
        CGPoint(x: 0.007126, y: 0.071823),
        CGPoint(x: 0.009501, y: 0.058932),
        CGPoint(x: 0.021378, y: 0.040516),
        CGPoint(x: 0.028504, y: 0.034991),
        CGPoint(x: 0.028504, y: 0.033149),
        CGPoint(x: 0.047506, y: 0.018416),
        CGPoint(x: 0.049881, y: 0.018416),
        CGPoint(x: 0.054632, y: 0.014733),
        CGPoint(x: 0.078385, y: 0.005525),
        CGPoint(x: 0.092637, y: 0.003683),
        CGPoint(x: 0.095012, y: 0.001842),
        CGPoint(x: 0.109264, y: 0.001842),
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        let scaledPoints = points.map {
            CGPoint(x: rect.minX + rect.width * $0.x, y: rect.minY + rect.height * $0.y)
        }

        path.move(to: CGPoint(x: rect.minX + rect.width * first.x, y: rect.minY + rect.height * first.y))

        guard scaledPoints.count > 2 else {
            for point in scaledPoints.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
            return path
        }

        for index in scaledPoints.indices {
            let p0 = scaledPoints[(index - 1 + scaledPoints.count) % scaledPoints.count]
            let p1 = scaledPoints[index]
            let p2 = scaledPoints[(index + 1) % scaledPoints.count]
            let p3 = scaledPoints[(index + 2) % scaledPoints.count]

            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )

            path.addCurve(to: p2, control1: control1, control2: control2)
        }

        path.closeSubpath()
        return path
    }
}
