import SwiftUI

/// Search a station by Korean, Japanese, English or code — or pick the nearest.
struct StationPickerView: View {
    let title: String
    let onPick: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @StateObject private var location = LocationFinder()

    private let network = RailNetwork.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    nearbyRow
                }
                Section {
                    ForEach(network.search(query)) { place in
                        Button {
                            onPick(place)
                            dismiss()
                        } label: {
                            row(place)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    if query.isEmpty { Text("모든 역 (가나다순)") }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "신주쿠, 新宿, Shinjuku, M08")
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func row(_ place: Place) -> some View {
        StationName(ko: place.ko, ja: place.ja, marks: place.marks)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var nearbyRow: some View {
        switch location.state {
        case .found(let c):
            let near = network.nearest(latitude: c.latitude, longitude: c.longitude).prefix(3)
            if near.isEmpty {
                Label("1.5km 안에 아는 역이 없어요", systemImage: "location.slash")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(near), id: \.place.id) { item in
                Button {
                    onPick(item.place)
                    dismiss()
                } label: {
                    HStack {
                        VStack(spacing: 2) {
                            Image(systemName: "location.fill").font(.caption).foregroundStyle(Theme.indigo)
                            Text("\(Int(item.meters))m").font(.caption2.monospacedDigit()).foregroundStyle(Theme.inkSoft)
                        }
                        .frame(width: 40)
                        row(item.place)
                    }
                }
                .buttonStyle(.plain)
            }
        case .locating:
            Label("현재 위치를 찾는 중…", systemImage: "location")
                .foregroundStyle(.secondary)
        case .denied:
            Label("설정에서 위치 권한을 켜면 가까운 역을 찾아요", systemImage: "location.slash")
                .foregroundStyle(.secondary)
        case .idle, .failed:
            Button {
                location.locate()
            } label: {
                Label(location.state == .failed ? "다시 찾기: 내 근처 역" : "내 근처 역 찾기", systemImage: "location")
            }
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
