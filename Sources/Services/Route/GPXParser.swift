import Foundation

// MARK: - GPX Parser

/// Minimal GPX parser for importing routes from other apps (Rever, Calimoto, etc.)

final class GPXParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser

    var routeName: String?
    var waypoints: [GPXWaypoint] = []
    var trackPoints: [RoutePoint] = []

    private var currentElement = ""
    private var currentName: String?
    private var currentLat: Double = 0
    private var currentLng: Double = 0
    private var currentElevation: Double?
    private var inTrack = false
    private var inRoute = false
    private var trackOrder = 0

    struct GPXWaypoint {
        let latitude: Double
        let longitude: Double
        let name: String?
    }

    init?(url: URL) {
        guard let parser = XMLParser(contentsOf: url) else { return nil }
        self.parser = parser
        super.init()
        parser.delegate = self
    }

    func parse() -> Bool {
        parser.parse()
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        switch elementName {
        case "rte":
            inRoute = true
        case "trk":
            inTrack = true
        case "rtept", "trkpt", "wpt":
            if let latStr = attributeDict["lat"], let lngStr = attributeDict["lon"] {
                currentLat = Double(latStr) ?? 0
                currentLng = Double(lngStr) ?? 0
            }
        case "ele":
            currentElevation = nil
        case "name":
            currentName = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        switch currentElement {
        case "name":
            currentName = (currentName ?? "") + text
        case "ele":
            let elev = Double(text)
            if currentElevation == nil { currentElevation = elev }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "rtept", "wpt":
            waypoints.append(GPXWaypoint(
                latitude: currentLat,
                longitude: currentLng,
                name: currentName
            ))

        case "trkpt":
            trackPoints.append(RoutePoint(
                latitude: currentLat,
                longitude: currentLng,
                order: trackOrder,
                timestamp: nil,
                speed: nil,
                altitude: currentElevation
            ))
            trackOrder += 1

        case "rte":
            inRoute = false
        case "trk":
            inTrack = false
        case "name" where !inRoute && !inTrack:
            routeName = currentName
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        print("📍 GPX Parse error: \(parseError)")
    }
}

// MARK: - GPX Exporter

final class GPXExporter {
    static func export(route: Route, trackPoints: [RoutePoint]) -> String {
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="WAWA Ride"
             xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(route.name)</name>
          </metadata>
          <rte>
        """

        for wp in route.waypoints.sorted(by: { $0.order < $1.order }) {
            gpx += """
              <rtept lat="\(wp.latitude)" lon="\(wp.longitude)">
                <name>\(wp.name ?? "Waypoint \(wp.order)")</name>
              </rtept>
            """
        }

        gpx += """
          </rte>
          <trk>
            <trkseg>
        """

        let points = trackPoints.isEmpty ? (route.simplifiedTrack ?? []) : trackPoints
        for pt in points {
            var trkpt = "      <trkpt lat=\"\(pt.latitude)\" lon=\"\(pt.longitude)\">"
            if let alt = pt.altitude {
                trkpt += "<ele>\(alt)</ele>"
            }
            trkpt += "</trkpt>\n"
            gpx += trkpt
        }

        gpx += """
            </trkseg>
          </trk>
        </gpx>
        """

        return gpx
    }
}
