import SwiftUI
import MapKit
import UIKit

// MARK: - Place Card View (Bottom Sheet)

/// Bottom sheet showing place details — mimics Apple Maps place card.
/// Appears when user taps a pin or search result on the map.

struct PlaceCardView: View {
    let item: PlaceCardItem
    var onDirections: () -> Void
    var onDismiss: () -> Void

    @State private var detent: PresentationDetent = .medium

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Place name
                    Text(item.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.top, 12)

                    // Address
                    if let address = item.address {
                        Label(address, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Distance from current location
                    if let distance = item.distance {
                        Label("\(String(format: "%.1f", distance / 1000)) km de você", systemImage: "location")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Actions
                    Button(action: onDirections) {
                        HStack {
                            Image(systemName: "car.fill")
                                .font(.title3)
                            Text("Traçar Rota")
                                .font(.headline)
                            Spacer()
                            if let eta = item.estimatedTime {
                                Text("~\(eta) min")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(12)
                    }

                    // Coordinates
                    HStack(spacing: 16) {
                        Button {
                            UIPasteboard.general.string = "\(item.coordinate.latitude), \(item.coordinate.longitude)"
                        } label: {
                            Label("Copiar", systemImage: "doc.on.doc")
                                .font(.subheadline)
                        }

                        Button {
                            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: item.coordinate))
                            mapItem.name = item.name
                            mapItem.openInMaps()
                        } label: {
                            Label("Abrir no Maps", systemImage: "arrow.turn.up.forward.iphone")
                                .font(.subheadline)
                        }
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
    }
}

// MARK: - Place Card Item

struct PlaceCardItem: Identifiable {
    let id = UUID()
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance?
    let estimatedTime: TimeInterval?
    let phoneNumber: String?
    let url: URL?

    init(mapItem: MKMapItem, currentLocation: CLLocation? = nil) {
        self.name = mapItem.name ?? "Local"
        self.address = mapItem.placemark.title
        self.coordinate = mapItem.placemark.coordinate
        self.phoneNumber = mapItem.phoneNumber
        self.url = mapItem.url

        if let location = currentLocation {
            self.distance = location.distance(from: CLLocation(
                latitude: coordinate.latitude, longitude: coordinate.longitude
            ))
            self.estimatedTime = (self.distance ?? 0) / (60.0 * 1000 / 60) // rough: 60km/h
        } else {
            self.distance = nil
            self.estimatedTime = nil
        }
    }

    init(coordinate: CLLocationCoordinate2D, name: String, address: String? = nil) {
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.distance = nil
        self.estimatedTime = nil
        self.phoneNumber = nil
        self.url = nil
    }
}
