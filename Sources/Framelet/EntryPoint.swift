import AppKit

@main
enum EntryPoint {
    @MainActor
    static func main() async {
        if CommandLine.arguments.contains("--self-test") {
            do {
                try await SelfChecks.run()
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
                exit(EXIT_FAILURE)
            }
        } else {
            FrameletApp.main()
        }
    }
}