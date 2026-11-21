import ActivityKit
import SwiftUI

// 잠금화면 · 다이내믹 아일랜드의 길 안내. 앱과 위젯 확장이 함께 쓴다 (앱의 다른 코드에 기대지 않는다).
//
// 지하에서는 앱이 깨어 있지 않으니, 시간이 가면 저절로 바뀌는 것만 담는다:
// 내릴 역까지 남은 시간은 도착 예정 시각으로 주고 시스템이 센다.

struct TripActivityAttributes: ActivityAttributes {
    /// "우메다 → 기온시조"
    let title: String

    struct ContentState: Codable, Hashable {
        enum Stage: String, Codable { case board, ride, change, leave }
        var stage: Stage
        /// 노선 글자와 색 ("JY", "#9ACD32").
        var badge: String
        var color: String
        /// 지금 할 일, 한국어로: "요도야바시에서 내려요".
        var title: String
        /// 표지판 · 역명판에서 찾을 글자: "渋谷・品川方面", "淀屋橋".
        var sign: String
        var detail: String?
        /// 탈 칸이 정해진 열차: "1〜4号車".
        var cars: String?
        /// 타고 가는 중: 탄 시각과 내릴 역 도착 예정.
        var start: Date?
        var arrival: Date?
    }
}

/// 잠금화면에 서는 한 장.
struct TripActivityView: View {
    let title: String
    let state: TripActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                TripActivityBadge(state: state, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.headline.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(state.sign)
                        .font(.title2.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                if let arrival = state.arrival {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("도착까지 약")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(timerInterval: Date.now...max(arrival, .now), countsDown: true)
                            .font(.title2.weight(.heavy).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90, alignment: .trailing)
                    }
                }
            }
            if let start = state.start, let arrival = state.arrival, arrival > start {
                ProgressView(timerInterval: start...arrival, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(Color(tripHex: state.color))
            }
            HStack(spacing: 6) {
                if let cars = state.cars {
                    Text(cars)
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(tripHex: state.color).opacity(0.25), in: Capsule())
                }
                Text(state.detail ?? title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
    }
}

/// 노선 글자를 노선색 동그라미에.
struct TripActivityBadge: View {
    let state: TripActivityAttributes.ContentState
    var size: CGFloat = 24

    var body: some View {
        Text(state.badge)
            .font(.system(size: size * (state.badge.count > 1 ? 0.4 : 0.52), weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.5)
            .frame(width: size, height: size)
            .background(Color(tripHex: state.color), in: Circle())
    }
}

extension Color {
    /// "#9ACD32" — 위젯 확장에는 앱의 색 도구가 없어 따로 둔다.
    init(tripHex hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
