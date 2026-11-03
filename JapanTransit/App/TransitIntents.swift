//
//  TransitIntents.swift
//  JapanTransit
//
//  Siri · 단축어로 길찾기를 시작한다.
//
//  - "일본길찾기로 시부야 가는 법": 지금 있는 곳에서 가장 가까운 역을 출발지로, 말한 역을 도착지로
//    길찾기 화면을 연다. 위치를 모르면 도착지만 채운다.
//  - "일본길찾기 가까운 역": 가장 가까운 역과 거리를 알려 준다.
//
//  역은 한국어 · 일본어 · 영어 · 역 번호(M08) 어느 것으로 말해도 찾는다(`RailNetwork.search`).
//

import AppIntents
import CoreLocation
import Foundation

// MARK: - 앱 화면으로 넘기는 요청

@MainActor @Observable
final class TransitRouter {
    static let shared = TransitRouter()
    /// 늘어날 때마다 첫 화면이 길찾기 탭으로 간다.
    var showPlannerRequest = 0
}

// MARK: - 역

struct StationEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "역")
    static let defaultQuery = StationQuery()

    /// `RailNetwork.key` (지역/일본어 이름). 길찾기 화면이 저장하는 값과 같다.
    let id: String
    let ko: String
    let ja: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(ko)", subtitle: "\(ja)")
    }

    init(_ place: Place) {
        id = place.id
        ko = place.ko
        ja = place.ja
    }
}

struct StationQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [StationEntity] {
        identifiers.compactMap { RailNetwork.shared.place($0) }.map(StationEntity.init)
    }

    func entities(matching string: String) async throws -> [StationEntity] {
        RailNetwork.shared.search(string).prefix(20).map(StationEntity.init)
    }

    /// 마지막으로 길을 찾은 두 역.
    func suggestedEntities() async throws -> [StationEntity] {
        ["planner.to", "planner.from"]
            .compactMap { UserDefaults.standard.string(forKey: $0) }
            .compactMap { RailNetwork.shared.place($0) }
            .map(StationEntity.init)
    }
}

// MARK: - 인텐트

/// 그 역까지 가는 길을 연다.
struct RouteToStationIntent: AppIntent {
    static let title: LocalizedStringResource = "역까지 길찾기"
    static let description = IntentDescription("지금 있는 곳에서 가장 가까운 역부터 고른 역까지 가는 길을 엽니다.")
    static let openAppWhenRun = true

    @Parameter(title: "도착역", requestValueDialog: "어느 역으로 갈까요?")
    var station: StationEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults.standard
        defaults.set(station.id, forKey: "planner.to")
        // 위치 권한은 앱의 "가까운 역" 단추가 받아 둔다. 마지막으로 안 위치를 쓰고 새로 묻지 않는다.
        if let here = CLLocationManager().location,
           let nearest = RailNetwork.shared.nearest(latitude: here.coordinate.latitude, longitude: here.coordinate.longitude).first,
           nearest.place.id != station.id {
            defaults.set(nearest.place.id, forKey: "planner.from")
        }
        TransitRouter.shared.showPlannerRequest &+= 1
        return .result()
    }
}

/// 가장 가까운 역과 거리.
struct NearestStationIntent: AppIntent {
    static let title: LocalizedStringResource = "가까운 역"
    static let description = IntentDescription("지금 있는 곳에서 가장 가까운 역을 알려 줍니다.")

    func perform() async throws -> some IntentResult & ReturnsValue<StationEntity?> & ProvidesDialog {
        guard let here = CLLocationManager().location else {
            return .result(value: nil, dialog: "지금 위치를 몰라요. 앱에서 ‘가까운 역’을 한 번 눌러 위치를 허용해 주세요.")
        }
        guard let nearest = RailNetwork.shared.nearest(latitude: here.coordinate.latitude, longitude: here.coordinate.longitude).first else {
            return .result(value: nil, dialog: "1.5km 안에 아는 역이 없어요.")
        }
        let meters = Int(nearest.meters.rounded())
        return .result(
            value: StationEntity(nearest.place),
            dialog: "가장 가까운 역은 \(nearest.place.ko)(\(nearest.place.ja))역이에요. \(meters)m 떨어져 있어요."
        )
    }
}

// MARK: - Siri 문구

struct JapanTransitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RouteToStationIntent(),
            phrases: [
                "Get directions to \(\.$station) with \(.applicationName)",
                "Route to a station with \(.applicationName)"
            ],
            shortTitle: "Route to Station",
            systemImageName: "point.topleft.down.to.point.bottomright.curvepath"
        )
        AppShortcut(
            intent: NearestStationIntent(),
            phrases: [
                "Nearest station with \(.applicationName)",
                "\(.applicationName) nearest station"
            ],
            shortTitle: "Nearest Station",
            systemImageName: "location.circle"
        )
    }
}
