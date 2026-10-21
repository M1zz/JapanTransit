import Foundation
import SwiftUI

// MARK: - Line data (data/lines/*.json)
//
// One JSON file per line, collected from Japanese/Korean Wikipedia with the
// sources listed in each file. The app bundles the folder as-is ("lines/").
// Stations are identified across lines by their Japanese name (what's on the
// sign): 新宿 on Marunouchi, Shinjuku and Oedo lines is one place to transfer at.

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

    var isPaid: Bool { paid ?? false }
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
        (services ?? []).filter { !$0.signWords.isEmpty && Set($0.stops).count < stations.count }
    }

    var swiftColor: Color { Color(hex: color) }

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

    var id: String { RailNetwork.key(ja) }
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

    init(lines: [RailLine], walkGroups: [[String]] = []) {
        self.lines = lines
        var links: [String: [String]] = [:]
        for group in walkGroups.map({ $0.map(Self.key) }) {
            for name in group {
                links[name, default: []].append(contentsOf: group.filter { $0 != name })
            }
        }
        walkLinks = links
        linesByID = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var stops: [String: [Place.Stop]] = [:]
        var first: [String: RailStation] = [:]
        var coords: [String: [(Double, Double)]] = [:]
        for line in lines {
            for (i, s) in line.stations.enumerated() {
                let k = Self.key(s.ja)
                stops[k, default: []].append(.init(lineID: line.id, index: i, code: s.code))
                if first[k] == nil { first[k] = s }
                coords[k, default: []].append((s.lat, s.lng))
            }
        }
        places = first.map { k, s in
            let c = coords[k] ?? [(s.lat, s.lng)]
            return Place(ja: s.ja, ko: s.ko, en: s.en, kana: s.kana, stops: stops[k] ?? [],
                         lat: c.map(\.0).reduce(0, +) / Double(c.count),
                         lng: c.map(\.1).reduce(0, +) / Double(c.count))
        }
        .sorted { $0.ko < $1.ko }
        placesByJa = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// One spelling per station: 市ヶ谷 and 市ケ谷 are the same place.
    static func key(_ ja: String) -> String {
        ja.replacingOccurrences(of: "ヶ", with: "ケ").replacingOccurrences(of: "ヵ", with: "カ")
    }

    private convenience init() {
        self.init(lines: Self.loadBundledLines(), walkGroups: Self.loadBundledWalkGroups())
    }

    /// data/transfers.json: {"groups": [{"stations": [...], "source": "..."}]}
    static func loadBundledWalkGroups(bundle: Bundle = .main) -> [[String]] {
        struct File: Decodable {
            struct Group: Decodable { let stations: [String] }
            let groups: [Group]
        }
        guard let url = bundle.url(forResource: "transfers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.groups.map(\.stations)
    }

    /// Lines in the order riders expect: Tokyo Metro, Toei, JR, others.
    static func loadBundledLines(bundle: Bundle = .main) -> [RailLine] {
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "lines") ?? []
        let decoder = JSONDecoder()
        let lines = urls.compactMap { url -> RailLine? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(RailLine.self, from: data)
        }
        let operatorOrder = ["東京メトロ", "都営地下鉄", "JR東日本"]
        return lines.sorted { a, b in
            let oa = operatorOrder.firstIndex(of: a.operator) ?? operatorOrder.count
            let ob = operatorOrder.firstIndex(of: b.operator) ?? operatorOrder.count
            return oa != ob ? oa < ob : a.id < b.id
        }
    }

    func line(_ id: String) -> RailLine? { linesByID[id] }

    func place(_ ja: String) -> Place? { placesByJa[Self.key(ja)] }

    /// Station names you can transfer to from `ja` without leaving: itself plus walk links.
    func transferNames(at ja: String) -> [String] {
        [Self.key(ja)] + (walkLinks[Self.key(ja)] ?? [])
    }

    /// Every line you can change to at `ja`, walk links included.
    func transferLines(at ja: String) -> [RailLine] {
        transferNames(at: ja)
            .flatMap { place($0)?.stops ?? [] }
            .compactMap { line($0.lineID) }
            .uniqued()
    }
}

// MARK: - Search

extension RailNetwork {
    /// Matches Korean (신주쿠), Japanese (新宿, しんじゅく, シンジュク), English
    /// (Shinjuku) and station codes (M08, m8). Prefix matches first.
    func search(_ query: String) -> [Place] {
        let q = Self.searchKey(query)
        guard !q.isEmpty else { return places }
        let codeQuery = Self.codeKey(query)
        var prefix: [Place] = []
        var contains: [Place] = []
        for p in places {
            let keys = [Self.searchKey(p.ko), Self.searchKey(p.ja), Self.searchKey(p.kana), Self.searchKey(p.en)]
            if keys.contains(where: { $0.hasPrefix(q) }) || p.codes.contains(where: { Self.codeKey($0) == codeQuery }) {
                prefix.append(p)
            } else if keys.contains(where: { $0.contains(q) }) {
                contains.append(p)
            }
        }
        return prefix + contains
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
