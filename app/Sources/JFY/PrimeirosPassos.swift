import AppKit
import SwiftUI
import UserNotifications

/// Os primeiros passos depois do login: um assistente que liga tudo o que o jfy usa, um passo de cada vez. Google (já
/// feito no login), Journify (obrigatório: sem ele o jfy não vê as tasks), GitHub, as pastas dos projetos e as
/// notificações (esses dá para pular). Quem já tem tudo ligado passa direto. Refazer: Configurações.
struct PrimeirosPassos: View {
    var automatico = true  // na primeira vez, quem já tem tudo ligado passa direto; ao refazer, não
    let concluir: () -> Void

    enum Passo: Int, CaseIterable {
        case google, journify, github, projetos, notificacoes, pronto
        var titulo: String {
            switch self {
            case .google: "Conta da Souv"
            case .journify: "Journify"
            case .github: "GitHub"
            case .projetos: "Seus projetos"
            case .notificacoes: "Notificações"
            case .pronto: "Tudo pronto"
            }
        }
        var obrigatorio: Bool { self == .google || self == .journify }
    }

    @State private var passo = Passo.google
    @State private var contas: ConfiguracoesTela.Contas?
    @State private var semPasta: [ProjetosTela.Projetos.Projeto] = []
    @State private var configurados = 0
    @State private var token = ""
    @State private var salvandoToken = false
    @State private var aviso: String?
    @State private var comando: ComandoTerminal?
    @State private var tituloComando = ""
    @State private var configurando: PedidoProjeto?
    @State private var notificacoes: UNAuthorizationStatus = .notDetermined

    var body: some View {
        HStack(spacing: 0) {
            trilha.frame(width: 260)
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                Text(passo.titulo).font(Souv.titulo(30)).foregroundStyle(Souv.texto)
                conteudo
                if let aviso { Label(aviso, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
                Spacer()
                rodape
            }
            .padding(36)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Souv.fundo)
        .toolbar(removing: .title)
        .task { await carregar(primeira: true) }
        .sheet(item: Binding(get: { comando.map { Caixa(c: $0) } }, set: { if $0 == nil { comando = nil } })) { caixa in
            VStack(alignment: .leading, spacing: 12) {
                Text(tituloComando).font(Souv.titulo(20))
                ComandoTerminalView(comando: caixa.c).frame(width: 720, height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack {
                    Text(caixa.c.terminou == nil ? "Siga o que aparece acima. Ao terminar, esta janela fecha sozinha." : "Terminou.")
                        .font(.caption).foregroundStyle(Souv.texto2)
                    Spacer()
                    Button("Fechar") { comando = nil; Task { await carregar() } }
                }
            }
            .padding(20)
            .background(Souv.fundo).identidadeSouv()
            .onChange(of: caixa.c.terminou) { if caixa.c.terminou != nil { comando = nil; Task { await carregar() } } }
        }
        .sheet(item: $configurando) { pedido in
            NovoProjeto(pedido: pedido, semPasta: semPasta, fechar: { configurando = nil },
                        salvou: { _ in configurando = nil; Task { await carregar() } })
                .identidadeSouv()
        }
    }

    private struct Caixa: Identifiable { let c: ComandoTerminal; var id: ObjectIdentifier { ObjectIdentifier(c) } }

    // ---------- a trilha dos passos ----------
    private var trilha: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let s = Souv.simbolo { Image(nsImage: s).resizable().foregroundStyle(Souv.destaque).frame(width: 30, height: 30) }
                Text("Primeiros passos").font(Souv.titulo(20)).foregroundStyle(Souv.texto)
            }
            .padding(.bottom, 26)
            ForEach(Passo.allCases, id: \.self) { p in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(feito(p) ? Color.green : p == passo ? Souv.primaria : Souv.superficie2).frame(width: 26, height: 26)
                        if feito(p) { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                        else { Text("\(p.rawValue + 1)").font(.caption.weight(.bold)).foregroundStyle(p == passo ? .white : Souv.texto2) }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.titulo).fontWeight(p == passo ? .semibold : .regular).foregroundStyle(p == passo ? Souv.texto : Souv.texto2)
                        if !p.obrigatorio && p != .pronto { Text("opcional").font(.caption2).foregroundStyle(Souv.texto2) }
                    }
                }
                .padding(.vertical, 9)
            }
            Spacer()
        }
        .padding(28)
        .background(Souv.superficie)
    }

    private func feito(_ p: Passo) -> Bool {
        switch p {
        case .google: contas?.google.conectado == true
        case .journify: contas?.journify.conectado == true && contas?.journify.erro == nil
        case .github: !(contas?.github.contas.isEmpty ?? true)
        case .projetos: semPasta.isEmpty && contas != nil
        case .notificacoes: notificacoes == .authorized || notificacoes == .provisional
        case .pronto: false
        }
    }

    // ---------- o passo atual ----------
    @ViewBuilder private var conteudo: some View {
        switch passo {
        case .google:
            explicacao("O login do jfy é a sua conta Google da Souv. Ela também liga a Agenda e o Gmail.")
            if let c = contas?.google.conta { ok("Conectado como \(c)") }
        case .journify:
            explicacao("É pelo Journify que o jfy e o Claude veem e mexem nas suas tasks. No Journify, em Configurações › Conectar meu Claude, clique em Gerar token e cole aqui.")
            if feito(.journify), let n = contas?.journify.tasks { ok("Conectado: o jfy enxerga \(n) task\(n == 1 ? "" : "s") suas.") } else {
                Button { if let u = URL(string: (contas?.journify.site ?? "https://journify.souv.tech") + "/settings") { NSWorkspace.shared.open(u) } } label: {
                    Label("Abrir as Configurações do Journify", systemImage: "arrow.up.right.square")
                }
                HStack {
                    SecureField("Cole o token aqui", text: $token).campoSouv().onSubmit(salvarToken)
                    Button(salvandoToken ? "Conferindo…" : "Conferir e salvar", action: salvarToken).buttonStyle(.souvPrimario)
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || salvandoToken)
                }
                Text("O jfy testa o token no Journify antes de salvar. Ele fica no Claude Code (o MCP journify).")
                    .font(.caption).foregroundStyle(Souv.texto2)
            }
        case .github:
            explicacao("A aba GitHub (PRs, revisão, commits) usa o GitHub CLI, o gh, com a conta que você usa nos repositórios da Souv.")
            if let g = contas?.github {
                if !g.contas.isEmpty {
                    ok("Conectado: " + g.contas.joined(separator: ", ") + (g.ativa.map { " · em uso: \($0)" } ?? ""))
                    Button("Adicionar outra conta") { rodar("gh auth login -h github.com --web --git-protocol https", "Conectar o GitHub") }
                } else if g.instalado == false {
                    if g.brew == true {
                        Button { rodar("brew install gh", "Instalar o GitHub CLI") } label: { Label("Instalar o GitHub CLI", systemImage: "arrow.down.circle") }
                            .buttonStyle(.souvPrimario)
                    } else {
                        Text("Falta o Homebrew para instalar o gh. Instale em brew.sh e volte aqui.").foregroundStyle(.orange)
                        Link("Abrir brew.sh", destination: URL(string: "https://brew.sh")!).buttonStyle(.souvLink)
                    }
                } else {
                    Button { rodar("gh auth login -h github.com --web --git-protocol https", "Conectar o GitHub") } label: {
                        Label("Conectar o GitHub", systemImage: "person.badge.key")
                    }
                    .buttonStyle(.souvPrimario)
                    Text("Abre o login do gh aqui mesmo: copie o código que ele mostrar, aperte Enter e confirme no navegador.")
                        .font(.caption).foregroundStyle(Souv.texto2)
                }
            }
        case .projetos:
            explicacao("Cada projeto do Journify em que você tem task precisa da pasta do código neste Mac. É ela que liga as tasks, o GitHub, as portas e as horas ao projeto.")
            if semPasta.isEmpty {
                ok(configurados > 0 ? "Todos os seus projetos já têm pasta." : "Nenhum projeto seu sem pasta agora.")
            } else {
                ForEach(semPasta) { p in
                    HStack(spacing: 10) {
                        Circle().fill(Color(hex: p.cor)).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.exemplo.map { "ex.: \($0)" } ?? p.id).lineLimit(1)
                            Text("\(p.tasks) task\(p.tasks == 1 ? "" : "s") sua\(p.tasks == 1 ? "" : "s")").font(.caption).foregroundStyle(Souv.texto2)
                        }
                        Spacer()
                        Button("Escolher a pasta…") { configurando = PedidoProjeto(pid: p.id, nome: nil, pastas: []) }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Souv.superficie))
                }
            }
        case .notificacoes:
            explicacao("O jfy avisa quando o Claude precisa de você, quando chega email, um PR pede a sua revisão ou uma reunião vai começar. O clique leva direto para a aba certa.")
            if feito(.notificacoes) { ok("Notificações ligadas.") } else if notificacoes == .denied {
                Text("As notificações do jfy estão desligadas no macOS.").foregroundStyle(.orange)
                Button("Abrir Ajustes › Notificações") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            } else {
                Button { pedirNotificacoes() } label: { Label("Permitir notificações", systemImage: "bell.badge") }.buttonStyle(.souvPrimario)
            }
        case .pronto:
            explicacao("O jfy está pronto. Dá para mudar tudo isso depois em Configurações (contas, modelos do Claude e a sessão) e, nos projetos, pela aba Projetos.")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Passo.allCases.filter { $0 != .pronto }, id: \.self) { p in
                    Label(p.titulo, systemImage: feito(p) ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(feito(p) ? Color.green : Souv.texto2)
                }
            }
        }
    }

    private var rodape: some View {
        HStack {
            if passo != .google { Button("Voltar") { mover(-1) } }
            Spacer()
            if !passo.obrigatorio && passo != .pronto && !feito(passo) { Button("Pular por agora") { mover(1) } }
            if passo == .pronto {
                Button("Começar a usar o jfy", action: concluir).buttonStyle(.souvPrimario).keyboardShortcut(.defaultAction)
            } else {
                Button("Continuar") { mover(1) }.buttonStyle(.souvPrimario).keyboardShortcut(.defaultAction)
                    .disabled(passo.obrigatorio && !feito(passo))
            }
        }
    }

    // ---------- peças ----------
    private func explicacao(_ t: String) -> some View {
        Text(t).font(Souv.corpo(15)).foregroundStyle(Souv.texto2).fixedSize(horizontal: false, vertical: true)
    }

    private func ok(_ t: String) -> some View {
        Label(t, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(Souv.corpo(15))
    }

    private func mover(_ n: Int) {
        aviso = nil
        if let p = Passo(rawValue: passo.rawValue + n) { passo = p }
    }

    private func rodar(_ cmd: String, _ titulo: String) {
        tituloComando = titulo
        comando = ComandoTerminal(cmd)
    }

    private func salvarToken() {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Task {
            salvandoToken = true
            aviso = await JFY.fazer(["--journify-token"], entrada: t)
            salvandoToken = false
            if aviso == nil { token = "" }
            await carregar()
        }
    }

    private func pedirNotificacoes() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            Task { @MainActor in await lerNotificacoes() }
        }
    }

    private func lerNotificacoes() async {
        notificacoes = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func carregar(primeira: Bool = false) async {
        let (c, msg): (ConfiguracoesTela.Contas?, String?) = await JFY.ler(["--contas-json"])
        if let c { contas = c } else { aviso = msg }
        let (p, _): (ProjetosTela.Projetos?, String?) = await JFY.ler(["--projetos-json"])
        if let p {
            semPasta = p.projetos.filter { $0.nome == nil }
            configurados = p.projetos.count - semPasta.count
        }
        await lerNotificacoes()
        // quem já tem tudo ligado não precisa do assistente
        if primeira, automatico, feito(.journify), feito(.github), feito(.projetos) { concluir() }
    }
}
