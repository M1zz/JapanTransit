//
//  JapanTransitTests.swift
//  핵심 로직 시험: 노선 데이터가 온전한지, 길을 제대로 찾는지, 카메라 판정이 맞는지.
//

import XCTest
import TrainBoardKit
@testable import JapanTransit

final class RailDataTests: XCTestCase {
    private let network = RailNetwork.shared

    func testEveryBundledLineDecodes() {
        let files = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "lines") ?? []
        XCTAssertFalse(files.isEmpty)
        XCTAssertEqual(network.lines.count, files.count, "디코딩에 실패한 노선 파일이 있다")
    }

    func testStationsAreSaneOnEveryLine() {
        for line in network.lines {
            XCTAssertGreaterThanOrEqual(line.stations.count, 2, line.id)
            XCTAssertEqual(Set(line.stations.map(\.code)).count, line.stations.count, "\(line.id) 역 번호 중복")
            XCTAssertEqual(Set(line.stations.map(\.ja)).count, line.stations.count, "\(line.id) 역 이름 중복")
            for s in line.stations {
                XCTAssertFalse(s.ko.isEmpty, "\(line.id) \(s.ja) 한국어 이름 없음")
                // 일본 안
                XCTAssertTrue((24.0...46.0).contains(s.lat) && (122.0...146.0).contains(s.lng),
                              "\(line.id) \(s.ja) 좌표 이상: \(s.lat), \(s.lng)")
            }
            for service in line.services ?? [] {
                let names = Set(line.stations.map(\.ja))
                for stop in service.stops {
                    XCTAssertTrue(names.contains(stop), "\(line.id) \(service.id) 정차역 \(stop) 이 노선에 없음")
                }
            }
        }
    }

    func testOutsideTransfers() {
        let n = network
        let t = { (ja: String) in RailNetwork.key(ja, region: "tokyo") }
        XCTAssertTrue(n.isOutsideTransfer(from: t("蔵前"), to: t("蔵前")), "蔵前 는 두 역이 떨어져 있다")
        XCTAssertFalse(n.isOutsideTransfer(from: t("新宿"), to: t("新宿")))
        XCTAssertEqual(t("市ヶ谷"), t("市ケ谷"))
    }

    func testCitiesDoNotMerge() {
        // 다른 도시의 같은 이름 역은 다른 장소다.
        for p in network.places {
            let regions = Set(p.stops.compactMap { network.line($0.lineID)?.regionID })
            XCTAssertEqual(regions.count, 1, "\(p.ja) 가 여러 도시에 걸쳐 있다")
        }
    }

    func testWalkLinksNameRealStations() {
        for (name, others) in network.walkLinks {
            XCTAssertNotNil(network.place(name), "transfers.json: \(name) 없는 역")
            for o in others { XCTAssertNotNil(network.place(o), "transfers.json: \(o) 없는 역") }
        }
    }
}

final class HolidaySkipTests: XCTestCase {
    func testChuoRapidSkipsOnWeekends() throws {
        let line = try XCTUnwrap(RailNetwork.shared.line("JC"))
        let rapid = try XCTUnwrap(line.services?.first { $0.id == "rapid" })
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let saturday = c.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))!
        let monday = c.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12))!
        XCTAssertFalse(rapid.stops(on: saturday).contains("高円寺"))
        XCTAssertTrue(rapid.stops(on: monday).contains("高円寺"))
    }
}

final class SpotTests: XCTestCase {
    private let network = RailNetwork.shared

    func testEverySpotStationExists() {
        XCTAssertFalse(network.spots.isEmpty)
        for spot in network.spots {
            XCTAssertNotNil(Region.named(spot.region), "\(spot.id) 도시 이름")
            XCTAssertFalse(spot.stations.isEmpty, "\(spot.id) 역 없음")
            for a in spot.stations {
                let line = network.line(a.line)
                XCTAssertNotNil(line, "\(spot.id): 노선 \(a.line) 없음")
                XCTAssertNotNil(network.place(for: a, in: spot), "\(spot.id): \(a.ja) 가 \(a.line) 에 없음")
                XCTAssertEqual(line?.regionID, spot.region, "\(spot.id): 다른 도시 역")
            }
        }
    }

    func testFindAStationFromAPlace() {
        // 빅사이트를 찾으면 국제전시장(린카이선)으로 간다.
        let spot = network.searchSpots("빅사이트").first
        XCTAssertEqual(spot?.id.hasPrefix("tokyo."), true)
        XCTAssertTrue(spot?.stations.contains { $0.ja == "国際展示場" } ?? false)
    }
}

final class SearchTests: XCTestCase {
    private let network = RailNetwork.shared

    func testKoreanJapaneseEnglishAndCode() {
        XCTAssertEqual(network.search("신주쿠").first?.ja, "新宿")
        XCTAssertEqual(network.search("新宿").first?.ja, "新宿")
        XCTAssertEqual(network.search("shinjuku").first?.ja, "新宿")
        XCTAssertEqual(network.search("シンジュク").first?.ja, "新宿")
        XCTAssertEqual(network.search("m8", preferring: "tokyo").first?.ja, "新宿")
        XCTAssertEqual(network.search("m8", preferring: "nagoya").first?.ja, "名城公園")
    }
}

final class RoutePlannerTests: XCTestCase {
    private let planner = RoutePlanner(network: RailNetwork.shared)

    private func check(_ route: Route, from: String, to: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(route.segments.first?.boarding.ja, from, file: file, line: line)
        XCTAssertEqual(route.segments.last?.alighting.ja, to, file: file, line: line)
        for (a, b) in zip(route.segments, route.segments.dropFirst()) {
            let walk = RailNetwork.shared.transferNames(at: a.line.placeID(a.alighting))
            XCTAssertTrue(walk.contains(b.line.placeID(b.boarding)), "환승이 끊김: \(a.alighting.ja) → \(b.boarding.ja)", file: file, line: line)
        }
    }

    func testOneLineNoTransfer() throws {
        // 긴자선 한 줄: 시부야 → 아사쿠사
        let route = try XCTUnwrap(planner.routes(from: "渋谷", to: "浅草").first)
        check(route, from: "渋谷", to: "浅草")
        XCTAssertEqual(route.transferCount, 0)
        XCTAssertEqual(route.segments.first?.line.id, "G")
        XCTAssertEqual(route.segments.first?.headingSign, "浅草方面")
    }

    func testMinutesFollowTheEverydayTrain() throws {
        // 지하철은 역마다 서는 시간 그대로(긴자선 약 32분), 교외 노선은 급행 기준.
        // 모든 역에 서는 셈이면 나리타 공항이 2시간을 넘었다.
        let ginza = try XCTUnwrap(planner.routes(from: "渋谷", to: "浅草").first)
        XCTAssertEqual(ginza.estimatedMinutes, 32, accuracy: 3)
        let narita = try XCTUnwrap(planner.routes(from: "京成上野", to: "成田空港").first)
        XCTAssertLessThan(narita.estimatedMinutes, 90)
        XCTAssertGreaterThan(narita.estimatedMinutes, 45)
    }

    func testRouteWithTransfer() throws {
        let routes = planner.routes(from: "池袋", to: "銀座")
        XCTAssertFalse(routes.isEmpty)
        for r in routes { check(r, from: "池袋", to: "銀座") }
    }

    func testYamanoteLoopDirection() throws {
        // 시나가와 → 다마치: 야마노테선만 다니는 구간, 번호가 커지는 쪽(内回り).
        let r = try XCTUnwrap(planner.routes(from: "品川", to: "田町").first)
        let seg = try XCTUnwrap(r.segments.first)
        XCTAssertEqual(seg.line.id, "JY")
        XCTAssertEqual(seg.loopSign, "内回り")
        // 표지판은 주요 역 둘: 東京・上野方面
        XCTAssertEqual(seg.headingSign, "東京・上野方面")
    }

    func testOedoChangesTrainsWhenPassingTochomae() throws {
        // 新宿(E27) → 新宿西口(E01) 를 오에도선으로 가면 都庁前 을 지나므로 거기서 열차를 바꾼다.
        let r = try XCTUnwrap(planner.routes(from: "東新宿", to: "西新宿五丁目").first)
        for seg in r.segments where seg.line.loopBreak != nil {
            let inner = seg.stations.dropFirst().dropLast().map(\.ja)
            XCTAssertFalse(inner.contains("都庁前"), "都庁前 을 지나치는 한 구간이 있다: \(seg.stations.map(\.ja))")
        }
    }

    func testFewerTransfersLabelIsTrue() {
        // "환승 적게" 는 정말 환승이 적을 때만 붙는다.
        for (a, b) in [("池袋", "浅草"), ("渋谷", "押上"), ("新宿", "東京"), ("中野", "大門")] {
            let routes = planner.routes(from: a, to: b)
            guard let first = routes.first else { continue }
            for r in routes where RoutePlanner.label(for: r, in: routes) == "환승 적게" {
                XCTAssertLessThan(r.transferCount, first.transferCount, "\(a)→\(b)")
            }
        }
    }

    func testArrivingAtAPassageLinkedStationIsArriving() throws {
        // 모노레일로 하네다 제1·제2터미널에 닿으면 게이큐 하네다역까지 한 번 더 타지 않는다.
        let r = try XCTUnwrap(planner.routes(from: "新宿", to: "羽田空港第1・第2ターミナル").first)
        let names = RailNetwork.shared.transferNames(at: RailNetwork.key("羽田空港第1・第2ターミナル", region: "tokyo"))
        let last = try XCTUnwrap(r.segments.last)
        XCTAssertTrue(names.contains(last.line.placeID(last.alighting)))
        XCTAssertLessThanOrEqual(r.transferCount, 1)
    }

    func testShinjukuToKokusaiTenjijo() throws {
        // 신주쿠 → 국제전시장(도쿄 빅사이트): 사이쿄선이 린카이선으로 그대로 이어 간다.
        let r = try XCTUnwrap(planner.routes(from: "新宿", to: "国際展示場").first)
        XCTAssertEqual(r.segments.first?.boarding.ja, "新宿")
        XCTAssertEqual(r.segments.last?.alighting.ja, "国際展示場")
        if r.segments.count == 2 {
            XCTAssertTrue(r.staysOnTrain(between: r.segments[0], and: r.segments[1]))
        }
    }

    func testOtherCitiesRoute() throws {
        // 오사카 우메다 → 난바(미도스지선 한 줄), 교토역 → 가라스마오이케.
        let osaka = try XCTUnwrap(planner.routes(from: "osaka/梅田", to: "osaka/なんば").first)
        XCTAssertEqual(osaka.transferCount, 0)
        XCTAssertFalse(planner.routes(from: "kyoto/京都", to: "kyoto/烏丸御池").isEmpty)
        // 도시가 다르면 경로가 없다.
        XCTAssertTrue(planner.routes(from: "新宿", to: "osaka/梅田").isEmpty)
    }

    func testSameStationHasNoRoute() {
        XCTAssertTrue(planner.routes(from: "新宿", to: "新宿").isEmpty)
    }
}

final class BoardJudgeOnRouteTests: XCTestCase {
    func testBranchingTrainBeforeYourStopIsWrong() throws {
        // 후쿠오카 공항선: 天神 → 博多. 貝塚行 은 中洲川端 에서 箱崎線 으로 빠져 博多 에 안 간다.
        let planner = RoutePlanner(network: RailNetwork.shared)
        let toHakata = try XCTUnwrap(planner.routes(from: "fukuoka/天神", to: "fukuoka/博多").first?.segments.first)
        XCTAssertEqual(toHakata.boardJudge().judge(row: "貝塚 行"), .wrongDirection(matched: "貝塚"))
        // 中洲川端 까지라면 貝塚行 을 타도 된다.
        let toNakasu = try XCTUnwrap(planner.routes(from: "fukuoka/天神", to: "fukuoka/中洲川端").first?.segments.first)
        XCTAssertEqual(toNakasu.boardJudge().judge(row: "貝塚 行"), .board(matched: "貝塚"))
    }

    func testGinzaLineTowardAsakusa() throws {
        let planner = RoutePlanner(network: RailNetwork.shared)
        // 긴자에서 우에노로: 아사쿠사행은 타고, 시부야행은 반대.
        let seg = try XCTUnwrap(planner.routes(from: "銀座", to: "上野").first?.segments.first)
        let judge = seg.boardJudge()
        XCTAssertEqual(judge.judge(row: "浅草 行"), .board(matched: "浅草"))
        XCTAssertEqual(judge.judge(row: "渋谷 行"), .wrongDirection(matched: "渋谷"))
        // 타는 역 이름(승강장 역 이름판)은 판정에 쓰지 않는다.
        XCTAssertNil(judge.judge(row: "銀座"))
    }
}

/// 길찾기에서 틀리기 쉬운 곳: 행선지 · 열차 종류 · 환승 걷기 · 출구 · 멈춘 노선.
final class RouteGuideTests: XCTestCase {
    private let network = RailNetwork.shared
    private var planner: RoutePlanner { RoutePlanner(network: network) }

    private func segment(_ lineID: String, from: String, to: String) throws -> RouteSegment {
        let line = try XCTUnwrap(network.line(lineID))
        let a = try XCTUnwrap(line.stations.firstIndex { $0.ja == from })
        let b = try XCTUnwrap(line.stations.firstIndex { $0.ja == to })
        return RouteSegment(line: line, indices: Array(stride(from: a, through: b, by: a < b ? 1 : -1)), step: a < b ? 1 : -1)
    }

    func testDestinationsThatStopShortOfYours() throws {
        // 긴자선 시부야 → 긴자: 종점 浅草 는 타고, 그 앞 역에서 끝나는 열차는 닿지 않는다.
        let guide = try segment("G", from: "渋谷", to: "銀座").destinationGuide
        XCTAssertEqual(guide.ok, ["浅草"])
        XCTAssertTrue(guide.shortOfStop.map(\.ja).contains("表参道"))
        XCTAssertFalse(guide.shortOfStop.map(\.ja).contains("銀座"))
        XCTAssertNil(guide.junction)
    }

    func testBranchBeforeYourStopIsDrawnAsWrong() throws {
        // 주오선 신주쿠 → 하치오지: 青梅行 은 立川 에서 갈라진다.
        let past = try segment("JC", from: "新宿", to: "八王子").destinationGuide
        XCTAssertEqual(past.branchingOff, ["青梅"])
        XCTAssertEqual(past.junction?.ja, "立川")
        // 立川 까지만 가면 青梅行 도 탄다.
        let before = try segment("JC", from: "新宿", to: "立川").destinationGuide
        XCTAssertTrue(before.branchingOff.isEmpty)
        XCTAssertTrue(before.ok.contains("青梅"))
        // 반대쪽(도쿄 방면)으로 가면 갈라지는 곳은 뒤에 있어 그리지 않는다.
        XCTAssertNil(try segment("JC", from: "新宿", to: "東京").destinationGuide.junction)
    }

    func testExpressIsFasterAndSkipsSmallStations() throws {
        // 후쿠토신선 시부야 → 이케부쿠로: 급행이 각역정차보다 빠르다.
        let options = try segment("F", from: "渋谷", to: "池袋").serviceOptions
        let local = try XCTUnwrap(options.first)
        let express = try XCTUnwrap(options.first { $0.id == "express" })
        XCTAssertEqual(local.sign, "各停")
        XCTAssertTrue(local.stopsAt.allSatisfy { $0 })
        XCTAssertEqual(express.verdict, .board)
        XCTAssertLessThan(try XCTUnwrap(express.minutes), try XCTUnwrap(local.minutes))
        XCTAssertEqual(options.first { $0.id == "s-train" }?.verdict, .needsPaidSeat)
        // 기타산도에 내리려면 급행은 지나친다.
        let toKitasando = try segment("F", from: "渋谷", to: "北参道").serviceOptions
        let skipping = try XCTUnwrap(toKitasando.first { $0.id == "express" })
        XCTAssertEqual(skipping.verdict, .skipsYourStop)
        XCTAssertEqual(skipping.stopsAt.last, false)
        XCTAssertNil(skipping.minutes)
        // 각역정차만 다니는 노선에는 고를 것이 없다.
        XCTAssertTrue(try segment("G", from: "渋谷", to: "銀座").serviceOptions.isEmpty)
    }

    func testAllStationsTrainAppearsOnce() throws {
        // 주오선 쾌속은 快速 이 모든 역에 서는 열차다. 한 줄만 나온다.
        let options = try segment("JC", from: "新宿", to: "三鷹").serviceOptions
        XCTAssertEqual(options.first?.sign, "快速")
        XCTAssertEqual(options.filter { $0.sign == "快速" }.count, 1)
        XCTAssertEqual(Set(options.map(\.id)).count, options.count)
    }

    func testWalkBetweenDifferentlyNamedStations() throws {
        // 하라주쿠(JR) → 메이지진구마에(지요다선): 이름이 다르고 개찰구를 나간다.
        let walk = try segment("JY", from: "新宿", to: "原宿").walk(to: segment("C", from: "明治神宮前", to: "表参道"))
        XCTAssertTrue(walk.renamed)
        XCTAssertTrue(walk.outside)
        XCTAssertTrue(walk.changesOperator)
        // 같은 회사 같은 역: 이름도 같고 거리 숫자도 없다.
        let same = try segment("G", from: "渋谷", to: "表参道").walk(to: segment("C", from: "表参道", to: "乃木坂"))
        XCTAssertFalse(same.renamed)
        XCTAssertFalse(same.outside)
        XCTAssertNil(same.meters)
        // 구라마에는 이름이 같아도 떨어진 두 역이다.
        let kuramae = try segment("A", from: "浅草", to: "蔵前").walk(to: segment("E", from: "蔵前", to: "両国"))
        XCTAssertTrue(kuramae.outside)
        XCTAssertGreaterThan(try XCTUnwrap(kuramae.meters), 150)
        XCTAssertGreaterThan(try XCTUnwrap(kuramae.minutes), 3)
    }

    func testExitsAtArrival() {
        // 난바: 도톤보리는 14번 출구.
        let exits = network.exits(at: RailNetwork.key("なんば", region: "osaka"), preferring: "osaka.M")
        XCTAssertTrue(exits.contains { $0.spot.id == "osaka.dotonbori" && $0.exit == "14" })
        XCTAssertEqual(Set(exits.map(\.spot.id)).count, exits.count, "한 곳은 한 번만")
    }

    func testDetourLeavesTheStoppedLineOut() throws {
        // 긴자선이 멈추면 시부야 → 아사쿠사는 긴자선 없이 간다.
        let route = try XCTUnwrap(planner.routes(from: "渋谷", to: "浅草").first)
        let ginza = try XCTUnwrap(route.segments.first)
        let detour = try XCTUnwrap(planner.detours(around: ginza, of: route).first)
        XCTAssertFalse(detour.segments.contains { $0.line.id == "G" })
        XCTAssertEqual(detour.segments.first?.boarding.ja, "渋谷")
        // 오에도선은 파일 둘(E · Et)이 한 노선이다. 둘 다 뺀다.
        let oedo = try segment("E", from: "六本木", to: "大門")
        let around = planner.detours(around: oedo, of: Route(segments: [oedo]))
        XCTAssertFalse(around.isEmpty)
        XCTAssertFalse(around.contains { $0.segments.contains { ["E", "Et"].contains($0.line.id) } })
    }

    func testLastTrainHours() throws {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let at = { (h: Int) in c.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: h, minute: 30))! }
        XCTAssertTrue(LastTrain.isNear(at(23)))
        XCTAssertTrue(LastTrain.isNear(at(0)))
        XCTAssertFalse(LastTrain.isNear(at(12)))
        XCTAssertFalse(LastTrain.isNear(at(21)))
    }
}

/// 이름이 비슷한 역: 신주쿠에 역이 많아 출발역을 잘못 고른다.
final class LookalikeStationTests: XCTestCase {
    private let network = RailNetwork.shared
    private func place(_ ja: String, _ region: String = "tokyo") throws -> Place {
        try XCTUnwrap(network.place(ja: ja, region: region), ja)
    }

    func testShinjukuFamily() throws {
        let sanchome = try XCTUnwrap(network.lookalike(of: place("新宿三丁目")))
        XCTAssertEqual(sanchome.place.ja, "新宿")
        XCTAssertFalse(sanchome.linked)
        XCTAssertTrue((250...600).contains(sanchome.meters), "\(sanchome.meters)m")
        // 新宿西口 는 新宿 와 역 안으로 이어진다.
        XCTAssertEqual(try network.lookalike(of: place("新宿西口"))?.linked, true)
        // 西新宿五丁目 는 西新宿 보다 노선이 많은 新宿 를 가리킨다.
        XCTAssertEqual(try network.lookalike(of: place("西新宿五丁目"))?.place.ja, "新宿")
        // 큰 역 자신에는 표시가 없다.
        XCTAssertNil(try network.lookalike(of: place("新宿")))
    }

    func testOtherCitiesAndFarNames() throws {
        XCTAssertEqual(try network.lookalike(of: place("東梅田", "osaka"))?.place.ja, "梅田")
        // 이름만 같고 먼 역은 표시하지 않는다(1.5km 넘음).
        XCTAssertNil(try network.lookalike(of: place("新横浜", "yokohama")))
    }
}
