import Foundation

// MARK: - KML Parser

/// Parses KML files (Google Maps export format).
/// Handles Placemarks (points) and LineStrings (tracks).
/// KML coordinates are lng,lat,alt (note: longitude FIRST, unlike GPX).

final class KMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser

    var routeName: String?
    var waypoints: [KMLWaypoint] = []
    var trackPoints: [RoutePoint] = []
    var error: String?

    private var currentElement = ""
    private var currentName: String?
    private var currentCoordinates: String?
    private var inPlacemark = false
    private var trackOrder = 0

    struct KMLWaypoint {
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

    init?(data: Data) {
        let parser = XMLParser(data: data)
        self.parser = parser
        super.init()
        parser.delegate = self
    }

    func parse() -> Bool {
        let result = parser.parse()
        if let error = parser.parserError {
            self.error = error.localizedDescription
            print("📍 KML Parse error: \(error)")
        }
        return result && error == nil
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        switch elementName {
        case "Placemark":
            inPlacemark = true
            currentName = nil
            currentCoordinates = nil
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
        case "coordinates":
            currentCoordinates = (currentCoordinates ?? "") + text
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "Placemark":
            if let coordsStr = currentCoordinates {
                let coordPairs = coordsStr.components(separatedBy: .whitespacesAndNewlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                if coordPairs.count == 1 {
                    // Single point = waypoint
                    let parts = coordPairs[0].components(separatedBy: ",")
                    if parts.count >= 2,
                       let lng = Double(parts[0]),
                       let lat = Double(parts[1]) {
                        waypoints.append(KMLWaypoint(
                            latitude: lat,
                            longitude: lng,
                            name: currentName
                        ))
                    }
                } else if coordPairs.count > 1 {
                    // Multiple points = track/LineString
                    for coords in coordPairs {
                        let parts = coords.components(separatedBy: ",")
                        if parts.count >= 2,
                           let lng = Double(parts[0]),
                           let lat = Double(parts[1]) {
                            let alt = parts.count >= 3 ? Double(parts[2]) : nil
                            trackPoints.append(RoutePoint(
                                latitude: lat,
                                longitude: lng,
                                order: trackOrder,
                                timestamp: nil,
                                speed: nil,
                                altitude: alt
                            ))
                            trackOrder += 1
                        }
                    }
                }
            }
            inPlacemark = false

        case "Document", "Folder":
            // If we have a name at document level, use it as route name
            if routeName == nil { routeName = currentName }

        case "name" where !inPlacemark:
            routeName = currentName

        default:
            break
        }
    }
}
