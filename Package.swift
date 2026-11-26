// swift-tools-version: 5.9
import PackageDescription
import Foundation
let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().path

let package = Package(
    name: "WaveStudio",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WaveStudio", targets: ["WaveStudio"])],
    targets: [
         .systemLibrary(name:"CLame",path:"Sources/CLame"),
        .target(name:"AudioCore",dependencies:["CLame"],linkerSettings:[.unsafeFlags(["-L\(root)/ThirdParty/lame/install/lib","-Xlinker","-rpath","-Xlinker","@executable_path/../Frameworks","-Xlinker","-rpath","-Xlinker","\(root)/ThirdParty/lame/install/lib"])]),
        .executableTarget(name: "WaveStudio", dependencies: ["AudioCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["AudioCore"], path: "Tests/AudioCoreTests"),
        .executableTarget(name: "WorkflowChecks", dependencies: ["AudioCore"], path: "Tests/EditorWorkflowChecks")
    ]
)
