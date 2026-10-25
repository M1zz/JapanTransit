import SwiftUI

/// 노선: 회사별 노선 목록과 노선마다 역 순서.
struct LinesView: View {
    private let network = RailNetwork.shared

    private var groups: [(String, [RailLine])] {
        var order: [String] = []
        var byOperator: [String: [RailLine]] = [:]
        for line in network.lines {
            if byOperator[line.operatorKo] == nil { order.append(line.operatorKo) }
            byOperator[line.operatorKo, default: []].append(line)
        }
        return order.map { ($0, byOperator[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.0) { name, lines in
                    Section(name) {
                        ForEach(lines) { line in
                            NavigationLink {
                                LineDetailView(line: line)
                            } label: {
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
            .navigationTitle("노선")
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
                            Text("서는 역: " + s.stops.map { network.place($0)?.ko ?? $0 }.joined(separator: ", "))
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
                                Text(s.ja).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink)
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
        network.transferLines(at: s.ja).filter { $0.id != line.id }
    }
}
