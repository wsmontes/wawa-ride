import Foundation
import MapKit
import UIKit

// MARK: - Map Apps Exporter

/// Opens routes and locations in external navigation apps:
/// Apple Maps, Google Maps, and Waze.

struct MapAppsExporter {

    // MARK: - Availability

    static var canOpenGoogleMaps: Bool {
        URL(string: "comgooglemaps://") != nil
            && UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!)
    }

    static var canOpenWaze: Bool {
        URL(string: "waze://") != nil
            && UIApplication.shared.canOpenURL(URL(string: "waze://")!)
    }

    // MARK: - Single Location

    /// Open a single coordinate in the selected app
    static func openLocation(_ coordinate: CLLocationCoordinate2D, name: String, in app: MapApp) {
        switch app {
        case .appleMaps:
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = name
            item.openInMaps()

        case .googleMaps:
            let url = URL(string: "comgooglemaps://?q=\(coordinate.latitude),\(coordinate.longitude)&zoom=14")!
            UIApplication.shared.open(url)

        case .waze:
            let url = URL(string: "waze://?ll=\(coordinate.latitude),\(coordinate.longitude)&navigate=yes")!
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Route

    /// Open a route from source to destination
    static func openRoute(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, in app: MapApp) {
        switch app {
        case .appleMaps:
            let src = MKMapItem(placemark: MKPlacemark(coordinate: source))
            src.name = "Início"
            let dst = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            dst.name = "Destino"
            MKMapItem.openMaps(with: [src, dst], launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])

        case .googleMaps:
            let url = URL(string: "comgooglemaps://?saddr=\(source.latitude),\(source.longitude)&daddr=\(destination.latitude),\(destination.longitude)&directionsmode=driving")!
            UIApplication.shared.open(url)

        case .waze:
            let url = URL(string: "waze://?ll=\(destination.latitude),\(destination.longitude)&navigate=yes")!
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Multi-Waypoint Route

    /// Open a route with multiple waypoints.
    /// Apple Maps: opens first and last with intermediate stops
    /// Google Maps: waypoints in URL
    /// Waze: only final destination
    static func openRouteWithWaypoints(_ waypoints: [CLLocationCoordinate2D], names: [String] = [], in app: MapApp) {
        guard waypoints.count >= 2 else { return }

        switch app {
        case .appleMaps:
            var items: [MKMapItem] = []
            for (i, coord) in waypoints.enumerated() {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                item.name = i < names.count ? names[i] : "Ponto \(i + 1)"
                items.append(item)
            }
            MKMapItem.openMaps(with: items, launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])

        case .googleMaps:
            let origin = waypoints.first!
            let dest = waypoints.last!
            var urlStr = "comgooglemaps://?saddr=\(origin.latitude),\(origin.longitude)&daddr=\(dest.latitude),\(dest.longitude)&directionsmode=driving"
            if waypoints.count > 2 {
                let mid = waypoints[1..<(waypoints.count-1)]
                    .map { "\($0.latitude),\($0.longitude)" }
                    .joined(separator: "|")
                urlStr += "&waypoints=\(mid)"
            }
            if let url = URL(string: urlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlStr) {
                UIApplication.shared.open(url)
            }

        case .waze:
            let dest = waypoints.last!
            let url = URL(string: "waze://?ll=\(dest.latitude),\(dest.longitude)&navigate=yes")!
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Map App Enum

enum MapApp: String, CaseIterable {
    case appleMaps = "Apple Maps"
    case googleMaps = "Google Maps"
    case waze = "Waze"

    var icon: String {
        switch self {
        case .appleMaps: return "map"
        case .googleMaps: return "mappin"
        case .waze: return "car"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .appleMaps: return true
        case .googleMaps: return MapAppsExporter.canOpenGoogleMaps
        case .waze: return MapAppsExporter.canOpenWaze
        }
    }
}
