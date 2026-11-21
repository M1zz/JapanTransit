import SwiftUI

/// 길 안내: 지금 할 일 하나만 크게. 타는 곳 → 타고 가기 → 갈아타기 → 나가기를
/// 한 단계씩 넘긴다. 타고 가는 동안은 남은 정거장과 내릴 역을 보여 주고,
/// 차내 화면과 다르면 지금 역을 눌러 맞춘다.
struct GuideView: View {
    @Bindable private var session = TripSession.shared
    @State private var scanning: RouteSegment?
    @State private var confirmingEnd = false
    @State private var showPast = false

    var body: some View {
        if let guide = session.guide, let step = session.step {
            VStack(spacing: 0) {
                header(guide)
                ScrollView {
                    content(step, guide)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(session.stepIndex)   // 단계가 바뀌면 맨 위부터
                .onChange(of: session.stepIndex) { showPast = false }
                footer(step)
            }
            .background(Theme.paper.ignoresSafeArea())
            .fullScreenCover(item: $scanning) { seg in
                BoardScannerView(segment: seg).foldConfined()
            }
            .confirmationDialog("안내를 끝낼까요?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("안내 끝내기", role: .destructive) { session.end() }
            }
        }
    }

    // MARK: Header

    private func header(_ guide: TripGuide) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button { session.isShowing = false } label: {
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("안내 접기")
                Spacer()
                Text("\(guide.route.segments.first?.boarding.ko ?? "") → \(guide.route.segments.last?.alighting.ko ?? "")")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("끝내기") { confirmingEnd = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(height: 44)
            }
            .tint(Theme.inkSoft)
            progress(guide)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .background(Theme.card)
    }

    /// 단계마다 한 칸. 지난 칸과 지금 칸은 그 열차의 노선색.
    private func progress(_ guide: TripGuide) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                Capsule()
                    .fill(i <= session.stepIndex ? color(of: step, in: guide) : Theme.hairline)
                    .frame(height: i == session.stepIndex ? 6 : 4)
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement()
        .accessibilityLabel("\(guide.steps.count)단계 중 \(session.stepIndex + 1)단계")
    }

    private func color(of step: TripGuide.Step, in guide: TripGuide) -> Color {
        switch step {
        case .board(let i), .ride(let i): guide.legs[i].first.line.swiftColor
        case .change, .leave: Theme.inkSoft
        }
    }

    // MARK: Steps

    @ViewBuilder
    private func content(_ step: TripGuide.Step, _ guide: TripGuide) -> some View {
        switch step {
        case .board(let i): board(guide.legs[i], number: i + 1, of: guide.legs.count)
        case .ride(let i): ride(guide.legs[i])
        case .change(let i): change(from: guide.legs[i], to: guide.legs[i + 1])
        case .leave: leave(guide.legs[guide.legs.count - 1])
        }
    }

    private func board(_ leg: TripGuide.Leg, number: Int, of total: Int) -> some View {
        let seg = leg.first
        return VStack(alignment: .leading, spacing: 20) {
            stepTitle(total > 1 ? "\(number)번째 열차 · 타는 곳으로" : "타는 곳으로",
                      "\(seg.line.nameKo) 승강장으로 가세요")
            lineHeader(seg.line)
            VStack(alignment: .leading, spacing: 8) {
                Text("표지판에서 이 글자를 찾으세요")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.inkSoft)
                DirectionSign(segment: seg)
            }
            if let split = leg.cars {
                CarAdvice(split: split)
            }
            DestinationMap(segment: seg, through: leg.segments.count > 1 ? leg.segments[1] : nil)
                .card()
            Button { scanning = seg } label: {
                Label("승강장에서 열차 비춰 보기", systemImage: "camera.viewfinder")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(Theme.indigo)
        }
    }

    private func ride(_ leg: TripGuide.Leg) -> some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            let clock = session.clock ?? RideClock(index: 0, at: context.date)
            let here = clock.stopIndex(on: leg, at: context.date)
            let left = leg.stops.count - 1 - here
            let minutes = max(Int((clock.arrival(at: leg.stops.count - 1, on: leg).timeIntervalSince(context.date) / 60).rounded(.up)), 0)
            VStack(alignment: .leading, spacing: 20) {
                rideHeadline(left: left, minutes: minutes, leg: leg)
                stopList(leg, here: here)
                Text("차내 화면의 역 이름과 다르면 지금 역을 눌러 맞춰 주세요. 지하에서는 시간으로 어림해요")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .sensoryFeedback(.warning, trigger: left <= 1)
        }
    }

    private func rideHeadline(left: Int, minutes: Int, leg: TripGuide.Leg) -> some View {
        let soon = left <= 1
        let stop = leg.alighting.station
        return VStack(alignment: .leading, spacing: 10) {
            Text(left == 0 ? "내릴 역이에요" : left == 1 ? "다음 역에서 내려요" : "\(left)정거장 남았어요")
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .foregroundStyle(soon ? Theme.vermilion : Theme.ink)
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 2) {
                Text("내릴 역")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.inkSoft)
                StationName(ko: stop.ko, ja: stop.ja, en: stop.en,
                            marks: [Place.Mark(code: stop.code, color: leg.alighting.line.swiftColor, lineID: leg.alighting.line.id)],
                            large: true)
            }
            if left > 0 {
                Text(minutes <= 1 ? "곧 도착해요" : "약 \(minutes)분 뒤 도착해요")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            if soon {
                Label("문 쪽으로 가 있으세요", systemImage: "door.left.hand.open")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.vermilion)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(soon ? Theme.vermilion.opacity(0.08) : Theme.card,
                    in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .strokeBorder(soon ? Theme.vermilion : Theme.hairline, lineWidth: soon ? 2 : 1))
        .animation(.default, value: left)
    }

    /// 탄 역부터 내릴 역까지 한 줄. 지금 역에 점, 누르면 거기로 맞춘다.
    private func stopList(_ leg: TripGuide.Leg, here: Int) -> some View {
        let runsOn = Set(leg.runsOn.map(\.station))
        // 지난 역은 바로 앞 하나만. 펼치면 모두 (지난 역으로 맞출 때).
        let from = showPast ? 0 : max(here - 1, 0)
        return VStack(alignment: .leading, spacing: 0) {
            if from > 0 {
                Button { showPast = true } label: {
                    Label("지난 역 \(from)곳", systemImage: "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 36)
                        .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(leg.stops.enumerated()).filter { $0.offset >= from }, id: \.offset) { i, stop in
                Button { session.setHere(i) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Rectangle()
                                .fill(stop.line.swiftColor.opacity(i < here ? 0.35 : 1))
                                .frame(width: 5)
                                .padding(.top, i == from ? 22 : 0)
                                .padding(.bottom, i == leg.stops.count - 1 ? 22 : 0)
                            Circle()
                                .fill(i == here ? stop.line.swiftColor : Theme.card)
                                .overlay(Circle().strokeBorder(stop.line.swiftColor, lineWidth: 3))
                                .frame(width: i == here ? 20 : 13, height: i == here ? 20 : 13)
                        }
                        .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(stop.station.ja)
                                    .font(i == here || i == leg.stops.count - 1 ? .headline.weight(.heavy) : .subheadline.weight(.semibold))
                                Text(stop.station.ko)
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            if i == here {
                                Text(i == 0 ? "여기서 탔어요" : "지금 여기쯤")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(stop.line.swiftColor)
                            } else if runsOn.contains(stop.station), let next = leg.stops[safe: i + 1] {
                                Text("\(Josa.ro(next.line.nameKo)) 그대로 이어 가요. 여기서 끝나는 열차면 갈아타요")
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSoft)
                            } else if i == leg.stops.count - 1 {
                                Text("내려요")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.vermilion)
                            }
                        }
                        .foregroundStyle(i < here ? Theme.inkSoft : Theme.ink)
                        Spacer()
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(stop.station.ko)\(i == here ? ", 지금 여기" : "")")
                .accessibilityHint("지금 이 역이면 눌러 맞춥니다")
            }
        }
        .card(padding: 14)
    }

    private func change(from: TripGuide.Leg, to: TripGuide.Leg) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("갈아타기", "\(from.alighting.station.ko)에서 내려 \(to.first.line.nameKo) 타는 곳으로 가요")
            TransferInstructions(from: from.last, to: to.first)
                .card()
        }
    }

    private func leave(_ leg: TripGuide.Leg) -> some View {
        let stop = leg.alighting.station
        let exits = RailNetwork.shared.exits(at: leg.last.line.placeID(stop), preferring: leg.last.line.id)
        return VStack(alignment: .leading, spacing: 20) {
            stepTitle("도착했어요", "개찰구를 나가면 끝이에요")
            StationName(ko: stop.ko, ja: stop.ja, en: stop.en, large: true)
                .card()
            if !exits.isEmpty {
                ExitSigns(hints: exits, station: stop)
            }
        }
    }

    // MARK: Pieces

    private func stepTitle(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.heavy))
                .foregroundStyle(Theme.indigo)
            Text(detail)
                .font(.title2.weight(.heavy))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lineHeader(_ line: RailLine) -> some View {
        HStack(spacing: 10) {
            LineBadge(line: line, size: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(line.nameKo).font(.headline.weight(.heavy)).foregroundStyle(Theme.ink)
                Text("\(line.nameJa) · \(line.nameEn)").font(.caption).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func footer(_ step: TripGuide.Step) -> some View {
        let (title, icon): (String, String) = switch step {
        case .board: ("탔어요", "tram.fill")
        case .ride: ("내렸어요", "figure.walk.departure")
        case .change: ("갈아탈 승강장에 왔어요", "arrow.right")
        case .leave: ("안내 끝내기", "checkmark")
        }
        return HStack(spacing: 10) {
            if session.stepIndex > 0 {
                Button { session.back() } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.bold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.bordered)
                .tint(Theme.inkSoft)
                .accessibilityLabel("이전 단계")
            }
            Button { session.next() } label: {
                Label(title, systemImage: icon)
                    .font(.headline.weight(.heavy))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.indigo)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.card.shadow(.drop(color: .black.opacity(0.06), radius: 8, y: -2)), ignoresSafeAreaEdges: .bottom)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// 안내를 접어 둔 동안 길찾기 화면 맨 위에: 누르면 안내로 돌아간다.
struct TripResumeBar: View {
    @Bindable private var session = TripSession.shared

    var body: some View {
        if let guide = session.guide, !session.isShowing, let leg = session.leg {
            Button { session.isShowing = true } label: {
                HStack(spacing: 12) {
                    LineBadge(line: leg.first.line, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("길 안내 중").font(.caption.weight(.bold)).foregroundStyle(Theme.indigo)
                        Text("\(guide.route.segments.first?.boarding.ko ?? "") → \(guide.route.segments.last?.alighting.ko ?? "")")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Text("이어 보기").font(.subheadline.weight(.bold)).foregroundStyle(Theme.indigo)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.indigo)
                }
                .card(padding: 14)
            }
            .buttonStyle(.plain)
        }
    }
}
