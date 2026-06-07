import SwiftUI
import MapKit
import UIKit

// MARK: - Place Card View (Bottom Sheet)

struct PlaceCardView: View {
    let item: PlaceCardItem
    var onDirections: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Place name
                    Text(item.name)
                        .font(.title3).fontWeight(.bold)
                        .padding(.top, 12)

                    // Address
                    if let address = item.address {
                        Label(address, systemImage: "mappin.and.ellipse")
                            .font(.subheadline).foregroundColor(.secondary)
                    }

                    // Distance
                    if let distance = item.distance {
                        Label("\(String(format: "%.1f", distance / 1000)) km de você", systemImage: "location")
                            .font(.subheadline).foregroundColor(.secondary)
                    }

                    Divider()

                    // Primary action: Directions
                    Button(action: onDirections) {
                        HStack {
                            Image(systemName: "car.fill").font(.title3)
                            Text("Traçar Rota").font(.headline)
                            Spacer()
                            if let eta = item.estimatedTime {
                                Text("~\(Int(eta)) min").font(.subheadline).foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(12)
                    }

                    // Contact actions
                    if item.phoneNumber != nil || item.url != nil {
                        HStack(spacing: 12) {
                            if let phone = item.phoneNumber {
                                Button {
                                    if let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "phone.fill").font(.title3)
                                        Text("Ligar").font(.caption)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(10)
                                }
                            }

                            if let url = item.url {
                                Button {
                                    UIApplication.shared.open(url)
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "safari").font(.title3)
                                        Text("Site").font(.caption)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(10)
                                }
                            }
                        }
                    }

                    // Open in external maps
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Abrir em").font(.subheadline).foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                MapAppsExporter.openLocation(item.coordinate, name: item.name, in: .appleMaps)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "map").font(.title3)
                                    Text("Maps").font(.caption2)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Color(.systemGray5)).cornerRadius(8)
                            }

                            if MapAppsExporter.canOpenGoogleMaps {
                                Button {
                                    MapAppsExporter.openLocation(item.coordinate, name: item.name, in: .googleMaps)
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "mappin").font(.title3)
                                        Text("Google").font(.caption2)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(Color(.systemGray5)).cornerRadius(8)
                                }
                            }

                            if MapAppsExporter.canOpenWaze {
                                Button {
                                    MapAppsExporter.openLocation(item.coordinate, name: item.name, in: .waze)
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "car").font(.title3)
                                        Text("Waze").font(.caption2)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(Color(.systemGray5)).cornerRadius(8)
                                }
                            }
                        }

                        Button {
                            UIPasteboard.general.string = "\(item.coordinate.latitude), \(item.coordinate.longitude)"
                        } label: {
                            Label("Copiar coordenadas", systemImage: "doc.on.doc").font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
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

struct PlaceCardItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance?
    let estimatedTime: TimeInterval?
    let phoneNumber: String?
    let url: URL?

    static func == (lhs: PlaceCardItem, rhs: PlaceCardItem) -> Bool { lhs.id == rhs.id }

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
            self.estimatedTime = (self.distance ?? 0) / (60.0 * 1000 / 60)
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
