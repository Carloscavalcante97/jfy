import AppKit
import SwiftUI

/// GitHub dos projetos: os PRs abertos (com merge, aprovar, comentar e fechar) e o git de cada repositório (fetch, pull,
/// push). Quem fala com o GitHub é o jfy, pelo gh e pela conta ativa dele (--github-json, --pr-json, --pr-acao,
/// --repos-json, --repo-acao, --github-conta, --github-login).
struct GithubTela: View {
    let ativa: Bool
    @ObservedObject var nav: Navegacao
    let irParaJFY: () -> Void

    struct PR: Decodable, Hashable {
        let repo, titulo, url, atualizado: String
        let n, comentarios: Int
        let autor, projeto, cor: String?
        let rascunho: Bool
        var ref: String { "\(repo)#\(n)" }
    }

    struct Dados: Decodable {
        let conta: String?
        let contas: [String]
        let prs, revisar, meus: [PR]
    }

    struct Repo: Decodable, Identifiable {
        struct Commit: Decodable, Identifiable {
            let sha, msg, autor, quando: String
            var id: String { sha }
        }
        let pasta, nome, projeto: String
        let cor, remote, branch, upstream: String?
        let frente, atras, nMexidos: Int
        let mexidos: [String]
        let commits: [Commit]
        var id: String { pasta }
    }

    /// O que está escolhido na coluna da esquerda: as duas listas de PRs de todos os repos, ou um repositório.
    private enum Lado: Hashable { case revisar, meus, repo(String) }

    @State private var lado: Lado? = .meus
    @State private var pr: String?  // "dono/repo#n"
    @State private var dados: Dados?
    @State private var repos: [Repo] = []
    @State private var aviso: String?
    @State private var carregando = false
    @State private var pushEm: Repo?

    var body: some View {
        VStack(spacing: 0) {
            cabecalho.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            if let aviso { Label(aviso, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).padding(10).textSelection(.enabled) }
            if dados != nil && dados?.conta == nil {
                semConta
            } else {
                HStack(spacing: 0) {
                    colunaRepos.frame(width: 250)
                    Divider()
                    colunaMeio.frame(width: 380)
                    Divider()
                    if let pr, pr.hasPrefix("alteracoes|") {
                        CommitPainel(pasta: String(pr.dropFirst("alteracoes|".count)), mudou: { Task { await carregar() } }).id(pr)
                    } else if let pr, let i = pr.lastIndex(of: "#"), let n = Int(pr[pr.index(after: i)...]) {
                        PRDetalhe(repo: String(pr[..<i]), n: n, nav: nav, irParaJFY: irParaJFY,
                                  mudou: { Task { await carregar() } }).id(pr)
                    } else {
                        Text("Escolha um PR").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .task(id: ativa) { if ativa { await carregar() } }
        .onChange(of: nav.abrirPR) {
            guard let alvo = nav.abrirPR else { return }  // veio de uma task na aba Projetos
            pr = alvo
            let slug = String(alvo[..<(alvo.lastIndex(of: "#") ?? alvo.endIndex)])
            if let r = repos.first(where: { $0.remote == slug }) { lado = .repo(r.pasta) }
            nav.abrirPR = nil
        }
        .confirmationDialog("Dar push de \(pushEm?.branch ?? "") em \(pushEm?.nome ?? "")?",
                            isPresented: Binding(get: { pushEm != nil }, set: { if !$0 { pushEm = nil } })) {
            Button("Push") { if let r = pushEm { acaoRepo(r, "push") } }
        } message: {
            Text("Sobe os commits da branch atual para o origin (cria o upstream se faltar). Usa a conta ativa do gh.")
        }
    }

    // ---------- topo: conta ----------
    private var cabecalho: some View {
        HStack(spacing: 14) {
            Text("GitHub").font(.title2.bold())
            if let d = dados, let conta = d.conta {
                Menu {
                    ForEach(d.contas, id: \.self) { c in
                        Button { trocarConta(c) } label: { Text(c == conta ? "✓ \(c)" : c) }
                    }
                    Divider()
                    Button("Conectar outra conta…") { conectar() }
                } label: { Label(conta, systemImage: "person.crop.circle") }
                .menuStyle(.borderlessButton).fixedSize()
                .help("A conta ativa do gh: vale para o gh e o git deste Mac")
            }
            Spacer()
            if carregando { ProgressView().controlSize(.small) }
            Button { Task { await carregar() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Atualizar").disabled(carregando)
        }
    }

    private var semConta: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("Conecte sua conta do GitHub").font(.title3.weight(.semibold))
            Text("O login abre numa aba do jfy e pede para confirmar no navegador.").foregroundStyle(.secondary)
            Button("Conectar GitHub") { conectar() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ---------- esquerda: listas e repositórios ----------
    private var colunaRepos: some View {
        List(selection: $lado) {
            Label("Pedem sua revisão", systemImage: "eye").badge(dados?.revisar.count ?? 0).tag(Lado.revisar)
            Label("Seus PRs", systemImage: "person").badge(dados?.meus.count ?? 0).tag(Lado.meus)
            Section("Repositórios") {
                ForEach(repos) { r in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: r.cor)).frame(width: 8, height: 8)
                            Text(r.projeto).fontWeight(.medium).lineLimit(1)
                            Spacer()
                            let n = prsDo(r).count
                            if n > 0 { Text("\(n) PR").font(.caption2.bold()).padding(.horizontal, 5).background(Capsule().fill(Color.accentColor.opacity(0.2))) }
                        }
                        HStack(spacing: 6) {
                            Text(r.nome).lineLimit(1)
                            if r.frente > 0 { Text("↑\(r.frente)").foregroundStyle(.blue) }
                            if r.atras > 0 { Text("↓\(r.atras)").foregroundStyle(.orange) }
                            if r.nMexidos > 0 { Text("●\(r.nMexidos)").help("arquivos mexidos sem commit") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(Lado.repo(r.pasta))
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func prsDo(_ r: Repo) -> [PR] { (dados?.prs ?? []).filter { $0.repo == r.remote } }

    // ---------- meio: o repositório (git e PRs) ou uma lista de PRs ----------
    @ViewBuilder private var colunaMeio: some View {
        switch lado {
        case .revisar: listaPRs("Pedem sua revisão", dados?.revisar ?? [], repo: nil)
        case .meus, .none: listaPRs("Seus PRs", dados?.meus ?? [], repo: nil)
        case let .repo(pasta):
            if let r = repos.first(where: { $0.pasta == pasta }) { listaPRs(r.projeto, prsDo(r), repo: r) }
        }
    }

    private func listaPRs(_ titulo: String, _ lista: [PR], repo: Repo?) -> some View {
        VStack(spacing: 0) {
            if let r = repo { cartaoGit(r).padding(12); Divider() } else {
                Text(titulo).font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                Divider()
            }
            List(selection: $pr) {
                Section("Pull requests abertos (\(lista.count))") {
                    if lista.isEmpty { Text("nenhum").foregroundStyle(.secondary) }
                    ForEach(lista, id: \.ref) { linhaPR($0, comRepo: repo == nil).tag($0.ref) }
                }
                if let r = repo {
                    Section("Commit") {
                        Label(r.nMexidos > 0 ? "Alterações (\(r.nMexidos)): escolher arquivos e commitar" : "Nenhuma alteração para commitar",
                              systemImage: "checklist")
                            .foregroundStyle(r.nMexidos > 0 ? .primary : .secondary)
                            .tag("alteracoes|\(r.pasta)")
                    }
                    Section("Últimos commits em \(r.branch ?? "?")") {
                        ForEach(r.commits) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.msg).lineLimit(2)
                                Text("\(c.sha) · \(c.autor) · \(relativo(c.quando))").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func linhaPR(_ p: PR, comRepo: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(p.titulo).lineLimit(2)
                if p.rascunho { Text("rascunho").font(.caption2).padding(.horizontal, 5).background(Capsule().fill(Color.secondary.opacity(0.2))) }
            }
            HStack(spacing: 5) {
                if comRepo, p.projeto != nil { Circle().fill(Color(hex: p.cor)).frame(width: 6, height: 6) }
                Text((comRepo ? "\(p.projeto ?? p.repo) " : "") + "#\(p.n) · \(p.autor ?? "?") · \(relativo(p.atualizado))")
                if p.comentarios > 0 { Label("\(p.comentarios)", systemImage: "text.bubble") }
            }
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    private func cartaoGit(_ r: Repo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: r.cor)).frame(width: 9, height: 9)
                Text(r.projeto).font(.headline)
                Text(r.remote ?? r.nome).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 10) {
                Label(r.branch ?? "?", systemImage: "arrow.triangle.branch").font(.callout.monospaced()).lineLimit(1)
                if r.upstream == nil { Text("sem upstream").foregroundStyle(.orange) }
                if r.frente > 0 { Text("↑\(r.frente) para subir").foregroundStyle(.blue) }
                if r.atras > 0 { Text("↓\(r.atras) para baixar").foregroundStyle(.orange) }
                if r.frente == 0 && r.atras == 0 && r.upstream != nil { Text("em dia").foregroundStyle(.secondary) }
            }
            .font(.callout)
            HStack {
                Button("Fetch") { acaoRepo(r, "fetch") }.help("Busca o que mudou no origin, sem mexer nos seus arquivos")
                Button("Pull") { acaoRepo(r, "pull") }.disabled(r.atras == 0).help("Só fast-forward: nunca cria merge sozinho")
                Button("Push") { pushEm = r }.disabled(r.frente == 0 && r.upstream != nil)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ---------- jfy ----------
    private func carregar() async {
        carregando = true
        defer { carregando = false }
        async let g: (Dados?, String?) = JFY.ler(["--github-json"])
        async let r: ([Repo]?, String?) = JFY.ler(["--repos-json"])
        let ((d, m1), (lista, m2)) = await (g, r)
        if let d { dados = d }
        if let lista { repos = lista }
        aviso = m1 ?? m2
    }

    private func acaoRepo(_ r: Repo, _ acao: String) {
        Task {
            aviso = await JFY.fazer(["--repo-acao", r.pasta, acao])
            await carregar()
        }
    }

    private func trocarConta(_ c: String) {
        Task {
            aviso = await JFY.fazer(["--github-conta", c])
            await carregar()
        }
    }

    private func conectar() {
        Task { if let e = await JFY.fazer(["--github-login"]) { aviso = e } else { irParaJFY() } }
    }
}

// ---------- um PR ----------
struct PRDetalhe: View {
    let repo: String
    let n: Int
    @ObservedObject var nav: Navegacao
    let irParaJFY: () -> Void
    let mudou: () -> Void

    struct Detalhe: Decodable {
        struct Check: Decodable { let nome, estado: String }
        struct Commit: Decodable { let sha, msg: String; let autor, quando: String? }
        struct Nota: Decodable { let autor, estado, quando: String?; let texto: String }
        struct TaskLigada: Decodable { let id, titulo, status, pid: String; let projeto, cor: String? }
        let titulo, corpo, url, de, para: String
        let autor, mergeavel, situacao, revisao, criado: String?
        let rascunho: Bool
        let mais, menos, arquivos: Int
        let checks: [Check]
        let commits: [Commit]
        let revisoes, comentarios: [Nota]
        let metodos: [String]
        let tasks: [TaskLigada]
    }

    @State private var d: Detalhe?
    @State private var aviso: String?
    @State private var ocupado = false
    @State private var comentario = ""
    @State private var mergeCom: String?
    @State private var confirmarFechar = false
    @State private var confirmarReview = false

    var body: some View {
        Group {
            if let d { conteudo(d) } else if let aviso { Text(aviso).foregroundStyle(.secondary).padding() } else { ProgressView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await carregar() }
        .confirmationDialog("Merge (\(mergeCom ?? "")) de #\(n) em \(d?.para ?? "")?",
                            isPresented: Binding(get: { mergeCom != nil }, set: { if !$0 { mergeCom = nil } })) {
            Button("Fazer merge") { if let m = mergeCom { agir("merge", m) } }
        } message: {
            Text(d?.situacao == "UNSTABLE" ? "Atenção: há checks falhando." : "O PR entra em \(d?.para ?? "") e fecha. Não tem volta pelo app.")
        }
        .confirmationDialog("Fechar #\(n) sem merge?", isPresented: $confirmarFechar) {
            Button("Fechar sem merge", role: .destructive) { agir("fechar") }
        }
        .confirmationDialog("Revisar #\(n) com o Claude?", isPresented: $confirmarReview) {
            Button("Revisar") { revisar() }
        } message: {
            Text("Abre uma aba do jfy com o Claude rodando o /code-review deste PR (usa tokens). Ele só mostra o que achou: não comenta nem aprova no GitHub sem você pedir.")
        }
    }

    private func conteudo(_ d: Detalhe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("\(repo) #\(n)").foregroundStyle(.secondary)
                    Spacer()
                    Link(destination: URL(string: d.url)!) { Label("Abrir no GitHub", systemImage: "arrow.up.right.square") }
                }
                .font(.callout)
                Text(d.titulo).font(.title2.weight(.semibold)).textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(d.de).font(.callout.monospaced())
                    Image(systemName: "arrow.right")
                    Text(d.para).font(.callout.monospaced())
                    Text("· \(d.autor ?? "?") · +\(d.mais) −\(d.menos) em \(d.arquivos) arquivo(s)").foregroundStyle(.secondary)
                }
                .lineLimit(1)
                HStack(spacing: 8) {
                    if d.rascunho { Selo(texto: "rascunho", cor: .gray) }
                    if let r = TEXTO_REVISAO[d.revisao ?? ""] { Selo(texto: r.0, cor: r.1) }
                    if let s = TEXTO_SITUACAO[d.situacao ?? ""] { Selo(texto: s.0, cor: s.1) }
                }
                if let aviso { Label(aviso, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
                HStack {
                    Menu("Merge") {
                        ForEach(d.metodos, id: \.self) { m in Button(NOME_METODO[m] ?? m) { mergeCom = m } }
                    }
                    .fixedSize().disabled(d.rascunho || d.metodos.isEmpty)
                    Button { confirmarReview = true } label: { Label("Revisar com o Claude", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent)
                    Button("Aprovar") { agir("aprovar") }
                    Button("Fechar sem merge") { confirmarFechar = true }
                }
                .disabled(ocupado)
                if !d.tasks.isEmpty {
                    Grupo("Tasks do Journify") {
                        ForEach(d.tasks, id: \.id) { t in
                            Button { nav.abrirTask = .init(pid: t.pid, tid: t.id); nav.tela = .projetos } label: {
                                HStack(spacing: 8) {
                                    StatusChip(status: t.status)
                                    Text(t.titulo).lineLimit(1)
                                    if let p = t.projeto { Text("· \(p)").foregroundStyle(.secondary) }
                                }
                            }
                            .buttonStyle(.plain).help("Abrir a task na aba Projetos")
                        }
                    }
                }
                if !d.checks.isEmpty {
                    Grupo("Checks") {
                        ForEach(Array(d.checks.enumerated()), id: \.offset) { _, c in
                            let e = ESTADO_CHECK(c.estado)
                            Label { Text(c.nome) } icon: { Image(systemName: e.0).foregroundStyle(e.1) }
                        }
                    }
                }
                Grupo("Descrição") {
                    if d.corpo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("(sem descrição)").foregroundStyle(.secondary)
                    } else {
                        Markdown(texto: d.corpo)
                    }
                }
                Grupo("Commits (\(d.commits.count))") {
                    ForEach(Array(d.commits.enumerated()), id: \.offset) { _, c in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(c.sha).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(c.msg).lineLimit(2)
                            Spacer()
                            Text("\(c.autor ?? "") · \(relativo(c.quando))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Grupo("Revisões e comentários") {
                    ForEach(Array((d.revisoes + d.comentarios).sorted { ($0.quando ?? "") < ($1.quando ?? "") }.enumerated()), id: \.offset) { _, c in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(c.autor ?? "?").font(.callout.weight(.semibold))
                                if let e = c.estado, let r = TEXTO_REVISAO[e] { Selo(texto: r.0, cor: r.1) }
                                Text(relativo(c.quando)).font(.caption).foregroundStyle(.secondary)
                            }
                            if !c.texto.isEmpty { Markdown(texto: c.texto) }
                        }
                    }
                    HStack(alignment: .bottom) {
                        TextField("Comentar no PR", text: $comentario, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                        Button("Enviar") { agir("comentar", comentario); comentario = "" }
                            .disabled(comentario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ocupado)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .opacity(ocupado ? 0.6 : 1)
    }

    private func carregar() async {
        let (r, msg): (Detalhe?, String?) = await JFY.ler(["--pr-json", repo, String(n)])
        if let r { d = r }
        aviso = msg
    }

    private func revisar() {
        Task { if let e = await JFY.fazer(["--pr-revisar", repo, String(n)]) { aviso = e } else { irParaJFY() } }
    }

    private func agir(_ acao: String, _ valor: String = "") {
        Task {
            ocupado = true
            let erro = await JFY.fazer(["--pr-acao", repo, String(n), acao] + (valor.isEmpty ? [] : [valor]))
            await carregar()
            ocupado = false
            aviso = erro
            if erro == nil { mudou() }
        }
    }
}

// ---------- textos e peças ----------
private let NOME_METODO = ["squash": "Squash e merge", "merge": "Merge commit", "rebase": "Rebase e merge"]
private let TEXTO_REVISAO: [String: (String, Color)] = [
    "APPROVED": ("aprovado", .green), "CHANGES_REQUESTED": ("pediram mudanças", .orange),
    "REVIEW_REQUIRED": ("precisa de revisão", .yellow), "COMMENTED": ("comentou", .gray), "DISMISSED": ("descartada", .gray),
]
private let TEXTO_SITUACAO: [String: (String, Color)] = [
    "CLEAN": ("pronto para merge", .green), "UNSTABLE": ("checks falhando", .red), "BLOCKED": ("bloqueado pela regra da branch", .orange),
    "DIRTY": ("conflito com a base", .red), "BEHIND": ("atrás da base", .orange), "HAS_HOOKS": ("pronto para merge", .green),
    "UNKNOWN": ("calculando…", .gray),
]
private func ESTADO_CHECK(_ e: String) -> (String, Color) {
    switch e {
    case "success": ("checkmark.circle.fill", .green)
    case "failure", "error", "cancelled", "timed_out", "action_required", "startup_failure": ("xmark.circle.fill", .red)
    case "skipped", "neutral", "stale": ("minus.circle", .gray)
    default: ("clock", .yellow)  // pending, in_progress, queued, expected
    }
}

private func relativo(_ iso: String?) -> String {
    guard let iso, let d = (try? Date(iso, strategy: .iso8601)) ?? (try? Date(iso, strategy: .iso8601.year().month().day()
        .time(includingFractionalSeconds: true).timeZone(separator: .omitted))) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.unitsStyle = .short
    return f.localizedString(for: d, relativeTo: Date())
}

private struct Selo: View {
    let texto: String
    let cor: Color
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(cor).frame(width: 7, height: 7)
            Text(texto)
        }
        .font(.caption).padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }
}

private struct Grupo<C: View>: View {
    let titulo: String
    @ViewBuilder let conteudo: C
    init(_ titulo: String, @ViewBuilder _ conteudo: () -> C) {
        self.titulo = titulo
        self.conteudo = conteudo()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            conteudo
        }
    }
}

// ---------- commit pelos arquivos marcados (como o GitHub Desktop) ----------
/// Os arquivos mexidos com caixa de marcar, o diff do escolhido e a mensagem: o "Gerar com o committer" escreve pelas
/// regras do agente committer, e o commit é do jfy, com as travas dele (--repo-mudancas, --repo-diff,
/// --commit-mensagem, --commit-autor, --commit-fazer).
struct CommitPainel: View {
    let pasta: String
    let mudou: () -> Void

    struct Mudancas: Decodable {
        struct Arquivo: Decodable, Hashable {
            let estado, arquivo: String
        }
        let branch: String
        let gitflow: Bool
        let arquivos: [Arquivo]
    }

    @State private var dados: Mudancas?
    @State private var marcados: Set<String> = []
    @State private var atual: String?
    @State private var diff = ""
    @State private var resumo = ""
    @State private var descricao = ""
    @State private var gerando = false
    @State private var commitando = false
    @State private var aviso: String?
    @State private var feito: String?
    @State private var pedirNome = false
    @State private var nome = ""

    /// O que o committer deixa de fora (segredo e ruído): já vem desmarcado.
    private static let ruido = #/(^|/)(\.env(?!\.example)[^/]*|\.DS_Store|[^/]*\.(pem|key)|node_modules/.*|(dist|\.next|build|coverage)/.*)$/#

    var body: some View {
        VStack(spacing: 0) {
            if let d = dados {
                HStack {
                    Label(d.branch, systemImage: "arrow.triangle.branch").font(.headline.monospaced())
                    Text("\(d.arquivos.count) alteração(ões)").foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await carregar() } } label: { Image(systemName: "arrow.clockwise") }.help("Atualizar")
                }
                .padding(12)
                if !d.gitflow {
                    Label("O committer não commita em \(d.branch): crie uma branch feature/, bugfix/, hotfix/ ou release/.",
                          systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).padding(.horizontal, 12).padding(.bottom, 8)
                }
                Divider()
                HStack(spacing: 0) {
                    arquivos(d).frame(width: 300)
                    Divider()
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(diff.components(separatedBy: "\n").enumerated()), id: \.offset) { _, l in linhaDiff(l) }
                        }
                        .padding(8)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                }
                Divider()
                caixaCommit(d)
            } else if let aviso {
                Text(aviso).foregroundStyle(.secondary).padding()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await carregar() }
        .task(id: atual) { await carregarDiff() }
    }

    private func arquivos(_ d: Mudancas) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: Binding(get: { !d.arquivos.isEmpty && marcados.count == d.arquivos.count },
                                 set: { marcados = $0 ? Set(d.arquivos.map(\.arquivo)) : [] })) {
                Text("\(marcados.count) de \(d.arquivos.count) marcados").font(.callout)
            }
            .toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading).padding(8)
            Divider()
            List(selection: $atual) {
                ForEach(d.arquivos, id: \.arquivo) { a in
                    HStack(spacing: 6) {
                        Toggle("", isOn: Binding(get: { marcados.contains(a.arquivo) },
                                                 set: { if $0 { marcados.insert(a.arquivo) } else { marcados.remove(a.arquivo) } }))
                            .toggleStyle(.checkbox).labelsHidden()
                        let e = estado(a.estado)
                        Text(e.0).font(.caption.monospaced().bold()).foregroundStyle(e.1).frame(width: 14)
                        Text(a.arquivo).lineLimit(1).truncationMode(.head).help(a.arquivo)
                    }
                    .tag(a.arquivo)
                }
            }
        }
    }

    private func caixaCommit(_ d: Mudancas) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let aviso { Label(aviso, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
            if let feito { Label(feito, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            if pedirNome {
                HStack {
                    TextField("Seu nome para o prefixo [Nome] dos commits (conta compartilhada)", text: $nome).textFieldStyle(.roundedBorder)
                    Button("Salvar e gerar") { salvarNome() }.disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            TextField("Resumo (obrigatório)", text: $resumo).textFieldStyle(.roundedBorder).font(.body.monospaced())
            TextEditor(text: $descricao).font(.body.monospaced()).frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            HStack {
                Button { gerar() } label: { Label("Gerar com o committer", systemImage: "sparkles") }
                    .disabled(marcados.isEmpty || gerando)
                if gerando { ProgressView().controlSize(.small); Text("O committer está escrevendo…").foregroundStyle(.secondary) }
                Spacer()
                Button("Commit de \(marcados.count) arquivo(s) em \(d.branch)") { commitar() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!d.gitflow || marcados.isEmpty || resumo.trimmingCharacters(in: .whitespaces).isEmpty || commitando)
            }
            Text("A mensagem segue as regras do agente committer (formato, prefixo na conta compartilhada, linha Journify). Gerar usa tokens; o commit leva só os marcados.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    @ViewBuilder private func linhaDiff(_ l: String) -> some View {
        let cor: Color? = l.hasPrefix("+") && !l.hasPrefix("+++") ? .green : l.hasPrefix("-") && !l.hasPrefix("---") ? .red
            : l.hasPrefix("@@") ? .blue : nil
        Text(l.isEmpty ? " " : l).font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(cor ?? .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((cor ?? .clear).opacity(cor == .blue ? 0 : 0.08))
            .textSelection(.enabled)
    }

    private func estado(_ e: String) -> (String, Color) {
        e == "??" || e.contains("A") ? ("+", .green) : e.contains("D") ? ("−", .red) : e.contains("R") ? ("R", .blue) : ("M", .orange)
    }

    // ---------- jfy ----------
    private func carregar() async {
        let (d, msg): (Mudancas?, String?) = await JFY.ler(["--repo-mudancas", pasta])
        if let d {
            let primeira = dados == nil
            dados = d
            let todos = Set(d.arquivos.map(\.arquivo))
            marcados = primeira ? Set(todos.filter { $0.firstMatch(of: Self.ruido) == nil }) : marcados.intersection(todos)
            if atual == nil || !todos.contains(atual!) { atual = d.arquivos.first?.arquivo }
        }
        aviso = msg
    }

    private func carregarDiff() async {
        guard let atual else { diff = ""; return }
        struct D: Decodable { let diff: String }
        let (r, _): (D?, String?) = await JFY.ler(["--repo-diff", pasta, atual])
        if self.atual == atual { diff = r?.diff ?? "" }
    }

    private func gerar() {
        Task {
            gerando = true
            feito = nil
            struct M: Decodable { let mensagem: String }
            let (r, msg): (M?, String?) = await JFY.ler(["--commit-mensagem", pasta] + marcados.sorted())
            gerando = false
            if let r {
                let linhas = r.mensagem.components(separatedBy: "\n")
                resumo = linhas.first ?? ""
                descricao = linhas.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                aviso = nil
            } else if let msg, msg.hasPrefix("NOME:") {
                pedirNome = true
                aviso = String(msg.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else {
                aviso = msg
            }
        }
    }

    private func salvarNome() {
        Task {
            if let e = await JFY.fazer(["--commit-autor", nome]) { aviso = e; return }
            pedirNome = false
            gerar()
        }
    }

    private func commitar() {
        Task {
            commitando = true
            struct C: Decodable { let sha, assunto: String }
            let msg = resumo + (descricao.isEmpty ? "" : "\n\n" + descricao)
            let (r, erro): (C?, String?) = await JFY.ler(["--commit-fazer", pasta, msg] + marcados.sorted())
            commitando = false
            aviso = r == nil ? erro : nil
            if let r {
                feito = "Commit \(r.sha): \(r.assunto)"
                resumo = ""
                descricao = ""
                await carregar()
                mudou()
            }
        }
    }
}
