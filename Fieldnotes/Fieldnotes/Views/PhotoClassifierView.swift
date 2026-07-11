import CoreLocation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit

struct PhotoClassifierView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var predictions: [BioCAPPhotoPrediction] = []
    @State private var classificationResult: BioCAPClassificationResult?
    @State private var classificationContext: BioCAPPhotoContext?
    @State private var cropRequest: PhotoCropRequest?
    @State private var status: PhotoClassificationStatus = .idle
    @State private var elapsedSeconds: TimeInterval?
    @State private var isShowingCamera = false
    @State private var addedScientificNames: Set<String> = []
    @State private var addingScientificName: String?
    @State private var pendingLogPrediction: BioCAPPhotoPrediction?
    @State private var assetSummary: BioCAPAssetSummary?
    @State private var classificationService = BioCAPImageClassificationService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PhotoGeographyPicker(
                        mode: model.photoGeographyMode,
                        selectedStateCode: model.photoStateCode,
                        selectedRegionID: model.photoRegionID,
                        states: assetSummary?.states ?? [],
                        regions: assetSummary?.regions
                            ?? BioCAPUSRegion.allCases.map {
                                BioCAPRegionDefinition(
                                    id: $0.rawValue,
                                    displayName: $0.displayName
                                )
                        },
                        onModeChange: model.setPhotoGeographyMode,
                        onStateChange: model.setPhotoStateCode,
                        onRegionChange: model.setPhotoRegionID
                    )

                    PhotoSelectionPanel(
                        selectedImage: selectedImage,
                        isClassifying: status.isClassifying,
                        selectedItem: $selectedItem,
                        onTakePhoto: { isShowingCamera = true },
                        onClear: resetPhotoClassification
                    )

                    if status != .idle {
                        PhotoResultsPanel(
                            status: status,
                            predictions: predictions,
                            classificationResult: classificationResult,
                            addedScientificNames: addedScientificNames,
                            addingScientificName: addingScientificName,
                            onSearchAllUS: searchAllUS,
                            onAddToLog: addToLog
                        )
                    }
                }
                .padding(.horizontal, AlmanacLayout.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, .tabBarClearance)
            }
            .almanacBackground()
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: selectedItem) { _, item in
                guard let item else { return }
                prepareCrop(item)
            }
            .task {
                loadAssetSummary()
                model.startPhotoClassificationContext()
            }
            .onDisappear {
                model.stopPhotoClassificationContext()
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraCaptureView { image in
                    prepareCrop(image)
                }
            }
            .fullScreenCover(item: $cropRequest) { request in
                PhotoCropView(request: request) { image, context in
                    classifyCroppedImage(image, context: context)
                }
            }
            .confirmationDialog(
                pendingLogPrediction.map { "Add \($0.commonName) to your log?" }
                    ?? "Add identification to your log?",
                isPresented: Binding(
                    get: { pendingLogPrediction != nil },
                    set: { if !$0 { pendingLogPrediction = nil } }
                ),
                presenting: pendingLogPrediction
            ) { prediction in
                Button("Add \(prediction.commonName)") {
                    confirmAddToLog(prediction)
                }
                Button("Cancel", role: .cancel) {
                    pendingLogPrediction = nil
                }
            } message: { prediction in
                Text("Confirming \(prediction.scientificName) will save this photo identification.")
            }
        }
    }

    private func prepareCrop(_ item: PhotosPickerItem) {
        status = .preparing
        predictions = []
        classificationResult = nil
        classificationContext = nil
        elapsedSeconds = nil
        addedScientificNames = []
        addingScientificName = nil
        pendingLogPrediction = nil

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let previewImage = UIImage(data: data) else {
                    throw PhotoClassificationError.unreadableImage
                }

                let classificationImage = previewImage.normalizedForPhotoClassification()
                let context = await model.photoClassificationContext(
                    at: data.embeddedCaptureDate ?? Date(),
                    photoCoordinate: data.embeddedCoordinate
                )
                cropRequest = PhotoCropRequest(image: classificationImage, context: context)
                status = .idle
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func resetPhotoClassification() {
        selectedItem = nil
        selectedImage = nil
        predictions = []
        classificationResult = nil
        classificationContext = nil
        cropRequest = nil
        status = .idle
        elapsedSeconds = nil
        addedScientificNames = []
        addingScientificName = nil
        pendingLogPrediction = nil
    }

    private func prepareCrop(_ image: UIImage) {
        let classificationImage = image.normalizedForPhotoClassification()
        status = .preparing
        predictions = []
        classificationResult = nil
        classificationContext = nil
        elapsedSeconds = nil
        addedScientificNames = []
        addingScientificName = nil
        pendingLogPrediction = nil

        Task {
            let context = await model.photoClassificationContext()
            // Let UIImagePickerController finish dismissing before presenting
            // the crop editor from the same screen.
            try? await Task.sleep(for: .milliseconds(300))
            cropRequest = PhotoCropRequest(image: classificationImage, context: context)
            status = .idle
        }
    }

    private func classifyCroppedImage(_ image: UIImage, context: BioCAPPhotoContext) {
        selectedImage = image
        status = .classifying
        predictions = []
        classificationResult = nil
        classificationContext = context
        elapsedSeconds = nil
        addedScientificNames = []
        addingScientificName = nil
        pendingLogPrediction = nil

        Task {
            do {
                guard let data = image.jpegData(compressionQuality: 0.95) else {
                    throw PhotoClassificationError.unreadableImage
                }
                let result = try await classify(data, context: context)
                classificationResult = result.0
                predictions = result.0.predictions
                elapsedSeconds = result.1
                status = .ready
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func classify(
        _ data: Data,
        context: BioCAPPhotoContext
    ) async throws -> (BioCAPClassificationResult, TimeInterval) {
        let start = Date()
        let result = try await classificationService.classifyJPEGData(
            data,
            limit: 5,
            context: context
        )
        return (result, Date().timeIntervalSince(start))
    }

    private func searchAllUS() {
        guard let selectedImage,
              let data = selectedImage.jpegData(compressionQuality: 0.95),
              var context = classificationContext else {
            return
        }
        context.geographyPreference = BioCAPGeographyPreference(mode: .everywhere)
        status = .classifying

        Task {
            do {
                let result = try await classify(data, context: context)
                classificationContext = context
                classificationResult = result.0
                predictions = result.0.predictions
                elapsedSeconds = result.1
                status = .ready
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func addToLog(_ prediction: BioCAPPhotoPrediction) {
        guard addingScientificName == nil else {
            return
        }
        pendingLogPrediction = prediction
    }

    private func confirmAddToLog(_ prediction: BioCAPPhotoPrediction) {
        guard addingScientificName == nil else { return }
        pendingLogPrediction = nil
        addingScientificName = prediction.scientificName
        Task {
            await model.addPhotoPredictionToLog(
                prediction,
                image: selectedImage,
                context: classificationContext
            )
            addedScientificNames.insert(prediction.scientificName)
            addingScientificName = nil
        }
    }

    private func loadAssetSummary() {
        guard assetSummary == nil else {
            return
        }
        assetSummary = try? BioCAPImageClassifier.assetSummary()
    }
}

extension Data {
    var embeddedCoordinate: CLLocationCoordinate2D? {
        guard let source = CGImageSourceCreateWithData(self as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              let longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue else {
            return nil
        }
        let latitudeReference = gps[kCGImagePropertyGPSLatitudeRef] as? String
        let longitudeReference = gps[kCGImagePropertyGPSLongitudeRef] as? String
        let coordinate = CLLocationCoordinate2D(
            latitude: latitudeReference == "S" ? -latitude : latitude,
            longitude: longitudeReference == "W" ? -longitude : longitude
        )
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    var embeddedCaptureDate: Date? {
        guard let source = CGImageSourceCreateWithData(self as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let value = exif[kCGImagePropertyExifDateTimeOriginal] as? String else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }
}

private extension UIImage {
    func normalizedForPhotoClassification() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private enum PhotoClassificationStatus: Equatable {
    case idle
    case preparing
    case classifying
    case ready
    case failed(String)

    var isClassifying: Bool {
        if case .classifying = self {
            return true
        }
        if case .preparing = self {
            return true
        }
        return false
    }
}

private enum PhotoClassificationError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "Could not read the selected photo."
        }
    }
}

private struct PhotoSelectionPanel: View {
    var selectedImage: UIImage?
    var isClassifying: Bool
    @Binding var selectedItem: PhotosPickerItem?
    var onTakePhoto: () -> Void
    var onClear: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            PhotoFrame(categoryTag: nil) {
                Group {
                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        HatchPlaceholder()
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fit)
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(action: onTakePhoto) {
                    Text(
                        isClassifying
                            ? "Classifying…"
                            : selectedImage == nil ? "Take Photo" : "Take Another Photo"
                    )
                }
                .buttonStyle(AlmanacButton())
                .disabled(isClassifying)
            }

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text(
                    isClassifying
                        ? "Classifying…"
                        : selectedImage == nil ? "Choose Photo" : "Choose Another Photo"
                )
                    .font(.serif(19, .semibold))
                    .foregroundStyle(isClassifying ? Color.inkFaint : Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(isClassifying ? Color.lineWarm : Color.ink, lineWidth: 1))
            }
            .disabled(isClassifying)

            if selectedImage != nil && !isClassifying {
                Button("Clear Photo & Results", action: onClear)
                    .buttonStyle(AlmanacSecondaryButton())
            }
        }
    }
}

private struct PhotoGeographyPicker: View {
    var mode: BioCAPGeographyMode
    var selectedStateCode: String
    var selectedRegionID: String
    var states: [BioCAPStateDefinition]
    var regions: [BioCAPRegionDefinition]
    var onModeChange: (BioCAPGeographyMode) -> Void
    var onStateChange: (String) -> Void
    var onRegionChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search Area")
                        .font(.serif(18, .semibold))
                        .foregroundStyle(Color.ink)
                    Text("Where was this photo taken?")
                        .font(.serif(12))
                        .foregroundStyle(Color.inkSoft)
                }
                Spacer(minLength: 12)
                Picker("Search Area", selection: selection) {
                    Text("Automatic").tag("automatic")
                    if !states.isEmpty {
                        Section("States") {
                            ForEach(states, id: \.code) { state in
                                Text(state.displayName).tag("state:\(state.code)")
                            }
                        }
                    }
                    Section("Regions") {
                        ForEach(regions, id: \.id) { region in
                            Text(region.displayName).tag("region:\(region.id)")
                        }
                    }
                    Text("All U.S.").tag("everywhere")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.rust)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.paperCard))
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                switch mode {
                case .automatic: "automatic"
                case .selectedState: "state:\(selectedStateCode)"
                case .selectedRegion: "region:\(selectedRegionID)"
                case .everywhere: "everywhere"
                }
            },
            set: { value in
                if value == "automatic" {
                    onModeChange(.automatic)
                } else if value == "everywhere" {
                    onModeChange(.everywhere)
                } else if value.hasPrefix("state:") {
                    onStateChange(String(value.dropFirst("state:".count)))
                } else if value.hasPrefix("region:") {
                    onRegionChange(String(value.dropFirst("region:".count)))
                }
            }
        )
    }
}

private struct PhotoResultsPanel: View {
    var status: PhotoClassificationStatus
    var predictions: [BioCAPPhotoPrediction]
    var classificationResult: BioCAPClassificationResult?
    var addedScientificNames: Set<String>
    var addingScientificName: String?
    var onSearchAllUS: () -> Void
    var onAddToLog: (BioCAPPhotoPrediction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch status {
            case .idle:
                EmptyView()
            case .preparing:
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.rust)
                    Text("Preparing crop")
                        .font(.serif(16))
                        .foregroundStyle(Color.inkSoft)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            case .classifying:
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.rust)
                    Text("Running local BioCAP model")
                        .font(.serif(16))
                        .foregroundStyle(Color.inkSoft)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            case .ready:
                VStack(alignment: .leading, spacing: 0) {
                    if let classificationResult {
                        PhotoIdentificationSummary(
                            result: classificationResult,
                            onSearchAllUS: onSearchAllUS
                        )
                            .padding(.bottom, 8)
                    }
                    ForEach(Array(predictions.enumerated()), id: \.offset) { index, prediction in
                        PhotoPredictionRow(
                            rank: index + 1,
                            prediction: prediction,
                            isAdded: addedScientificNames.contains(prediction.scientificName),
                            isAdding: addingScientificName == prediction.scientificName,
                            isAddDisabled: addingScientificName != nil,
                            onAddToLog: { onAddToLog(prediction) }
                        )
                    }
                }
            case .failed(let message):
                AlmanacEmpty("Could not classify photo", message: message)
            }
        }
    }
}

private struct PhotoIdentificationSummary: View {
    var result: BioCAPClassificationResult
    var onSearchAllUS: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.serif(17, .semibold))
                .foregroundStyle(Color.ink)
            Text(detail)
                .font(.serif(13))
                .foregroundStyle(Color.inkSoft)
            if let geographyName = result.appliedGeographyName {
                Text("Search area: \(geographyName)")
                    .font(.mono(10, .medium))
                    .foregroundStyle(Color.inkFaint)
            }
            if result.shouldOfferAllUSSearch {
                Button("Search all U.S.", action: onSearchAllUS)
                    .font(.serif(13, .semibold))
                    .foregroundStyle(Color.rust)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.paperCard))
    }

    private var title: String {
        switch result.suggestedRank {
        case .species:
            return "Strong match: \(result.suggestedName ?? "top result")"
        case .genus:
            return "Several close matches"
        case .family:
            return "Several close matches"
        case .uncertain:
            return "Compare these matches"
        }
    }

    private var detail: String {
        switch result.suggestedRank {
        case .species:
            return "This match is clearly ahead of the other suggestions."
        case .genus, .family:
            return "The suggestions are closely related. Add the one you recognize."
        case .uncertain:
            return "Compare the suggestions, add the one you recognize, or try a tighter crop."
        }
    }
}

private struct MonoChip: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.mono(11, .medium))
            .tracking(.tracking(0.06, at: 11))
            .foregroundStyle(Color.inkSoft)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.paperCard))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ink, lineWidth: 1))
    }
}

private struct PhotoPredictionRow: View {
    var rank: Int
    var prediction: BioCAPPhotoPrediction
    var isAdded: Bool
    var isAdding: Bool
    var isAddDisabled: Bool
    var onAddToLog: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RankChip(rank: rank)

            VStack(alignment: .leading, spacing: 2) {
                Text(prediction.commonName)
                    .font(.serif(18, .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                Text(prediction.scientificName)
                    .font(.serifItalic(13))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(prediction.similarity.formatted(.number.precision(.fractionLength(3)))) similarity")
                    .font(.serif(19, .semibold))
                    .foregroundStyle(rank == 1 ? Color.ink : Color.inkSoft)
                addButton
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }

    private var addButton: some View {
        Button(action: onAddToLog) {
            HStack(spacing: 4) {
                Image(systemName: addSystemImage)
                    .font(.system(size: 9, weight: .bold))
                Text(addTitle.uppercased())
                    .font(.mono(10, .medium))
                    .tracking(.tracking(0.06, at: 10))
            }
            .foregroundStyle(addForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(addFill))
        }
        .buttonStyle(.plain)
        .disabled(isAdded || isAddDisabled)
    }

    private var addForeground: Color {
        if isAdded { return .inkSoft }
        if isAddDisabled { return .inkFaint }
        return .rust
    }

    private var addFill: Color {
        if isAdded { return .paperCard }
        return Color.rust.opacity(0.12)
    }

    private var addTitle: String {
        if isAdded {
            return "Added"
        }
        if isAdding {
            return "Adding"
        }
        return "Add to Log"
    }

    private var addSystemImage: String {
        if isAdded {
            return "checkmark"
        }
        if isAdding {
            return "hourglass"
        }
        return "plus"
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onImage: onImage)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let dismiss: DismissAction
        private let onImage: (UIImage) -> Void

        init(dismiss: DismissAction, onImage: @escaping (UIImage) -> Void) {
            self.dismiss = dismiss
            self.onImage = onImage
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
