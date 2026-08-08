import UIKit
import MapKit
import CoreLocation
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let applyButton = UIButton(type: .system)
    private var payload: SharedLocationPayload?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        extractPayload()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.text = "Set mock location"
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.text = "Reading shared location..."
        applyButton.setTitle("Apply", for: .normal)
        applyButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        applyButton.addTarget(self, action: #selector(applyLocation), for: .touchUpInside)
        applyButton.isEnabled = false

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, applyButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func extractPayload() {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        for item in items {
            if let text = item.attributedContentText?.string, let coordinate = Self.coordinate(from: text) {
                setPayload(SharedLocationPayload(latitude: coordinate.latitude, longitude: coordinate.longitude, title: "Shared location"))
                return
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier("com.apple.mapkit.map-item") {
                    provider.loadItem(forTypeIdentifier: "com.apple.mapkit.map-item", options: nil) { [weak self] item, _ in
                        guard let mapItem = item as? MKMapItem else {
                            self?.showInvalidLocation()
                            return
                        }
                        let coordinate = mapItem.placemark.coordinate
                        guard CLLocationCoordinate2DIsValid(coordinate) else {
                            self?.showInvalidLocation()
                            return
                        }
                        self?.setPayload(
                            SharedLocationPayload(
                                latitude: coordinate.latitude,
                                longitude: coordinate.longitude,
                                title: mapItem.name ?? "Shared location"
                            )
                        )
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                        let url = (item as? URL) ?? (item as? NSURL).flatMap { $0 as URL }
                        guard let url, let coordinate = Self.coordinate(from: url.absoluteString) else {
                            self?.showInvalidLocation()
                            return
                        }
                        self?.setPayload(SharedLocationPayload(latitude: coordinate.latitude, longitude: coordinate.longitude, title: url.host ?? "Shared location"))
                    }
                    return
                }
            }
        }
        showInvalidLocation()
    }

    private func setPayload(_ payload: SharedLocationPayload) {
        DispatchQueue.main.async {
            self.payload = payload
            self.detailLabel.text = String(format: "%.6f, %.6f", payload.latitude, payload.longitude)
            self.applyButton.isEnabled = true
        }
    }

    private func showInvalidLocation() {
        DispatchQueue.main.async {
            self.detailLabel.text = "No coordinates were found in this shared item."
        }
    }

    @objc private func applyLocation() {
        guard let payload, let data = try? JSONEncoder().encode(payload) else { return }
        SharedLocationStore.defaults.set(data, forKey: SharedLocationStore.pendingLocationKey)

        var components = URLComponents()
        components.scheme = "mocklocation"
        components.host = "set"
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(payload.latitude)),
            URLQueryItem(name: "lon", value: String(payload.longitude)),
            URLQueryItem(name: "title", value: payload.title)
        ]
        if let url = components.url {
            extensionContext?.open(url, completionHandler: { _ in
                self.extensionContext?.completeRequest(returningItems: nil)
            })
        } else {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private static func coordinate(from text: String) -> (latitude: Double, longitude: Double)? {
        if let components = URLComponents(string: text) {
            let values = components.queryItems ?? []
            for key in ["ll", "sll", "center"] {
                if let value = values.first(where: { $0.name == key })?.value,
                   let coordinate = coordinatePair(from: value) {
                    return coordinate
                }
            }
            if let latitude = values.first(where: { $0.name == "lat" })?.value.flatMap(Double.init),
               let longitude = values.first(where: { $0.name == "lon" })?.value.flatMap(Double.init) {
                return (latitude, longitude)
            }
        }
        return coordinatePair(from: text)
    }

    private static func coordinatePair(from text: String) -> (latitude: Double, longitude: Double)? {
        let pattern = "(-?\\d{1,2}(?:\\.\\d+)?)\\s*,\\s*(-?\\d{1,3}(?:\\.\\d+)?)"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let pair = String(text[range]).split(separator: ",", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard pair.count == 2, let latitude = Double(pair[0]), let longitude = Double(pair[1]),
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return nil
        }
        return (latitude, longitude)
    }
}
