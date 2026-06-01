import ApplicationServices
import AppKit
import Foundation

enum PrivacyPermissions {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}
