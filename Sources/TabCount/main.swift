import AppKit
import TabCountCore

let store = HistoryStore()
let counter = ChromeCounter()
let cli = CommandLineInterface(counter: counter, store: store)

switch cli.run(arguments: CommandLine.arguments) {
case .runApp:
    let app = NSApplication.shared
    let delegate = MenuBarApp()
    app.delegate = delegate
    app.run()
case let .exit(code):
    Foundation.exit(code)
}
