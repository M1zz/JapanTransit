import Foundation

// MARK: - A route as steps

/// A route the way a rider goes through it, one thing at a time: find the
/// platform and board, ride, change, walk out. A ride the train simply carries
/// on through (御堂筋線 → 北大阪急行 at 江坂) is one leg: nobody gets off.
struct TripGuide {
    let route: Route
    let legs: [Leg]
    let steps: [Step]

    enum Step: Hashable {
        /// Find the platform for leg n and check the train.
        case board(Int)
        /// On the train of leg n.
        case ride(Int)
        /// Off leg n, over to leg n + 1.
        case change(Int)
        /// Arrived: out through the gates.
        case leave
    }

    /// One train: rides joined where it carries on into the next line.
    struct Leg: Hashable {
        let segments: [RouteSegment]
        /// Every stop from boarding to alighting (a junction once), with the
        /// minutes from boarding to it.
        let stops: [Stop]

        struct Stop: Hashable {
            let station: RailStation
            let line: RailLine
            let minutes: Double
        }

        var first: RouteSegment { segments[0] }
        var last: RouteSegment { segments[segments.count - 1] }
        var boarding: Stop { stops[0] }
        var alighting: Stop { stops[stops.count - 1] }
        /// Stations where the train runs on into another line (江坂).
        var runsOn: [Stop] {
            segments.dropLast().map { seg in stops.first { $0.station == seg.alighting && $0.line == seg.line }! }
        }

        init(segments: [RouteSegment]) {
            self.segments = segments
            // Times follow the everyday train of each ride (rideMinutes), shared
            // out by distance: a guess that runs a little early rather than late.
            var stops: [Stop] = []
            var clock = 0.0
            for seg in segments {
                let stations = seg.stations
                let raw = zip(stations, stations.dropFirst()).map { RouteSegment.minutes($0, $1) }
                let scale = raw.reduce(0, +) > 0 ? seg.rideMinutes / raw.reduce(0, +) : 1
                if stops.isEmpty { stops.append(Stop(station: stations[0], line: seg.line, minutes: 0)) }
                for (i, station) in stations.enumerated().dropFirst() {
                    clock += raw[i - 1] * scale
                    stops.append(Stop(station: station, line: seg.line, minutes: clock))
                }
            }
            self.stops = stops
        }

        /// Which cars to board when the train splits on the way and only part of
        /// it goes where you're going (関空快速 1〜4号車).
        var cars: RailLine.Split? {
            for seg in segments {
                for split in seg.line.splits ?? [] where split.step == seg.step {
                    // You ride through the split point and on: the station is on your
                    // ride before the last stop.
                    if seg.indices.dropLast().contains(where: { seg.line.stations[$0].ja == split.atStation }) {
                        return split
                    }
                }
            }
            return nil
        }
    }

    init(route: Route) {
        self.route = route
        var legs: [Leg] = []
        var run: [RouteSegment] = []
        for seg in route.segments {
            if let last = run.last, !route.staysOnTrain(between: last, and: seg) {
                legs.append(Leg(segments: run))
                run = []
            }
            run.append(seg)
        }
        if !run.isEmpty { legs.append(Leg(segments: run)) }
        self.legs = legs

        var steps: [Step] = []
        for i in legs.indices {
            if i > 0 { steps.append(.change(i - 1)) }
            steps += [.board(i), .ride(i)]
        }
        self.steps = steps + [.leave]
    }
}

// MARK: - Where am I on the train

/// Where the rider is along a leg: the last stop they were known to be at, and
/// when. Without GPS underground, the rest is the timetable guess; a location
/// fix or a tap on "지금 여기" moves the anchor.
struct RideClock: Codable, Hashable {
    var index: Int
    var at: Date

    /// The stop the train has reached (or is standing at) by `now`.
    func stopIndex(on leg: TripGuide.Leg, at now: Date = .now) -> Int {
        let base = leg.stops[index].minutes + max(now.timeIntervalSince(at), 0) / 60
        let reached = leg.stops.lastIndex { $0.minutes <= base + 0.01 } ?? index
        return max(reached, index)
    }

    func stopsLeft(on leg: TripGuide.Leg, at now: Date = .now) -> Int {
        leg.stops.count - 1 - stopIndex(on: leg, at: now)
    }

    /// When the train should reach stop `target`.
    func arrival(at target: Int, on leg: TripGuide.Leg) -> Date {
        at.addingTimeInterval(max(leg.stops[target].minutes - leg.stops[index].minutes, 0) * 60)
    }

    /// When to warn "next stop is yours": as the train reaches the stop before.
    func warning(on leg: TripGuide.Leg) -> Date? {
        let before = leg.stops.count - 2
        return before > index ? arrival(at: before, on: leg) : nil
    }

    /// Snap to the stop the rider is near, if they're within `radius` metres of
    /// one not behind them.
    func corrected(latitude: Double, longitude: Double, on leg: TripGuide.Leg,
                   radius: Double = 300, now: Date = .now) -> RideClock? {
        let candidates = leg.stops.indices.filter { $0 >= index }
        guard let near = candidates.min(by: {
            RailNetwork.haversine(latitude, longitude, leg.stops[$0].station.lat, leg.stops[$0].station.lng)
                < RailNetwork.haversine(latitude, longitude, leg.stops[$1].station.lat, leg.stops[$1].station.lng)
        }) else { return nil }
        let s = leg.stops[near].station
        guard RailNetwork.haversine(latitude, longitude, s.lat, s.lng) <= radius,
              near != stopIndex(on: leg, at: now) else { return nil }
        return RideClock(index: near, at: now)
    }
}

// MARK: - Rebuilding a route

extension Route {
    /// The route a saved `id` names ("G:0,1,2|M:5,6"), if the line data still has it.
    init?(id: String, network: RailNetwork = .shared) {
        var segments: [RouteSegment] = []
        for part in id.split(separator: "|") {
            let bits = part.split(separator: ":", maxSplits: 1)
            guard bits.count == 2, let line = network.line(String(bits[0])) else { return nil }
            let indices = bits[1].split(separator: ",").compactMap { Int($0) }
            guard indices.count >= 2, indices.allSatisfy({ line.stations.indices.contains($0) }) else { return nil }
            let count = line.stations.count
            let step = (indices[1] - indices[0] + count) % count == 1 ? 1 : -1
            segments.append(RouteSegment(line: line, indices: indices, step: step))
        }
        guard !segments.isEmpty else { return nil }
        self.init(segments: segments)
    }
}
