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

    static func thumbnail(for media: Media) async -> CGImage? {
        guard let url = try? media.readableURL() else { return nil }
        if media.kind == .image {
            return image(at: url, limit: 420)
        }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 420, height: 420)
        return try? await generator.image(at: .zero).image
    }
}

struct MediaThumbnail: View {
    let media: Media
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
        .accessibilityHidden(true)
        .task(id: media) {
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
    @ViewState private var photo: CGImage?
    @ViewState private var animation: NSImage?
    @ViewState private var error: String?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let animation {
                    AnimatedPhoto(image: animation)
                } else if let photo {
                    Image(decorative: photo, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else if let error {
                    PreviewError(message: error)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在读取图片")
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: media.id) {
            do {
                let media = media
                let content = try await Task.detached(priority: .userInitiated) { () -> Picture in
                    let url = try media.readableURL()
                    if url.pathExtension.lowercased() == "gif" {
                        return try Picture.animation(Data(contentsOf: url, options: .mappedIfSafe))
                    }
                    guard let image = MediaImages.image(at: url, limit: 4096) else {
                        throw PreviewFailure.unreadablePhoto
                    }
                    return .still(image)
                }.value
                guard !Task.isCancelled else { return }
                switch content {
                case .still(let image):
                    photo = image
                case .animation(let data):
                    guard let image = NSImage(data: data), image.isValid else {
                        throw PreviewFailure.unreadablePhoto
                    }
                    animation = image
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
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
