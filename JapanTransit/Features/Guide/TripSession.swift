import ActivityKit
import CoreLocation
import Foundation
import Observation
import UserNotifications

/// The trip being guided right now: which step, where the train is, the alert
/// before your stop and the lock-screen card. One at a time; it survives the app
/// being closed (the route is saved by id).
@MainActor @Observable
final class TripSession: NSObject {
    static let shared = TripSession()

    private(set) var guide: TripGuide?
    private(set) var stepIndex = 0
    /// Set while riding: where the train was last known to be.
    private(set) var clock: RideClock?
    /// The full-screen guide is up.
    var isShowing = false

    @ObservationIgnored private var activity: Activity<TripActivityAttributes>?
    @ObservationIgnored private let location = CLLocationManager()
    @ObservationIgnored private var started = Date.now

    private struct Saved: Codable {
        let routeID: String
        let step: Int
        let clock: RideClock?
        let started: Date
    }
    private static let savedKey = "trip.saved"
    private static let alertID = "trip.alight"

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyHundredMeters
        location.distanceFilter = 50
        UNUserNotificationCenter.current().delegate = self
        restore()
    }

    var step: TripGuide.Step? { guide.map { $0.steps[min(stepIndex, $0.steps.count - 1)] } }

    /// The leg the current step is about.
    var leg: TripGuide.Leg? {
        guard let guide, let step else { return nil }
        switch step {
        case .board(let i), .ride(let i): return guide.legs[i]
        case .change(let i): return guide.legs[i + 1]
        case .leave: return guide.legs.last
        }
    }

    // MARK: Moving through the trip

    func start(_ route: Route) {
        end()
        guide = TripGuide(route: route)
        stepIndex = 0
        started = .now
        isShowing = true
        enter()
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
    }

    func next() {
        guard let guide else { return }
        if stepIndex + 1 >= guide.steps.count { return end() }
        stepIndex += 1
        enter()
    }

    func back() {
        guard stepIndex > 0 else { return }
        stepIndex -= 1
        enter()
    }

    /// "지금 여기": the rider says which stop the train is at.
    func setHere(_ stop: Int) {
        guard case .ride = step else { return }
        clock = RideClock(index: stop, at: .now)
        rideChanged()
    }

    func end() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.alertID])
        location.stopUpdatingLocation()
        let ending = activity
        activity = nil
        Task { await ending?.end(nil, dismissalPolicy: .immediate) }
        guide = nil
        clock = nil
        isShowing = false
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
    }

    /// A step begins: start the clock when boarding is done, stop it after.
    private func enter() {
        if case .ride = step {
            clock = RideClock(index: 0, at: .now)
            if [.authorizedWhenInUse, .authorizedAlways].contains(location.authorizationStatus) {
                location.startUpdatingLocation()
            }
        } else {
            clock = nil
            location.stopUpdatingLocation()
        }
        rideChanged()
    }

    private func rideChanged() {
        scheduleAlert()
        updateActivity()
        save()
    }

    // MARK: The alert before your stop

    private func scheduleAlert() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.alertID])
        guard case .ride = step, let leg, let clock, let when = clock.warning(on: leg) else { return }
        let stop = leg.alighting.station
        let content = UNMutableNotificationContent()
        content.title = "곧 \(stop.ko)예요"
        content.body = "다음 역 \(stop.ja)에서 내려요. 문 쪽으로 가 있으세요."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let seconds = max(when.timeIntervalSinceNow, 1)
        center.add(UNNotificationRequest(identifier: Self.alertID, content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
    }

    // MARK: Lock screen

    private func updateActivity() {
        guard let guide, let state = activityState() else { return }
        let content = ActivityContent(state: state, staleDate: state.arrival?.addingTimeInterval(15 * 60))
        if let activity {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            let first = guide.route.segments.first?.boarding.ko ?? "", last = guide.route.segments.last?.alighting.ko ?? ""
            activity = try? Activity.request(attributes: TripActivityAttributes(title: "\(first) → \(last)"), content: content)
        }
    }

    /// What the lock screen shows for the current step.
    func activityState() -> TripActivityAttributes.ContentState? {
        guard let guide, let step, let leg else { return nil }
        let line = leg.first.line
        func state(_ stage: TripActivityAttributes.ContentState.Stage, _ title: String, _ sign: String,
                   detail: String? = nil, cars: String? = nil, start: Date? = nil, arrival: Date? = nil) -> TripActivityAttributes.ContentState {
            .init(stage: stage, badge: line.badge, color: line.color, title: title, sign: sign,
                  detail: detail, cars: cars, start: start, arrival: arrival)
        }
        switch step {
        case .board:
            return state(.board, "\(line.nameKo) 타는 곳으로", leg.first.headingSign,
                         detail: "\(leg.alighting.station.ko)까지 \(leg.stops.count - 1)정거장", cars: leg.cars?.stayOn.cars)
        case .ride:
            let clock = clock ?? RideClock(index: 0, at: .now)
            return state(.ride, "\(leg.alighting.station.ko)에서 내려요", leg.alighting.station.ja,
                         detail: "\(line.nameKo) · \(leg.first.headingSign)", cars: leg.cars?.stayOn.cars,
                         start: clock.at, arrival: clock.arrival(at: leg.stops.count - 1, on: leg))
        case .change(let i):
            let from = guide.legs[i].alighting.station
            return state(.change, "\(from.ko)에서 갈아타요", "\(line.nameJa) のりかえ", detail: "\(line.nameKo) · \(leg.first.headingSign)")
        case .leave:
            let station = leg.alighting.station
            return state(.leave, "도착했어요", station.ja, detail: "\(station.ko) · 출구를 확인하세요")
        }
    }

    // MARK: Saving

    private func save() {
        guard let guide else { return }
        let saved = Saved(routeID: guide.route.id, step: stepIndex, clock: clock, started: started)
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.savedKey)
    }

    /// Picks up a trip from the last few hours and shows it again.
    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              Date.now.timeIntervalSince(saved.started) < 6 * 3600,
              let route = Route(id: saved.routeID) else {
            UserDefaults.standard.removeObject(forKey: Self.savedKey)
            return
        }
        guide = TripGuide(route: route)
        stepIndex = min(saved.step, (guide?.steps.count ?? 1) - 1)
        clock = saved.clock
        started = saved.started
        isShowing = true
        activity = Activity<TripActivityAttributes>.activities.first
    }
}

// MARK: - Location: snap the clock to the station you're at

extension TripSession: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy < 200 else { return }
        Task { @MainActor in
            guard case .ride = self.step, let leg = self.leg, let clock = self.clock,
                  let better = clock.corrected(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, on: leg)
            else { return }
            self.clock = better
            self.rideChanged()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - Show the alert even with the app open

extension TripSession: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { TripSession.shared.isShowing = TripSession.shared.guide != nil }
    }
}
