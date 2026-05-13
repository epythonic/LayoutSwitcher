import Carbon.HIToolbox
import Foundation

/// Sendable metadata snapshot of an input source, without the live TIS reference.
struct InputSourceSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let localizedName: String
    let primaryLanguage: String?
    let isSelectable: Bool
    let isEnabled: Bool
    let isKeyboardLayout: Bool

    init(
        id: String,
        localizedName: String,
        primaryLanguage: String?,
        isSelectable: Bool,
        isEnabled: Bool,
        isKeyboardLayout: Bool
    ) {
        self.id = id
        self.localizedName = localizedName
        self.primaryLanguage = primaryLanguage
        self.isSelectable = isSelectable
        self.isEnabled = isEnabled
        self.isKeyboardLayout = isKeyboardLayout
    }

    init(source: InputSource) {
        self.id = source.id
        self.localizedName = source.localizedName
        self.primaryLanguage = source.primaryLanguage
        self.isSelectable = source.isSelectable
        self.isEnabled = source.isEnabled
        self.isKeyboardLayout = source.isKeyboardLayout
    }
}

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

    /// Immutable metadata snapshot safe to pass without the live TIS reference.
    var snapshot: InputSourceSnapshot {
        InputSourceSnapshot(source: self)
    }

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
              let data: CFData = Self.typedProperty(
                ref,
                kTISPropertyUnicodeKeyLayoutData,
                expectedTypeID: CFDataGetTypeID()
              ) else {
            return nil
        }
        return Data(referencing: data)
    }

    /// Reads a string property from input-source metadata.
    private static func string(_ ref: TISInputSource, _ key: CFString) -> String? {
        guard let value: CFString = typedProperty(ref, key, expectedTypeID: CFStringGetTypeID()) else {
            return nil
        }
        return value as String
    }

    /// Reads a boolean property from input-source metadata.
    private static func bool(_ ref: TISInputSource, _ key: CFString) -> Bool {
        guard let value: CFBoolean = typedProperty(ref, key, expectedTypeID: CFBooleanGetTypeID()) else {
            return false
        }
        return CFBooleanGetValue(value)
    }

    /// Returns first preferred language code advertised by this source.
    private static func firstLanguage(_ ref: TISInputSource) -> String? {
        guard let value: CFArray = typedProperty(
            ref,
            kTISPropertyInputSourceLanguages,
            expectedTypeID: CFArrayGetTypeID()
        ) else {
            return nil
        }
        let array = value as? [String]
        return array?.first
    }

    /// Reads a borrowed TIS property only when the runtime CoreFoundation type matches.
    private static func typedProperty<T: AnyObject>(
        _ ref: TISInputSource,
        _ key: CFString,
        expectedTypeID: CFTypeID
    ) -> T? {
        guard let ptr = TISGetInputSourceProperty(ref, key) else { return nil }
        let value = Unmanaged<CFTypeRef>.fromOpaque(ptr).takeUnretainedValue()
        guard CFGetTypeID(value) == expectedTypeID else { return nil }
        return value as? T
    }
}
