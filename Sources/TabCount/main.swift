import AppKit
import TabCountCore

let store = HistoryStore()
let counter = ChromeCounter()
let cli = CommandLineInterface(counter: counter, store: store)

switch cli.run(arguments: CommandLine.arguments) {
case let .runApp(launchHidden):
    let app = NSApplication.shared
    let delegate = MenuBarApp(launchHidden: launchHidden)
    app.delegate = delegate
    app.run()
case let .exit(code):
    Foundation.exit(code)
}
