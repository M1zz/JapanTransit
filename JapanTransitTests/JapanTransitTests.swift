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
                // 도쿄·가나가와·사이타마·지바 안
                XCTAssertTrue((35.3...36.0).contains(s.lat) && (139.3...140.2).contains(s.lng),
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

    func testWalkLinksNameRealStations() {
        for (name, others) in network.walkLinks {
            XCTAssertNotNil(network.place(name), "transfers.json: \(name) 없는 역")
            for o in others { XCTAssertNotNil(network.place(o), "transfers.json: \(o) 없는 역") }
        }
    }
}

final class SearchTests: XCTestCase {
    private let network = RailNetwork.shared

    func testKoreanJapaneseEnglishAndCode() {
        XCTAssertEqual(network.search("신주쿠").first?.ja, "新宿")
        XCTAssertEqual(network.search("新宿").first?.ja, "新宿")
        XCTAssertEqual(network.search("shinjuku").first?.ja, "新宿")
        XCTAssertEqual(network.search("シンジュク").first?.ja, "新宿")
        XCTAssertEqual(network.search("m8").first?.ja, "新宿")
    }
}

final class RoutePlannerTests: XCTestCase {
    private let planner = RoutePlanner(network: RailNetwork.shared)

    private func check(_ route: Route, from: String, to: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(route.segments.first?.boarding.ja, from, file: file, line: line)
        XCTAssertEqual(route.segments.last?.alighting.ja, to, file: file, line: line)
        for (a, b) in zip(route.segments, route.segments.dropFirst()) {
            let walk = RailNetwork.shared.transferNames(at: a.alighting.ja)
            XCTAssertTrue(walk.contains(b.boarding.ja), "환승이 끊김: \(a.alighting.ja) → \(b.boarding.ja)", file: file, line: line)
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

    func testRouteWithTransfer() throws {
        let routes = planner.routes(from: "池袋", to: "銀座")
        XCTAssertFalse(routes.isEmpty)
        for r in routes { check(r, from: "池袋", to: "銀座") }
    }

    func testYamanoteLoopDirection() throws {
        // 도쿄 → 간다: 번호가 커지는 쪽(内回り), 한 정거장.
        let r = try XCTUnwrap(planner.routes(from: "東京", to: "神田").first)
        let seg = try XCTUnwrap(r.segments.first)
        XCTAssertEqual(seg.line.id, "JY")
        XCTAssertEqual(seg.stopCount, 1)
        XCTAssertEqual(seg.loopSign, seg.step > 0 ? "内回り" : "外回り")
        // 표지판은 주요 역 둘: 도쿄에서 内回り 는 上野・池袋方面
        XCTAssertEqual(seg.headingSign, "上野・池袋方面")
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

    func testSameStationHasNoRoute() {
        XCTAssertTrue(planner.routes(from: "新宿", to: "新宿").isEmpty)
    }
}

final class BoardJudgeOnRouteTests: XCTestCase {
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
