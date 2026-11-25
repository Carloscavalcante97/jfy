import AppKit
import SwiftUI

/// O histórico do que o jfy avisou (reunião, email, o Claude, a jornada, o resumo das 7h). O notificar() do jfy grava
/// cada aviso em ~/.jfy/notificacoes.jsonl; o app lê o arquivo direto, sem rodar o jfy, e olha de novo a cada 10 s.
final class Notificacoes: ObservableObject {
    struct Item: Decodable, Identifiable {
        let ts: Double
        let titulo, texto: String
        let abrir, executar, app: String?
        var id: Double { ts }
        var tipo: (icone: String, nome: String) {
            titulo.hasPrefix("Reunião") ? ("calendar", "reunião") : titulo.hasPrefix("Email") ? ("envelope", "email")
                : titulo.hasPrefix("Claude") ? ("sparkles", "Claude") : ("flame", "jfy")
        }
    }

    static let arquivo = URL(fileURLWithPath: NSHomeDirectory() + "/.jfy/notificacoes.jsonl")
    @Published private(set) var itens: [Item] = [] { didSet { selo() } }
    /// Até onde você já viu; o que veio depois conta como novo na barra lateral e no ícone do Dock.
    @Published var vistoAte = UserDefaults.standard.double(forKey: "notificacoesVistoAte") {
        didSet {
            UserDefaults.standard.set(vistoAte, forKey: "notificacoesVistoAte")
            selo()
        }
    }
    private var lidoEm: Date?
    private var timer: Timer?

    var novas: Int { itens.prefix { $0.ts > vistoAte }.count }

    init() {
        ler()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.ler() }
    }

    func ler() {
        let mudou = (try? FileManager.default.attributesOfItem(atPath: Self.arquivo.path))?[.modificationDate] as? Date
        guard mudou != lidoEm else { return }  // arquivo igual: nada a fazer
        lidoEm = mudou
        let txt = (try? String(contentsOf: Self.arquivo, encoding: .utf8)) ?? ""
        let d = JSONDecoder()
        // ponytail: lê o arquivo todo quando ele muda; só as 300 últimas aparecem
        itens = txt.split(separator: "\n").suffix(300).compactMap { try? d.decode(Item.self, from: Data($0.utf8)) }.reversed()
    }

    /// O número de novas no ícone do Dock: com a janela fechada, é por ele que você vê que chegou algo.
    private func selo() { NSApp?.dockTile.badgeLabel = novas > 0 ? "\(novas)" : nil }

    func marcarLidas() { vistoAte = max(vistoAte, itens.first?.ts ?? 0) }

    func limpar() {
        try? Data().write(to: Self.arquivo)
        ler()
    }
}

struct NotificacoesTela: View {
    @ObservedObject var notificacoes: Notificacoes
    let ativa: Bool
    let irParaJFY: () -> Void
    @State private var destaqueAte: Double = .infinity  // o que era novo quando a aba abriu continua marcado enquanto ela está aberta
    @State private var confirmarLimpar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notificações").font(Souv.titulo(30))
                    Text("O que o jfy avisou: reuniões, emails, o Claude e a jornada. O clique faz o mesmo que na notificação.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Limpar") { confirmarLimpar = true }.disabled(notificacoes.itens.isEmpty)
            }
            if notificacoes.itens.isEmpty {
                Text("Nenhuma notificação ainda. As próximas que o jfy mandar aparecem aqui.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(porDia, id: \.0) { dia, itens in
                        Section(dia) { ForEach(itens) { linha($0) } }
                    }
                }
                .listStyle(.inset)
                .listaSouv(Souv.fundo)
            }
        }
        .padding(24)
        .onChange(of: ativa) { _, agora in
            if agora { destaqueAte = notificacoes.vistoAte }
            notificacoes.marcarLidas()  // ao abrir e ao sair da aba
        }
        .onChange(of: notificacoes.itens.first?.ts) { if ativa { notificacoes.marcarLidas() } }
        .confirmationDialog("Apagar o histórico de notificações?", isPresented: $confirmarLimpar) {
            Button("Apagar", role: .destructive) { notificacoes.limpar() }
        }
    }

    private var porDia: [(String, [Notificacoes.Item])] {
        var out: [(String, [Notificacoes.Item])] = []
        for it in notificacoes.itens {
            let d = Date(timeIntervalSince1970: it.ts)
            let nome = Calendar.current.isDateInToday(d) ? "Hoje" : Calendar.current.isDateInYesterday(d) ? "Ontem"
                : d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR")))
            if out.last?.0 == nome { out[out.count - 1].1.append(it) } else { out.append((nome, [it])) }
        }
        return out
    }

    private func linha(_ it: Notificacoes.Item) -> some View {
        let nova = it.ts > destaqueAte, acao = it.abrir != nil || it.executar != nil || it.app != nil
        return Button { clicar(it) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: it.tipo.icone).frame(width: 20).foregroundStyle(nova ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(it.titulo).fontWeight(nova ? .semibold : .regular)
                    Text(it.texto).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer()
                Text(Date(timeIntervalSince1970: it.ts).formatted(.dateTime.hour().minute())).font(.caption).foregroundStyle(.secondary)
                if nova { Circle().fill(Color.accentColor).frame(width: 8, height: 8).padding(.top, 4) }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!acao)
        .help(it.abrir != nil ? "Abrir o link" : it.executar != nil ? "Ir para o jfy" : "")
    }

    /// O mesmo clique da notificação: abre o link (a chamada da reunião) ou roda o comando do jfy (ir para a aba do
    /// Claude, abrir os emails) e traz o terminal.
    private func clicar(_ it: Notificacoes.Item) {
        if let app = it.app, let u = URL(string: "jfy://" + (app.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? app)) {
            NSWorkspace.shared.open(u)  // a aba certa do app, como na notificação
        } else if let a = it.abrir, let u = URL(string: a) {
            NSWorkspace.shared.open(u)
        } else if let cmd = it.executar {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", cmd]
            try? p.run()
            irParaJFY()
        }
    }
}
