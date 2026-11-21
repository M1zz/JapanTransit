import ActivityKit
import SwiftUI
import WidgetKit

@main
struct JapanTransitWidgets: WidgetBundle {
    var body: some Widget {
        TripLiveActivity()
    }
}

/// 길 안내 중 잠금화면과 다이내믹 아일랜드 (→ JapanTransit/Shared/TripActivity.swift).
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            TripActivityView(title: context.attributes.title, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
                .foregroundStyle(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TripActivityBadge(state: state, size: 36)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let arrival = state.arrival {
                        Text(timerInterval: Date.now...max(arrival, .now), countsDown: true)
                            .font(.title3.weight(.heavy).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80, alignment: .trailing)
                    } else if let cars = state.cars {
                        Text(cars).font(.headline.weight(.heavy))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(state.title).font(.subheadline.weight(.heavy)).lineLimit(1)
                        Text(state.sign).font(.title3.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let detail = state.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                TripActivityBadge(state: state, size: 22)
            } compactTrailing: {
                if let arrival = state.arrival {
                    Text(timerInterval: Date.now...max(arrival, .now), countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 48)
                } else {
                    Text(state.sign).lineLimit(1).frame(maxWidth: 64)
                }
            } minimal: {
                TripActivityBadge(state: state, size: 22)
            }
        }
    }
}
