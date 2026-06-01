import AppKit
import ApplicationServices
import Foundation
import TabCountCore

struct ChromeCounter {
    func count() throws -> TabSample {
        let chromeCount = try countFromChrome()
        let accessibilityCount: ChromeCount?

        do {
            accessibilityCount = try countFromAccessibility()
        } catch {
            if chromeCount.isSuspiciousSingleWindowSingleTab {
                throw ChromeCounterError.accessibilityRequiredForSuspiciousResult(String(describing: error))
            }
            accessibilityCount = nil
        }

        let windows = max(chromeCount.windows, accessibilityCount?.windows ?? chromeCount.windows)
        let tabs = max(chromeCount.tabs, accessibilityCount?.tabs ?? chromeCount.tabs)

        return TabSample(recordedAt: Date(), windows: windows, tabs: tabs)
    }

    private func countFromChrome() throws -> ChromeCount {
        let script = """
        if application "Google Chrome" is not running then
            return "0,0"
        end if

        tell application "Google Chrome"
            set windowCount to count of windows
            set tabCount to 0

            repeat with chromeWindow in windows
                set tabCount to tabCount + (count of tabs of chromeWindow)
            end repeat

            return (windowCount as text) & "," & (tabCount as text)
        end tell
        """

        let value = try run(script)
        let parts = value.split(separator: ",")
        guard parts.count == 2,
              let windows = Int(parts[0]),
              let tabs = Int(parts[1]) else {
            throw ChromeCounterError.invalidResult(value)
        }

        return ChromeCount(windows: windows, tabs: tabs)
    }

    private func countFromAccessibility() throws -> ChromeCount {
        guard let chrome = NSWorkspace.shared.runningApplications.first(where: { application in
            application.bundleIdentifier == "com.google.Chrome"
        }) else {
            return ChromeCount(windows: 0, tabs: 0)
        }

        guard AXIsProcessTrusted() else {
            throw ChromeCounterError.accessibilityNotTrusted
        }

        let applicationElement = AXUIElementCreateApplication(chrome.processIdentifier)
        var windowsValue: CFTypeRef?
        let windowsError = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        guard windowsError == .success,
              let windows = windowsValue as? [AXUIElement] else {
            throw ChromeCounterError.accessibilityFailed(windowsError.rawValue)
        }

        let browserWindows = windows.filter { window in
            stringAttribute(kAXSubroleAttribute, from: window) == kAXStandardWindowSubrole
                && (stringAttribute(kAXTitleAttribute, from: window)?.contains("Google Chrome") ?? false)
        }

        let tabs = browserWindows.reduce(0) { total, window in
            total + max(1, tabCount(in: window))
        }
        return ChromeCount(windows: browserWindows.count, tabs: tabs)
    }

    private func run(_ source: String) throws -> String {
        var errorInfo: NSDictionary?
        guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo) else {
            throw ChromeCounterError.appleScriptFailed(errorInfo?[NSAppleScript.errorMessage] as? String)
        }

        guard let value = descriptor.stringValue else {
            throw ChromeCounterError.invalidResult(nil)
        }

        return value
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return nil
        }

        return value as? String
    }

    private func tabCount(in window: AXUIElement) -> Int {
        let tabGroups = descendants(of: window).filter { element in
            stringAttribute(kAXRoleAttribute, from: element) == "AXTabGroup"
        }

        return tabGroups
            .map { countDescendants(withRole: "AXRadioButton", in: $0) }
            .max() ?? 0
    }

    private func countDescendants(withRole role: String, in root: AXUIElement) -> Int {
        descendants(of: root).filter { element in
            stringAttribute(kAXRoleAttribute, from: element) == role
        }.count
    }

    private func descendants(of root: AXUIElement) -> [AXUIElement] {
        var descendants: [AXUIElement] = []
        var stack = children(of: root)

        while let element = stack.popLast() {
            descendants.append(element)

            let role = stringAttribute(kAXRoleAttribute, from: element)
            if role == "AXWebArea" {
                continue
            }

            stack.append(contentsOf: children(of: element))
        }

        return descendants
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard error == .success else {
            return []
        }

        return value as? [AXUIElement] ?? []
    }
}

private struct ChromeCount {
    let windows: Int
    let tabs: Int

    var isSuspiciousSingleWindowSingleTab: Bool {
        windows == 1 && tabs == 1
    }
}

enum ChromeCounterError: Error, CustomStringConvertible {
    case appleScriptFailed(String?)
    case accessibilityFailed(AXError.RawValue)
    case accessibilityRequiredForSuspiciousResult(String)
    case accessibilityNotTrusted
    case invalidResult(String?)

    var description: String {
        switch self {
        case let .appleScriptFailed(message):
            if let message {
                return message
            }
            return "AppleScript failed while counting Chrome tabs."
        case let .accessibilityFailed(code):
            return "Accessibility failed while counting Chrome tabs: AXError \(code)."
        case let .accessibilityRequiredForSuspiciousResult(message):
            return "Chrome reported 1 window and 1 tab, which is a known undercount. Accessibility is required for the real count. \(message)"
        case .accessibilityNotTrusted:
            return "Accessibility is not enabled for tabcount."
        case let .invalidResult(value):
            return "Chrome counter returned an invalid result: \(value ?? "nil")"
        }
    }
}
