import Foundation
import TabCountCore

struct CountTabsCSVImporter {
    func samples(from url: URL) throws -> [TabSample] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents
            .split(separator: "\n")
            .dropFirst()
            .compactMap(parseLine)
    }

    private func parseLine(_ line: Substring) -> TabSample? {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count == 3,
              let recordedAt = Self.dateFormatter.date(from: String(fields[0])),
              let windows = Int(fields[1]),
              let tabs = Int(fields[2]) else {
            return nil
        }

        return TabSample(recordedAt: recordedAt, windows: windows, tabs: tabs)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'PT'"
        return formatter
    }()
}
