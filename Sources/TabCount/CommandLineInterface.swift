import Foundation
import TabCountCore

enum CommandLineResult {
    case runApp
    case exit(Int32)
}

struct CommandLineInterface {
    let counter: ChromeCounter
    let store: HistoryStore

    func run(arguments: [String]) -> CommandLineResult {
        let command = arguments.dropFirst().first

        switch command {
        case nil:
            return .runApp
        case "sample":
            return sample()
        case "print":
            return printCurrentCount()
        case "import-counttabs":
            return importCountTabs(arguments: arguments)
        case "paths":
            return printPaths()
        case "help", "--help", "-h":
            return printHelp()
        default:
            fputs("Unknown command: \(command ?? "")\n\n", stderr)
            _ = printHelp()
            return .exit(64)
        }
    }

    private func sample() -> CommandLineResult {
        do {
            let sample = try counter.count()
            let appended = try store.record(sample)
            print(format(sample) + (appended ? " recorded" : " latest"))
            return .exit(0)
        } catch {
            fputs("tabcount sample failed: \(error)\n", stderr)
            return .exit(1)
        }
    }

    private func printCurrentCount() -> CommandLineResult {
        do {
            print(format(try counter.count()))
            return .exit(0)
        } catch {
            fputs("tabcount print failed: \(error)\n", stderr)
            return .exit(1)
        }
    }

    private func importCountTabs(arguments: [String]) -> CommandLineResult {
        let path = arguments.dropFirst(2).first ?? "\(NSHomeDirectory())/counttabs_tracker.csv"
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)

        do {
            let samples = try CountTabsCSVImporter().samples(from: url)
            try store.merge(samples)
            print("Imported \(samples.count) samples from \(url.path)")
            print("History: \(store.historyURL.path)")
            return .exit(0)
        } catch {
            fputs("tabcount import-counttabs failed: \(error)\n", stderr)
            return .exit(1)
        }
    }

    private func printPaths() -> CommandLineResult {
        print("data: \(store.directoryURL.path)")
        print("history: \(store.historyURL.path)")
        print("latest: \(store.latestURL.path)")
        return .exit(0)
    }

    private func printHelp() -> CommandLineResult {
        print(
            """
            Usage:
              tabcount          Run the macOS menu bar app.
              tabcount sample   Count Chrome windows/tabs and append to the app history file.
              tabcount print    Print the current Chrome windows/tabs without writing history.
              tabcount import-counttabs [csv_path]
                                Import ~/counttabs_tracker.csv into TabCount history.
              tabcount paths    Print the app-owned data file paths.
            """
        )
        return .exit(0)
    }

    private func format(_ sample: TabSample) -> String {
        "\(sample.windows) windows, \(sample.tabs) tabs"
    }
}
