import AppKit

if CommandLine.arguments.contains("--probe") {
    let client = CodexClient()
    var finished = false
    var succeeded = false
    client.onChange = { snapshot, error in
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            print(String(decoding: data, as: UTF8.self))
            succeeded = true
        } else { fputs((error ?? "Unknown error") + "\n", stderr) }
        finished = true
    }
    client.start()
    let deadline = Date().addingTimeInterval(30)
    while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    client.stop()
    if !finished { fputs("额度接口读取超时\n", stderr) }
    exit(succeeded ? 0 : 1)
}

let app = NSApplication.shared
let delegate = OverlayController()
app.delegate = delegate
app.run()
