import Foundation

public struct HistoryStore: Sendable {
    public let directoryURL: URL
    public let historyURL: URL
    public let latestURL: URL
    public let sampleInterval: TimeInterval

    public init(
        directoryURL: URL = HistoryStore.defaultDirectoryURL(),
        sampleInterval: TimeInterval = 300
    ) {
        self.directoryURL = directoryURL
        self.historyURL = directoryURL.appendingPathComponent("history.jsonl")
        self.latestURL = directoryURL.appendingPathComponent("latest.json")
        self.sampleInterval = sampleInterval
    }

    public static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TabCount", isDirectory: true)
    }

    @discardableResult
    public func record(_ sample: TabSample) throws -> Bool {
        try ensureDirectoryExists()
        try writeLatest(sample)

        if let lastSample = try loadLastSample(),
           bucket(for: lastSample.recordedAt) == bucket(for: sample.recordedAt) {
            try replaceLastSample(with: sample)
            return false
        }

        let line = try encode(sample) + Data("\n".utf8)
        if FileManager.default.fileExists(atPath: historyURL.path) {
            let handle = try FileHandle(forWritingTo: historyURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: historyURL, options: .atomic)
        }

        return true
    }

    public func loadLatestSample() throws -> TabSample? {
        guard FileManager.default.fileExists(atPath: latestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: latestURL)
        return try decoder.decode(TabSample.self, from: data)
    }

    public func loadSamples(since startDate: Date? = nil) throws -> [TabSample] {
        guard FileManager.default.fileExists(atPath: historyURL.path) else {
            return []
        }

        let data = try Data(contentsOf: historyURL)
        guard let contents = String(data: data, encoding: .utf8) else {
            return []
        }

        return contents
            .split(separator: "\n")
            .compactMap { line in
                guard let lineData = String(line).data(using: .utf8),
                      let sample = try? decoder.decode(TabSample.self, from: lineData) else {
                    return nil
                }
                if let startDate, sample.recordedAt < startDate {
                    return nil
                }
                return sample
            }
    }

    public func loadLastSample() throws -> TabSample? {
        guard FileManager.default.fileExists(atPath: historyURL.path) else {
            return nil
        }

        let handle = try FileHandle(forReadingFrom: historyURL)
        let fileSize = try handle.seekToEnd()
        let readSize = min(fileSize, 16 * 1024)
        try handle.seek(toOffset: fileSize - readSize)
        let data = try handle.readToEnd() ?? Data()
        try handle.close()

        guard let contents = String(data: data, encoding: .utf8) else {
            return nil
        }

        for line in contents.split(separator: "\n").reversed() {
            guard let lineData = String(line).data(using: .utf8),
                  let sample = try? decoder.decode(TabSample.self, from: lineData) else {
                continue
            }
            return sample
        }

        return nil
    }

    public func merge(_ samples: [TabSample]) throws {
        try ensureDirectoryExists()

        let existingSamples = try loadSamples()
        var samplesByBucket: [Int: TabSample] = [:]

        for sample in existingSamples + samples {
            let sampleBucket = bucket(for: sample.recordedAt)
            if let existingSample = samplesByBucket[sampleBucket],
               existingSample.recordedAt > sample.recordedAt {
                continue
            }
            samplesByBucket[sampleBucket] = sample
        }

        let mergedSamples = samplesByBucket.values.sorted { $0.recordedAt < $1.recordedAt }
        let historyContents = try mergedSamples
            .map { sample in
                String(data: try encode(sample), encoding: .utf8) ?? ""
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        if historyContents.isEmpty {
            try Data().write(to: historyURL, options: .atomic)
        } else {
            try Data((historyContents + "\n").utf8).write(to: historyURL, options: .atomic)
        }

        let latestSample = try loadLatestSample()
        let newestHistorySample = mergedSamples.max { $0.recordedAt < $1.recordedAt }
        let newestSample = [latestSample, newestHistorySample]
            .compactMap { $0 }
            .max { $0.recordedAt < $1.recordedAt }

        if let newestSample {
            try writeLatest(newestSample)
        }
    }

    public func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func writeLatest(_ sample: TabSample) throws {
        let data = try encode(sample)
        try data.write(to: latestURL, options: .atomic)
    }

    private func replaceLastSample(with sample: TabSample) throws {
        guard FileManager.default.fileExists(atPath: historyURL.path) else {
            return
        }

        let data = try Data(contentsOf: historyURL)
        guard let contents = String(data: data, encoding: .utf8) else {
            return
        }

        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let lastLineIndex = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return
        }

        lines[lastLineIndex] = String(data: try encode(sample), encoding: .utf8) ?? lines[lastLineIndex]
        let updatedContents = lines.joined(separator: "\n")
        try Data(updatedContents.utf8).write(to: historyURL, options: .atomic)
    }

    private func encode(_ sample: TabSample) throws -> Data {
        try encoder.encode(sample)
    }

    private func bucket(for date: Date) -> Int {
        Int(floor(date.timeIntervalSince1970 / sampleInterval))
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
