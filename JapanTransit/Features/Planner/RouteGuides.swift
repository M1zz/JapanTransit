import SwiftUI

// 경로 안내에 끼워 넣는 그림들. 일본 전철에서 처음 온 사람이 틀리는 곳마다 하나씩:
//
//   행선지 지도   같은 승강장에 다른 곳으로 가는 열차가 온다 · 도중에 갈라진다 · 내 역 앞에서 끝난다
//   정차역 도표   열차 종류마다 서는 역이 다르다
//   환승 그림     이름이 다른 역으로 걷는다 · 개찰구 밖으로 나간다
//   출구 표지판   큰 역은 출구가 수십 개다
//   멈췄을 때     노선이 멈추면 돌아가는 길 · 막차

// MARK: - 행선지 지도

/// 이 승강장에 오는 열차 가운데 어느 행선지를 타야 하는지: 내가 탈 구간을 선으로 그리고,
/// 내릴 역 앞에서 끝나는 열차 · 도중에 갈라지는 열차 · 끝까지 가는 열차를 그 위에 나눈다.
struct DestinationMap: View {
    let segment: RouteSegment
    /// 이 열차가 그대로 이어 달리는 다음 구간: 그 구간 끝까지 가는 행선지를 따로 짚는다
    var through: RouteSegment?

    var body: some View {
        let guide = segment.destinationGuide
        VStack(alignment: .leading, spacing: 12) {
            GuideHeading(title: "행선지를 확인하세요", detail: "같은 승강장에 다른 곳으로 가는 열차도 와요")
            Diagram(segment: segment, guide: guide)
                .frame(height: guide.junction == nil ? 62 : 96)
                .accessibilityHidden(true)
            board(guide)
            avoid(guide)
        }
        .accessibilityElement(children: .combine)
    }

    /// 타도 되는 행선지. 열차가 다음 노선으로 그대로 이어 가는 길이면(大阪 → 関西空港),
    /// 끝까지 가는 행선지를 먼저, 이음 역까지만 가는 행선지는 "거기서 갈아타요"로 나눈다.
    @ViewBuilder private func board(_ guide: DestinationGuide) -> some View {
        let names = (guide.loopSign.map { [$0] } ?? []) + guide.ok
        let far = through?.destinationGuide.ok ?? []
        if let through, !far.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Verdict(ok: true, text: "이 글자면 타세요")
                DestinationChips(names: far, fill: Theme.signBoard)
                Text("\(through.alighting.ko)까지 갈아타지 않고 가요")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.indigo)
                let partWay = names.filter { !far.contains($0) && $0 != guide.loopSign }
                if !partWay.isEmpty {
                    DestinationChips(names: partWay, fill: Theme.inkSoft, limit: 6)
                        .padding(.top, 6)
                    Text("이 글자면 \(segment.alighting.ko)까지만 같은 길이에요. 거기서 내려 \(Josa.ro(through.line.nameKo)) 갈아타요")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if !names.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Verdict(ok: true, text: "이 글자면 타세요")
                DestinationChips(names: names, fill: Theme.signBoard)
                if !segment.line.circular, segment.alighting != segment.headingStations.first {
                    Text("\(segment.alighting.ko)보다 먼 역 이름이면 모두 돼요")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 타면 안 되는 행선지: 갈라지는 열차, 내 역 앞에서 끝나는 열차.
    @ViewBuilder private func avoid(_ guide: DestinationGuide) -> some View {
        if !guide.branchingOff.isEmpty || !guide.shortOfStop.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Verdict(ok: false, text: "이 글자면 타지 마세요")
                if !guide.branchingOff.isEmpty {
                    DestinationChips(names: guide.branchingOff, fill: Theme.vermilionFill)
                    Text("\(guide.junction?.ko ?? "")에서 다른 길로 갈라져 \(segment.alighting.ko)에 가지 않아요")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !guide.shortOfStop.isEmpty {
                    DestinationChips(names: guide.shortOfStop.map(\.ja), fill: Theme.inkSoft, limit: 4)
                    Text("\(segment.alighting.ko)에 닿기 전에 끝나는 열차예요. 탔다면 끝나는 역에서 내려 다음 열차를 타세요")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 탄 역 ●━━━ 내릴 역 ◉━━━▶ 종점, 갈라지는 곳은 아래로 휘어 나간다.
    private struct Diagram: View {
        let segment: RouteSegment
        let guide: DestinationGuide

        var body: some View {
            GeometryReader { geo in
                let color = segment.line.swiftColor
                let x0: CGFloat = 8, xe = geo.size.width - 8, y: CGFloat = 30
                // 내릴 역 뒤로 더 가는 열차가 없으면(종점에서 내림) 내릴 역이 선의 끝이다.
                let endsHere = !segment.line.circular && segment.alighting == segment.headingStations.first
                    && segment.throughTermini.isEmpty
                let xa = endsHere ? xe : geo.size.width * 0.54

                // 탈 구간, 그 뒤로 이어지는 구간
                line(from: x0, to: xa, y: y).stroke(color, style: .init(lineWidth: 6, lineCap: .round))
                if !endsHere {
                    line(from: xa, to: xe - 6, y: y).stroke(color.opacity(0.4), style: .init(lineWidth: 6, lineCap: .round))
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(color.opacity(0.7))
                        .position(x: xe - 2, y: y)
                }

                // 갈라지는 곳
                if let junction = guide.junction {
                    let wrong = !guide.branchingOff.isEmpty
                    let xj = wrong ? (x0 + xa) / 2 : (xa + xe) / 2
                    Path { p in
                        p.move(to: CGPoint(x: xj, y: y))
                        p.addQuadCurve(to: CGPoint(x: xj + 32, y: y + 38), control: CGPoint(x: xj + 30, y: y))
                    }
                    .stroke(wrong ? Theme.vermilion : color.opacity(0.4),
                            style: .init(lineWidth: 5, lineCap: .round, dash: wrong ? [2, 8] : []))
                    Circle().fill(Theme.card).frame(width: 9, height: 9).position(x: xj, y: y)
                    Circle().strokeBorder(wrong ? Theme.vermilion : color, lineWidth: 2.5)
                        .frame(width: 11, height: 11).position(x: xj, y: y)
                    anchored("\(junction.ko)에서 갈라져요", color: wrong ? Theme.vermilion : Theme.inkSoft,
                             x: wrong ? xj + 42 : min(xj + 42, xe), y: y + 52, alignment: wrong ? .leading : .trailing)
                }

                // 구간 위의 말
                if !guide.shortOfStop.isEmpty {
                    anchored("여기서 끝나면 ✕", color: Theme.vermilion, x: (x0 + xa) / 2, y: 8, alignment: .center)
                }
                anchored(endsHere ? "끝까지 가면 ○" : "여기까지 가면 ○", color: Theme.indigo,
                         x: endsHere ? xe : (xa + xe) / 2, y: 8, alignment: endsHere ? .trailing : .center)

                // 탄 역, 내릴 역
                Circle().fill(Theme.card).frame(width: 12, height: 12).position(x: x0, y: y)
                Circle().strokeBorder(color, lineWidth: 4).frame(width: 16, height: 16).position(x: x0, y: y)
                Circle().fill(Theme.vermilionFill).frame(width: 18, height: 18).position(x: xa, y: y)
                Circle().fill(.white).frame(width: 6, height: 6).position(x: xa, y: y)
                anchored(segment.boarding.ko, color: Theme.inkSoft, x: x0 - 8, y: y + 20, alignment: .leading)
                anchored("\(segment.alighting.ko) 내림", color: Theme.vermilion, weight: .heavy,
                         x: endsHere ? xe + 8 : xa, y: y + 20, alignment: endsHere ? .trailing : .center)
            }
        }

        private func line(from a: CGFloat, to b: CGFloat, y: CGFloat) -> Path {
            Path { p in
                p.move(to: CGPoint(x: a, y: y))
                p.addLine(to: CGPoint(x: b, y: y))
            }
        }

        /// 한 점에 붙인 글자: 점에서 왼쪽 · 가운데 · 오른쪽으로 뻗는다.
        private func anchored(_ text: String, color: Color, weight: Font.Weight = .bold,
                              x: CGFloat, y: CGFloat, alignment: Alignment) -> some View {
            Text(text)
                .font(.caption2.weight(weight))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 0, height: 0, alignment: alignment)
                .position(x: x, y: y)
        }
    }
}

/// 전광판에 나올 행선지 글자들.
private struct DestinationChips: View {
    let names: [String]
    let fill: Color
    var limit = 8

    var body: some View {
        FlowRow(spacing: 6) {
            ForEach(names.prefix(limit), id: \.self) { name in
                Text(name)
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            if names.count > limit {
                Text("외 \(names.count - limit)곳")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.vertical, 4)
            }
        }
    }
}

private struct Verdict: View {
    let ok: Bool
    let text: String

    var body: some View {
        Label(text, systemImage: ok ? "circle" : "xmark")
            .font(.caption.weight(.heavy))
            .foregroundStyle(ok ? Theme.indigo : Theme.vermilion)
    }
}

struct GuideHeading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.heavy)).foregroundStyle(Theme.ink)
            Text(detail).font(.caption).foregroundStyle(Theme.inkSoft)
        }
    }
}

// MARK: - 정차역 도표

/// 열차 종류마다 한 줄: 탄 역부터 내릴 역까지 어디에 서는지 점으로 찍는다.
/// 내 역을 지나치는 열차는 그 자리에 ✕ 가 선다.
struct ServiceChart: View {
    let segment: RouteSegment

    var body: some View {
        let options = segment.serviceOptions
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GuideHeading(title: "열차 종류를 확인하세요", detail: "종류마다 서는 역이 달라요. 점이 서는 역이에요")
                ForEach(options) { row($0) }
                HStack {
                    Text(segment.boarding.ko)
                    Spacer()
                    Text(segment.alighting.ko)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.inkSoft)
                .accessibilityHidden(true)
                if options.contains(where: { $0.verdict != .board }), let local = options.first,
                   local.stopsAt.allSatisfy({ $0 }) {
                    Text("모르겠으면 \(local.sign) 열차를 타세요. 모든 역에 서요")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.caution)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.caution.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func row(_ option: ServiceOption) -> some View {
        let board = option.verdict == .board
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(option.sign)
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(board ? Theme.indigoFill : Theme.vermilionFill,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(option.nameKo)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(option.minutes.map { "약 \($0)분" } ?? "타지 마세요")
                    .font(.footnote.weight(.heavy))
                    .monospacedDigit()
                    .fixedSize()
                    .foregroundStyle(board ? Theme.indigo : Theme.vermilion)
            }
            if option.verdict == .needsPaidSeat {
                Text("지정석 유료 열차라 일반 표로는 못 타요")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            } else {
                StopTrack(stopsAt: option.stopsAt, color: board ? segment.line.swiftColor : Theme.inkSoft)
                    .frame(height: 16)
                if option.verdict == .skipsYourStop {
                    Text("\(skipped(option).joined(separator: ", "))에 서지 않아요")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !option.holidaySkipsKo.isEmpty {
                Text("토·일·공휴일에는 \(Josa.eul(option.holidaySkipsKo.joined(separator: "·"))) 지나쳐요")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.caution)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 이 열차가 서지 않는 내 역(탄 역 · 내릴 역).
    private func skipped(_ option: ServiceOption) -> [String] {
        [(option.stopsAt.first, segment.boarding.ko), (option.stopsAt.last, segment.alighting.ko)]
            .filter { $0.0 == false }.map(\.1)
    }
}

/// 한 열차의 정차역: 서는 역은 점, 지나치는 역은 선만. 양 끝(내 역)에 서지 않으면 ✕.
private struct StopTrack: View {
    let stopsAt: [Bool]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let n = stopsAt.count
            let inset: CGFloat = 7
            let dx = n > 1 ? (geo.size.width - inset * 2) / CGFloat(n - 1) : 0
            let y = geo.size.height / 2
            Path { p in
                p.move(to: CGPoint(x: inset, y: y))
                p.addLine(to: CGPoint(x: geo.size.width - inset, y: y))
            }
            .stroke(color.opacity(0.35), style: .init(lineWidth: 3, lineCap: .round))
            ForEach(Array(stopsAt.enumerated()), id: \.offset) { i, stops in
                let mine = i == 0 || i == n - 1
                Group {
                    if stops {
                        Circle().fill(color).frame(width: mine ? 13 : 7, height: mine ? 13 : 7)
                    } else if mine {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Theme.vermilion)
                            .background(Circle().fill(Theme.card).frame(width: 15, height: 15))
                    }
                }
                .position(x: inset + dx * CGFloat(i), y: y)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 환승 그림

/// 갈아탈 때 걷는 길: 내린 역 역명판 → 개찰구 안 / 밖 → 탈 역 역명판.
/// 역 이름이 다르거나, 개찰구를 나가거나, 역이 떨어져 있을 때만 그린다.
struct TransferWalkDiagram: View {
    let walk: TransferWalk
    let fromLine: RailLine
    let toLine: RailLine

    static func isWorthDrawing(_ walk: TransferWalk) -> Bool {
        walk.renamed || walk.outside || walk.meters != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                NamePlate(station: walk.from, color: fromLine.swiftColor)
                VStack(spacing: 3) {
                    Text(walk.outside ? "개찰구 밖" : "개찰구 안")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(walk.outside ? .white : Theme.ink)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(walk.outside ? Theme.vermilionFill : Theme.hairline, in: Capsule())
                    HStack(spacing: 2) {
                        Image(systemName: "figure.walk")
                        Image(systemName: "arrow.right")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.inkSoft)
                    if let meters = walk.meters, let minutes = walk.minutes {
                        Text("약 \(meters)m · \(minutes)분")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                    }
                }
                .fixedSize()
                NamePlate(station: walk.to, color: toLine.swiftColor)
            }
            if walk.renamed {
                Text("역 이름이 달라도 이어진 역이에요. \(walk.to.ja) 글자를 따라가세요")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if walk.outside {
                Text("개찰구를 나와 길로 걸어요. 나가는 게 맞아요")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else if walk.meters != nil {
                Text("같은 역 안이지만 승강장이 멀어요. 시간을 넉넉히 잡으세요")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 역명판(駅名標): 흰 판에 역 이름, 아래에 노선색 띠.
private struct NamePlate: View {
    let station: RailStation
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(station.ja)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Theme.ink)
            Text(station.ko)
                .font(.caption2)
                .foregroundStyle(Theme.inkSoft)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 6).padding(.top, 7).padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) { Rectangle().fill(color).frame(height: 4) }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.hairline))
    }
}

// MARK: - 출구 표지판

/// 내린 역에서 어느 출구로 나갈지: 역의 노란 출구 표지판처럼 그린다.
struct ExitSigns: View {
    let hints: [ExitHint]
    let station: RailStation

    /// 일본 역의 출구 표지판 노랑.
    private static let exitYellow = Color(light: 0xFF_D4_00, dark: 0xFF_D4_00)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideHeading(title: "어느 출구로 나갈까요?",
                         detail: "\(station.ko)역 노란 표지판(出口)에서 이 글자를 찾으세요")
            ForEach(hints.prefix(5)) { hint in
                HStack(spacing: 12) {
                    VStack(spacing: 0) {
                        Text("出口").font(.system(size: 9, weight: .heavy))
                        Text(hint.exit)
                            .font(.system(.headline, design: .rounded, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .foregroundStyle(.black)
                    .frame(width: 72)
                    .padding(.vertical, 6)
                    .background(Self.exitYellow, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hint.spot.ko).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                        Text(walkText(hint)).font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(hint.spot.ko): \(hint.exit) 출구. \(walkText(hint))")
            }
        }
        .card(padding: 16)
    }

    private func walkText(_ hint: ExitHint) -> String {
        switch hint.walkMinutes {
        case 0?: return "\(hint.spot.ja) · 출구와 바로 이어져요"
        case let m?: return "\(hint.spot.ja) · 걸어서 \(m)분"
        case nil: return hint.spot.ja
        }
    }
}

// MARK: - 멈췄을 때 · 막차

/// 밤늦게만 뜬다: 앱은 막차 시각을 모르므로 전광판을 보라고 말한다.
struct LastTrainNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BoardWord("最終")
            VStack(alignment: .leading, spacing: 2) {
                Text("막차 시간이 가까워요")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Theme.ink)
                Text("전광판에 最終(막차)이 붙은 열차가 마지막이에요. 갈아탈 노선의 막차가 더 이를 수 있어요. 이 앱은 아직 막차 시각을 알려 주지 못해요")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

/// 노선이 멈췄을 때: 전광판에서 읽을 글자와, 그 노선을 빼고 돌아가는 길.
struct DisruptionCard: View {
    let route: Route
    @State private var open: Bool

    /// 스크린샷·시험용: `-openDisruption` 으로 띄우면 펼친 채 뜬다.
    init(route: Route, open: Bool = ProcessInfo.processInfo.arguments.contains("-openDisruption")) {
        self.route = route
        _open = State(initialValue: open)
    }

    /// 탈 노선(이어 달리는 같은 노선은 한 번만)과 그 노선을 뺀 가장 빠른 길.
    private var detours: [(segment: RouteSegment, route: Route?)] {
        let planner = RoutePlanner(network: .shared)
        var seen = Set<String>()
        return route.segments
            .filter { seen.insert($0.line.operator + $0.line.nameJa).inserted }
            .map { ($0, planner.detours(around: $0, of: route).first) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.snappy) { open.toggle() }
            } label: {
                HStack {
                    Label("열차가 멈췄을 때", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .foregroundStyle(Theme.inkSoft)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "펼침" : "접힘")

            if open {
                VStack(alignment: .leading, spacing: 10) {
                    Text("전광판에 이 글자가 뜨면")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.inkSoft)
                    word("運転見合わせ", "운행 중단", "열차가 서 있어요. 아래에서 돌아가는 길을 찾으세요")
                    word("遅延", "지연", "늦게 오지만 다녀요. 기다리면 돼요")
                    word("振替輸送", "대신 태워 주기", "종이 표와 패스는 다른 회사 열차를 그대로 탈 수 있어요. 교통카드는 해당되지 않아요")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("멈춘 노선을 빼고 다시 찾기")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.inkSoft)
                    ForEach(detours, id: \.segment.id) { item in
                        detourRow(item.segment.line, item.route)
                    }
                }
            }
        }
        .card(padding: 16)
    }

    @ViewBuilder private func detourRow(_ line: RailLine, _ detour: Route?) -> some View {
        if let detour {
            NavigationLink {
                RouteDetailView(route: detour)
            } label: {
                detourLabel(line, "\(detour.estimatedMinutes)분 · 환승 \(detour.transferCount)번", chevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("\(Josa.eul(line.nameKo)) 타지 않는 길을 엽니다")
        } else {
            detourLabel(line, "이 앱이 아는 다른 길이 없어요", chevron: false)
        }
    }

    private func detourLabel(_ line: RailLine, _ detail: String, chevron: Bool) -> some View {
        HStack(spacing: 10) {
            LineBadge(line: line, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Josa.i(line.nameKo)) 멈췄다면")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text(detail).font(.caption).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(10)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func word(_ ja: String, _ ko: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            BoardWord(ja, minWidth: 96)
            VStack(alignment: .leading, spacing: 1) {
                Text(ko).font(.footnote.weight(.bold)).foregroundStyle(Theme.ink)
                Text(detail).font(.caption).foregroundStyle(Theme.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 전광판 글자: 검은 판에 주황 글씨.
private struct BoardWord: View {
    let text: String
    var minWidth: CGFloat?
    init(_ text: String, minWidth: CGFloat? = nil) {
        self.text = text
        self.minWidth = minWidth
    }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.heavy))
            .foregroundStyle(Color(light: 0xFF_B2_3E, dark: 0xFF_B2_3E))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(minWidth: minWidth)
            .background(Color(light: 0x15_17_1C, dark: 0x15_17_1C), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - 갈아타기

/// 내린 곳에서 다음 열차 타는 곳까지: 따라갈 안내판 글자, 걷는 길, 개찰구 · 요금.
struct TransferInstructions: View {
    let from: RouteSegment
    let to: RouteSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if from.line.id == to.line.id {
                Text("같은 \(to.line.nameKo)이지만 여기서 열차가 끝나요. 내려서 \(to.headingSign) 열차로 바꿔 타세요")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            } else {
                HStack(spacing: 8) {
                    LineBadge(line: to.line, size: 22)
                    Text("\(to.line.nameJa) のりかえ")
                        .font(.body.weight(.heavy))
                        .foregroundStyle(Theme.ink)
                }
                Text("이 글자가 적힌 안내판을 따라가세요")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            let walk = from.walk(to: to)
            if TransferWalkDiagram.isWorthDrawing(walk) {
                TransferWalkDiagram(walk: walk, fromLine: from.line, toLine: to.line)
            }
            if from.line.operator != to.line.operator {
                note("yensign.circle", "\(from.line.operatorKo)에서 \(Josa.ro(to.line.operatorKo)) 회사가 바뀌어요. 개찰구를 한 번 더 지나고 요금이 따로 붙어요. 교통카드(Suica·ICOCA 등)는 그대로 찍으면 돼요")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func note(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.caption.weight(.bold))
            Text(text).font(.caption)
        }
        .foregroundStyle(Theme.inkSoft)
    }
}

// MARK: - 타는 칸

/// 도중에 둘로 나뉘는 열차: 내 역까지 가는 칸에 타야 한다 (関空快速 1〜4号車).
struct CarAdvice: View {
    let split: RailLine.Split

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("열차가 도중에 둘로 나뉘어요", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Theme.vermilion)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(split.stayOn.cars)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Theme.ink)
                Text("에 타세요")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Theme.ink)
            }
            Text("\(split.stayOn.name) 칸이에요. \(split.leave.cars)(\(split.leave.name))는 \(split.atStation)에서 떨어져 \(split.leave.toward ?? "다른 곳")으로 가요")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Text("승강장 바닥과 표지판에 칸 번호가 적혀 있어요")
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.vermilion.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.vermilion.opacity(0.5), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}
