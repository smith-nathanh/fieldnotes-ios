import FieldnotesCore
import MapKit
import SwiftUI

/// One detection's location on the map.
final class DetectionAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let scientificName: String
    let commonName: String
    let taxon: Taxon
    let source: DetectionSource

    init?(detection: FieldDetection) {
        guard let latitude = detection.latitude, let longitude = detection.longitude else {
            return nil
        }
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        scientificName = detection.scientificName
        commonName = detection.commonName
        taxon = detection.taxon
        source = detection.source
    }

    var title: String? { commonName }
}

/// A clustered map of located detections. Muted (POI hidden), rust pins that
/// group into ink cluster bubbles. Tapping a pin selects its species; tapping a
/// cluster zooms in.
struct DetectionMapView: UIViewRepresentable {
    var detections: [FieldDetection]
    /// When false the map is a static thumbnail (no gestures) — safe to embed
    /// inside a scroll view.
    var isInteractive: Bool = true
    var onSelectSpecies: (String) -> Void

    private static let detReuseID = "detection"

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = isInteractive
        map.isUserInteractionEnabled = isInteractive
        // Suppress Apple's own tappable map features so only our pins are interactive.
        if #available(iOS 16.0, *) {
            map.selectableMapFeatures = []
        }
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Self.detReuseID)
        map.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let current = map.annotations.compactMap { $0 as? DetectionAnnotation }
        map.removeAnnotations(current)

        let annotations = detections.compactMap(DetectionAnnotation.init(detection:))
        map.addAnnotations(annotations)

        if !context.coordinator.didSetRegion, !annotations.isEmpty {
            map.showAnnotations(annotations, animated: false)
            context.coordinator.didSetRegion = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectSpecies: onSelectSpecies)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let onSelectSpecies: (String) -> Void
        var didSetRegion = false

        init(onSelectSpecies: @escaping (String) -> Void) {
            self.onSelectSpecies = onSelectSpecies
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: cluster
                ) as? MKMarkerAnnotationView
                view?.markerTintColor = UIColor(Color.ink)
                view?.glyphText = "\(cluster.memberAnnotations.count)"
                return view
            }

            guard let detection = annotation as? DetectionAnnotation else {
                return nil
            }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.detReuseID,
                for: detection
            ) as? MKMarkerAnnotationView
            view?.clusteringIdentifier = "detection"
            view?.markerTintColor = UIColor(Color.rust)
            view?.glyphImage = UIImage(systemName: detection.source == .photo ? "camera.fill" : "waveform")
            view?.animatesWhenAdded = false
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                var region = mapView.region
                region.center = cluster.coordinate
                region.span = MKCoordinateSpan(
                    latitudeDelta: region.span.latitudeDelta * 0.3,
                    longitudeDelta: region.span.longitudeDelta * 0.3
                )
                mapView.setRegion(region, animated: true)
                mapView.deselectAnnotation(cluster, animated: false)
            } else if let detection = view.annotation as? DetectionAnnotation {
                onSelectSpecies(detection.scientificName)
                mapView.deselectAnnotation(detection, animated: false)
            }
        }

        private static let detReuseID = "detection"
    }
}
