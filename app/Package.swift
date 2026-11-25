// swift-tools-version:5.9
// App do jfy para o Mac: janela com o jfy num terminal embutido, uso da IA e chat do Journify.
// Monta com ./build.sh (gera JFY.app). O jfy em Python continua sendo o motor: o app chama ./jfy.
import PackageDescription

let package = Package(
    name: "JFY",
    platforms: [.macOS("15.0")],
    dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")],
    targets: [.executableTarget(name: "JFY", dependencies: ["SwiftTerm"], path: "Sources/JFY")]
)
