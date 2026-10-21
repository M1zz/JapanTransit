import SwiftUI

/// 길찾기: 출발역과 도착역을 고르면 경로를 보여 준다.
struct PlannerView: View {
    @AppStorage("planner.from") private var fromJa = ""
    @AppStorage("planner.to") private var toJa = ""
    @State private var picking: Field?
    @State private var path: [Route] = []

    private enum Field: String, Identifiable {
        case from, to
        var id: String { rawValue }
    }

    private let network = RailNetwork.shared
    private var from: Place? { network.place(fromJa) }
    private var to: Place? { network.place(toJa) }

    private var routes: [Route] {
        guard let from, let to else { return [] }
        return RoutePlanner(network: network).routes(from: from.id, to: to.id)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    fieldRow(.from, place: from, placeholder: "출발역", icon: "circle")
                    fieldRow(.to, place: to, placeholder: "도착역", icon: "mappin.circle.fill")
                } footer: {
                    if from != nil || to != nil {
                        Button {
                            swap(&fromJa, &toJa)
                        } label: {
                            Label("출발·도착 바꾸기", systemImage: "arrow.up.arrow.down")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }

                if from != nil, to != nil {
                    if routes.isEmpty {
                        Section {
                            Text(from?.id == to?.id ? "출발역과 도착역이 같아요" : "이 두 역을 잇는 길을 찾지 못했어요")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section("경로") {
                            ForEach(routes) { route in
                                NavigationLink(value: route) {
                                    RouteSummaryRow(route: route, label: RoutePlanner.label(for: route, in: routes))
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        tips
                    }
                }
            }
            .navigationTitle("일본길찾기")
            .navigationDestination(for: Route.self) { RouteDetailView(route: $0) }
            .onAppear {
                // 스크린샷·시험용: `-openFirstRoute` 로 띄우면 첫 경로를 바로 연다.
                if ProcessInfo.processInfo.arguments.contains("-openFirstRoute"), path.isEmpty, let r = routes.first {
                    path = [r]
                }
            }
            .sheet(item: $picking) { field in
                StationPickerView(title: field == .from ? "출발역" : "도착역") { place in
                    if field == .from { fromJa = place.id } else { toJa = place.id }
                }
            }
        }
    }

    private func fieldRow(_ field: Field, place: Place?, placeholder: String, icon: String) -> some View {
        Button {
            picking = field
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                if let place {
                    StationTitle(ko: place.ko, ja: place.ja, codes: place.codes)
                } else {
                    Text(placeholder).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(place.map { "\(placeholder): \($0.ko)" } ?? "\(placeholder) 고르기")
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("한국어, 일본어, 영어, 역 번호(M08)로 역을 찾을 수 있어요", systemImage: "magnifyingglass")
            Label("표지판에 적힌 일본어 글자를 크게 보여 드려요. 글자 모양만 맞춰 보세요", systemImage: "character.ja")
            Label("승강장에서 카메라로 열차를 비추면 타도 되는지 알려 드려요", systemImage: "camera.viewfinder")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }
}

/// 경로 한 줄 요약: 노선 배지, 시간, 환승.
struct RouteSummaryRow: View {
    let route: Route
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("약 \(route.estimatedMinutes)분")
                    .font(.title3.bold())
                Text(label)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(.tint)
                Spacer()
            }
            HStack(spacing: 4) {
                ForEach(Array(route.segments.enumerated()), id: \.offset) { i, seg in
                    if i > 0 {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
                    LineBadge(line: seg.line, size: 22)
                    Text(seg.line.nameKo).font(.caption)
                }
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        var parts = ["\(route.stopCount)정거장"]
        parts.append(route.transferCount == 0 ? "환승 없음" : "환승 \(route.transferCount)번")
        if route.operatorChanges > 0 { parts.append("회사가 바뀌어 요금이 따로 붙어요") }
        return parts.joined(separator: " · ")
    }
}
