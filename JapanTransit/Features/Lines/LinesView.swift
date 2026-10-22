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
                                HStack(spacing: 12) {
                                    LineBadge(line: line)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(line.nameKo).font(.body.weight(.semibold))
                                        Text("\(line.nameJa) · \(line.stations.count)개 역")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
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
                            Text("\(s.signWords.first ?? "") (\(s.nameKo))\(s.isPaid ? String(localized: " · 지정석 유료") : "")")
                                .font(.subheadline.weight(.bold))
                            Text(String(localized: "서는 역: \(s.stops.map { network.place($0)?.ko ?? $0 }.joined(separator: ", "))"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section(line.circular ? String(localized: "순환선") : "\(line.stations.first?.ko ?? "") ↔ \(line.stations.last?.ko ?? "")") {
                ForEach(line.stations, id: \.code) { s in
                    HStack(spacing: 10) {
                        Text(s.code)
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 22)
                            .background(line.swiftColor, in: RoundedRectangle(cornerRadius: 5))
                        StationTitle(ko: s.ko, ja: s.ja)
                        Spacer()
                        HStack(spacing: 3) {
                            ForEach(transfers(at: s), id: \.id) { LineBadge(line: $0, size: 18) }
                        }
                    }
                }
            }
        }
        .navigationTitle(line.nameKo)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func transfers(at s: RailStation) -> [RailLine] {
        network.transferLines(at: s.ja).filter { $0.id != line.id }
    }
}
