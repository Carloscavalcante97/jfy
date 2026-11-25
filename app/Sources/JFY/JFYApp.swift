import AppKit
import SwiftUI

/// O jfy em Python é o motor; o app só chama ele. O caminho vem do Info.plist (o build.sh grava).
enum JFY {
    static let script = Bundle.main.object(forInfoDictionaryKey: "JFYScript") as? String
        ?? NSHomeDirectory() + "/jfy/jfy"

    /// Roda `jfy <args>` fora da thread principal e devolve o código de saída, a saída e o erro.
    static func rodar(_ args: [String]) async -> (status: Int32, saida: String, erro: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: script)
                p.arguments = args
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
                p.environment = env
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do {
                    try p.run()
                } catch {
                    return cont.resume(returning: (-1, "", "Não consegui rodar \(script): \(error.localizedDescription)"))
                }
                // ponytail: lê a saída toda antes do erro; o stderr do jfy é curto, então o pipe não enche
                let o = out.fileHandleForReading.readDataToEndOfFile()
                let e = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (p.terminationStatus, String(decoding: o, as: UTF8.self),
                                        String(decoding: e, as: UTF8.self)))
            }
        }
    }
}

enum Tela: String, CaseIterable, Identifiable {
    case terminal = "jfy", uso = "Uso da IA", chat = "Chat"
    var id: Self { self }
    var icone: String {
        switch self {
        case .terminal: "terminal"
        case .uso: "chart.bar.xaxis"
        case .chat: "bubble.left.and.bubble.right"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // fechar a janela fecha o app; as tasks continuam no tmux e voltam ao abrir de novo
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct JFYApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("jfy", id: "jfy") { Principal() }
            .defaultSize(width: 1200, height: 780)
    }
}

struct Principal: View {
    @State private var tela: Tela? = .terminal
    @StateObject private var terminal = TerminalHost()

    var body: some View {
        NavigationSplitView {
            List(Tela.allCases, selection: $tela) { t in
                Label(t.rawValue, systemImage: t.icone).tag(t)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            // as três ficam montadas: trocar de tela não reinicia o terminal nem perde a conversa
            ZStack {
                mostrar(.terminal) { TerminalTela(host: terminal) }
                mostrar(.uso) { UsoTela() }
                mostrar(.chat) { ChatTela() }
            }
        }
        .background { atalhos }
        .onChange(of: tela) { _, nova in
            if nova == .terminal { terminal.focar() }
        }
    }

    private func mostrar(_ t: Tela, @ViewBuilder _ conteudo: () -> some View) -> some View {
        let ativa = (tela ?? .terminal) == t
        return conteudo().opacity(ativa ? 1 : 0).allowsHitTesting(ativa).accessibilityHidden(!ativa)
    }

    /// ⌘1 jfy, ⌘2 uso da IA, ⌘3 chat
    private var atalhos: some View {
        ForEach(Array(Tela.allCases.enumerated()), id: \.element) { i, t in
            Button("") { tela = t }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command).hidden()
        }
    }
}
