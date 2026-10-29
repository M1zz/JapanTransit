import SwiftUI
import MapKit

/// 지도에서 역 고르기. 역은 노선색 점, 관광지는 빨간 별. 누르면 아래에 카드가 뜬다.
/// 멀리서 보면 갈아타는 역과 관광지만, 가까이 가면 모든 역을 보여 준다.
struct MapPickerView: View {
    let region: String
    let onPick: (Place) -> Void

    @State private var camera: MapCameraPosition
    @State private var span: Double = 0.2
    @State private var selection: Selection?

    private let network = RailNetwork.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Selection: Hashable {
        case place(String)
        case spot(String)
    }

    init(region: String, onPick: @escaping (Place) -> Void) {
        self.region = region
        self.onPick = onPick
        let places = RailNetwork.shared.places.filter { $0.region == region }
        let lat = places.map(\.lat).reduce(0, +) / Double(max(places.count, 1))
        let lng = places.map(\.lng).reduce(0, +) / Double(max(places.count, 1))
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: 0.16, longitudeDelta: 0.16))))
    }

    /// Far out, only stations with two or more lines — the ones a map of a big
    /// city needs to stay readable.
    private var visiblePlaces: [Place] {
        let places = network.places.filter { $0.region == region }
        return span > 0.09 ? places.filter { Set($0.stops.map(\.lineID)).count > 1 } : places
    }

    private var spots: [Spot] { network.spots.filter { $0.region == region } }

    var body: some View {
        Map(position: $camera, selection: $selection) {
            ForEach(visiblePlaces) { p in
                Annotation(p.ko, coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng),
                           anchor: .center) {
                    StationDot(place: p, selected: selection == .place(p.id))
                }
                .tag(Selection.place(p.id))
                .annotationTitles(span < 0.05 ? .visible : .hidden)
            }
            ForEach(spots) { s in
                Annotation(s.ko, coordinate: CLLocationCoordinate2D(latitude: s.lat, longitude: s.lng)) {
                    Image(systemName: s.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Theme.vermilionFill, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .scaleEffect(selection == .spot(s.id) ? 1.3 : 1)
                        .accessibilityLabel(s.ko)
                }
                .tag(Selection.spot(s.id))
            }
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { ctx in
            span = ctx.region.span.latitudeDelta
        }
        .safeAreaInset(edge: .bottom) {
            if let selection {
                card(for: selection)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selection)
    }

    @ViewBuilder private func card(for selection: Selection) -> some View {
        switch selection {
        case .place(let id):
            if let place = network.place(id) {
                VStack(alignment: .leading, spacing: 12) {
                    StationName(ko: place.ko, ja: place.ja, marks: place.marks, large: true)
                    Button {
                        onPick(place)
                    } label: {
                        Text("이 역 고르기")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.indigoFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .card(padding: 16)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
            }
        case .spot(let id):
            if let spot = spots.first(where: { $0.id == id }) {
                SpotCard(spot: spot, onPick: onPick)
                    .card(padding: 16)
                    .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
            }
        }
    }
}

/// A station on the map: a white dot ringed in its first line's colour,
/// bigger for stations where lines meet.
private struct StationDot: View {
    let place: Place
    let selected: Bool

    var body: some View {
        let lines = place.stops.compactMap { RailNetwork.shared.line($0.lineID) }
        let size: CGFloat = (lines.count > 1 ? 16 : 12) * (selected ? 1.5 : 1)
        Circle()
            .fill(.white)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(lines.first?.swiftColor ?? Theme.indigo, lineWidth: lines.count > 1 ? 4 : 3))
            .overlay {
                if lines.count > 1 {
                    Circle().strokeBorder(Theme.ink, lineWidth: 1).padding(-1)
                }
            }
            .accessibilityLabel("\(place.ko)역")
    }
}
