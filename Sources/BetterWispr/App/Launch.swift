import BetterWisprCore

@main
enum Launch {
    @MainActor static func main() {
        if CommandLine.arguments.dropFirst().contains("--mcp") { return MCPServer().serveStandardIO() }
        BetterWisprApp.main()
    }
}
