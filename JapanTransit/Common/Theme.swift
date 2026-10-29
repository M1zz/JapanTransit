import SwiftUI

// MARK: - Concept: 표지판 그대로
//
// 이 앱이 하는 일은 "역에서 볼 표지판을 미리 보여 주는 것"이다. 그래서 화면도 일본 역의
// 표지판 언어로 그린다: 역 번호 마크(노선색 테두리 사각형), 역명판(駅名標), 남색 방면 표지판,
// 노선도처럼 이어진 선. 화면에서 본 모양이 역에서 그대로 눈에 들어오게.
//
// 색은 아이콘에서 온다: 藍(남색) 바탕, 朱(빨강) 표시판. 바탕은 따뜻한 종이색(和紙).

enum Theme {
    /// 藍 — brand, tint.
    static let indigo = Color(light: 0x34_56_98, dark: 0x8F_AE_EE)
    /// 藍 as a fill under white text — stays deep in dark mode so white reads.
    static let indigoFill = Color(light: 0x34_56_98, dark: 0x3A_5F_B0)
    /// 朱 — the icon's destination plate. Used sparingly: arrival, warnings.
    static let vermilion = Color(light: 0xD6_33_3F, dark: 0xFF_6B_73)
    /// 朱 as a fill under white text.
    static let vermilionFill = Color(light: 0xD6_33_3F, dark: 0xC4_2D_3A)
    /// 和紙 — page background.
    static let paper = Color(light: 0xF4_F1_EA, dark: 0x0E_13_1E)
    /// Cards on the paper.
    static let card = Color(light: 0xFF_FF_FF, dark: 0x18_20_30)
    static let ink = Color(light: 0x1A_22_33, dark: 0xEC_EE_F3)
    static let inkSoft = Color(light: 0x5D_66_78, dark: 0xA3_AB_BB)
    static let hairline = Color(light: 0xE4_DF_D4, dark: 0x27_30_42)
    /// Platform direction signs: white type on deep navy, like the real ones.
    static let signBoard = Color(light: 0x1B_27_44, dark: 0x22_2F_4F)
    static let caution = Color(light: 0x9A_58_00, dark: 0xF2_B2_4C)

    static let corner: CGFloat = 18
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { trait in
            let v = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                           green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
}

/// White card on paper with a soft edge.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

// MARK: - Station number mark

/// Tokyo's station numbering mark: a rounded square with a thick line-colour
/// border, the line letter on top and the number below — "G / 09".
struct StationMark: View {
    let code: String
    let color: Color
    var size: CGFloat = 34

    private var parts: (String, String) {
        let letters = String(code.prefix { $0.isLetter })
        return (letters, String(code.dropFirst(letters.count)))
    }

    var body: some View {
        let (letters, number) = parts
        VStack(spacing: -size * 0.06) {
            Text(letters)
                .font(.system(size: size * (letters.count > 1 ? 0.26 : 0.3), weight: .heavy, design: .rounded))
            Text(number)
                .font(.system(size: size * 0.4, weight: .heavy, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(Color.black.opacity(0.85))
        .frame(width: size, height: size)
        .background(.white, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .strokeBorder(color, lineWidth: size * 0.13))
        .accessibilityLabel("역 번호 \(code)")
    }
}

// MARK: - Line badge

/// Line mark without a number — the line letter on its colour (G, M, JY…).
struct LineBadge: View {
    let line: RailLine
    var size: CGFloat = 28

    var body: some View {
        Text(line.badge)
            .font(.system(size: size * (line.badge.count > 1 ? 0.4 : 0.52), weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(line.swiftColor))
            .accessibilityLabel(line.nameKo)
    }
}

/// "● 긴자선 銀座線" — a line chip.
struct LineChip: View {
    let line: RailLine

    var body: some View {
        HStack(spacing: 6) {
            LineBadge(line: line, size: 20)
            Text(line.nameKo).font(.subheadline.weight(.semibold))
            Text(line.nameJa).font(.caption).foregroundStyle(Theme.inkSoft)
        }
        .foregroundStyle(Theme.ink)
    }
}

// MARK: - Station name

/// The sign's Japanese name big, the Korean reading above it, codes as marks.
struct StationName: View {
    let ko: String
    let ja: String
    var marks: [(code: String, color: Color)] = []
    var large = false
    /// 역명판 글씨도 글자 크기 설정을 따라 커진다
    @ScaledMetric(relativeTo: .title2) private var jaSize: CGFloat = 21
    @ScaledMetric(relativeTo: .largeTitle) private var jaLargeSize: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ko)
                    .font(large ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                Text(ja)
                    .font(.system(size: large ? jaLargeSize : jaSize, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                ForEach(Array(marks.prefix(4).enumerated()), id: \.offset) { _, m in
                    StationMark(code: m.code, color: m.color, size: large ? 32 : 26)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ko) 역, \(ja)")
    }
}

extension Place {
    /// Number marks for every line at this station, in line colour.
    var marks: [(code: String, color: Color)] {
        stops.compactMap { s in RailNetwork.shared.line(s.lineID).map { (s.code, $0.swiftColor) } }
    }
}

// MARK: - Direction sign

/// The text to find on the platform, drawn like the platform sign itself:
/// white type on deep navy, the line mark on the left, an arrow on the right.
struct DirectionSign: View {
    let segment: RouteSegment
    @ScaledMetric(relativeTo: .largeTitle) private var signSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                StationMark(code: segment.stations.count > 1 ? segment.stations[1].code : segment.boarding.code,
                            color: segment.line.swiftColor, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    if let loop = segment.loopSign {
                        Text(loop)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Text(segment.headingSign)
                        .font(.system(size: signSize, weight: .heavy))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.45)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(.white)
            }
            Rectangle().fill(segment.line.swiftColor).frame(height: 4)
            Text("\(segment.headingKo) · 역 번호가 \(segment.step > 0 ? "커지는" : "작아지는") 쪽")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(16)
        .background(Theme.signBoard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("표지판에서 \(segment.headingSign) 를 찾으세요. \(segment.headingKo)")
    }
}

// MARK: - Route strip

/// A route as one bar of line colours, each as long as its ride, with white
/// dots where you change — the route at a glance.
struct RouteStrip: View {
    let route: Route
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let total = max(route.stopCount, 1)
            let gap: CGFloat = 3
            let usable = geo.size.width - gap * CGFloat(max(route.segments.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(route.segments) { seg in
                    Capsule()
                        .fill(seg.line.swiftColor)
                        .frame(width: max(usable * CGFloat(seg.stopCount) / CGFloat(total), height))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Eyebrow

/// Small spaced caps label: "출発 FROM".
struct Eyebrow: View {
    let ko: String
    let en: String

    var body: some View {
        HStack(spacing: 6) {
            Text(ko).font(.caption.weight(.bold)).foregroundStyle(Theme.indigo)
            Text(en).font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(Theme.inkSoft)
        }
    }
}

// MARK: - Region bar

/// 도시 고르기: 도쿄 · 요코하마 · 오사카 … (only cities that have lines).
struct RegionBar: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RailNetwork.shared.regions) { r in
                    let on = selection == r.id
                    Button {
                        withAnimation(.snappy) { selection = r.id }
                    } label: {
                        HStack(spacing: 4) {
                            Text(r.ko).font(.subheadline.weight(.bold))
                            Text(r.ja).font(.caption)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(on ? .white : Theme.ink)
                        .background(on ? Theme.indigoFill : Theme.card, in: Capsule())
                        .overlay(Capsule().stroke(Theme.hairline))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Theme.paper)
    }
}
