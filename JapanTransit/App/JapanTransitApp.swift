import SwiftUI

@main
struct JapanTransitApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // 팁 상품을 불러오고 끝나지 않은 팁을 마저 센다 (무료 앱이라 LeeoStore 대신 혼자)
                .task { await JapanTransitSpec.tipJar.startStandalone() }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            PlannerView()
                .tabItem { Label("길찾기", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            LinesView()
                .tabItem { Label("노선", systemImage: "tram.fill") }
        }
        .tint(Theme.indigo)
    }
}

#Preview {
    RootView()
}
