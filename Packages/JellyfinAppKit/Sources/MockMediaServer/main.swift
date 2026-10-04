import Foundation
import JellyfinMocks

// Serves a folder of test clips (+ manifest.json) with HTTP Range support on
// the LAN, for an app on a real Apple TV launched with `-mockMediaURL`.
//   swift run mock-media-server <dir> [port]
let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: mock-media-server <dir> [port]"); exit(2) }
let directory = URL(filePath: args[1], directoryHint: .isDirectory)
let port = args.count > 2 ? UInt16(args[2]) ?? 8098 : 8098
let server = MockMedia.fileServer(directory: directory)
do {
    _ = try server.start(port: port)
    print("serving \(directory.path()) on port \(server.port)")
} catch {
    print("failed to start: \(error)"); exit(1)
}
dispatchMain()
