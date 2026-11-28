/// The spread containing the active image in the current contiguous run of images.
public struct PhotoSpread {
    public let first: Int
    public let second: Int?
    public let previous: Int?
    public let next: Int?

    public init(index: Int, count: Int, coverSingle: Bool, isImage: (Int) -> Bool) {
        var cover = index
        while cover > 0, isImage(cover - 1) { cover -= 1 }
        let pairedStart = coverSingle ? cover + 1 : cover
        first = index < pairedStart ? index : index - (index - pairedStart) % 2
        let following = first + 1
        second = first >= pairedStart && following < count && isImage(following) ? following : nil
        let prior = first > pairedStart ? first - 2 : first - 1
        previous = prior >= 0 ? prior : nil
        let after = (second ?? first) + 1
        next = after < count ? after : nil
    }
}
