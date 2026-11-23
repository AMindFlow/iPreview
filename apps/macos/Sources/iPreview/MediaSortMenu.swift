import SwiftUI
import iPreviewCore

struct MediaSortMenu: View {
    @Binding var sort: MediaSort

    var body: some View {
        Menu {
            Picker("排序方式", selection: $sort.field) {
                ForEach(MediaSort.Field.allCases, id: \.self) { field in
                    Text(field.title).tag(field)
                }
            }
            Divider()
            Picker("排列顺序", selection: $sort.descending) {
                Text("升序").tag(false)
                Text("降序").tag(true)
            }
            .disabled(sort.field == .original)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .frame(width: 25, height: 25)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("文件排序")
        .accessibilityIdentifier("media-sort")
        .help("文件排序")
    }
}

struct MediaSortRequest: Equatable {
    let items: [Media]
    let sort: MediaSort
    var revision = 0

    func ordered() async -> [Media] {
        guard sort.needsFileFacts else { return sort.arrange(items) }
        let worker = Task.detached(priority: .utility) { [items, sort] in sort.arrange(items) }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

struct SortedMedia<Content: View>: View {
    let request: MediaSortRequest
    @ViewBuilder let content: ([Media]) -> Content
    @ViewState private var completed: (request: MediaSortRequest, items: [Media])?

    var body: some View {
        let previous = completed.flatMap { $0.request.items == request.items ? $0.items : nil }
        content(request.sort.field == .original ? request.items : previous ?? request.items)
            .task(id: request) {
                let ordered = await request.ordered()
                if !Task.isCancelled { completed = (request, ordered) }
            }
    }
}
