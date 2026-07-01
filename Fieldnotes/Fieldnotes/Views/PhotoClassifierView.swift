import PhotosUI
import SwiftUI
import UIKit

struct PhotoClassifierView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var predictions: [BioCAPPhotoPrediction] = []
    @State private var status: PhotoClassificationStatus = .idle
    @State private var elapsedSeconds: TimeInterval?
    @State private var isShowingCamera = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    FieldPageHeader("Photo", subtitle: subtitle)

                    PhotoSelectionPanel(
                        selectedImage: selectedImage,
                        isClassifying: status.isClassifying,
                        selectedItem: $selectedItem,
                        onTakePhoto: { isShowingCamera = true }
                    )

                    PhotoResultsPanel(
                        status: status,
                        predictions: predictions,
                        elapsedSeconds: elapsedSeconds
                    )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .fieldPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FieldStyle.paper, for: .navigationBar)
            .onChange(of: selectedItem) { _, item in
                guard let item else { return }
                classify(item)
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraCaptureView { image in
                    classify(image)
                }
            }
        }
    }

    private var subtitle: String? {
        switch status {
        case .classifying:
            return "BioCAP image classification is running"
        case .ready:
            return "Top matches from the local image model"
        case .failed:
            return "Photo classification needs attention"
        case .idle:
            return nil
        }
    }

    private func classify(_ item: PhotosPickerItem) {
        status = .classifying
        predictions = []
        elapsedSeconds = nil

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
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FieldStyle.paperRecessed)
                    .aspectRatio(4 / 3, contentMode: .fit)

                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 46, weight: .medium))
                        .foregroundStyle(FieldStyle.inkFaint)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(FieldStyle.rule)
            }

            VStack(spacing: 10) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button(action: onTakePhoto) {
                        Label(isClassifying ? "Classifying" : "Take Photo", systemImage: isClassifying ? "hourglass" : "camera")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(FieldStyle.paperRaised)
                            .background(FieldStyle.moss, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isClassifying)
                }

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(isClassifying ? "Classifying" : "Choose Photo", systemImage: isClassifying ? "hourglass" : "photo.on.rectangle")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(FieldStyle.moss)
                        .background(FieldStyle.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(FieldStyle.rule)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isClassifying)
            }
        }
        .fieldPanel()
    }
}

private struct PhotoResultsPanel: View {
    var status: PhotoClassificationStatus
    var predictions: [BioCAPPhotoPrediction]
    var elapsedSeconds: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                FieldSectionLabel("top matches", systemImage: "scope")
                Spacer()
                if let elapsedSeconds {
                    FieldPill("\(elapsedSeconds.formatted(.number.precision(.fractionLength(2))))s", systemImage: "timer", color: FieldStyle.sky)
                }
            }

            switch status {
            case .idle:
                ContentUnavailableView("Choose a photo", systemImage: "camera.metering.center.weighted")
                    .foregroundStyle(FieldStyle.inkFaint)
                    .frame(maxWidth: .infinity, minHeight: 170)
            case .classifying:
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(FieldStyle.moss)
                    Text("Running local BioCAP model")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FieldStyle.inkMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 170)
            case .ready:
                VStack(spacing: 10) {
                    ForEach(Array(predictions.enumerated()), id: \.offset) { index, prediction in
                        PhotoPredictionRow(rank: index + 1, prediction: prediction)
                    }
                }
            case .failed(let message):
                ContentUnavailableView("Could not classify photo", systemImage: "exclamationmark.triangle", description: Text(message))
                    .foregroundStyle(FieldStyle.inkFaint)
                    .frame(maxWidth: .infinity, minHeight: 170)
            }
        }
        .fieldPanel()
    }
}

private struct PhotoPredictionRow: View {
    var rank: Int
    var prediction: BioCAPPhotoPrediction

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(rank)")
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(FieldStyle.paperRaised)
                .frame(width: 34, height: 34)
                .background(FieldStyle.moss, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(prediction.commonName)
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(FieldStyle.ink)
                    .lineLimit(2)
                Text(prediction.scientificName)
                    .font(.subheadline.italic())
                    .foregroundStyle(FieldStyle.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                Text(prediction.score.formatted(.number.precision(.fractionLength(3))))
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(FieldStyle.ink)
                Text("similarity")
                    .font(.caption2.weight(.medium))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(FieldStyle.inkFaint)
            }
        }
        .padding(12)
        .background(FieldStyle.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FieldStyle.rule)
        }
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
