import SwiftUI

/// 경로 안내: 탈 노선, 방향(표지판 글자), 정거장, 환승, 급행 주의, 카메라 확인.
struct RouteDetailView: View {
    let route: Route
    @State private var scanning: RouteSegment?

    private let network = RailNetwork.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ForEach(Array(route.segments.enumerated()), id: \.element.id) { i, seg in
                    if i > 0 {
                        TransferCard(from: route.segments[i - 1], to: seg,
                                     staysOnTrain: route.staysOnTrain(between: route.segments[i - 1], and: seg))
                    }
                    SegmentCard(segment: seg) { scanning = seg }
                }
                arrival
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(route.segments.first?.boarding.ko ?? "") → \(route.segments.last?.alighting.ko ?? "")")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $scanning) { seg in
            BoardScannerView(segment: seg)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            stat(String(localized: "\(route.estimatedMinutes)분"), String(localized: "예상"))
            stat("\(route.stopCount)", String(localized: "정거장"))
            stat(route.transferCount == 0 ? String(localized: "없음") : String(localized: "\(route.transferCount)번"), String(localized: "환승"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var arrival: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(.tint)
            if let last = route.segments.last?.alighting {
                StationTitle(ko: String(localized: "\(last.ko)에서 내려요"), ja: last.ja, codes: [last.code])
            }
            Spacer()
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Ride

private struct SegmentCard: View {
    let segment: RouteSegment
    let onScan: () -> Void
    @State private var showStops = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LineBadge(line: segment.line, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(segment.line.nameKo).font(.headline)
                    Text("\(segment.line.nameJa) · \(segment.line.operatorKo)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            StationTitle(ko: String(localized: "\(segment.boarding.ko)에서 타요"), ja: segment.boarding.ja, codes: [segment.boarding.code])

            signBox

            serviceAdvice

            Button {
                withAnimation { showStops.toggle() }
            } label: {
                HStack {
                    Text("\(segment.stopCount)정거장 가서 \(segment.alighting.ko)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: showStops ? "chevron.up" : "chevron.down")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showStops {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(segment.stations, id: \.code) { s in
                        HStack(spacing: 8) {
                            Circle().fill(segment.line.swiftColor).frame(width: 8, height: 8)
                            Text(s.code).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(s.ko).font(.subheadline)
                            Text(s.ja).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 4)
            }

            Button(action: onScan) {
                Label("승강장에서 카메라로 열차 확인", systemImage: "camera.viewfinder")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(segment.line.swiftColor)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(segment.line.swiftColor).frame(width: 4).padding(.vertical, 14)
        }
    }

    /// 표지판에서 찾을 글자. 일본어를 못 읽어도 모양으로 맞춰 볼 수 있게 크게.
    private var signBox: some View {
        let numbers = segment.step > 0 ? String(localized: "역 번호가 커지는 쪽") : String(localized: "역 번호가 작아지는 쪽")
        let nextCode = segment.stations.count > 1 ? segment.stations[1].code : ""
        return VStack(alignment: .leading, spacing: 6) {
            Text("표지판에서 이 글자를 찾으세요")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let loop = segment.loopSign {
                    Text(loop).font(.system(size: 30, weight: .heavy))
                }
                Text(segment.headingSign)
                    .font(.system(size: 30, weight: .heavy))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            Text("\(segment.headingKo) · \(numbers) (\(segment.boarding.code) → \(nextCode))")
                .font(.subheadline)
            if !segment.throughTermini.isEmpty {
                Text("다른 회사 노선으로 이어 달리는 열차는 행선지가 이렇게 나와요: \(segment.throughTermini.prefix(5).joined(separator: " · "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(segment.line.swiftColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var serviceAdvice: some View {
        let advice = segment.serviceAdvice
        if !advice.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(advice, id: \.service.id) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(item.ok ? .green : .orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(item.service.signWords.first ?? "") (\(item.service.nameKo))")
                                .font(.subheadline.weight(.bold))
                            Text(item.service.isPaid ? String(localized: "지정석 유료 열차라 일반 표로는 못 타요")
                                 : item.ok ? String(localized: "타도 돼요. 두 역에 다 서요") : skipText(item.service))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if advice.contains(where: { !$0.ok }) {
                    Text("모르겠으면 各駅停車(각역정차) 또는 各停 이라고 적힌 열차를 타세요")
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func skipText(_ s: RailService) -> String {
        let skipped = [segment.boarding, segment.alighting].filter { !s.stops.contains($0.ja) }.map(\.ko)
        return String(localized: "타지 마세요. \(skipped.joined(separator: ", "))에 서지 않아요")
    }
}

// MARK: - Transfer

private struct TransferCard: View {
    let from: RouteSegment
    let to: RouteSegment
    let staysOnTrain: Bool

    var body: some View {
        if staysOnTrain {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down").foregroundStyle(.secondary)
                Text("\(from.alighting.ko)에서 내리지 말고 그대로 타고 가요")
                    .font(.subheadline.weight(.bold))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        } else {
            change
        }
    }

    private var change: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.swap").foregroundStyle(.secondary)
                Text("\(from.alighting.ko)에서 갈아타요").font(.subheadline.weight(.bold))
            }
            if RailNetwork.shared.isOutsideTransfer(from: from.alighting.ja, to: to.boarding.ja) {
                Label("개찰구를 나와 길을 걸어서 \(to.boarding.ko)(\(to.boarding.ja))역으로 가요. 역 밖으로 나가는 게 맞아요",
                      systemImage: "figure.walk")
                    .font(.caption.weight(.semibold))
            } else if from.alighting.ja != to.boarding.ja {
                Label("역 안 통로로 걸어서 \(to.boarding.ko)(\(to.boarding.ja))역으로 가요", systemImage: "figure.walk")
                    .font(.caption.weight(.semibold))
            }
            if from.line.id == to.line.id {
                Text("같은 \(to.line.nameKo)이지만 이 역에서 열차가 끝나요. 내려서 \(to.headingSign) 열차로 바꿔 타세요")
                    .font(.caption.weight(.semibold))
            } else {
                HStack(spacing: 6) {
                    Text("이 글자를 따라가세요:").font(.caption).foregroundStyle(.secondary)
                    LineBadge(line: to.line, size: 20)
                    Text("\(to.line.nameJa) のりかえ").font(.headline)
                }
            }
            if from.line.operator != to.line.operator {
                Text("\(from.line.operatorKo)에서 \(to.line.operatorKo)로 회사가 바뀌어요. 개찰구를 한 번 더 지나고 요금이 따로 붙어요. 교통카드(Suica·PASMO)는 그대로 찍으면 돼요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
