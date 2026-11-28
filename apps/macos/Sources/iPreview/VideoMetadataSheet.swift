import SwiftUI
import iPreviewCore

struct VideoMetadataSheet: View {
    let media: Media
    @Environment(\.dismiss) private var dismiss
    @State private var result: Result<VideoMetadata, Error>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("媒体元信息")
                .font(.headline)
            Text(media.name)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            switch result {
            case .none:
                ProgressView("正在读取…").controlSize(.small)
            case .some(.failure(let error)):
                Text(error.localizedDescription).foregroundStyle(.secondary)
            case .some(.success(let metadata)):
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    field("分辨率（像素）", metadata.resolution)
                    field("时长", metadata.duration.map(videoTimeLabel))
                    field("标题", metadata.title)
                    field("作者", metadata.author)
                }
            }
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .task {
            let reading = await readMetadata()
            if !Task.isCancelled { result = reading }
        }
    }

    private func field(_ label: String, _ value: String?) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value ?? "未提供")
                .textSelection(.enabled)
        }
    }

    nonisolated private func readMetadata() async -> Result<VideoMetadata, Error> {
        let url: URL
        do {
            url = try media.readableURL()
        } catch {
            return .failure(FileError.unavailable)
        }
        do {
            return .success(try await VideoMetadata.read(from: url))
        } catch {
            return .failure(VideoMetadata.ReadError.unreadable)
        }
    }
}
