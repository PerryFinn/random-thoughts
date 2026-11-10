import AppKit

@main
struct RandomThoughtsApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppLifecycleDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
