import Foundation

// MARK: - Spots (data/spots/{region}.json)
//
// Places travellers know by name — 도쿄 빅사이트, 도톤보리, 후시미이나리 — and the
// stations that get you there. Someone who knows only the place can find the
// station: search "빅사이트" → 国際展示場 (린카이선, 도보 7분) or 東京ビッグサイト.

struct Spot: Codable, Identifiable, Hashable {
    struct Access: Codable, Hashable {
        /// Station name as on the sign, on line `line`.
        let ja: String
        let line: String
        let walkMinutes: Int?
        let exit: String?
        let note: String?
    }

    /// "tokyo.big-sight" — the region is the part before the dot.
    let id: String
    let ko: String
    let ja: String
    let en: String
    let aliases: [String]?
    let category: String
    let lat: Double
    let lng: Double
    let stations: [Access]
    let tip: String?

    var region: String { String(id.prefix { $0 != "." }) }

    /// SF Symbol for the category.
    var symbol: String {
        switch category {
        case "쇼핑": return "bag.fill"
        case "먹거리": return "fork.knife"
        case "신사·절": return "building.columns.fill"
        case "공원·자연": return "leaf.fill"
        case "전시·공연": return "theatermasks.fill"
        case "테마파크": return "sparkles"
        case "전망대": return "binoculars.fill"
        case "박물관·미술관": return "paintpalette.fill"
        default: return "star.fill"
        }
    }
}

extension RailNetwork {
    /// Every bundled spot (lazily loaded once).
    var spots: [Spot] { SpotStore.all }

    /// Spots whose Korean, Japanese, English name or alias matches, prefix first.
    func searchSpots(_ query: String, region: String? = nil) -> [Spot] {
        let q = Self.searchKey(query)
        guard !q.isEmpty else { return [] }
        let pool = region.map { r in spots.filter { $0.region == r } } ?? spots
        var prefix: [Spot] = [], contains: [Spot] = []
        for s in pool {
            let keys = ([s.ko, s.ja, s.en] + (s.aliases ?? [])).map(Self.searchKey)
            if keys.contains(where: { $0.hasPrefix(q) }) { prefix.append(s) }
            else if keys.contains(where: { $0.contains(q) }) { contains.append(s) }
        }
        return prefix + contains
    }

    /// The place a spot's access station belongs to (nil if the data doesn't have it).
    func place(for access: Spot.Access, in spot: Spot) -> Place? {
        place(ja: access.ja, region: line(access.line)?.regionID ?? spot.region)
    }
}

private enum SpotStore {
    static let all: [Spot] = {
        struct File: Decodable { let spots: [Spot] }
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "spots") ?? []
        return urls.flatMap { url -> [Spot] in
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
            return file.spots
        }
    }()
}
