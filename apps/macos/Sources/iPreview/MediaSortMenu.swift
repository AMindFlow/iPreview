import SwiftUI
import iPreviewCore

struct MediaSortMenu: View {
    @Binding var sort: MediaSort

    var body: some View {
        Menu {
            Section("排序方式") {
                Picker("排序方式", selection: field) {
                    ForEach(MediaSort.Field.allCases, id: \.self) { field in
                        Text(field.title).tag(field)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("排列顺序") {
                Picker("排列顺序", selection: $sort.descending) {
                    Text("升序").tag(false)
                    Text("降序").tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .disabled(sort.field == .original)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
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

    private var field: Binding<MediaSort.Field> {
        Binding(get: { sort.field }, set: { field in
            if field == .original {
                sort = MediaSort()
            } else {
                sort.field = field
            }
        })
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
