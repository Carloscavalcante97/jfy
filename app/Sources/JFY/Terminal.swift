import AppKit
import SwiftTerm
import SwiftUI

/// O jfy (menu e abas do tmux) num terminal dentro da janela. Quem guarda as sessões é o tmux: fechar o app
/// não mata task nenhuma, e abrir de novo volta para o mesmo menu.
final class TerminalHost: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 960, height: 640))
    @Published var encerrado = false

    override init() {
        super.init()
        view.processDelegate = self
        // JFY Mono vem dentro do app (ATSApplicationFontsPath no Info.plist): os ícones dos temas aparecem sem instalar nada
        view.font = NSFont(name: "JFYMono-Regular", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.nativeBackgroundColor = NSColor(srgbRed: 10 / 255, green: 14 / 255, blue: 45 / 255, alpha: 1)  // Midnight Blue #0A0E2D
        view.nativeForegroundColor = NSColor(white: 0.9, alpha: 1)
        view.optionAsMetaKey = true
        iniciar()
    }

    func iniciar() {
        encerrado = false
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "pt_BR.UTF-8"
        // o jfy grava este app como o "terminal" dele: "Abrir o jfy" e o clique nas notificações trazem o app
        env["__CFBundleIdentifier"] = Bundle.main.bundleIdentifier ?? env["__CFBundleIdentifier"]
        // shell de login interativo: pega o PATH do ~/.zprofile e do ~/.zshrc (claude, tmux, brew)
        view.startProcess(executable: "/bin/zsh", args: ["-lic", "exec \"$0\"", JFY.script],
                          environment: env.map { "\($0.key)=\($0.value)" })
        focar()
    }

    func focar() {
        DispatchQueue.main.async { self.view.window?.makeFirstResponder(self.view) }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { self.encerrado = true }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}

struct TerminalTela: View {
    @ObservedObject var host: TerminalHost

    var body: some View {
        ZStack {
            Color(nsColor: host.view.nativeBackgroundColor)
            Representavel(host: host).padding(8)
            if host.encerrado {
                VStack(spacing: 12) {
                    Text("O jfy fechou. As tasks que estavam rodando continuam no tmux.")
                        .foregroundStyle(.white.opacity(0.85))
                    Button("Abrir o jfy de novo") { host.iniciar() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear { host.focar() }
    }

    private struct Representavel: NSViewRepresentable {
        let host: TerminalHost
        func makeNSView(context: Context) -> LocalProcessTerminalView { host.view }
        func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}
    }
}

/// As abas do tmux do jfy (o menu e uma por task, revisão, PR…), para a barra lateral listar embaixo de "jfy". Pergunta
/// ao tmux a cada 3 s, direto, sem rodar o jfy.
final class AbasTmux: ObservableObject {
    struct Aba: Identifiable, Equatable {
        let id, nome: String  // id = o da janela no tmux (@5)
        let ativa, sino: Bool  // sino: o Claude daquela aba pediu atenção
    }

    @Published private(set) var itens: [Aba] = []
    private var timer: Timer?

    init() {
        ler()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.ler() }
    }

    func ler() {
        DispatchQueue.global(qos: .utility).async {
            // separador de texto comum: sem locale UTF-8 o tmux troca o TAB (e os acentos) por "_"
            let saida = Self.tmux(["list-windows", "-t", "jfy", "-F", "#{window_id}|~|#{window_name}|~|#{window_active}|~|#{window_bell_flag}"])
            let lista = saida.split(separator: "\n").compactMap { l -> Aba? in
                let c = l.components(separatedBy: "|~|")
                return c.count == 4 ? Aba(id: c[0], nome: c[1], ativa: c[2] == "1", sino: c[3] == "1") : nil
            }
            DispatchQueue.main.async { if lista != self.itens { self.itens = lista } }
        }
    }

    /// Leva o terminal do jfy para a aba (vale para todos os terminais ligados ao jfy, como no Ctrl-b + número).
    func ir(_ a: Aba) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.tmux(["select-window", "-t", a.id])
            DispatchQueue.main.async { self.ler() }
        }
    }

    /// Vai para uma janela (@n) ou um painel (%n) do tmux do jfy: o destino das notificações do Claude.
    func irPara(_ alvo: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.tmux(["select-window", "-t", alvo])
            DispatchQueue.main.async { self.ler() }
        }
    }

    /// Renomeia a aba. O jfy acha as abas pela marca @jfy, não pelo nome; só o "menu" é pelo nome (por isso ele não
    /// muda, e nenhuma outra vira "menu").
    func renomear(_ a: Aba, _ nome: String) {
        let n = nome.trimmingCharacters(in: .whitespaces)
        guard a.nome != "menu", !n.isEmpty, n != "menu" else { return }
        mexer([["rename-window", "-t", a.id, n.replacingOccurrences(of: "#", with: "##")]])  // o tmux expande formatos no nome
    }

    /// Fecha a aba e o que roda nela (o Claude daquela task, por exemplo). O menu não fecha.
    func fechar(_ a: Aba) {
        guard a.nome != "menu" else { return }
        mexer([["kill-window", "-t", a.id]])
    }

    /// Arrastar na barra lateral: troca as janelas de lugar no tmux até a ordem ficar a da lista (o menu fica em
    /// primeiro: o jfy recria ele no índice 0 se sumir).
    func mover(_ origem: IndexSet, _ destino: Int) {
        var nova = itens
        nova.move(fromOffsets: origem, toOffset: destino)
        if let m = nova.firstIndex(where: { $0.nome == "menu" }) { nova.insert(nova.remove(at: m), at: 0) }
        var atual = itens.map(\.id), trocas: [[String]] = []
        for (i, a) in nova.enumerated() where atual[i] != a.id {
            let j = atual.firstIndex(of: a.id)!
            trocas.append(["swap-window", "-d", "-s", a.id, "-t", atual[i]])
            atual.swapAt(i, j)
        }
        // as trocas em cadeia mudam a aba ativa (com ou sem -d): no fim, volta para a que estava
        if let ativa = itens.first(where: \.ativa), !trocas.isEmpty { trocas.append(["select-window", "-t", ativa.id]) }
        itens = nova  // já mostra na ordem nova; a leitura confirma
        mexer(trocas)
    }

    private func mexer(_ comandos: [[String]]) {
        DispatchQueue.global(qos: .userInitiated).async {
            for c in comandos { _ = Self.tmux(c) }
            DispatchQueue.main.async { self.ler() }
        }
    }

    private static func tmux(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["tmux", "-L", "jfy"] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["LC_ALL"] = "en_US.UTF-8"  // aberto pelo Finder, o app não tem LANG: sem ele o tmux estraga os acentos
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let dados = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: dados, as: UTF8.self)
    }
}
