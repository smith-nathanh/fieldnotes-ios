import Combine
import Foundation
import FieldnotesCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var detections: [FieldDetection] = []
    @Published private(set) var summaries: [SpeciesSummary] = []
    @Published private(set) var recentHits: [FieldDetection] = []
    @Published private(set) var isListening = false
    @Published private(set) var status = "Ready"

    private var store = DetectionStore()
    private let repository: DetectionRepository
    private let detector: DetectionEngine
    private var listeningTask: Task<Void, Never>?

    init(
        repository: DetectionRepository = DetectionRepository(),
        detector: DetectionEngine = LiveDetectionEngine()
    ) {
        self.repository = repository
        self.detector = detector
    }

    func load() async {
        do {
            detections = try await repository.load()
            store = DetectionStore(detections: detections)
            refreshDerivedState()
        } catch {
            status = "Could not load field log"
        }
    }

    func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    func startListening() {
        guard !isListening else {
            return
        }
        isListening = true
        status = "Listening"

        listeningTask = Task { [detector] in
            do {
                for try await detection in detector.detections() {
                    if Task.isCancelled {
                        break
                    }
                    await record(detection)
                }
            } catch {
                await MainActor.run {
                    self.status = error.localizedDescription
                    self.isListening = false
                }
            }
        }
    }

    func stopListening() {
        listeningTask?.cancel()
        listeningTask = nil
        isListening = false
        status = "Paused"
    }

    func detections(for summary: SpeciesSummary) -> [FieldDetection] {
        detections
            .filter { $0.scientificName == summary.scientificName }
            .sorted { $0.detectedAt > $1.detectedAt }
    }

    private func record(_ detection: FieldDetection) async {
        let decision = store.record(detection)
        if case .skip = decision {
            return
        }

        detections = store.detections.sorted { $0.detectedAt > $1.detectedAt }
        refreshDerivedState()
        status = "\(detection.commonName) \(Int(detection.confidence * 100))%"

        do {
            try await repository.save(store.detections)
        } catch {
            status = "Could not save field log"
        }
    }

    private func refreshDerivedState() {
        summaries = store.summaries()
        recentHits = detections.prefix(8).map { $0 }
    }
}
