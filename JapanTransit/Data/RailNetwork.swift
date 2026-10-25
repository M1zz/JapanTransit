import Foundation
import SwiftUI

// MARK: - Line data (data/lines/*.json)
//
// One JSON file per line, collected from Japanese/Korean Wikipedia with the
// sources listed in each file. The app bundles the folder as-is ("lines/").
// Stations are identified across lines by region + Japanese name (what's on the
// sign): 新宿 on Marunouchi, Shinjuku and Oedo lines is one place to transfer at,
// while 本町 in Osaka never joins a station of the same name in another city.

struct RailStation: Codable, Hashable {
    let code: String
    let ja: String
    /// Sub-name on the sign: 押上〈スカイツリー前〉 → "スカイツリー前".
    let jaSub: String?
    let kana: String
    let ko: String
    let en: String
    let lat: Double
    let lng: Double
}

struct RailService: Codable, Hashable {
    let id: String
    let signWords: [String]
    let nameKo: String
    let stops: [String]
    let note: String?
    /// Reserved-seat trains (TH ライナー, ロマンスカー): a regular ticket isn't enough.
    let paid: Bool?
    /// Stops this type passes on Saturdays, Sundays and holidays (中央線快速: 高円寺 …).
    let holidaySkips: [String]?

    var isPaid: Bool { paid ?? false }

    /// Where it stops on `date` (Japan time). National holidays aren't known to
    /// the app, so they count as weekdays — the advice text says so.
    func stops(on date: Date = .now) -> [String] {
        guard let skips = holidaySkips, !skips.isEmpty, Self.isWeekendInJapan(date) else { return stops }
        return stops.filter { !skips.contains($0) }
    }

    static func isWeekendInJapan(_ date: Date) -> Bool {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return c.isDateInWeekend(date)
    }
}

struct RailLine: Codable, Identifiable, Hashable {
    struct Termini: Codable, Hashable {
        let start: [String]
        let end: [String]
    }

    /// A junction where some trains leave this line (泉岳寺 → Keikyu, 京急蒲田 → airport).
    struct Junction: Codable, Hashable {
        let atStation: String
        let towardStart: [String]?
        let towardEnd: [String]?
    }

    let id: String
    /// City network (tokyo, osaka …). Routes never cross regions. Old Tokyo files omit it.
    let region: String?
    let `operator`: String
    let operatorKo: String
    let nameJa: String
    let nameKo: String
    let nameEn: String
    let color: String
    let circular: Bool
    let stations: [RailStation]
    let throughTermini: Termini?
    let services: [RailService]?
    let junctionTermini: Junction?
    /// Circular lines: sign words for the two loop directions (外回り / 内回り).
    let circularForwardSign: String?
    let circularBackwardSign: String?
    /// Circular lines: the major stations platform signs name ("上野・池袋方面").
    let directionLandmarks: Landmarks?
    /// A loop station trains don't run through (大江戸線 都庁前): riding past it
    /// means changing trains there.
    let loopBreak: String?
    /// Where a train on this line runs on into another line without a change
    /// (大江戸線 新宿 → 都庁前 → 光が丘).
    let continuations: [Continuation]?

    struct Continuation: Codable, Hashable {
        let step: Int
        let atStation: String
        let intoLine: String
        let intoStep: Int
    }

    struct Landmarks: Codable, Hashable {
        let majorStations: [String]?
    }

    /// Train types that skip stations — the ones a rider has to look out for.
    var skippingServices: [RailService] {
        (services ?? []).filter {
            !$0.signWords.isEmpty && (Set($0.stops(on: .now)).count < stations.count || !($0.holidaySkips ?? []).isEmpty)
        }
    }

    var swiftColor: Color { Color(hex: color) }

    var regionID: String { region ?? Region.tokyo.id }

    /// The place a station of this line belongs to.
    func placeID(_ station: RailStation) -> String { RailNetwork.key(station.ja, region: regionID) }

    /// Badge letter(s) — the station-code prefix (G, M, JY…).
    var badge: String {
        let code = stations.first?.code ?? id
        return String(code.prefix { $0.isLetter })
    }
}

// MARK: - Places (a station name across lines)

/// One station name as the rider thinks of it — "신주쿠" — with every line
/// that stops there.
struct Place: Identifiable, Hashable {
    struct Stop: Hashable {
        let lineID: String
        let index: Int
        let code: String
    }

    var id: String { RailNetwork.key(ja, region: region) }
    let region: String
    let ja: String
    let ko: String
    let en: String
    let kana: String
    let stops: [Stop]
    let lat: Double
    let lng: Double

    var codes: [String] { stops.map(\.code) }
}

// MARK: - Network

final class RailNetwork {
    static let shared = RailNetwork()

    let lines: [RailLine]
    let linesByID: [String: RailLine]
    let places: [Place]
    let placesByJa: [String: Place]
    /// Stations with different names you can walk between inside the station
    /// (浜松町 ↔ 大門, 原宿 ↔ 明治神宮前). From data/transfers.json.
    let walkLinks: [String: [String]]
    /// Transfers that leave the ticket gates and use the street ("a|b", sorted),
    /// and same-name stations that are really two separate stations (蔵前).
    private let outsidePairs: Set<String>
    private let separateSameName: Set<String>

    struct WalkGroup {
        let region: String
        let stations: [String]
        let outside: Bool
    }

    init(lines: [RailLine], walkGroups: [WalkGroup] = [], separateSameName: [String] = []) {
        self.lines = lines
        var links: [String: [String]] = [:]
        var outside = Set<String>()
        for group in walkGroups {
            let names = group.stations.map { Self.key($0, region: group.region) }
            for name in names {
                links[name, default: []].append(contentsOf: names.filter { $0 != name })
                if group.outside {
                    for other in names where other != name { outside.insert(Self.pair(name, other)) }
                }
            }
        }
        walkLinks = links
        outsidePairs = outside
        self.separateSameName = Set(separateSameName)
        linesByID = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var stops: [String: [Place.Stop]] = [:]
        var first: [String: (RailStation, String)] = [:]
        var coords: [String: [(Double, Double)]] = [:]
        for line in lines {
            for (i, s) in line.stations.enumerated() {
                let k = line.placeID(s)
                stops[k, default: []].append(.init(lineID: line.id, index: i, code: s.code))
                if first[k] == nil { first[k] = (s, line.regionID) }
                coords[k, default: []].append((s.lat, s.lng))
            }
        }
        places = first.map { k, entry in
            let (s, region) = entry
            let c = coords[k] ?? [(s.lat, s.lng)]
            return Place(region: region, ja: s.ja, ko: s.ko, en: s.en, kana: s.kana, stops: stops[k] ?? [],
                         lat: c.map(\.0).reduce(0, +) / Double(c.count),
                         lng: c.map(\.1).reduce(0, +) / Double(c.count))
        }
        .sorted { $0.ko < $1.ko }
        placesByJa = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// A place id: region + one spelling per name ("tokyo/市ケ谷" for 市ヶ谷 and 市ケ谷).
    static func key(_ ja: String, region: String) -> String {
        region + "/" + ja.replacingOccurrences(of: "ヶ", with: "ケ").replacingOccurrences(of: "ヵ", with: "カ")
    }

    private convenience init() {
        let transfers = Self.loadBundledTransfers()
        self.init(lines: Self.loadBundledLines(), walkGroups: transfers.groups,
                  separateSameName: transfers.separateSameName)
    }

    /// data/transfers.json: {"groups": [{"region": "tokyo", "stations": [...], "outside": bool, "source": "..."}],
    ///                       "separateSameName": [{"region": "tokyo", "station": "蔵前"}]}
    /// `region` defaults to tokyo. Returns separate-same-name stations as place ids.
    static func loadBundledTransfers(bundle: Bundle = .main) -> (groups: [WalkGroup], separateSameName: [String]) {
        struct File: Decodable {
            struct Group: Decodable { let region: String?; let stations: [String]; let outside: Bool? }
            struct Separate: Decodable { let region: String?; let station: String }
            let groups: [Group]
            let separateSameName: [Separate]?
        }
        guard let url = bundle.url(forResource: "transfers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return ([], []) }
        return (file.groups.map { WalkGroup(region: $0.region ?? Region.tokyo.id, stations: $0.stations, outside: $0.outside ?? false) },
                (file.separateSameName ?? []).map { key($0.station, region: $0.region ?? Region.tokyo.id) })
    }

    private static func pair(_ a: String, _ b: String) -> String {
        a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }

    /// Changing from place `a` to place `b` means leaving the gates and walking on the street.
    func isOutsideTransfer(from a: String, to b: String) -> Bool {
        a == b ? separateSameName.contains(a) : outsidePairs.contains(Self.pair(a, b))
    }

    /// Lines in the order riders expect: Tokyo Metro, Toei, JR, others.
    static func loadBundledLines(bundle: Bundle = .main) -> [RailLine] {
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "lines") ?? []
        let decoder = JSONDecoder()
        let lines = urls.compactMap { url -> RailLine? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(RailLine.self, from: data)
        }
        let operatorOrder = ["東京メトロ", "都営地下鉄", "JR東日本", "Osaka Metro", "JR西日本"]
        return lines.sorted { a, b in
            let oa = operatorOrder.firstIndex(of: a.operator) ?? operatorOrder.count
            let ob = operatorOrder.firstIndex(of: b.operator) ?? operatorOrder.count
            return oa != ob ? oa < ob : a.id < b.id
        }
    }

    func line(_ id: String) -> RailLine? { linesByID[id] }

    /// A place by id ("tokyo/新宿"). A bare name is read as Tokyo — what earlier
    /// versions saved before there were other cities.
    func place(_ id: String) -> Place? {
        if let p = placesByJa[id] { return p }
        return id.contains("/") ? nil : placesByJa[Self.key(id, region: Region.tokyo.id)]
    }

    func place(ja: String, region: String) -> Place? { placesByJa[Self.key(ja, region: region)] }

    /// Places you can transfer to from `id` without leaving: itself plus walk links.
    func transferNames(at id: String) -> [String] {
        [id] + (walkLinks[id] ?? [])
    }

    /// Every line you can change to at place `id`, walk links included.
    func transferLines(at id: String) -> [RailLine] {
        transferNames(at: id)
            .flatMap { place($0)?.stops ?? [] }
            .compactMap { line($0.lineID) }
            .uniqued()
    }

    /// Regions that have lines, in display order.
    var regions: [Region] {
        let present = Set(lines.map(\.regionID))
        return Region.all.filter { present.contains($0.id) }
    }
}

// MARK: - Regions

/// A city network. Lines in one region connect; regions never do.
struct Region: Identifiable, Hashable {
    let id: String
    let ko: String
    let ja: String

    static let tokyo = Region(id: "tokyo", ko: "도쿄", ja: "東京")
    static let all: [Region] = [
        tokyo,
        Region(id: "yokohama", ko: "요코하마", ja: "横浜"),
        Region(id: "osaka", ko: "오사카", ja: "大阪"),
        Region(id: "kyoto", ko: "교토", ja: "京都"),
        Region(id: "kobe", ko: "고베", ja: "神戸"),
        Region(id: "nagoya", ko: "나고야", ja: "名古屋"),
        Region(id: "fukuoka", ko: "후쿠오카", ja: "福岡"),
        Region(id: "sapporo", ko: "삿포로", ja: "札幌"),
        Region(id: "sendai", ko: "센다이", ja: "仙台"),
    ]

    static func named(_ id: String) -> Region? { all.first { $0.id == id } }
}

// MARK: - Search

extension RailNetwork {
    /// Matches Korean (신주쿠), Japanese (新宿, しんじゅく, シンジュク), English
    /// (Shinjuku) and station codes (M08, m8). Prefix matches first.
    /// `region` limits the search to one city; `preferring` keeps every city but
    /// lists that one first (M08 is 新宿 in Tokyo and 名城公園 in Nagoya).
    func search(_ query: String, region: String? = nil, preferring: String? = nil) -> [Place] {
        let pool = region.map { r in places.filter { $0.region == r } } ?? places
        let q = Self.searchKey(query)
        guard !q.isEmpty else { return pool }
        let codeQuery = Self.codeKey(query)
        var prefix: [Place] = []
        var contains: [Place] = []
        for p in pool {
            let keys = [Self.searchKey(p.ko), Self.searchKey(p.ja), Self.searchKey(p.kana), Self.searchKey(p.en)]
            if keys.contains(where: { $0.hasPrefix(q) }) || p.codes.contains(where: { Self.codeKey($0) == codeQuery }) {
                prefix.append(p)
            } else if keys.contains(where: { $0.contains(q) }) {
                contains.append(p)
            }
        }
        guard let preferring else { return prefix + contains }
        func ordered(_ list: [Place]) -> [Place] {
            list.filter { $0.region == preferring } + list.filter { $0.region != preferring }
        }
        return ordered(prefix) + ordered(contains)
    }

    /// Lowercased, no spaces/hyphens/dots, katakana folded to hiragana.
    static func searchKey(_ s: String) -> String {
        let folded = s.applyingTransform(.hiraganaToKatakana, reverse: true) ?? s
        return folded.lowercased().filter { !" -・.·'’".contains($0) }
    }

    /// "M08", "m8", "M-8" → "m8".
    static func codeKey(_ s: String) -> String {
        let t = s.lowercased().filter { $0.isLetter || $0.isNumber }
        let letters = t.prefix { $0.isLetter }
        let digits = t.dropFirst(letters.count)
        guard !letters.isEmpty, !digits.isEmpty, digits.allSatisfy(\.isNumber),
              let n = Int(digits) else { return t }
        return "\(letters)\(n)"
    }
}

// MARK: - Nearest station

extension RailNetwork {
    func nearest(latitude: Double, longitude: Double, maxMeters: Double = 1500) -> [(place: Place, meters: Double)] {
        places
            .map { ($0, Self.haversine(latitude, longitude, $0.lat, $0.lng)) }
            .filter { $0.1 <= maxMeters }
            .sorted { $0.1 < $1.1 }
    }

    static func haversine(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let r = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

// MARK: - Color

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
