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
}

struct Route: Hashable, Identifiable {
    let segments: [RouteSegment]

    var id: String { segments.map(\.id).joined(separator: "|") }
    var stopCount: Int { segments.map(\.stopCount).reduce(0, +) }
    var transferCount: Int { max(segments.count - 1, 0) }
    /// Rough minutes: ~2 min a stop, ~6 min a transfer.
    var estimatedMinutes: Int { stopCount * 2 + transferCount * 6 }
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

    /// Fastest route and, when different, the one with the fewest transfers.
    func routes(from: String, to: String) -> [Route] {
        guard RailNetwork.key(from) != RailNetwork.key(to) else { return [] }
        var result: [Route] = []
        for transferCost in [6.0, 30.0] {
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
        func nodes(around name: String) -> [Node] {
            network.transferNames(at: name)
                .filter { $0 == RailNetwork.key(name) || !network.isOutsideTransfer(from: name, to: $0) }
                .flatMap { network.place($0)?.stops ?? [] }
                .compactMap { s in lineIndex[s.lineID].map { Node(line: $0, index: s.index) } }
        }
        let starts = nodes(around: from)
        let goals = Set(nodes(around: to))

        var dist: [Node: Double] = [:]
        var prev: [Node: Node] = [:]
        var queue: [(Double, Node)] = []
        for s in starts {
            dist[s] = 0
            queue.append((0, s))
        }

        func neighbours(_ n: Node) -> [(Node, Double)] {
            let line = lines[n.line]
            let count = line.stations.count
            var out: [(Node, Double)] = []
            for d in [-1, 1] {
                var j = n.index + d
                if line.circular { j = (j + count) % count }
                if j >= 0, j < count, j != n.index { out.append((Node(line: n.line, index: j), 2)) }
            }
            // Transfers: the same station name on another line, or a station
            // you walk to inside (浜松町 → 大門) for a little more.
            let name = RailNetwork.key(line.stations[n.index].ja)
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
        while !queue.isEmpty {
            // Small graph (a few hundred nodes): a linear scan beats a heap here.
            let i = queue.indices.min { queue[$0].0 < queue[$1].0 } ?? 0
            let (d, n) = queue.remove(at: i)
            if done.contains(n) { continue }
            done.insert(n)
            if goals.contains(n) { reached = n; break }
            for (m, w) in neighbours(n) where !done.contains(m) {
                let nd = d + w
                if nd < dist[m, default: .infinity] {
                    dist[m] = nd
                    prev[m] = n
                    queue.append((nd, m))
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

    /// Destinations of trains that run on past the line's end in this direction.
    var throughTermini: [String] {
        guard !line.circular else { return [] }
        var names = (step > 0 ? line.throughTermini?.end : line.throughTermini?.start) ?? []
        if let j = line.junctionTermini {
            names += (step > 0 ? j.towardEnd : j.towardStart) ?? []
        }
        return names
    }

    /// Station-skipping train types on this line and whether each stops at
    /// both ends of this ride.
    var serviceAdvice: [(service: RailService, ok: Bool)] {
        line.skippingServices.map { s in
            (s, !s.isPaid && s.stops.contains(boarding.ja) && s.stops.contains(alighting.ja))
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
            TrainService(id: $0.id, signWords: $0.signWords, stops: $0.isPaid ? [] : Set($0.stops))
        }
        return TrainBoardJudge(forward: forward, backward: backward, nextStop: next,
                               boarding: boarding.ja, destination: alighting.ja, services: services)
    }
}
