import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("failed: \(message)\n", stderr)
        Foundation.exit(1)
    }
}

@main
struct HistoryStoreSmokeTest {
    static func main() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = HistoryStore(directoryURL: directoryURL, sampleInterval: 300)

        let first = TabSample(recordedAt: Date(timeIntervalSince1970: 100), windows: 1, tabs: 10)
        let second = TabSample(recordedAt: Date(timeIntervalSince1970: 200), windows: 2, tabs: 20)
        let third = TabSample(recordedAt: Date(timeIntervalSince1970: 301), windows: 3, tabs: 30)

        let firstAppended = try store.record(first)
        let secondAppended = try store.record(second)
        let thirdAppended = try store.record(third)
        let latestSample = try store.loadLatestSample()
        let allSamples = try store.loadSamples()
        let filteredSamples = try store.loadSamples(since: Date(timeIntervalSince1970: 300))

        expect(firstAppended, "first sample should append")
        expect(!secondAppended, "same-bucket sample should update latest but skip append")
        expect(thirdAppended, "next-bucket sample should append")
        expect(latestSample == third, "latest sample should be the most recent record")
        expect(allSamples.map(\.tabs) == [20, 30], "history should contain the newest line per bucket")
        expect(filteredSamples == [third], "since filter should return later samples")

        let imported = TabSample(recordedAt: Date(timeIntervalSince1970: 900), windows: 9, tabs: 90)
        try store.merge([imported])
        let mergedSamples = try store.loadSamples()
        let mergedLatestSample = try store.loadLatestSample()
        expect(mergedSamples.map(\.tabs) == [20, 30, 90], "merge should preserve existing samples and append imported history")
        expect(mergedLatestSample == imported, "merge should keep latest aligned with newest history")

        try? FileManager.default.removeItem(at: directoryURL)
        print("history store smoke test passed")
    }
}
