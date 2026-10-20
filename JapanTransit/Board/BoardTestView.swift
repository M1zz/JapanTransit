import SwiftUI
import TrainBoardKit

/// 전광판 시험: 카메라가 읽은 글자를 전광판 줄 단위로 그대로 보여 준다.
/// 실제 역에서 줄이 제대로 묶이는지(種別·行先·時刻 가 한 줄로 오는지) 보려고 쓴다.
struct BoardTestView: View {
    @StateObject private var camera = BoardCamera(recognitionLanguages: ["ja-JP", "en-US"])

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                BoardCameraPreview(session: camera.session)
                Color.black.opacity(0.001)   // keep the layer alive even before frames
                if camera.denied {
                    Label("카메라 권한이 필요합니다", systemImage: "video.slash.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.black.opacity(0.6), in: Capsule())
                }
            }
            .frame(height: 300)
            .clipped()

            List {
                Section("읽은 줄 (위에서부터)") {
                    if camera.rows.isEmpty {
                        Text("전광판을 비춰 주세요")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(camera.rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(row)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("전광판 시험")
        .navigationBarTitleDisplayMode(.inline)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }
}
