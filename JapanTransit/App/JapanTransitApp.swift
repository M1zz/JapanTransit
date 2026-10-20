import SwiftUI

@main
struct JapanTransitApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// 첫 화면. 노선 데이터가 들어오기 전까지는 전광판 시험 도구만 연다.
struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        BoardTestView()
                    } label: {
                        Label("전광판 시험", systemImage: "camera.viewfinder")
                    }
                } footer: {
                    Text("일본 전광판을 비추면 글자를 줄 단위로 어떻게 읽는지 보여 줍니다. 노선 데이터를 넣기 전에 인식 품질을 확인하는 도구입니다.")
                }
            }
            .navigationTitle("일본길찾기")
        }
    }
}

#Preview {
    RootView()
}
