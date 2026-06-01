import Foundation

public struct TabSample: Codable, Equatable, Sendable {
    public let recordedAt: Date
    public let windows: Int
    public let tabs: Int

    public init(recordedAt: Date, windows: Int, tabs: Int) {
        self.recordedAt = recordedAt
        self.windows = windows
        self.tabs = tabs
    }
}
