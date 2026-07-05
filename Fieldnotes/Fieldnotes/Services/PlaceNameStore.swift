import Combine
import CoreLocation
import Foundation

/// Turns coordinates into short, human-readable place labels via reverse
/// geocoding, cached per coarse location so repeat spots resolve instantly and
/// stay available offline. Lookups are serialized to respect CLGeocoder's
/// one-at-a-time throttling.
@MainActor
final class PlaceNameStore: ObservableObject {
    /// Coarse key → resolved label. Published so views update when a name lands.
    @Published private(set) var names: [String: String] = [:]

    private let geocoder = CLGeocoder()
    private let defaults: UserDefaults
    // v2: naming prefers neighborhood/street over landmarks; bumping the key
    // discards names cached under the old landmark-first logic.
    private let storageKey = "placeNameCacheV2"

    private var inFlight: Set<String> = []
    private var pending: [(key: String, latitude: Double, longitude: Double)] = []
    private var isDraining = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            names = decoded
        }
    }

    /// ~110 m grid — keeps "home", "the park", and "the field" distinct while
    /// collapsing the jitter of coarse GPS at one spot.
    static func key(latitude: Double, longitude: Double) -> String {
        String(format: "%.3f,%.3f", latitude, longitude)
    }

    /// Cached label if available; otherwise schedules a lookup and returns nil.
    func name(latitude: Double, longitude: Double) -> String? {
        let key = Self.key(latitude: latitude, longitude: longitude)
        if let name = names[key] {
            return name
        }
        scheduleLookup(key: key, latitude: latitude, longitude: longitude)
        return nil
    }

    private func scheduleLookup(key: String, latitude: Double, longitude: Double) {
        guard names[key] == nil, !inFlight.contains(key) else {
            return
        }
        inFlight.insert(key)
        pending.append((key, latitude, longitude))
        Task { await drainQueue() }
    }

    private func drainQueue() async {
        guard !isDraining else {
            return
        }
        isDraining = true
        defer { isDraining = false }

        while !pending.isEmpty {
            let item = pending.removeFirst()
            let location = CLLocation(latitude: item.latitude, longitude: item.longitude)
            let label = await Self.reverseGeocode(location, geocoder: geocoder)
            inFlight.remove(item.key)
            if let label {
                names[item.key] = label
                persist()
            }
            // Ease off CLGeocoder's rate limit between requests.
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(names) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func reverseGeocode(_ location: CLLocation, geocoder: CLGeocoder) async -> String? {
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return nil
        }
        // Prefer the street, then neighborhood — reverse geocoding attaches the
        // nearest landmark even when you're only *near* it, which mislabels a
        // home next to a park. Landmarks are only a last resort.
        return placemark.thoroughfare
            ?? placemark.subLocality
            ?? placemark.areasOfInterest?.first
            ?? placemark.locality
            ?? placemark.name
    }
}
