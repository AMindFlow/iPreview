import SwiftUI

struct VideoTimeline<Control: Hashable>: View {
    let video: VideoPlayback
    let focus: FocusState<Control?>.Binding
    let control: Control
    let spacing: CGFloat
    @Binding var showsKeyboardFocus: Bool
    var seekLabel = "视频进度"
    var keys: Set<KeyEquivalent> = []
    var handleKey: (KeyPress) -> KeyPress.Result = { _ in .ignored }

    @ViewState private var scrubPosition: Double?
    @ViewState private var scrubbing = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var canSeek: Bool { video.duration > 0 && video.message == nil }

    var body: some View {
        let elapsed = videoTimeLabel(scrubPosition ?? video.elapsed)
        let duration = videoTimeLabel(video.duration)
        HStack(spacing: spacing) {
            Text(elapsed)
                .monospacedDigit()
                .accessibilityLabel("播放位置 \(elapsed)")

            Slider(value: Binding(
                get: { min(scrubPosition ?? video.elapsed, max(video.duration, 1)) },
                set: { position in
                    if scrubbing {
                        scrubPosition = position
                    } else {
                        video.seek(position)
                    }
                }
            ), in: 0...max(video.duration, 1), onEditingChanged: { editing in
                scrubbing = editing
                showsKeyboardFocus = false
                if !editing {
                    if let scrubPosition {
                        video.seek(scrubPosition)
                        self.scrubPosition = nil
                    }
                    focus.wrappedValue = control
                }
            })
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel(seekLabel)
            .disabled(!canSeek)
            .focusable(canSeek, interactions: .edit)
            .focusEffectDisabled()
            .focused(focus, equals: control)
            .onKeyPress(keys: keys, phases: [.down, .repeat], action: handleKey)
            .overlay {
                if canSeek, showsKeyboardFocus, focus.wrappedValue == control {
                    Capsule()
                        .strokeBorder(contrast == .increased ? Color.primary : Color.accentColor, lineWidth: 2)
                        .padding(-3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

            Text(duration)
                .monospacedDigit()
                .accessibilityLabel("总时长 \(duration)")
        }
        .font(.caption)
    }
}
