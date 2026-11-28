import AppKit
import AVFoundation
import ImageIO
import SwiftUI
import iPreviewCore

enum MediaImages {
    static func image(at url: URL, limit: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }

    static func cassetteCover(for video: Media, candidates: [Media]) async -> CGImage? {
        let ranked = candidates.compactMap { media -> (url: URL, distance: Double, area: Double, name: String)? in
            guard !Task.isCancelled, let url = try? media.readableURL(),
                  let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = metadata[kCGImagePropertyPixelWidth] as? Double, width > 0,
                  let height = metadata[kCGImagePropertyPixelHeight] as? Double, height > 0 else { return nil }
            let orientation = metadata[kCGImagePropertyOrientation] as? Int ?? 1
            let aspect = (5...8).contains(orientation) ? height / width : width / height
            return (url, abs(log(aspect / (9.0 / 16))), width * height, media.name)
        }.sorted {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            if $0.area != $1.area { return $0.area > $1.area }
            return compareNaturally($0.name, $1.name) == .orderedAscending
        }
        for candidate in ranked {
            guard !Task.isCancelled else { return nil }
            if let image = image(at: candidate.url, limit: 1200) { return image }
        }
        guard !Task.isCancelled else { return nil }
        return await thumbnail(for: video, limit: 1200)
    }

    static func thumbnail(for media: Media, limit: Int = 420) async -> CGImage? {
        guard let url = try? media.readableURL() else { return nil }
        if media.kind == .image {
            return image(at: url, limit: limit)
        }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: limit, height: limit)
        return try? await generator.image(at: .zero).image
    }
}

struct MediaThumbnail: View {
    private struct Load: Equatable {
        let media: Media
        let revision: Int
    }

    let media: Media
    var revision = 0
    var previewCornerRadius: CGFloat?
    @ViewState private var image: CGImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.mediaSurface
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Image(systemName: media.isAvailable ? (media.kind == .video ? "film" : "photo") : "externaldrive.badge.xmark")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .transformAnchorPreference(key: PreviewOriginKey.self, value: .bounds) { origins, bounds in
            if let previewCornerRadius {
                origins.items[media.id] = PreviewOrigin(bounds: bounds, cornerRadius: previewCornerRadius, image: image)
            }
        }
        .accessibilityHidden(true)
        .task(id: Load(media: media, revision: revision)) {
            image = nil
            let item = media
            let newImage = await Task.detached(priority: .utility) {
                await MediaImages.thumbnail(for: item)
            }.value
            if !Task.isCancelled { image = newImage }
        }
    }
}

struct PhotoCanvas: View {
    let media: Media
    var poster: CGImage?
    var onResolved: ((Int64) -> Void)?
    @ViewState private var loadedID: Int64?
    @ViewState private var photo: CGImage?
    @ViewState private var animation: NSImage?
    @ViewState private var error: String?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if loadedID == media.id, let error {
                    PreviewError(message: error)
                } else if loadedID != media.id, let poster {
                    stillImage(poster)
                } else if let animation {
                    AnimatedPhoto(image: animation)
                } else if let still = photo ?? poster {
                    stillImage(still)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在读取图片")
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: media.id) {
            let media = media
            let load = Task.detached(priority: .userInitiated) { () -> Picture in
                try Task.checkCancellation()
                let url = try media.readableURL()
                if url.pathExtension.lowercased() == "gif" {
                    return try Picture.animation(Data(contentsOf: url, options: .mappedIfSafe))
                }
                guard let image = MediaImages.image(at: url, limit: 4096) else {
                    throw PreviewFailure.unreadablePhoto
                }
                return .still(image)
            }
            do {
                let content = try await withTaskCancellationHandler {
                    try await load.value
                } onCancel: {
                    load.cancel()
                }
                try Task.checkCancellation()
                switch content {
                case .still(let image):
                    photo = image
                    animation = nil
                case .animation(let data):
                    guard let image = NSImage(data: data), image.isValid else {
                        throw PreviewFailure.unreadablePhoto
                    }
                    photo = nil
                    animation = image
                }
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            loadedID = media.id
            onResolved?(media.id)
        }
    }

    private func stillImage(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
    }
}

private enum Picture: Sendable {
    case still(CGImage)
    case animation(Data)
}

enum PreviewFailure: LocalizedError {
    case unreadablePhoto

    var errorDescription: String? {
        "无法解码此图片。文件可能损坏，或当前系统不支持其编码。"
    }
}

struct PreviewError: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.title2)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(20)
    }
}

private struct AnimatedPhoto: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image { view.image = image }
    }
}
