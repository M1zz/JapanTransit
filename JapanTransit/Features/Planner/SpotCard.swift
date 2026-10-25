import SwiftUI

/// 관광지 한 곳과 거기로 가는 역들. 역을 누르면 그 역을 고른다.
struct SpotCard: View {
    let spot: Spot
    let onPick: (Place) -> Void

    private let network = RailNetwork.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: spot.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.vermilionFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(spot.ko).font(.headline).foregroundStyle(Theme.ink)
                    Text("\(spot.ja) · \(spot.category)").font(.caption).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
            }

            Text("이 역에서 내리세요")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.inkSoft)

            VStack(spacing: 8) {
                ForEach(Array(spot.stations.enumerated()), id: \.offset) { _, access in
                    accessRow(access)
                }
            }

            if let tip = spot.tip, !tip.isEmpty {
                Label(tip, systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(Theme.caution)
            }
        }
    }

    @ViewBuilder private func accessRow(_ access: Spot.Access) -> some View {
        let line = network.line(access.line)
        let place = network.place(for: access, in: spot)
        let code = line?.stations.first { $0.ja == access.ja }?.code
        Button {
            if let place { onPick(place) }
        } label: {
            HStack(spacing: 10) {
                if let line, let code {
                    StationMark(code: code, color: line.swiftColor, size: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(access.ja).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                        Text(place?.ko ?? "").font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    Text(detail(access, line: line))
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft)
            }
            .padding(10)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(place == nil)
        .accessibilityLabel("\(place?.ko ?? access.ja)역 고르기. \(detail(access, line: line))")
    }

    private func detail(_ a: Spot.Access, line: RailLine?) -> String {
        var parts: [String] = []
        if let line { parts.append(line.nameKo) }
        if let exit = a.exit, !exit.isEmpty { parts.append("\(exit) 출구") }
        switch a.walkMinutes {
        case 0?: parts.append("역과 바로 이어져요")
        case let m? where m > 20: parts.append("걸어가기엔 멀어요 (약 \(m)분)")
        case let m?: parts.append("걸어서 \(m)분")
        case nil: break
        }
        if var note = a.note, !note.isEmpty {
            // Notes often open with the line name we've already shown.
            if let name = line?.nameKo, note.hasPrefix(name) {
                note = String(note.dropFirst(name.count)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            }
            if !note.isEmpty { parts.append(note) }
        }
        return parts.joined(separator: " · ")
    }
}
