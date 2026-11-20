import SwiftUI

/// 출발역을 고르는지 도착역을 고르는지. 같은 검색이라도 말이 다르다:
/// 출발이면 "지금 있는 곳 근처 역", 도착이면 "가고 싶은 곳에서 내릴 역".
enum StationPickPurpose {
    case departure, arrival

    var title: String { self == .departure ? "출발역" : "도착역" }
    var prompt: String {
        self == .departure ? "지금 있는 역이나 장소 (신주쿠, 新宿, 가부키초)" : "역이나 가고 싶은 곳 (신주쿠, 新宿, 빅사이트)"
    }
    var spotSection: String { self == .departure ? "지금 있는 곳" : "가고 싶은 곳" }
    var spotCaption: String { self == .departure ? "여기서 가까운 역이에요" : "이 역에서 내리세요" }
}

/// Search a station by Korean, Japanese, English or code, by a place you want
/// to visit (빅사이트 → 国際展示場), on a map — or pick the nearest.
struct StationPickerView: View {
    let purpose: StationPickPurpose
    let onPick: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var region: String
    @State private var mode: Mode = .list

    private enum Mode: String, CaseIterable {
        case list = "목록"
        case map = "지도"
    }

    init(purpose: StationPickPurpose, region: String, onPick: @escaping (Place) -> Void) {
        self.purpose = purpose
        self.onPick = onPick
        _region = State(initialValue: region)
        // 스크린샷·시험용: `-pickerMap`, `-pickerQuery <말>`.
        let args = ProcessInfo.processInfo.arguments
        _mode = State(initialValue: args.contains("-pickerMap") ? .map : .list)
        if let i = args.firstIndex(of: "-pickerQuery"), i + 1 < args.count {
            _query = State(initialValue: args[i + 1])
        }
    }
    @StateObject private var location = LocationFinder()

    private let network = RailNetwork.shared

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .list: list
                case .map:
                    MapPickerView(region: region, purpose: purpose) { pick($0) }
                        .id(region)   // recentre when the city changes
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { RegionBar(selection: $region) }
            .navigationTitle(purpose.title)
            // 출발역은 대개 지금 있는 역이다. 위치 권한이 이미 있으면 열자마자 근처 역을 찾는다.
            .task {
                if purpose == .departure, location.isAuthorized, location.state == .idle { location.locate() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Picker("보기", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
            }
        }
    }

    private var list: some View {
        // With a query, look in every city: someone typing 도톤보리 while 도쿄 is
        // selected still finds it. Without one, list the selected city.
        let spots = network.searchSpots(query)
        let places = query.isEmpty ? network.search("", region: region) : network.search(query, preferring: region)
        return List {
            if query.isEmpty {
                Section { nearbyRow } header: {
                    if purpose == .departure { Text("지금 있는 역") }
                }
            }
            if !spots.isEmpty {
                Section(purpose.spotSection) {
                    ForEach(spots.prefix(5)) { spot in
                        SpotCard(spot: spot, purpose: purpose) { pick($0) }
                            .padding(.vertical, 6)
                    }
                }
            }
            Section {
                ForEach(places) { place in
                    Button {
                        pick(place)
                    } label: {
                        row(place)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                if query.isEmpty { Text("\(Region.named(region)?.ko ?? "") 모든 역 (가나다순)") }
                else if !places.isEmpty { Text("역") }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: purpose.prompt)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
    }

    private func pick(_ place: Place) {
        onPick(place)
        dismiss()
    }

    private func row(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if place.region != region, let r = Region.named(place.region) {
                Text(r.ko).font(.caption2.weight(.bold)).foregroundStyle(Theme.indigo)
            }
            StationName(ko: place.ko, ja: place.ja, marks: place.marks)
            if let look = network.lookalike(of: place) {
                Label(lookalikeText(look), systemImage: look.linked ? "arrow.left.arrow.right" : "exclamationmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(look.linked ? Theme.inkSoft : Theme.caution)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// "신주쿠역과 다른 역이에요 · 약 350m" — 이름이 비슷해 헷갈리는 큰 역과 구별한다.
    private func lookalikeText(_ look: RailNetwork.Lookalike) -> String {
        look.linked ? "\(look.place.ko)역과 역 안 통로로 이어진 다른 역이에요"
            : "\(look.place.ko)역과 다른 역이에요 · 약 \(look.meters)m"
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
                    pick(item.place)
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
