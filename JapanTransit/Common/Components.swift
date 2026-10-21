import SwiftUI
import CoreLocation

// MARK: - Line badge

/// Rounded square in the line colour with its letter (G, M, JY…) — the same
/// mark riders see on Tokyo signs.
struct LineBadge: View {
    let line: RailLine
    var size: CGFloat = 28

    var body: some View {
        Text(line.badge)
            .font(.system(size: size * (line.badge.count > 1 ? 0.42 : 0.55), weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(line.swiftColor, in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityLabel(line.nameKo)
    }
}

/// "신주쿠" with the sign's Japanese "新宿" and codes beneath.
struct StationTitle: View {
    let ko: String
    let ja: String
    var codes: [String] = []
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ko)
                .font(large ? .title2.bold() : .body.weight(.semibold))
            HStack(spacing: 6) {
                Text(ja)
                    .font(large ? .headline : .subheadline)
                    .foregroundStyle(.secondary)
                ForEach(codes, id: \.self) { code in
                    Text(code)
                        .font(.caption2.monospaced().weight(.bold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.5)))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Location

/// One-shot current location for "nearest station".
@MainActor
final class LocationFinder: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State: Equatable { case idle, locating, found(CLLocationCoordinate2D), denied, failed }

    @Published private(set) var state: State = .idle
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func locate() {
        state = .locating
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: state = .denied
        default: manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.state == .locating else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .denied, .restricted: self.state = .denied
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in self.state = .found(c) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.state = .failed }
    }
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> Bool {
        a.latitude == b.latitude && a.longitude == b.longitude
    }
}
