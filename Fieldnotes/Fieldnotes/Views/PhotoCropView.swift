import SwiftUI
import UIKit
import Vision

struct PhotoCropRequest: Identifiable {
    let id = UUID()
    var image: UIImage
    var context: BioCAPPhotoContext
}

struct PhotoCropView: View {
    @Environment(\.dismiss) private var dismiss

    var request: PhotoCropRequest
    var onUseCrop: (UIImage, BioCAPPhotoContext) -> Void

    @State private var cropRect: CGRect
    @State private var focusRect: CGRect
    @State private var focusRevision = 0
    @State private var suggestionText = "Centering subject…"

    init(
        request: PhotoCropRequest,
        onUseCrop: @escaping (UIImage, BioCAPPhotoContext) -> Void
    ) {
        self.request = request
        self.onUseCrop = onUseCrop
        let initial = PhotoCropGeometry.squareCrop(imageSize: request.image.size)
        _cropRect = State(initialValue: initial)
        _focusRect = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Frame the animal")
                        .font(.serif(26, .semibold))
                        .foregroundStyle(Color.ink)
                    Text("Pinch to zoom and drag to adjust the square.")
                        .font(.serif(15))
                        .foregroundStyle(Color.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PhotoCropScrollView(
                    image: request.image,
                    cropRect: $cropRect,
                    focusRect: focusRect,
                    focusRevision: focusRevision
                )
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.ink, lineWidth: 2)
                        .allowsHitTesting(false)
                }
                .overlay {
                    CropGuide()
                        .allowsHitTesting(false)
                }

                HStack {
                    Label(suggestionText, systemImage: "viewfinder")
                        .font(.mono(11, .medium))
                        .foregroundStyle(Color.inkSoft)
                    Spacer()
                    Button("Recenter") {
                        recenter()
                    }
                    .font(.mono(11, .semibold))
                    .foregroundStyle(Color.rust)
                }

                Spacer(minLength: 0)

                Button("Use This Crop") {
                    useCrop()
                }
                .buttonStyle(AlmanacButton())
            }
            .padding(.horizontal, AlmanacLayout.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .almanacBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
            .task(id: request.id) {
                await suggestSubjectCrop()
            }
        }
    }

    private func suggestSubjectCrop() async {
        let suggestion = await PhotoSubjectCropper.suggestedCrop(for: request.image)
        focusRect = suggestion.rect
        cropRect = suggestion.rect
        focusRevision += 1
        suggestionText = suggestion.foundSubject ? "Subject centered" : "Centered crop"
    }

    private func recenter() {
        let centered = PhotoCropGeometry.squareCrop(imageSize: request.image.size)
        focusRect = centered
        cropRect = centered
        focusRevision += 1
        suggestionText = "Centered crop"
    }

    private func useCrop() {
        guard let cropped = request.image.cropped(toNormalizedRect: cropRect) else {
            return
        }
        onUseCrop(cropped, request.context)
        dismiss()
    }
}

private struct CropGuide: View {
    var body: some View {
        GeometryReader { geometry in
            let length = geometry.size.width * 0.11
            Path { path in
                for corner in CropCorner.allCases {
                    let point = corner.point(in: geometry.size, inset: 14)
                    path.move(to: CGPoint(x: point.x + corner.horizontal * length, y: point.y))
                    path.addLine(to: point)
                    path.addLine(to: CGPoint(x: point.x, y: point.y + corner.vertical * length))
                }
            }
            .stroke(Color.paper, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}

private enum CropCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var horizontal: CGFloat {
        switch self {
        case .topLeft, .bottomLeft: 1
        case .topRight, .bottomRight: -1
        }
    }

    var vertical: CGFloat {
        switch self {
        case .topLeft, .topRight: 1
        case .bottomLeft, .bottomRight: -1
        }
    }

    func point(in size: CGSize, inset: CGFloat) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: inset, y: inset)
        case .topRight: CGPoint(x: size.width - inset, y: inset)
        case .bottomLeft: CGPoint(x: inset, y: size.height - inset)
        case .bottomRight: CGPoint(x: size.width - inset, y: size.height - inset)
        }
    }
}

struct PhotoCropScrollView: UIViewRepresentable {
    var image: UIImage
    @Binding var cropRect: CGRect
    var focusRect: CGRect
    var focusRevision: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .black
        context.coordinator.imageView.image = image
        scrollView.addSubview(context.coordinator.imageView)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.imageView.image = image
        DispatchQueue.main.async {
            context.coordinator.configureIfNeeded(scrollView)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: PhotoCropScrollView
        let imageView = UIImageView()
        private var lastFocusRevision = -1
        private var lastViewportSize = CGSize.zero

        init(parent: PhotoCropScrollView) {
            self.parent = parent
            super.init()
            imageView.contentMode = .scaleToFill
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            publishCrop(from: scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            publishCrop(from: scrollView)
        }

        func configureIfNeeded(_ scrollView: UIScrollView) {
            let viewport = scrollView.bounds.size
            guard viewport.width > 0, viewport.height > 0 else { return }
            let imageSize = parent.image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            if lastViewportSize != viewport {
                imageView.frame = CGRect(origin: .zero, size: imageSize)
                scrollView.contentSize = imageSize
                let minimum = max(viewport.width / imageSize.width, viewport.height / imageSize.height)
                scrollView.minimumZoomScale = minimum
                scrollView.maximumZoomScale = max(minimum * 8, minimum + 0.01)
                lastViewportSize = viewport
                lastFocusRevision = -1
            }

            guard lastFocusRevision != parent.focusRevision else { return }
            apply(parent.focusRect, to: scrollView)
            lastFocusRevision = parent.focusRevision
        }

        private func apply(_ normalizedRect: CGRect, to scrollView: UIScrollView) {
            let imageSize = parent.image.size
            let viewport = scrollView.bounds.size
            let targetWidth = max(normalizedRect.width * imageSize.width, 1)
            let targetHeight = max(normalizedRect.height * imageSize.height, 1)
            let scale = min(
                scrollView.maximumZoomScale,
                max(
                    scrollView.minimumZoomScale,
                    max(viewport.width / targetWidth, viewport.height / targetHeight)
                )
            )
            scrollView.setZoomScale(scale, animated: false)
            let desired = CGPoint(
                x: normalizedRect.midX * imageSize.width * scale - viewport.width / 2,
                y: normalizedRect.midY * imageSize.height * scale - viewport.height / 2
            )
            let maximum = CGPoint(
                x: max(0, imageSize.width * scale - viewport.width),
                y: max(0, imageSize.height * scale - viewport.height)
            )
            scrollView.contentOffset = CGPoint(
                x: min(max(0, desired.x), maximum.x),
                y: min(max(0, desired.y), maximum.y)
            )
            publishCrop(from: scrollView)
        }

        private func publishCrop(from scrollView: UIScrollView) {
            let imageSize = parent.image.size
            let scale = scrollView.zoomScale
            guard imageSize.width > 0, imageSize.height > 0, scale > 0 else { return }
            let rect = CGRect(
                x: scrollView.contentOffset.x / scale / imageSize.width,
                y: scrollView.contentOffset.y / scale / imageSize.height,
                width: scrollView.bounds.width / scale / imageSize.width,
                height: scrollView.bounds.height / scale / imageSize.height
            ).standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }
            if parent.cropRect != rect {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.cropRect = rect
                }
            }
        }
    }
}

nonisolated enum PhotoSubjectCropper {
    nonisolated struct Suggestion: Sendable {
        var rect: CGRect
        var foundSubject: Bool
    }

    static func suggestedCrop(for image: UIImage) async -> Suggestion {
        guard let cgImage = image.cgImage else {
            return Suggestion(
                rect: PhotoCropGeometry.squareCrop(imageSize: image.size),
                foundSubject: false
            )
        }
        return await Task.detached(priority: .userInitiated) {
            let request = VNGenerateAttentionBasedSaliencyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            do {
                try handler.perform([request])
                guard let observation = request.results?.first as? VNSaliencyImageObservation,
                      let subject = observation.salientObjects?.max(by: {
                          $0.boundingBox.width * $0.boundingBox.height
                              < $1.boundingBox.width * $1.boundingBox.height
                      }) else {
                    return Suggestion(
                        rect: PhotoCropGeometry.squareCrop(imageSize: image.size),
                        foundSubject: false
                    )
                }
                let visionRect = subject.boundingBox
                let topLeftRect = CGRect(
                    x: visionRect.minX,
                    y: 1 - visionRect.maxY,
                    width: visionRect.width,
                    height: visionRect.height
                )
                return Suggestion(
                    rect: PhotoCropGeometry.squareCrop(
                        around: topLeftRect,
                        imageSize: image.size
                    ),
                    foundSubject: true
                )
            } catch {
                return Suggestion(
                    rect: PhotoCropGeometry.squareCrop(imageSize: image.size),
                    foundSubject: false
                )
            }
        }.value
    }
}

nonisolated enum PhotoCropGeometry {
    static func squareCrop(
        around normalizedSubjectRect: CGRect? = nil,
        imageSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let maximumSide = min(imageSize.width, imageSize.height)
        let subject = normalizedSubjectRect?.standardized.intersection(
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        let center = CGPoint(
            x: (subject?.midX ?? 0.5) * imageSize.width,
            y: (subject?.midY ?? 0.5) * imageSize.height
        )
        let subjectWidth = (subject?.width ?? 0) * imageSize.width
        let subjectHeight = (subject?.height ?? 0) * imageSize.height
        let side: CGFloat
        if subject != nil {
            side = min(
                maximumSide,
                max(max(subjectWidth, subjectHeight) * 1.6, maximumSide * 0.42)
            )
        } else {
            side = maximumSide
        }
        let origin = CGPoint(
            x: min(max(0, center.x - side / 2), imageSize.width - side),
            y: min(max(0, center.y - side / 2), imageSize.height - side)
        )
        return CGRect(
            x: origin.x / imageSize.width,
            y: origin.y / imageSize.height,
            width: side / imageSize.width,
            height: side / imageSize.height
        )
    }
}

extension UIImage {
    func cropped(toNormalizedRect normalizedRect: CGRect) -> UIImage? {
        let image = normalizedForCropping()
        guard let cgImage = image.cgImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let crop = CGRect(
            x: normalizedRect.minX * bounds.width,
            y: normalizedRect.minY * bounds.height,
            width: normalizedRect.width * bounds.width,
            height: normalizedRect.height * bounds.height
        ).integral.intersection(bounds)
        guard crop.width > 0, crop.height > 0,
              let cropped = cgImage.cropping(to: crop) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    private func normalizedForCropping() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
