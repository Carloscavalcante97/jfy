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

extension JFY {
    /// Roda um comando do app e decodifica o JSON da saída. O segundo valor é a mensagem para mostrar: o erro
    /// (stderr do jfy, ex.: o Journify recusou) ou um aviso que veio junto com o resultado.
    static func ler<T: Decodable>(_ args: [String]) async -> (T?, String?) {
        let r = await rodar(args)
        let msg = r.erro.trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.status == 0 else { return (nil, msg.isEmpty ? "jfy \(args[0]) falhou (código \(r.status))" : msg) }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return (try d.decode(T.self, from: Data(r.saida.utf8)), msg.isEmpty ? nil : msg)
        } catch {
            return (nil, "Não entendi a resposta do jfy \(args[0]): \(error)")
        }
    }

    /// Roda um comando que só muda algo. Devolve nil se deu certo, senão a mensagem de erro.
    static func fazer(_ args: [String]) async -> String? {
        let r = await rodar(args)
        let msg = r.erro.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.status == 0 ? nil : msg.isEmpty ? "jfy \(args[0]) falhou (código \(r.status))" : msg
    }
}

extension Color {
    /// "#rrggbb" do jfy (a cor do projeto nas abas do tmux, a do tema); sem cor, o cinza secundário.
    init(hex: String?) {
        guard let hex, hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else {
            self = .secondary
            return
        }
        self.init(red: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255)
    }
}

enum Tela: String, CaseIterable, Identifiable {
    case terminal = "jfy", projetos = "Projetos", github = "GitHub", horas = "Horas", reunioes = "Reuniões", emails = "Emails",
         portas = "Portas", uso = "Uso da IA",
         chat = "Chat", notificacoes = "Notificações", temas = "Temas"
    var id: Self { self }
    var icone: String {
        switch self {
        case .terminal: "terminal"
        case .projetos: "folder"
        case .github: "arrow.triangle.branch"
        case .horas: "clock"
        case .reunioes: "calendar"
        case .emails: "envelope"
        case .portas: "network"
        case .uso: "chart.bar.xaxis"
        case .chat: "bubble.left.and.bubble.right"
        case .notificacoes: "bell"
        case .temas: "paintpalette"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // fechar a janela não fecha o app: o jfy segue rodando em segundo plano (o terminal e as notificações são do app,
    // não da janela) e volta igual pelo ícone do Dock ou por Janela > jfy. ⌘Q sai de verdade; as tasks ficam no tmux
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct JFYApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var terminal = TerminalHost()
    @StateObject private var notificacoes = Notificacoes()
    @StateObject private var caixa = CaixaEmail()
    @StateObject private var portas = PortasAbertas()

    var body: some Scene {
        Window("jfy", id: "jfy") { Principal(terminal: terminal, notificacoes: notificacoes, caixa: caixa, portas: portas) }
            .defaultSize(width: 1200, height: 780)
    }
}

struct Principal: View {
    @ObservedObject var terminal: TerminalHost
    @ObservedObject var notificacoes: Notificacoes
    @ObservedObject var caixa: CaixaEmail
    @ObservedObject var portas: PortasAbertas
    @State private var tela: Tela? = .terminal

    var body: some View {
        NavigationSplitView {
            List(Tela.allCases, selection: $tela) { t in
                Label(t.rawValue, systemImage: t.icone).tag(t)
                    .badge(t == .notificacoes ? notificacoes.novas : t == .emails ? caixa.naoLidos : t == .portas ? portas.itens.count : 0)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            // todas ficam montadas: trocar de tela não reinicia o terminal nem perde a conversa
            ZStack {
                mostrar(.terminal) { TerminalTela(host: terminal) }
                mostrar(.projetos) { ProjetosTela(ativa: tela == .projetos, irParaJFY: { tela = .terminal }) }
                mostrar(.github) { GithubTela(ativa: tela == .github, irParaJFY: { tela = .terminal }) }
                mostrar(.horas) { HorasTela(ativa: tela == .horas, irParaJFY: { tela = .terminal }) }
                mostrar(.reunioes) { ReunioesTela(ativa: tela == .reunioes, irParaJFY: { tela = .terminal }) }
                mostrar(.emails) { EmailsTela(caixa: caixa, ativa: tela == .emails) }
                mostrar(.portas) { PortasTela(portas: portas, ativa: tela == .portas) }
                mostrar(.uso) { UsoTela() }
                mostrar(.chat) { ChatTela(ativa: tela == .chat) }
                mostrar(.notificacoes) {
                    NotificacoesTela(notificacoes: notificacoes, ativa: tela == .notificacoes, irParaJFY: { tela = .terminal })
                }
                mostrar(.temas) { TemasTela(ativa: tela == .temas) }
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

    /// ⌘1 a ⌘9 para as nove primeiras da barra lateral (não existe ⌘10)
    private var atalhos: some View {
        ForEach(Array(Tela.allCases.prefix(9).enumerated()), id: \.element) { i, t in
            Button("") { tela = t }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command).hidden()
        }
    }
}
