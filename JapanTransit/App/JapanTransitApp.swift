import SwiftUI

@main
struct JapanTransitApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
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
    }
}

#Preview {
    RootView()
}
