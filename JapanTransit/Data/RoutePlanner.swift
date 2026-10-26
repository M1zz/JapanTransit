import Foundation
import TrainBoardKit

// MARK: - Route

/// One ride on one line, in travel order.
struct RouteSegment: Hashable, Identifiable {
    let line: RailLine
    /// Station indices on `line`, boarding first. On a circular line they wrap.
    let indices: [Int]
    /// +1 = station numbers go up (G09 → G10), -1 = down.
    let step: Int

    var id: String { "\(line.id):\(indices.map(String.init).joined(separator: ","))" }
    var stations: [RailStation] { indices.map { line.stations[$0] } }
    var boarding: RailStation { line.stations[indices[0]] }
    var alighting: RailStation { line.stations[indices[indices.count - 1]] }
    var stopCount: Int { indices.count - 1 }

    /// Riding time on the everyday train: the free service that stops at both
    /// ends and skips some stations in between (the most stopping of those, so
    /// a rare 特快 doesn't set the time). With none, every station counts.
    var rideMinutes: Double {
        let stations = self.stations
        let inside = Set(stations.map(\.ja))
        let stopping = (line.services ?? [])
            .filter { !$0.isPaid }
            .map { Set($0.stops(on: .now)).intersection(inside) }
            .filter { $0.contains(boarding.ja) && $0.contains(alighting.ja) && $0.count < stations.count }
            .max { $0.count < $1.count } ?? inside
        var total = 0.0, run = 0.0
        for (a, b) in zip(stations, stations.dropFirst()) {
            run += RailNetwork.haversine(a.lat, a.lng, b.lat, b.lng)
            if stopping.contains(b.ja) {
                total += Self.minutes(run: run)
                run = 0
            }
        }
        return total
    }

    static func minutes(_ a: RailStation, _ b: RailStation) -> Double {
        minutes(run: RailNetwork.haversine(a.lat, a.lng, b.lat, b.lng))
    }

    /// One run between two stops of `meters`: half a minute standing, ~36 km/h
    /// for the first 1.5 km while the train speeds up, ~90 km/h after that.
    static func minutes(run meters: Double) -> Double {
        0.5 + min(meters, 1500) / 600 + max(meters - 1500, 0) / 1500
    }
}

struct Route: Hashable, Identifiable {
    let segments: [RouteSegment]

    var id: String { segments.map(\.id).joined(separator: "|") }
    var stopCount: Int { segments.map(\.stopCount).reduce(0, +) }
    var transferCount: Int { max(segments.count - 1, 0) }
    /// Rough minutes: riding time from distance, ~8 min a change (walk + wait).
    var estimatedMinutes: Int {
        Int((segments.map(\.rideMinutes).reduce(0, +) + Double(transferCount) * RoutePlanner.transferMinutes).rounded())
    }
    /// Transfers that change company (Metro ↔ Toei ↔ JR): a separate fare and
    /// often a second ticket gate.
    var operatorChanges: Int {
        zip(segments, segments.dropFirst()).filter { $0.line.operator != $1.line.operator }.count
    }
}

// MARK: - Planner

struct RoutePlanner {
    let network: RailNetwork

    private struct Node: Hashable {
        let line: Int
        let index: Int
    }

    /// A change of trains: walking to the other platform and waiting.
    static let transferMinutes: Double = 8

    /// Fastest route and, when different, the one with the fewest transfers.
    /// `from` and `to` are place ids; places in different regions have no route.
    func routes(from: String, to: String) -> [Route] {
        guard let a = network.place(from), let b = network.place(to), a.id != b.id, a.region == b.region else { return [] }
        let from = a.id, to = b.id
        var result: [Route] = []
        for transferCost in [Self.transferMinutes, 30] {
            if let r = shortest(from: from, to: to, transferCost: transferCost), !result.contains(r) {
                result.append(r)
            }
        }
        return result.sorted { ($0.estimatedMinutes, $0.transferCount) < ($1.estimatedMinutes, $1.transferCount) }
    }

    /// Label for a route in a list sorted by `routes(from:to:)`: the first is the
    /// pick; a later one earns "환승 적게" only if it really has fewer transfers.
    static func label(for route: Route, in routes: [Route]) -> String {
        guard let first = routes.first, route != first else { return "추천" }
        return route.transferCount < first.transferCount ? "환승 적게" : "다른 길"
    }

    private func shortest(from: String, to: String, transferCost: Double) -> Route? {
        let lines = network.lines
        guard network.place(from) != nil, network.place(to) != nil else { return nil }
        let lineIndex = Dictionary(lines.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        // A station joined by an indoor passage counts as the same place to start
        // from or arrive at: reaching モノレール 羽田空港第1ターミナル is reaching
        // 京急 羽田空港第1・第2ターミナル. Street walks (outside) don't.
        func nodes(around id: String) -> [Node] {
            network.transferNames(at: id)
                .filter { $0 == id || !network.isOutsideTransfer(from: id, to: $0) }
                .flatMap { network.place($0)?.stops ?? [] }
                .compactMap { s in lineIndex[s.lineID].map { Node(line: $0, index: s.index) } }
        }
        let starts = nodes(around: from)
        let goals = Set(nodes(around: to))

        var dist: [Node: Double] = [:]
        var prev: [Node: Node] = [:]
        var queue = MinHeap<Node>()
        for s in starts {
            dist[s] = 0
            queue.push(s, 0)
        }

        func neighbours(_ n: Node) -> [(Node, Double)] {
            let line = lines[n.line]
            let count = line.stations.count
            var out: [(Node, Double)] = []
            for d in [-1, 1] {
                var j = n.index + d
                if line.circular { j = (j + count) % count }
                if j >= 0, j < count, j != n.index {
                    out.append((Node(line: n.line, index: j), RouteSegment.minutes(line.stations[n.index], line.stations[j])))
                }
            }
            // Transfers: the same station name on another line, or a station
            // you walk to inside (浜松町 → 大門) for a little more.
            let name = line.placeID(line.stations[n.index])
            for other in network.transferNames(at: name) {
                // Walking to a differently named station, or out on the street, costs more.
                let walk = (other == name ? 0 : 2.0) + (network.isOutsideTransfer(from: name, to: other) ? 4 : 0)
                for s in network.place(other)?.stops ?? [] {
                    guard let li = lineIndex[s.lineID], li != n.line || other != name else { continue }
                    out.append((Node(line: li, index: s.index), transferCost + walk))
                }
            }
            return out
        }

        var done = Set<Node>()
        var reached: Node?
        while let (d, n) = queue.pop() {
            if done.contains(n) { continue }
            done.insert(n)
            if goals.contains(n) { reached = n; break }
            for (m, w) in neighbours(n) where !done.contains(m) {
                let nd = d + w
                if nd < dist[m, default: .infinity] {
                    dist[m] = nd
                    prev[m] = n
                    queue.push(m, nd)
                }
            }
        }
        guard var cur = reached else { return nil }
        var path = [cur]
        while let p = prev[cur] {
            path.append(p)
            cur = p
        }
        path.reverse()
        let segs = segments(of: path)
        return segs.isEmpty ? nil : Route(segments: segs)
    }

    /// Splits a node path into rides: a run of nodes on one line is one segment;
    /// a hop to another line is a transfer (and leaves no ride of its own).
    private func segments(of path: [Node]) -> [RouteSegment] {
        let lines = network.lines
        var segs: [RouteSegment] = []
        var run: [Node] = []
        func flush() {
            defer { run = [] }
            guard run.count >= 2 else { return }
            let line = lines[run[0].line]
            let count = line.stations.count
            let a = run[0].index, b = run[1].index
            let step = (b - a + count) % count == 1 ? 1 : -1
            segs.append(RouteSegment(line: line, indices: run.map(\.index), step: step))
        }
        for n in path {
            if let last = run.last, last.line != n.line { flush() }
            // Riding through a loop break (都庁前) means changing trains there:
            // end this ride at the break and start a new one from it.
            if run.count >= 2, let brk = lines[n.line].loopBreak,
               let last = run.last, lines[last.line].stations[last.index].ja == brk {
                flush()
                run.append(last)
            }
            run.append(n)
        }
        flush()
        return segs
    }
}

// MARK: - Changing trains

extension Route {
    /// True when the train you're on simply carries on into the next ride
    /// (大江戸線 都庁前): no change needed, just stay on.
    func staysOnTrain(between a: RouteSegment, and b: RouteSegment) -> Bool {
        (a.line.continuations ?? []).contains {
            $0.step == a.step && $0.atStation == a.alighting.ja && $0.intoLine == b.line.id && $0.intoStep == b.step
        }
    }
}

// MARK: - Which way to go

extension RouteSegment {
    /// What the platform sign says this way goes to — "○○方面".
    /// Non-circular: the line's end. Circular: the next two major stations
    /// the line's signs use (山手線: 上野・池袋), or the next two stops.
    var headingStations: [RailStation] {
        let all = line.stations
        guard line.circular else { return [step > 0 ? all[all.count - 1] : all[0]] }
        let count = all.count
        let ahead = (1..<count).map { all[(indices[0] + step * $0 + count * count) % count] }
        if let majors = line.directionLandmarks?.majorStations, !majors.isEmpty {
            let picked = ahead.filter { majors.contains($0.ja) }.prefix(2)
            if !picked.isEmpty { return Array(picked) }
        }
        return Array(ahead.prefix(2))
    }

    /// "上野・池袋方面" — the text to look for on the sign.
    var headingSign: String { headingStations.map(\.ja).joined(separator: "・") + "方面" }
    /// "우에노·이케부쿠로 방면"
    var headingKo: String { headingStations.map(\.ko).joined(separator: "·") + " 방면" }

    /// Loop direction word on the sign (外回り / 内回り), if the line has one.
    var loopSign: String? {
        guard line.circular else { return nil }
        return step > 0 ? line.circularForwardSign : line.circularBackwardSign
    }

    /// Destinations of trains that run on past the line's end in this direction,
    /// plus those that branch off after you've got off — both are fine to board.
    var throughTermini: [String] {
        let names = line.circular ? [] : ((step > 0 ? line.throughTermini?.end : line.throughTermini?.start) ?? [])
        return names + junctionTermini.ok
    }

    /// Trains that leave this line at a junction (泉岳寺 → 京急, 中洲川端 → 箱崎線,
    /// 環状線 天王寺 → 関西空港): wrong if they branch off before your stop — the
    /// junction lies on your ride short of where you get off — fine otherwise.
    var junctionTermini: (ok: [String], wrong: [String]) {
        guard let j = line.junctionTermini,
              let at = line.stations.firstIndex(where: { $0.ja == j.atStation }) else { return ([], []) }
        let names = (step > 0 ? j.towardEnd : j.towardStart) ?? []
        let branchesBeforeStop = indices.dropLast().contains(at)
        return branchesBeforeStop ? ([], names) : (names, [])
    }

    /// Station-skipping train types on this line and whether each stops at
    /// both ends of this ride.
    var serviceAdvice: [(service: RailService, ok: Bool)] {
        line.skippingServices.map { s in
            let stops = s.stops(on: .now)
            return (s, !s.isPaid && stops.contains(boarding.ja) && stops.contains(alighting.ja))
        }
    }

    /// The judge for the camera: which destinations on a board mean "board".
    func boardJudge() -> TrainBoardJudge {
        let all = line.stations
        let count = all.count
        let board = indices[0], dest = indices[indices.count - 1]
        var forward = Set<String>()
        var backward = Set<String>()
        var next = Set<String>()

        if line.circular {
            // Every station along the way is a fine thing to see on the front;
            // the loop word (外回り/内回り) settles it when shown.
            forward.formUnion(indices.dropFirst().map { all[$0].ja })
            if let s = loopSign { forward.insert(s) }
            let opposite = step > 0 ? line.circularBackwardSign : line.circularForwardSign
            if let s = opposite { backward.insert(s) }
            // Stations just behind the boarding point mean the other way round.
            for k in 1...3 { backward.insert(all[(board - step * k + count * 4) % count].ja) }
            forward.formUnion(junctionTermini.ok)
            backward.formUnion(junctionTermini.wrong)
            forward.subtract(junctionTermini.wrong)
            backward.subtract(forward)
        } else {
            if step > 0 {
                forward.formUnion(all[dest...].map(\.ja))
                backward.formUnion(all[..<dest].map(\.ja))
                forward.formUnion(throughTermini)
                backward.formUnion(line.throughTermini?.start ?? [])
            } else {
                forward.formUnion(all[...dest].map(\.ja))
                backward.formUnion(all[(dest + 1)...].map(\.ja))
                forward.formUnion(throughTermini)
                backward.formUnion(line.throughTermini?.end ?? [])
            }
            backward.formUnion(junctionTermini.wrong)
            forward.subtract(junctionTermini.wrong)
            backward.subtract(forward)
            backward.remove(all[board].ja)
            let n = all[board + step].ja
            if !forward.contains(n) {
                next.insert(n)
                backward.remove(n)
            }
        }

        // A paid train never "stops" for a regular ticket: judge it as skipping.
        let services = line.skippingServices.map {
            TrainService(id: $0.id, signWords: $0.signWords, stops: $0.isPaid ? [] : Set($0.stops(on: .now)))
        }
        return TrainBoardJudge(forward: forward, backward: backward, nextStop: next,
                               boarding: boarding.ja, destination: alighting.ja, services: services)
    }
}

// MARK: - Min-heap

/// Binary min-heap keyed by cost — the Dijkstra frontier.
private struct MinHeap<Element> {
    private var items: [(cost: Double, element: Element)] = []

    mutating func push(_ element: Element, _ cost: Double) {
        items.append((cost, element))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard items[i].cost < items[parent].cost else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func pop() -> (Double, Element)? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var i = 0
        while true {
            let l = 2 * i + 1, r = l + 1
            var m = i
            if l < items.count, items[l].cost < items[m].cost { m = l }
            if r < items.count, items[r].cost < items[m].cost { m = r }
            guard m != i else { break }
            items.swapAt(i, m)
            i = m
        }
        return (top.cost, top.element)
    }
}
