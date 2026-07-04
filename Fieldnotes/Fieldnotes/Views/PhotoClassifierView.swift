import PhotosUI
import SwiftUI
import UIKit

struct PhotoClassifierView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var predictions: [BioCAPPhotoPrediction] = []
    @State private var status: PhotoClassificationStatus = .idle
    @State private var elapsedSeconds: TimeInterval?
    @State private var isShowingCamera = false
    @State private var addedScientificNames: Set<String> = []
    @State private var addingScientificName: String?
    @State private var assetSummary: BioCAPAssetSummary?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Masthead(title: "Photo", eyebrow: "Field Specimen")

                    PhotoSelectionPanel(
                        selectedImage: selectedImage,
                        isClassifying: status.isClassifying,
                        selectedItem: $selectedItem,
                        onTakePhoto: { isShowingCamera = true }
                    )

                    PhotoResultsPanel(
                        status: status,
                        predictions: predictions,
                        elapsedSeconds: elapsedSeconds,
                        assetSummary: assetSummary,
                        addedScientificNames: addedScientificNames,
                        addingScientificName: addingScientificName,
                        onAddToLog: addToLog
                    )
                }
                .padding(.horizontal, AlmanacLayout.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, .tabBarClearance)
            }
            .almanacBackground()
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: selectedItem) { _, item in
                guard let item else { return }
                classify(item)
            }
            .task {
                loadAssetSummary()
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraCaptureView { image in
                    classify(image)
                }
            }
        }
    }

    private func classify(_ item: PhotosPickerItem) {
        status = .classifying
        predictions = []
        elapsedSeconds = nil
        addedScientificNames = []
        addingScientificName = nil

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let previewImage = UIImage(data: data) else {
                    throw PhotoClassificationError.unreadableImage
                }

                let classificationImage = previewImage.normalizedForPhotoClassification()
                guard let classificationData = classificationImage.jpegData(compressionQuality: 0.95) else {
                    throw PhotoClassificationError.unreadableImage
                }

                selectedImage = classificationImage
                let result = try await Task.detached(priority: .userInitiated) {
                    guard let image = UIImage(data: classificationData) else {
                        throw PhotoClassificationError.unreadableImage
                    }
                    let start = Date()
                    let classifier = try BioCAPImageClassifier()
                    let predictions = try classifier.classify(image, limit: 3)
                    return (predictions, Date().timeIntervalSince(start))
                }.value

                predictions = result.0
                elapsedSeconds = result.1
                status = .ready
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func classify(_ image: UIImage) {
        let classificationImage = image.normalizedForPhotoClassification()
        selectedImage = classificationImage
        status = .classifying
        predictions = []
        elapsedSeconds = nil
        addedScientificNames = []
        addingScientificName = nil

        Task {
            do {
                guard let data = classificationImage.jpegData(compressionQuality: 0.95) else {
                    throw PhotoClassificationError.unreadableImage
                }
                let result = try await Task.detached(priority: .userInitiated) {
                    guard let image = UIImage(data: data) else {
                        throw PhotoClassificationError.unreadableImage
                    }
                    let start = Date()
                    let classifier = try BioCAPImageClassifier()
                    let predictions = try classifier.classify(image, limit: 3)
                    return (predictions, Date().timeIntervalSince(start))
                }.value

                predictions = result.0
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
        addingScientificName = prediction.scientificName
        Task {
            await model.addPhotoPredictionToLog(prediction, image: selectedImage)
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
    case classifying
    case ready
    case failed(String)

    var isClassifying: Bool {
        if case .classifying = self {
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
                    Text(isClassifying ? "Classifying…" : "Take Photo")
                }
                .buttonStyle(AlmanacButton())
                .disabled(isClassifying)
            }

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text(isClassifying ? "Classifying…" : "Choose Photo")
                    .font(.serif(19, .semibold))
                    .foregroundStyle(isClassifying ? Color.inkFaint : Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(isClassifying ? Color.lineWarm : Color.ink, lineWidth: 1))
            }
            .disabled(isClassifying)
        }
    }
}

private struct PhotoResultsPanel: View {
    var status: PhotoClassificationStatus
    var predictions: [BioCAPPhotoPrediction]
    var elapsedSeconds: TimeInterval?
    var assetSummary: BioCAPAssetSummary?
    var addedScientificNames: Set<String>
    var addingScientificName: String?
    var onAddToLog: (BioCAPPhotoPrediction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Top Matches")
                Spacer()
                if let assetSummary {
                    MonoChip(text: "\(assetSummary.speciesCount.formatted()) species")
                }
                if let elapsedSeconds {
                    MonoChip(text: "\(elapsedSeconds.formatted(.number.precision(.fractionLength(2))))s")
                }
            }

            switch status {
            case .idle:
                AlmanacEmpty("Choose a photo", message: "top matches from the local image model")
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
                VStack(spacing: 0) {
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
                Text(prediction.score.formatted(.number.precision(.fractionLength(3))))
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
