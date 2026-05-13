import ApplicationServices

/// Centralizes the checked CF-to-AXUIElement bridge used by Accessibility APIs.
enum AXElementBridge {
    /// Returns an AX element only after verifying the Core Foundation type ID.
    static func element(from value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // AXUIElement is a CFType-backed reference. The type ID check above keeps
        // the unsafe cast contained and avoids repeating it at call sites.
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}
