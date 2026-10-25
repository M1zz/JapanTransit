import SwiftUI

/// 길찾기: 출발역과 도착역을 고르면 경로를 보여 준다.
struct PlannerView: View {
    @AppStorage("planner.from") private var fromJa = ""
    @AppStorage("planner.to") private var toJa = ""
    @State private var picking: Field?
    @State private var path: [Route] = []

    private enum Field: String, Identifiable {
        case from, to
        var id: String { rawValue }
    }

    private let network = RailNetwork.shared
    private var from: Place? { network.place(fromJa) }
    private var to: Place? { network.place(toJa) }

    private var routes: [Route] {
        guard let from, let to else { return [] }
        return RoutePlanner(network: network).routes(from: from.id, to: to.id)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    ticket
                    if from != nil, to != nil {
                        results
                    } else {
                        tips
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Theme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { RouteDetailView(route: $0) }
            .onAppear {
                // 스크린샷·시험용: `-openFirstRoute` 로 띄우면 첫 경로를 바로 연다.
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-openFirstRoute"), path.isEmpty, let r = routes.first {
                    path = [r]
                }
            }
            .task {
                // `-openPicker` 로 도착역 고르기를 연다 (스크린샷용). 첫 화면이 뜬 뒤에.
                guard ProcessInfo.processInfo.arguments.contains("-openPicker") else { return }
                try? await Task.sleep(for: .milliseconds(600))
                picking = .to
            }
            .sheet(item: $picking) { field in
                StationPickerView(title: field == .from ? "출발역" : "도착역",
                                  region: (field == .from ? to ?? from : from ?? to)?.region ?? Region.tokyo.id) { place in
                    if field == .from { fromJa = place.id } else { toJa = place.id }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("일본길찾기")
                .font(.footnote.weight(.heavy))
                .tracking(1)
                .foregroundStyle(Theme.indigo)
            Text("어디로 갈까요?")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(Theme.ink)
        }
        .padding(.top, 24)
    }

    // MARK: Ticket

    /// 출발·도착을 기차표(切符)처럼: 두 칸 사이에 절취선, 오른쪽에 바꾸기.
    private var ticket: some View {
        VStack(spacing: 0) {
            ticketRow(.from, place: from, eyebrow: ("출발", "FROM"))
            ZStack(alignment: .trailing) {
                Perforation()
                    .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .frame(height: 1)
                    .padding(.horizontal, 18)
                Button {
                    withAnimation(.snappy) { swap(&fromJa, &toJa) }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Theme.indigoFill, in: Circle())
                        .overlay(Circle().stroke(Theme.card, lineWidth: 3))
                }
                .padding(.trailing, 22)
                .disabled(from == nil && to == nil)
                .accessibilityLabel("출발역과 도착역 바꾸기")
            }
            ticketRow(.to, place: to, eyebrow: ("도착", "TO"))
        }
        .background(Theme.card, in: TicketShape(notchY: 0.5))
        .overlay(TicketShape(notchY: 0.5).stroke(Theme.hairline))
        .shadow(color: Theme.ink.opacity(0.06), radius: 14, y: 6)
    }

    private func ticketRow(_ field: Field, place: Place?, eyebrow: (String, String)) -> some View {
        Button {
            picking = field
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(ko: eyebrow.0, en: eyebrow.1)
                if let place {
                    StationName(ko: place.ko, ja: place.ja, marks: place.marks)
                } else {
                    Text(field == .from ? "출발역 고르기" : "도착역 고르기")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Theme.inkSoft.opacity(0.6))
                        .frame(height: 44, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(place.map { "\(eyebrow.0): \($0.ko)" } ?? "\(eyebrow.0)역 고르기")
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        let routes = self.routes   // one search per render
        if routes.isEmpty {
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .card()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("경로")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                ForEach(routes) { route in
                    NavigationLink(value: route) {
                        RouteSummaryCard(route: route, label: RoutePlanner.label(for: route, in: routes))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyMessage: String {
        guard let from, let to else { return "" }
        if from.id == to.id { return "출발역과 도착역이 같아요" }
        if from.region != to.region {
            let a = Region.named(from.region)?.ko ?? from.region, b = Region.named(to.region)?.ko ?? to.region
            return "\(a)와 \(b)는 다른 도시예요. 도시 사이(신칸센 등)는 아직 안내하지 않아요"
        }
        if network.transferNames(at: from.id).contains(to.id) {
            return network.isOutsideTransfer(from: from.id, to: to.id)
                ? "두 역은 가까워요. 개찰구를 나와 걸어서 가세요"
                : "두 역은 역 안 통로로 이어져 있어요. 걸어서 가세요"
        }
        return "이 두 역을 잇는 길을 찾지 못했어요"
    }

    // MARK: Tips

    private var tips: some View {
        VStack(alignment: .leading, spacing: 16) {
            tip(1, "역을 찾아요", "신주쿠, 新宿, Shinjuku, M08 무엇으로든")
            tip(2, "표지판 글자를 맞춰 봐요", "일본어를 못 읽어도 글자 모양만 맞추면 돼요")
            tip(3, "열차를 비춰 봐요", "승강장에서 카메라로 타도 되는 열차인지 확인해요")
        }
        .card(padding: 20)
    }

    private func tip(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.indigo)
                .frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.indigo, lineWidth: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                Text(detail).font(.footnote).foregroundStyle(Theme.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Route summary

/// 경로 한 장: 큰 시간, 노선색 띠, 탈 노선, 요약.
struct RouteSummaryCard: View {
    let route: Route
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(route.estimatedMinutes)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("분").font(.headline)
                Spacer()
                Text(label)
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(label == "추천" ? .white : Theme.indigo)
                    .background(label == "추천" ? Theme.indigoFill : Theme.indigo.opacity(0.12), in: Capsule())
            }
            .foregroundStyle(Theme.ink)

            RouteStrip(route: route)

            FlowRow(spacing: 10) {
                ForEach(route.segments) { LineChip(line: $0.line) }
            }

            Text(summary)
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
        .card(padding: 18)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        var parts = ["\(route.stopCount)정거장"]
        parts.append(route.transferCount == 0 ? "갈아타지 않아요" : "환승 \(route.transferCount)번")
        if route.operatorChanges > 0 { parts.append("회사가 바뀌어 요금이 따로") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Shapes & layout

/// A ticket: rounded card with a half-circle notch cut into both sides.
struct TicketShape: Shape {
    var notchY: CGFloat
    var radius: CGFloat = Theme.corner
    var notch: CGFloat = 11

    func path(in r: CGRect) -> Path {
        let y = r.minY + r.height * notchY
        var p = Path()
        p.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: y - notch))
        p.addArc(center: CGPoint(x: r.maxX, y: y), radius: notch,
                 startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addArc(center: CGPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: y + notch))
        p.addArc(center: CGPoint(x: r.minX, y: y), radius: notch,
                 startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// The dashed tear line across the ticket.
struct Perforation: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

/// Wraps its children onto new lines, left to right.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { y += line + spacing; x = 0; line = 0 }
            x += s.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, s.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { y += line + spacing; x = bounds.minX; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}
