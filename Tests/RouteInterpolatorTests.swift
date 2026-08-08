import XCTest
@testable import MockLocation

final class RouteInterpolatorTests: XCTestCase {
    func testSinglePointDoesNotCreateExtraCoordinates() {
        let origin = GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
        XCTAssertEqual(
            RouteInterpolator.interpolatedCoordinates(waypoints: [origin], speedMetersPerSecond: 5),
            [origin]
        )
    }

    func testRouteIncludesBothEndpoints() {
        let start = GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
        let end = GeoCoordinate(latitude: 31.2314, longitude: 121.4747)
        let route = RouteInterpolator.interpolatedCoordinates(
            waypoints: [start, end],
            speedMetersPerSecond: 5,
            maximumSpacingMeters: 20
        )
        XCTAssertEqual(route.first, start)
        XCTAssertEqual(route.last, end)
        XCTAssertGreaterThan(route.count, 2)
    }

    func testDistanceIsSymmetric() {
        let first = GeoCoordinate(latitude: 39.9042, longitude: 116.4074)
        let second = GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
        XCTAssertEqual(
            RouteInterpolator.distanceMeters(from: first, to: second),
            RouteInterpolator.distanceMeters(from: second, to: first),
            accuracy: 0.001
        )
    }
}
