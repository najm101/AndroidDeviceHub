import DesignSystem
import DeviceDomain
import MapKit
import SwiftUI

struct LocationSection: View {
    let model: DeviceSettingsModel

    @State private var latitude = 0.0
    @State private var longitude = 0.0
    @State private var altitude = 0.0
    @State private var camera: MapCameraPosition = .automatic
    @State private var hasCentered = false

    private static let coordinateFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...6))

    var body: some View {
        LiveContent(setting: model.location) { location in
            map(location)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            TextField("Latitude", value: $latitude, format: Self.coordinateFormat)
            TextField("Longitude", value: $longitude, format: Self.coordinateFormat)
            TextField("Altitude (m)", value: $altitude, format: .number.precision(.fractionLength(0...1)))
            HStack {
                Spacer()
                Button("Set Location") {
                    model.setLocation(latitude: latitude, longitude: longitude, altitude: altitude)
                    center(on: GeoLocation(latitude: latitude, longitude: longitude))
                }
                .disabled(!GeoLocation(latitude: latitude, longitude: longitude).isValid || isUnchanged(location))
            }
            .onChange(of: location, initial: true) { _, newValue in
                latitude = newValue.latitude
                longitude = newValue.longitude
                altitude = newValue.altitude
                if !hasCentered {
                    hasCentered = true
                    center(on: newValue)
                }
            }
        }
    }

    private func map(_ location: GeoLocation) -> some View {
        MapReader { proxy in
            Map(position: $camera) {
                Marker("Device", systemImage: "location.fill", coordinate: location.coordinate)
            }
            .mapControls { MapZoomStepper() }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                model.setLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
            .help("Click the map to move the device there.")
        }
    }

    private func isUnchanged(_ location: GeoLocation) -> Bool {
        latitude == location.latitude && longitude == location.longitude && altitude == location.altitude
    }

    private func center(on location: GeoLocation) {
        camera = .region(
            MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000))
    }
}

private extension GeoLocation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
