import Foundation

enum Config {
    static let debugLogging = false  // set to true to enable debug output in the terminal
}

func debugLog(_ message: String) {
    guard Config.debugLogging else { return }
    print(message)
}
