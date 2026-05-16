import CoreGraphics

/// Tags synthetic events emitted by the app so the tap can ignore feedback loops.
enum SyntheticEventFilter {
    /// Marker we put into `kCGEventSourceUserData` so our event tap recognises and ignores its own events.
    private static let magic: Int64 = 0x4C53_5757 // "LSWW"

    /// Marks event as synthetic by writing magic token to user-data field.
    static func tag(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: magic)
    }

    /// Returns `true` when event was previously tagged as synthetic.
    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == magic
    }
}
