import Carbon.HIToolbox
import Foundation

/// Value-object wrapper around `TISInputSource` with strongly typed properties.
struct InputSource: Identifiable, Hashable {
    let id: String
    let localizedName: String
    let primaryLanguage: String?
    let isSelectable: Bool
    let isEnabled: Bool
    /// True for raw keyboard layouts; false for IMEs (CJK input methods, marked-text composers).
    let isKeyboardLayout: Bool

    fileprivate let ref: TISInputSource?

    /// Equality is based on stable system input-source identifier.
    static func == (lhs: InputSource, rhs: InputSource) -> Bool { lhs.id == rhs.id }
    /// Hashes by stable identifier for collection usage.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Constructs wrapper from raw Carbon input source.
    init?(_ ref: TISInputSource) {
        self.ref = ref
        guard let id = Self.string(ref, kTISPropertyInputSourceID) else { return nil }
        self.id = id
        self.localizedName = Self.string(ref, kTISPropertyLocalizedName) ?? id
        self.primaryLanguage = Self.firstLanguage(ref)
        self.isSelectable = Self.bool(ref, kTISPropertyInputSourceIsSelectCapable)
        self.isEnabled = Self.bool(ref, kTISPropertyInputSourceIsEnabled)
        self.isKeyboardLayout = Self.string(ref, kTISPropertyInputSourceType) == (kTISTypeKeyboardLayout as String)
    }

    /// Detached initializer for tests — bypasses TIS entirely. `selectAsCurrent`
    /// is a no-op for instances built this way, returning `paramErr`.
    init(
        id: String,
        localizedName: String? = nil,
        primaryLanguage: String?,
        isSelectable: Bool = true,
        isEnabled: Bool = true,
        isKeyboardLayout: Bool = true
    ) {
        self.id = id
        self.localizedName = localizedName ?? id
        self.primaryLanguage = primaryLanguage
        self.isSelectable = isSelectable
        self.isEnabled = isEnabled
        self.isKeyboardLayout = isKeyboardLayout
        self.ref = nil
    }

    /// Requests this source to become active layout.
    func selectAsCurrent() -> OSStatus {
        guard let ref else { return OSStatus(paramErr) }
        return TISSelectInputSource(ref)
    }

    /// Extracts `kTISPropertyUnicodeKeyLayoutData` for keycode-to-unicode encoding.
    func unicodeKeyLayoutData() -> Data? {
        guard let ref,
              let ptr = TISGetInputSourceProperty(ref, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
        return Data(referencing: data)
    }

    /// Reads a string property from input-source metadata.
    private static func string(_ ref: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(ref, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// Reads a boolean property from input-source metadata.
    private static func bool(_ ref: TISInputSource, _ key: CFString) -> Bool {
        guard let ptr = TISGetInputSourceProperty(ref, key) else { return false }
        let value = Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }

    /// Returns first preferred language code advertised by this source.
    private static func firstLanguage(_ ref: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(ref, kTISPropertyInputSourceLanguages) else { return nil }
        let array = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String]
        return array?.first
    }
}
