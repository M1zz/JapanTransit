import SwiftUI
import LeeoKit

/// 경로 안내: 노선도처럼 위에서 아래로. 노선색 선이 탄 역과 내릴 역을 잇고,
/// 갈아타는 곳은 걷는 점선으로 잇는다. 탈 때마다 찾을 표지판을 그 자리에 보여 준다.
struct RouteDetailView: View {
    let route: Route
    @State private var scanning: RouteSegment?
    @AppStorage(JapanTransitTipMoments.boardedKey) private var boardedCount = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summary
                    .padding(.bottom, 24)
                // 카메라로 확인하고 탄 열차가 쌓였을 때만, 드물게 응원을 부탁한다. 카메라를 닫고 돌아온 자리다 (모달 아님)
                LeeoTipAskSlot<JapanTransitSpec>(tipJar: JapanTransitSpec.tipJar,
                                                 reached: JapanTransitTipMoments.reached(boardedCount: boardedCount))
                    .padding(.bottom, 24)
                ForEach(Array(route.segments.enumerated()), id: \.element.id) { i, seg in
                    if i > 0 {
                        let prev = route.segments[i - 1]
                        TransferBlock(from: prev, to: seg,
                                      staysOnTrain: route.staysOnTrain(between: prev, and: seg))
                    } else {
                        StopNode(station: seg.boarding, line: seg.line, title: "\(seg.boarding.ko)에서 타요", kind: .start,
                                 below: (seg.line.swiftColor, .ride))
                    }
                    RideBlock(segment: seg) { scanning = seg }
                }
                if let last = route.segments.last {
                    StopNode(station: last.alighting, line: last.line, title: "\(last.alighting.ko)에서 내려요", kind: .end,
                             above: (last.line.swiftColor, .ride))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("\(route.segments.first?.boarding.ko ?? "") → \(route.segments.last?.alighting.ko ?? "")")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $scanning) { seg in
            BoardScannerView(segment: seg)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                stat("\(route.estimatedMinutes)", "분")
                stat("\(route.stopCount)", "정거장")
                stat("\(route.transferCount)", "번 환승")
                Spacer()
            }
            RouteStrip(route: route, height: 10)
        }
        .card(padding: 18)
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.inkSoft)
        }
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rail column

/// The left column of the timeline: a vertical line in the line colour, solid
/// for a ride and dotted for a walk.
private struct Rail: View {
    enum Style { case ride, walk }
    let color: Color
    var style: Style = .ride

    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: geo.size.width / 2, y: 0))
                p.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
            }
            .stroke(color, style: style == .ride
                    ? StrokeStyle(lineWidth: 6, lineCap: .round)
                    : StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 7]))
        }
        .frame(width: railWidth)
        .accessibilityHidden(true)
    }
}

private let railWidth: CGFloat = 40

// MARK: - Station node

/// A station on the timeline: a round node on the rail and the station name
/// as it appears on the sign. Start and end are a bit bolder.
private struct StopNode: View {
    enum Kind { case start, end, transfer }
    let station: RailStation
    let line: RailLine
    let title: String
    let kind: Kind
    /// The rail coming in from above and going out below the node.
    var above: (Color, Rail.Style)?
    var below: (Color, Rail.Style)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Color.clear.frame(width: railWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(kind == .end ? Theme.vermilion : Theme.inkSoft)
                HStack(spacing: 8) {
                    Text(station.ja)
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    StationMark(code: station.code, color: line.swiftColor, size: 28)
                }
            }
            .padding(.vertical, 8)
            Spacer(minLength: 0)
        }
        // The rail runs the full height of the row, behind the node.
        .background(alignment: .leading) {
            VStack(spacing: 0) {
                railPiece(above)
                railPiece(below)
            }
            .frame(width: railWidth)
        }
        .overlay(alignment: .leading) {
            node.frame(width: railWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(station.ja), 역 번호 \(station.code)")
    }

    @ViewBuilder private func railPiece(_ piece: (Color, Rail.Style)?) -> some View {
        if let piece { Rail(color: piece.0, style: piece.1) } else { Color.clear }
    }

    private var node: some View {
        ZStack {
            Circle()
                .fill(kind == .end ? Theme.vermilionFill : Theme.card)
            Circle()
                .strokeBorder(kind == .end ? Theme.vermilionFill : line.swiftColor, lineWidth: 6)
            if kind == .end {
                Circle().fill(.white).frame(width: 8, height: 8)
            }
        }
        .frame(width: 26, height: 26)
    }
}

// MARK: - Ride

private struct RideBlock: View {
    let segment: RouteSegment
    let onScan: () -> Void
    @State private var showStops = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rail(color: segment.line.swiftColor)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    LineChip(line: segment.line)
                    Spacer()
                    Text(segment.line.operatorKo)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.inkSoft)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("표지판에서 이 글자를 찾으세요")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.inkSoft)
                    DirectionSign(segment: segment)
                }

                if !segment.throughTermini.isEmpty {
                    Text("다른 회사 노선까지 가는 열차는 행선지가 이렇게도 나와요: \(segment.throughTermini.prefix(4).joined(separator: " · "))")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                }

                ServiceAdvice(segment: segment)

                stops

                Button(action: onScan) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                        Text("승강장에서 열차 비춰 보기")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.indigoFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .card(padding: 16)
            .padding(.vertical, 10)
        }
    }

    private var stops: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { showStops.toggle() }
            } label: {
                HStack {
                    Text("\(segment.stopCount)정거장")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text("\(segment.alighting.ko)까지")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(showStops ? 180 : 0))
                        .foregroundStyle(Theme.inkSoft)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showStops {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(segment.stations.enumerated()), id: \.element.code) { i, s in
                        HStack(spacing: 10) {
                            StationMark(code: s.code, color: segment.line.swiftColor, size: 24)
                            Text(s.ja).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(s.ko).font(.caption).foregroundStyle(Theme.inkSoft)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .opacity(i == 0 || i == segment.stations.count - 1 ? 1 : 0.85)
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

/// 역을 건너뛰는 열차 주의.
private struct ServiceAdvice: View {
    let segment: RouteSegment

    var body: some View {
        let advice = segment.serviceAdvice
        if !advice.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(advice, id: \.service.id) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.service.signWords.first ?? "")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(item.ok ? Theme.indigoFill : Theme.vermilionFill,
                                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.service.nameKo)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.ink)
                            Text(item.service.isPaid ? "지정석 유료 열차라 일반 표로는 못 타요"
                                 : item.ok ? "타도 돼요. 두 역에 다 서요" : skipText(item.service))
                                .font(.caption)
                                .foregroundStyle(Theme.inkSoft)
                            if let skips = item.service.holidaySkips, !skips.isEmpty {
                                Text("토·일·공휴일에는 \(Josa.eul(skips.map { ko($0) }.joined(separator: "·"))) 지나쳐요")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.caution)
                            }
                        }
                    }
                }
                if advice.contains(where: { !$0.ok }) {
                    Text("모르겠으면 各停(각역정차)을 타세요")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.caution)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.caution.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func ko(_ ja: String) -> String {
        RailNetwork.shared.place(ja: ja, region: segment.line.regionID)?.ko ?? ja
    }

    private func skipText(_ s: RailService) -> String {
        let stops = s.stops(on: .now)
        let skipped = [segment.boarding, segment.alighting].filter { !stops.contains($0.ja) }.map(\.ko)
        return "타지 마세요. \(skipped.joined(separator: ", "))에 서지 않아요"
    }
}

// MARK: - Transfer

private struct TransferBlock: View {
    let from: RouteSegment
    let to: RouteSegment
    let staysOnTrain: Bool

    var body: some View {
        if staysOnTrain {
            HStack(spacing: 12) {
                Rail(color: from.line.swiftColor)
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(Josa.ro(to.line.nameKo)) 이어 가는 열차면 그대로 타고 가요", systemImage: "arrow.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text("\(from.alighting.ko)에서 끝나는 열차면 내려서 \(to.headingSign) 열차로 갈아타세요")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(.vertical, 12)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                StopNode(station: from.alighting, line: from.line, title: "\(from.alighting.ko)에서 내려 갈아타요", kind: .transfer,
                         above: (from.line.swiftColor, .ride), below: (Theme.inkSoft, .walk))
                HStack(alignment: .top, spacing: 12) {
                    Rail(color: Theme.inkSoft, style: .walk)
                    walk
                        .padding(.vertical, 8)
                }
                StopNode(station: to.boarding, line: to.line, title: "\(to.line.nameKo) 타는 곳", kind: .transfer,
                         above: (Theme.inkSoft, .walk), below: (to.line.swiftColor, .ride))
            }
        }
    }

    private var walk: some View {
        VStack(alignment: .leading, spacing: 8) {
            if from.line.id == to.line.id {
                Text("같은 \(to.line.nameKo)이지만 여기서 열차가 끝나요. 내려서 \(to.headingSign) 열차로 바꿔 타세요")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            } else {
                HStack(spacing: 8) {
                    LineBadge(line: to.line, size: 22)
                    Text("\(to.line.nameJa) のりかえ")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
                Text("이 글자가 적힌 안내판을 따라가세요")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            if RailNetwork.shared.isOutsideTransfer(from: from.line.placeID(from.alighting), to: to.line.placeID(to.boarding)) {
                note("figure.walk", "개찰구를 나와 걸어서 \(to.boarding.ko)(\(to.boarding.ja))역으로 가요. 개찰구 밖으로 나가는 게 맞아요")
            } else if from.alighting.ja != to.boarding.ja {
                note("figure.walk", "역 안 통로로 걸어서 \(to.boarding.ko)(\(to.boarding.ja))역으로 가요")
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
