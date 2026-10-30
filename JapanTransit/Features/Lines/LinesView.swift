import SwiftUI
import LeeoKit

/// 노선: 회사별 노선 목록과 노선마다 역 순서.
struct LinesView: View {
    private let network = RailNetwork.shared
    @AppStorage("lines.region") private var region = Region.tokyo.id
    @State private var path: [RailLine] = []
    /// 아이폰 듀오를 폈을 때 결과 쪽 판에 펼친 노선. 없거나 다른 도시면 그 도시 첫 노선.
    @State private var shownLine: RailLine?
    @Environment(\.foldLayout) private var fold

    private var groups: [(String, [RailLine])] {
        var order: [String] = []
        var byOperator: [String: [RailLine]] = [:]
        for line in network.lines where line.regionID == region {
            if byOperator[line.operatorKo] == nil { order.append(line.operatorKo) }
            byOperator[line.operatorKo, default: []].append(line)
        }
        return order.map { ($0, byOperator[$0] ?? []) }
    }

    var body: some View {
        // 아이폰 듀오를 펴면 고르는 쪽(왼쪽 · 아래)에 노선 목록, 결과 쪽(오른쪽 · 위)에 그 노선의 역 순서.
        // 접혀 있거나 보통 아이폰이면 목록만 그린다. 지금 화면 그대로.
        FoldSplitView {
            list
        } result: {
            NavigationStack {
                if let line = shown {
                    LineDetailView(line: line)
                        .id(line.id)
                }
            }
        }
        .onChange(of: fold.isUnfolded) { _, unfolded in
            // 접힌 채 보던 노선이 있으면 펴는 순간 결과 쪽으로 옮긴다.
            guard unfolded, let last = path.last else { return }
            shownLine = last
            path.removeAll()
        }
    }

    private var shown: RailLine? {
        if let shownLine, shownLine.regionID == region { return shownLine }
        return groups.first?.1.first
    }

    /// 노선을 누르면: 접혀 있으면 밀어 넣고, 펴져 있으면 결과 쪽 판에 펼친다.
    private var linePath: Binding<[RailLine]> {
        Binding {
            path
        } set: { newPath in
            if fold.isUnfolded, newPath.count > path.count, let line = newPath.last {
                shownLine = line
            } else {
                path = newPath
            }
        }
    }

    private var list: some View {
        NavigationStack(path: linePath) {
            List {
                ForEach(groups, id: \.0) { name, lines in
                    Section(name) {
                        ForEach(lines) { line in
                            NavigationLink(value: line) {
                                HStack(spacing: 14) {
                                    LineBadge(line: line, size: 34)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(line.nameKo).font(.body.weight(.bold)).foregroundStyle(Theme.ink)
                                        Text("\(line.nameJa) · \(line.stations.count)개 역")
                                            .font(.caption).foregroundStyle(Theme.inkSoft)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            // 펼친 화면에서 결과 쪽에 열린 노선
                            .listRowBackground(fold.isUnfolded && line == shown ? Theme.indigo.opacity(0.12) : nil)
                            .accessibilityAddTraits(fold.isUnfolded && line == shown ? .isSelected : [])
                        }
                    }
                }
                #if DEBUG
                Section("개발") {
                    NavigationLink {
                        BoardTestView()
                    } label: {
                        Label("전광판 시험", systemImage: "text.viewfinder")
                    }
                }
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .safeAreaInset(edge: .top, spacing: 0) { RegionBar(selection: $region) }
            .navigationTitle("노선")
            .navigationDestination(for: RailLine.self) { LineDetailView(line: $0) }
        }
    }
}

struct LineDetailView: View {
    let line: RailLine
    private let network = RailNetwork.shared

    var body: some View {
        List {
            if !line.skippingServices.isEmpty {
                Section("역을 건너뛰는 열차") {
                    ForEach(line.skippingServices, id: \.id) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(s.signWords.first ?? "") (\(s.nameKo))\(s.isPaid ? " · 지정석 유료" : "")")
                                .font(.subheadline.weight(.bold))
                            Text("서는 역: " + s.stops.map { network.place(ja: $0, region: line.regionID)?.ko ?? $0 }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section(line.circular ? "순환선" : "\(line.stations.first?.ko ?? "") ↔ \(line.stations.last?.ko ?? "")") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(line.stations.enumerated()), id: \.element.code) { i, s in
                        HStack(spacing: 14) {
                            StationMark(code: s.code, color: line.swiftColor, size: 36)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(s.ja).font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
                                Text(s.ko).font(.caption).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            HStack(spacing: 3) {
                                ForEach(transfers(at: s), id: \.id) { LineBadge(line: $0, size: 20) }
                            }
                        }
                        .padding(.vertical, 7)
                        // The line runs behind the marks, like a route map.
                        .background(alignment: .leading) {
                            VStack(spacing: 0) {
                                line.swiftColor.opacity(i == 0 && !line.circular ? 0 : 1)
                                line.swiftColor.opacity(i == line.stations.count - 1 && !line.circular ? 0 : 1)
                            }
                            .frame(width: 6)
                            .padding(.leading, 15)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(line.nameKo)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func transfers(at s: RailStation) -> [RailLine] {
        network.transferLines(at: line.placeID(s)).filter { $0.id != line.id }
    }
}
