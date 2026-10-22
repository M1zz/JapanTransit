import SwiftUI
import TrainBoardKit

/// 승강장에서 열차 앞이나 전광판을 비추면 이 경로에 탈 열차인지 알려 준다.
/// 초록 = 타세요, 빨강 = 반대 방향이거나 내 역에 서지 않는 열차.
struct BoardScannerView: View {
    let segment: RouteSegment

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = BoardCamera(recognitionLanguages: ["ja-JP", "en-US"])
    @StateObject private var model = ScannerModel()

    var body: some View {
        ZStack {
            BoardCameraPreview(session: camera.session)
                .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.6), .clear, .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if let color = model.verdictColor {
                Rectangle()
                    .strokeBorder(color, lineWidth: 16)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                header
                Spacer()
                verdictCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.verdict)
        .task {
            let judge = segment.boardJudge()
            camera.onRows = { [weak model] rows in
                let v = judge.judge(rows: rows)
                DispatchQueue.main.async { model?.update(v) }
            }
            await camera.start()
        }
        .onDisappear { camera.stop() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("열차 앞이나 전광판을 비추세요")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 8) {
                    LineBadge(line: segment.line, size: 26)
                    Text(segment.headingSign)
                        .font(.title2.weight(.black))
                        .foregroundStyle(.white)
                }
                Text("\(segment.boarding.ko) → \(segment.alighting.ko)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("닫기")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    @ViewBuilder private var verdictCard: some View {
        if camera.denied {
            card(icon: "video.slash.fill", title: String(localized: "카메라 권한이 필요해요"),
                 detail: String(localized: "설정 ▸ 일본길찾기 ▸ 카메라를 켜 주세요"), color: .orange)
        } else {
            switch model.verdict {
            case .board(let matched):
                card(icon: "checkmark.circle.fill", title: String(localized: "타세요"),
                     detail: reading(matched).map { String(localized: "\(matched) (\($0)) 방향이 맞아요") } ?? String(localized: "\(matched) 방향이 맞아요"),
                     color: .green)
            case .wrongDirection(let matched):
                card(icon: "xmark.octagon.fill", title: String(localized: "반대 방향이에요"),
                     detail: reading(matched).map { String(localized: "\(matched) (\($0)) 쪽으로 가는 열차예요") } ?? String(localized: "\(matched) 쪽으로 가는 열차예요"),
                     color: .red)
            case .skipsStop(let word, let station):
                card(icon: "forward.fill", title: String(localized: "이 열차는 타지 마세요"),
                     detail: String(localized: "\(word) 열차는 \(reading(station) ?? station)에서 탈 수 없어요. 各停(각역정차)을 타세요"),
                     color: .red)
            case .ambiguous:
                card(icon: "questionmark.circle", title: String(localized: "양쪽 역 이름이 다 보여요"),
                     detail: String(localized: "열차 앞의 행선지나 전광판을 비춰 주세요"), color: .white)
            case nil:
                card(icon: "viewfinder", title: String(localized: "행선지를 찾는 중…"),
                     detail: String(localized: "\(segment.headingStations[0].ja) 같은 글자가 화면에 들어오게 해 주세요"), color: .white)
            }
        }
    }

    private func reading(_ ja: String) -> String? {
        RailNetwork.shared.place(ja)?.ko
    }

    private func card(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .black))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.black)).foregroundStyle(.white)
                Text(detail).font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .background(color.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

/// 판정을 화면에 올린다. 아무것도 못 읽은 프레임이 이어질 때만 비워서 깜빡임을 막는다.
@MainActor
final class ScannerModel: ObservableObject {
    @Published private(set) var verdict: TrainBoardJudge.Verdict?
    private var missStreak = 0

    var verdictColor: Color? {
        switch verdict {
        case .board: return .green
        case .wrongDirection, .skipsStop: return .red
        default: return nil
        }
    }

    func update(_ v: TrainBoardJudge.Verdict?) {
        if let v {
            missStreak = 0
            if v != verdict { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            verdict = v
        } else {
            missStreak += 1
            if missStreak >= 3 { verdict = nil }
        }
    }
}
