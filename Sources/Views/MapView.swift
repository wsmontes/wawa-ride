import SwiftUI
import MapKit

struct MapView: View {
    let riders: [Rider]
    let localRiderID: String

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedRider: Rider?
    @State private var mapLoaded = false

    var body: some View {
        ZStack {
            Map(position: $position, selection: $selectedRider) {
                ForEach(riders) { rider in
                    Annotation(
                        rider.displayName,
                        coordinate: rider.coordinate,
                        anchor: .bottom
                    ) {
                        RiderAnnotationView(
                            displayName: rider.displayName,
                            isLocal: rider.id == localRiderID,
                            heading: rider.heading
                        )
                    }
                    .tag(rider)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onAppear {
                updateCamera()
                mapLoaded = true
            }
            .onChange(of: riders) { _, newRiders in
                if mapLoaded, let first = newRiders.first {
                    withAnimation {
                        position = .region(MKCoordinateRegion(
                            center: first.coordinate,
                            latitudinalMeters: 500,
                            longitudinalMeters: 500
                        ))
                    }
                }
            }

            // Empty state
            if riders.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Aguardando localizacao...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func updateCamera() {
        guard let first = riders.first else { return }
        position = .region(MKCoordinateRegion(
            center: first.coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        ))
    }
}

// MARK: - Rider Annotation

struct RiderAnnotationView: View {
    let displayName: String
    let isLocal: Bool
    let heading: Double?

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(isLocal ? Color.blue : Color.orange)
                    .frame(width: 36, height: 36)

                Image(systemName: "motorcycle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .overlay(alignment: .top) {
                if let heading {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isLocal ? .blue : .orange)
                        .rotationEffect(.degrees(heading))
                        .offset(y: -22)
                }
            }

            Text(displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

// MARK: - Preview

#Preview {
    MapView(
        riders: [
            Rider(
                id: "rider-1",
                displayName: "Voce",
                coordinate: CLLocationCoordinate2D(latitude: -23.5505, longitude: -46.6333),
                heading: 45,
                speed: 60,
                lastUpdate: Date(),
                isConnected: true
            )
        ],
        localRiderID: "rider-1"
    )
}
