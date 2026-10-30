import SwiftUI
import LeeoKit

@main
struct JapanTransitApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // 아이폰 듀오: 접힘을 재서 아래로 흘리고, 시트 · 알림창이 접힌 선을 비키게 한다.
                .foldAware()
                // 팁 상품을 불러오고 끝나지 않은 팁을 마저 센다 (무료 앱이라 LeeoStore 대신 혼자)
                .task { await JapanTransitSpec.tipJar.startStandalone() }
        }
    }
}

struct RootView: View {
    private enum Tab { case planner, lines }
    @State private var tab = Tab.planner

    var body: some View {
        TabView(selection: $tab) {
            PlannerView()
                .foldTabBarRoom()
                .tabItem { Label("길찾기", systemImage: Self.plannerSymbol) }
                .tag(Tab.planner)
            LinesView()
                .foldTabBarRoom()
                .tabItem { Label("노선", systemImage: "tram.fill") }
                .tag(Tab.lines)
        }
        // 아이폰 듀오를 펴면 시스템 탭바 대신 고르는 쪽 판 바닥에 막대가 선다.
        .foldTabBar(items: [
            .init(value: Tab.planner, title: String(localized: "길찾기"), symbol: Self.plannerSymbol),
            .init(value: Tab.lines, title: String(localized: "노선"), symbol: "tram.fill"),
        ], selected: tab) { tab = $0 }
        .tint(Theme.indigo)
    }

    private static let plannerSymbol = "point.topleft.down.to.point.bottomright.curvepath"
}

#Preview {
    RootView()
}
