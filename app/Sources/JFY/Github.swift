import AppKit
import SwiftUI

/// GitHub dos projetos: os PRs abertos (com merge, aprovar, comentar e fechar) e o git de cada repositório (fetch, pull,
/// push). Quem fala com o GitHub é o jfy, pelo gh e pela conta ativa dele (--github-json, --pr-json, --pr-acao,
/// --repos-json, --repo-acao, --github-conta, --github-login).
struct GithubTela: View {
    let ativa: Bool
    let irParaJFY: () -> Void

    struct PR: Decodable, Hashable {
        let repo, titulo, url, atualizado: String
        let n, comentarios: Int
        let autor, projeto, cor: String?
        let rascunho: Bool
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

    private enum Modo: String, CaseIterable { case prs = "Pull requests", repos = "Repositórios" }

    @State private var modo = Modo.prs
    @State private var dados: Dados?
    @State private var repos: [Repo] = []
    @State private var selecao: String?  // "seção|repo#n": o mesmo PR pode estar em duas seções
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
            } else if modo == .prs {
                prs
            } else {
                listaRepos
            }
        }
        .task(id: "\(ativa)|\(modo.rawValue)") { if ativa { await carregar() } }
        .confirmationDialog("Dar push de \(pushEm?.branch ?? "") em \(pushEm?.nome ?? "")?",
                            isPresented: Binding(get: { pushEm != nil }, set: { if !$0 { pushEm = nil } })) {
            Button("Push") { if let r = pushEm { acaoRepo(r, "push") } }
        } message: {
            Text("Sobe os commits da branch atual para o origin (cria o upstream se faltar). Usa a conta ativa do gh.")
        }
    }

    // ---------- topo: conta e modo ----------
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
            Picker("Modo", selection: $modo) { ForEach(Modo.allCases, id: \.self) { Text($0.rawValue) } }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
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

    // ---------- pull requests ----------
    private var prs: some View {
        HStack(spacing: 0) {
            List(selection: $selecao) {
                if let d = dados {
                    secao("Pedem sua revisão", "revisar", d.revisar)
                    secao("Seus PRs", "meus", d.meus)
                    secao("Nos projetos", "prs", d.prs)
                } else if carregando {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .frame(width: 380)
            Divider()
            if let sel = selecao, let ref = sel.split(separator: "|").last, let i = ref.lastIndex(of: "#"),
               let n = Int(ref[ref.index(after: i)...]) {
                PRDetalhe(repo: String(ref[..<i]), n: n, mudou: { Task { await carregar() } }).id(sel)
            } else {
                Text("Escolha um PR").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private func secao(_ titulo: String, _ chave: String, _ lista: [PR]) -> some View {
        Section("\(titulo) (\(lista.count))") {
            if lista.isEmpty { Text("nenhum").foregroundStyle(.secondary) }
            ForEach(lista, id: \.self) { p in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(p.titulo).lineLimit(2)
                        if p.rascunho { Text("rascunho").font(.caption2).padding(.horizontal, 5).background(Capsule().fill(Color.secondary.opacity(0.2))) }
                    }
                    HStack(spacing: 5) {
                        if p.projeto != nil { Circle().fill(Color(hex: p.cor)).frame(width: 6, height: 6) }
                        Text("\(p.projeto ?? p.repo) #\(p.n) · \(p.autor ?? "?") · \(relativo(p.atualizado))")
                        if p.comentarios > 0 { Label("\(p.comentarios)", systemImage: "text.bubble") }
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.vertical, 3)
                .tag("\(chave)|\(p.repo)#\(p.n)")
            }
        }
    }

    // ---------- repositórios ----------
    private var listaRepos: some View {
        ScrollView {
            VStack(spacing: 12) {
                if repos.isEmpty && carregando { ProgressView().padding(40) }
                ForEach(repos) { cartaoRepo($0) }
            }
            .padding(20)
        }
    }

    private func cartaoRepo(_ r: Repo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: r.cor)).frame(width: 9, height: 9)
                Text(r.projeto).font(.headline)
                Text(r.remote ?? r.nome).foregroundStyle(.secondary)
                Spacer()
                Button("Fetch") { acaoRepo(r, "fetch") }.help("Busca o que mudou no origin, sem mexer nos seus arquivos")
                Button("Pull") { acaoRepo(r, "pull") }.disabled(r.atras == 0).help("Só fast-forward: nunca cria merge sozinho")
                Button("Push") { pushEm = r }.disabled(r.frente == 0 && r.upstream != nil)
            }
            HStack(spacing: 14) {
                Label(r.branch ?? "?", systemImage: "arrow.triangle.branch").font(.callout.monospaced())
                if r.upstream == nil { Text("sem upstream").foregroundStyle(.orange) }
                if r.frente > 0 { Label("\(r.frente) para subir", systemImage: "arrow.up").foregroundStyle(.blue) }
                if r.atras > 0 { Label("\(r.atras) para baixar", systemImage: "arrow.down").foregroundStyle(.orange) }
                if r.frente == 0 && r.atras == 0 && r.upstream != nil { Text("em dia com o origin").foregroundStyle(.secondary) }
            }
            .font(.callout)
            if r.nMexidos > 0 {
                DisclosureGroup("\(r.nMexidos) arquivo(s) mexido(s) sem commit") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(r.mexidos, id: \.self) { Text($0).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            DisclosureGroup("Últimos commits") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(r.commits) { c in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(c.sha).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(c.msg).lineLimit(1)
                            Spacer()
                            Text("\(c.autor) · \(relativo(c.quando))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
    }

    // ---------- jfy ----------
    private func carregar() async {
        carregando = true
        defer { carregando = false }
        if modo == .prs || dados == nil {
            let (d, msg): (Dados?, String?) = await JFY.ler(["--github-json"])
            if let d { dados = d }
            aviso = msg
        }
        if modo == .repos {
            let (r, msg): ([Repo]?, String?) = await JFY.ler(["--repos-json"])
            if let r { repos = r }
            aviso = msg ?? aviso
        }
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
    let mudou: () -> Void

    struct Detalhe: Decodable {
        struct Check: Decodable { let nome, estado: String }
        struct Commit: Decodable { let sha, msg: String; let autor, quando: String? }
        struct Nota: Decodable { let autor, estado, quando: String?; let texto: String }
        let titulo, corpo, url, de, para: String
        let autor, mergeavel, situacao, revisao, criado: String?
        let rascunho: Bool
        let mais, menos, arquivos: Int
        let checks: [Check]
        let commits: [Commit]
        let revisoes, comentarios: [Nota]
        let metodos: [String]
    }

    @State private var d: Detalhe?
    @State private var aviso: String?
    @State private var ocupado = false
    @State private var comentario = ""
    @State private var mergeCom: String?
    @State private var confirmarFechar = false

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
                    Button("Aprovar") { agir("aprovar") }
                    Button("Fechar sem merge") { confirmarFechar = true }
                }
                .disabled(ocupado)
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
