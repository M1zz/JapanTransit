import SwiftUI
import CoreLocation

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

// MARK: - Korean particles

/// 받침에 맞는 조사: "린카이선" + 으로, "유리카모메" + 로, "도에이 지하철" + 로(ㄹ 받침).
enum Josa {
    /// 으로 / 로
    static func ro(_ word: String) -> String {
        word + (batchim(word).map { $0 != 8 } == true ? "으로" : "로")
    }

    /// 을 / 를
    static func eul(_ word: String) -> String {
        word + (batchim(word) != nil ? "을" : "를")
    }

    /// The final consonant index of the last Hangul syllable (nil = none / not Hangul). ㄹ = 8.
    private static func batchim(_ word: String) -> Int? {
        guard let s = word.unicodeScalars.last(where: { (0xAC00...0xD7A3).contains($0.value) }) else { return nil }
        let jong = Int((s.value - 0xAC00) % 28)
        return jong == 0 ? nil : jong
    }
}
