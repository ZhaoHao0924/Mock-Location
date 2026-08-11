import CoreLocation
import Foundation

enum ChinaCoordinateConverter {
    private static let earthRadius = 6_378_245.0
    private static let eccentricitySquared = 0.006_693_421_622_965_943_23
    private static let bdOffsetFactor = Double.pi * 3_000 / 180

    static func wgs84ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard CLLocationCoordinate2DIsValid(coordinate), !isOutsideChina(coordinate) else { return coordinate }
        let delta = offset(for: coordinate)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + delta.latitude,
            longitude: coordinate.longitude + delta.longitude
        )
    }

    static func gcj02ToWGS84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard CLLocationCoordinate2DIsValid(coordinate), !isOutsideChina(coordinate) else { return coordinate }
        var estimate = coordinate
        for _ in 0..<3 {
            let transformed = wgs84ToGCJ02(estimate)
            estimate = CLLocationCoordinate2D(
                latitude: estimate.latitude + coordinate.latitude - transformed.latitude,
                longitude: estimate.longitude + coordinate.longitude - transformed.longitude
            )
        }
        return estimate
    }

    static func wgs84ToBD09(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard CLLocationCoordinate2DIsValid(coordinate), !isOutsideChina(coordinate) else { return coordinate }
        return gcj02ToBD09(wgs84ToGCJ02(coordinate))
    }

    static func bd09ToWGS84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard CLLocationCoordinate2DIsValid(coordinate), !isOutsideChina(coordinate) else { return coordinate }
        return gcj02ToWGS84(bd09ToGCJ02(coordinate))
    }

    private static func gcj02ToBD09(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let x = coordinate.longitude
        let y = coordinate.latitude
        let distance = sqrt(x * x + y * y) + 0.00002 * sin(y * bdOffsetFactor)
        let angle = atan2(y, x) + 0.000003 * cos(x * bdOffsetFactor)
        return CLLocationCoordinate2D(
            latitude: distance * sin(angle) + 0.006,
            longitude: distance * cos(angle) + 0.0065
        )
    }

    private static func bd09ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let x = coordinate.longitude - 0.0065
        let y = coordinate.latitude - 0.006
        let distance = sqrt(x * x + y * y) - 0.00002 * sin(y * bdOffsetFactor)
        let angle = atan2(y, x) - 0.000003 * cos(x * bdOffsetFactor)
        return CLLocationCoordinate2D(
            latitude: distance * sin(angle),
            longitude: distance * cos(angle)
        )
    }

    private static func offset(for coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let x = coordinate.longitude - 105
        let y = coordinate.latitude - 35
        var latitudeOffset = transformLatitude(x, y)
        var longitudeOffset = transformLongitude(x, y)
        let radians = coordinate.latitude * Double.pi / 180
        var magic = sin(radians)
        magic = 1 - eccentricitySquared * magic * magic
        let sqrtMagic = sqrt(magic)
        latitudeOffset = latitudeOffset * 180 / ((earthRadius * (1 - eccentricitySquared)) / (magic * sqrtMagic) * Double.pi)
        longitudeOffset = longitudeOffset * 180 / (earthRadius / sqrtMagic * cos(radians) * Double.pi)
        return CLLocationCoordinate2D(latitude: latitudeOffset, longitude: longitudeOffset)
    }

    private static func isOutsideChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.longitude < 72.004 || coordinate.longitude > 137.8347 || coordinate.latitude < 0.8293 || coordinate.latitude > 55.8271
    }

    private static func transformLatitude(_ x: Double, _ y: Double) -> Double {
        var result = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20 * sin(6 * x * Double.pi) + 20 * sin(2 * x * Double.pi)) * 2 / 3
        result += (20 * sin(y * Double.pi) + 40 * sin(y / 3 * Double.pi)) * 2 / 3
        result += (160 * sin(y / 12 * Double.pi) + 320 * sin(y * Double.pi / 30)) * 2 / 3
        return result
    }

    private static func transformLongitude(_ x: Double, _ y: Double) -> Double {
        var result = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20 * sin(6 * x * Double.pi) + 20 * sin(2 * x * Double.pi)) * 2 / 3
        result += (20 * sin(x * Double.pi) + 40 * sin(x / 3 * Double.pi)) * 2 / 3
        result += (150 * sin(x / 12 * Double.pi) + 300 * sin(x / 30 * Double.pi)) * 2 / 3
        return result
    }
}
