//
//  BoardImageTests.swift
//  카메라 시험: 전광판 그림(JapanTransitTests/Boards)을 아이폰 카메라와 같은 글자 인식에 넣어
//  앱이 정답(cases.json)대로 판정하는지 본다. 그림은 scripts/make_test_boards.py 가 만든다.
//

import XCTest
import Vision
import TrainBoardKit
@testable import JapanTransit

final class BoardImageTests: XCTestCase {
    struct Case: Decodable {
        let id: String
        let from: String
        let to: String
        let expect: String
        let matched: String
        let rows: [String]
    }

    private lazy var cases: [Case] = {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "cases", withExtension: "json", subdirectory: "Boards"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Case].self, from: data)) ?? []
    }()

    /// 그 경로의 첫 구간 — 앱에서 '승강장에서 열차 비춰 보기' 를 누른 그 구간.
    private func segment(_ c: Case) throws -> RouteSegment {
        let route = try XCTUnwrap(RoutePlanner(network: .shared).routes(from: c.from, to: c.to).first, c.id)
        return try XCTUnwrap(route.segments.first)
    }

    /// 앱이 화면에 내는 답과 같은 말로: board · wrong · skip · short.
    private func answer(_ v: TrainBoardJudge.Verdict?, on seg: RouteSegment) -> (String, String)? {
        switch v {
        case .board(let m): ("board", m)
        case .wrongDirection(let m): (seg.endsShort(at: m) ? "short" : "wrong", m)
        case .skipsStop(_, let station): ("skip", station)
        case .ambiguous, nil: nil
        }
    }

    func testEveryCaseIsThere() {
        XCTAssertGreaterThanOrEqual(cases.count, 15)
    }

    /// 글자 인식 없이: 그림에 쓴 줄 그대로 판정에 넣는다.
    func testJudgeOnBoardText() throws {
        for c in cases {
            let seg = try segment(c)
            let got = answer(seg.boardJudge().judge(rows: c.rows), on: seg)
            XCTAssertEqual(got?.0, c.expect, "\(c.id): \(c.rows.first ?? "")")
            XCTAssertEqual(got?.1, c.matched, c.id)
        }
    }

    /// 그림 → 글자 인식(카메라와 같은 설정) → 줄 묶기 → 판정.
    func testJudgeOnRecognizedImage() throws {
        let bundle = Bundle(for: Self.self)
        for c in cases {
            let url = try XCTUnwrap(bundle.url(forResource: c.id, withExtension: "png", subdirectory: "Boards"), c.id)
            let rows = try recognizeRows(url)
            let seg = try segment(c)
            let got = answer(seg.boardJudge().judge(rows: rows), on: seg)
            XCTAssertEqual(got?.0, c.expect, "\(c.id) 읽은 줄: \(rows)")
            XCTAssertEqual(got?.1, c.matched, "\(c.id) 읽은 줄: \(rows)")
        }
    }

    private func recognizeRows(_ url: URL) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["ja-JP", "en-US"]
        try VNImageRequestHandler(url: url).perform([request])
        let boxes = (request.results ?? []).compactMap { obs -> TrainBoardJudge.TextBox? in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            let r = obs.boundingBox
            return .init(text: text, minY: r.minY, maxY: r.maxY, minX: r.minX)
        }
        return TrainBoardJudge.rows(from: boxes)
    }
}
