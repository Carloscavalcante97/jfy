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
        let pasta, nome, projeto: String
        let cor, remote, branch, upstream: String?
        let frente, atras, nMexidos: Int
        var id: String { pasta }
    }

    /// À esquerda: as duas listas de PRs de todos os repos, ou um repositório.
    enum Lado: Hashable { case revisar, meus, repo(String) }

    @State private var lado: Lado? = .meus
    @State private var pr: String?  // "dono/repo#n"
    @State private var aba = RepoPainel.Aba.alteracoes
    @State private var dados: Dados?
    @State private var repos: [Repo] = []
    @State private var aviso: String?
    @State private var carregando = false

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
                    switch lado {
                    case let .repo(pasta):
                        if let r = repos.first(where: { $0.pasta == pasta }) {
                            RepoPainel(repo: r, prs: prsDo(r), aba: $aba, pr: $pr, nav: nav, irParaJFY: irParaJFY,
                                       mudou: { Task { await carregar() } }).id(pasta)
                        }
                    default:
                        HStack(spacing: 0) {
                            listaPRs(lado == .revisar ? dados?.revisar ?? [] : dados?.meus ?? []).frame(width: 380)
                            Divider()
                            detalhePR
                        }
                    }
                }
            }
        }
        .task(id: ativa) { if ativa { await carregar() } }
        .onChange(of: nav.abrirPR) {
            guard let alvo = nav.abrirPR else { return }  // veio de uma task na aba Projetos
            pr = alvo
            let slug = String(alvo[..<(alvo.lastIndex(of: "#") ?? alvo.endIndex)])
            if let r = repos.first(where: { $0.remote == slug }) { lado = .repo(r.pasta); aba = .prs } else { lado = .meus }
            nav.abrirPR = nil
        }
    }

    // ---------- topo: conta ----------
    private var cabecalho: some View {
        HStack(spacing: 14) {
            Text("GitHub").font(Souv.titulo(24))
            if let d = dados, let conta = d.conta {
                SouvSelect(opcoes: d.contas.map { .init(valor: $0, rotulo: $0) }, selecionado: conta,
                           extra: ("Conectar outra conta…", { conectar() })) { trocarConta($0) }
                    .frame(width: 230)
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
        List {
            Label("Pedem sua revisão", systemImage: "eye").badge(dados?.revisar.count ?? 0).linhaSouv(lado == .revisar) { lado = .revisar }
            Label("Seus PRs", systemImage: "person").badge(dados?.meus.count ?? 0).linhaSouv(lado == .meus) { lado = .meus }
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
                            Text(r.branch ?? r.nome).lineLimit(1).truncationMode(.middle)
                            if r.frente > 0 { Text("↑\(r.frente)").foregroundStyle(.blue) }
                            if r.atras > 0 { Text("↓\(r.atras)").foregroundStyle(.orange) }
                            if r.nMexidos > 0 { Text("●\(r.nMexidos)").help("arquivos mexidos sem commit") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .linhaSouv(lado == .repo(r.pasta)) { lado = .repo(r.pasta) }
                }
            }
        }
        .listStyle(.sidebar)
        .listaSouv()
    }

    private func prsDo(_ r: Repo) -> [PR] { (dados?.prs ?? []).filter { $0.repo == r.remote } }

    private func listaPRs(_ lista: [PR]) -> some View {
        List {
            Section("\(lado == .revisar ? "Pedem sua revisão" : "Seus PRs") (\(lista.count))") {
                if lista.isEmpty { Text("nenhum").foregroundStyle(.secondary) }
                ForEach(lista, id: \.ref) { p in LinhaPR(p: p, comRepo: true).linhaSouv(pr == p.ref) { pr = p.ref } }
            }
        }
    }

    @ViewBuilder private var detalhePR: some View {
        if let pr, let i = pr.lastIndex(of: "#"), let n = Int(pr[pr.index(after: i)...]) {
            PRDetalhe(repo: String(pr[..<i]), n: n, nav: nav, irParaJFY: irParaJFY, mudou: { Task { await carregar() } }).id(pr)
        } else {
            Text("Escolha um PR").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

struct LinhaPR: View {
    let p: GithubTela.PR
    let comRepo: Bool
    var body: some View {
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
}

// ---------- um repositório: o git no topo e as abas do fluxo ----------
struct RepoPainel: View {
    let repo: GithubTela.Repo
    let prs: [GithubTela.PR]
    @Binding var aba: Aba
    @Binding var pr: String?
    @ObservedObject var nav: Navegacao
    let irParaJFY: () -> Void
    let mudou: () -> Void

    enum Aba: String, CaseIterable {
        case alteracoes = "Alterações", historico = "Histórico", prs = "PRs", branches = "Branches e worktrees"
        var icone: String {
            switch self {
            case .alteracoes: "square.and.pencil"
            case .historico: "clock.arrow.circlepath"
            case .prs: "arrow.triangle.pull"
            case .branches: "arrow.triangle.branch"
            }
        }
    }

    @State private var aviso: String?
    @State private var confirmarPush = false
    @State private var ocupado = false
    @State private var branches: [BranchesPainel.Dados.Branch] = []

    /// O botão principal muda com o estado, como no GitHub Desktop: baixar, subir, publicar ou só buscar.
    private var sincronizar: (titulo: String, icone: String, acao: String) {
        repo.atras > 0 ? ("Pull ↓\(repo.atras)", "arrow.down.circle", "pull")
            : repo.upstream == nil ? ("Publicar branch", "icloud.and.arrow.up", "push")
            : repo.frente > 0 ? ("Push ↑\(repo.frente)", "arrow.up.circle", "push")
            : ("Fetch", "arrow.triangle.2.circlepath", "fetch")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(Color(hex: repo.cor)).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text(repo.projeto).font(.headline)
                    Text(repo.remote ?? repo.nome).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Divider().frame(height: 28)
                Menu {
                    Section("Trocar para") {
                        ForEach(branches.filter { !$0.atual }.prefix(12)) { b in Button(b.nome) { trocar(b.nome) } }
                    }
                    Divider()
                    Button("Nova branch…") { aba = .branches }
                    Button("Todas as branches e worktrees") { aba = .branches }
                } label: {
                    Label(repo.branch ?? "?", systemImage: "arrow.triangle.branch").font(.callout.monospaced())
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Branch atual: clique para trocar ou criar outra")
                Spacer()
                if ocupado { ProgressView().controlSize(.small) }
                HStack(spacing: 0) {
                    Button { sincronizar.acao == "push" ? (confirmarPush = true) : git(sincronizar.acao) } label: {
                        Label(sincronizar.titulo, systemImage: sincronizar.icone)
                    }
                    Menu {
                        Button("Fetch") { git("fetch") }
                        Button("Pull (só fast-forward)") { git("pull") }.disabled(repo.atras == 0)
                        Button("Push") { confirmarPush = true }.disabled(repo.frente == 0 && repo.upstream != nil)
                    } label: { EmptyView() }
                    .menuStyle(.borderlessButton).frame(width: 18)
                }
                .disabled(ocupado)
                Button { abrirPR() } label: { Label("Abrir PR", systemImage: "arrow.triangle.pull") }
                    .buttonStyle(.borderedProminent)
                    .help("O Claude abre o PR desta branch pelas regras do pr-creator, numa aba do jfy, com a sua aprovação")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            if let aviso {
                Label(aviso, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 8)
            }
            Picker("Aba", selection: $aba) {
                ForEach(Aba.allCases, id: \.self) { a in
                    Label(a == .alteracoes && repo.nMexidos > 0 ? "Alterações (\(repo.nMexidos))"
                          : a == .prs && !prs.isEmpty ? "PRs (\(prs.count))" : a.rawValue, systemImage: a.icone).tag(a)
                }
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 14).padding(.bottom, 10)
            Divider()
            switch aba {
            case .alteracoes: CommitPainel(pasta: repo.pasta, branch: repo.branch ?? "?", mudou: mudou)
            case .historico: HistoricoPainel(pasta: repo.pasta)
            case .prs:
                HStack(spacing: 0) {
                    List {
                        if prs.isEmpty { Text("Nenhum PR aberto neste repositório.").foregroundStyle(.secondary) }
                        ForEach(prs, id: \.ref) { p in LinhaPR(p: p, comRepo: false).linhaSouv(pr == p.ref) { pr = p.ref } }
                    }
                    .listaSouv()
                    .frame(width: 340)
                    Divider()
                    if let pr, let i = pr.lastIndex(of: "#"), let n = Int(pr[pr.index(after: i)...]) {
                        PRDetalhe(repo: String(pr[..<i]), n: n, nav: nav, irParaJFY: irParaJFY, mudou: mudou).id(pr)
                    } else {
                        Text("Escolha um PR").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            case .branches: BranchesPainel(pasta: repo.pasta, irParaJFY: irParaJFY, mudou: mudou)
            }
        }
        .task(id: repo.branch) { await carregarBranches() }
        .confirmationDialog(repo.upstream == nil ? "Publicar \(repo.branch ?? "") no origin?" : "Dar push de \(repo.branch ?? "")?",
                            isPresented: $confirmarPush) {
            Button(repo.upstream == nil ? "Publicar" : "Push") { git("push") }
        } message: {
            Text("Sobe os commits da branch atual para o origin (cria o upstream se faltar). Usa a conta ativa do gh.")
        }
    }

    private func carregarBranches() async {
        let (d, _): (BranchesPainel.Dados?, String?) = await JFY.ler(["--repo-branches", repo.pasta])
        branches = d?.branches ?? []
    }

    private func git(_ acao: String) {
        Task {
            ocupado = true
            aviso = await JFY.fazer(["--repo-acao", repo.pasta, acao])
            ocupado = false
            mudou()
        }
    }

    private func trocar(_ b: String) {
        Task {
            ocupado = true
            aviso = await JFY.fazer(["--repo-branch", repo.pasta, "trocar", b])
            ocupado = false
            mudou()
        }
    }

    private func abrirPR() {
        Task { if let e = await JFY.fazer(["--pr-abrir", repo.pasta]) { aviso = e } else { irParaJFY() } }
    }
}

// ---------- histórico ----------
struct HistoricoPainel: View {
    let pasta: String
    struct Commit: Decodable, Identifiable {
        let sha, assunto, autor, quando, refs: String
        var id: String { sha }
    }
    struct Detalhe: Decodable {
        struct Arquivo: Decodable, Hashable { let estado, arquivo: String }
        let mensagem, diff: String
        let arquivos: [Arquivo]
    }
    @State private var commits: [Commit] = []
    @State private var sel: String?
    @State private var detalhe: Detalhe?

    var body: some View {
        HStack(spacing: 0) {
            List {
                ForEach(commits) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.assunto).lineLimit(2)
                        HStack(spacing: 6) {
                            Text(c.sha).font(.caption.monospaced())
                            Text("\(c.autor) · \(relativo(c.quando))")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        if !c.refs.isEmpty { Text(c.refs).font(.caption2.monospaced()).foregroundStyle(.blue).lineLimit(1) }
                    }
                    .padding(.vertical, 2)
                    .linhaSouv(sel == c.sha) { sel = c.sha }
                }
            }
            .listaSouv()
            .frame(width: 340)
            Divider()
            if let d = detalhe {
                VStack(alignment: .leading, spacing: 0) {
                    Text(d.mensagem).textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    if !d.arquivos.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(d.arquivos, id: \.self) { a in ArquivoLinha(estado: a.estado, caminho: a.arquivo) }
                        }
                        .padding(.horizontal, 12).padding(.bottom, 10)
                    }
                    Divider()
                    ScrollView([.vertical, .horizontal]) { Diff(texto: d.diff).padding(8) }
                        .background(Color(nsColor: .textBackgroundColor))
                }
            } else {
                Text("Escolha um commit").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let (c, _): ([Commit]?, String?) = await JFY.ler(["--repo-historico", pasta])
            commits = c ?? []
            if sel == nil { sel = commits.first?.sha }
        }
        .task(id: sel) {
            guard let sel else { return }
            let (d, _): (Detalhe?, String?) = await JFY.ler(["--repo-commit", pasta, sel])
            if self.sel == sel { detalhe = d }
        }
    }
}

// ---------- branches e worktrees ----------
struct BranchesPainel: View {
    let pasta: String
    let irParaJFY: () -> Void
    let mudou: () -> Void

    struct Dados: Decodable {
        struct Branch: Decodable, Identifiable {
            let nome, quando, assunto: String
            let upstream: String?
            let atual, sumiu, entrou: Bool
            let frente, atras: Int
            var id: String { nome }
        }
        struct Worktree: Decodable, Identifiable {
            let pasta, branch: String
            let principal, orfao: Bool
            let mexidos: Int
            var id: String { pasta }
        }
        let atual: String
        let base: String?
        let taskRodando: Bool
        let branches: [Branch]
        let worktrees: [Worktree]
    }

    @State private var d: Dados?
    @State private var aviso: String?
    @State private var tipo = "feature"
    @State private var titulo = ""
    @State private var removerWt: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let aviso { Label(aviso, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
                if d?.taskRodando == true {
                    Label("Tem uma task do jfy rodando neste repositório: trocar ou criar branch fica bloqueado até ela acabar.",
                          systemImage: "lock.fill").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOVA BRANCH").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack {
                        Picker("Tipo", selection: $tipo) {
                            ForEach(["feature", "bugfix", "hotfix", "release"], id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        Text("/").foregroundStyle(.secondary)
                        TextField("o que ela faz (vira o nome)", text: $titulo).textFieldStyle(.roundedBorder).onSubmit(criar)
                        Button("Criar e trocar") { criar() }.disabled(titulo.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text(tipo == "hotfix" || tipo == "release" ? "Sai da main atualizada." : "Sai da \(d?.base?.replacingOccurrences(of: "origin/", with: "") ?? "develop") atualizada.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("BRANCHES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(d?.branches ?? []) { b in
                        HStack(spacing: 8) {
                            Image(systemName: b.atual ? "checkmark.circle.fill" : "circle").foregroundStyle(b.atual ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.nome).font(.callout.monospaced()).lineLimit(1)
                                Text([b.upstream == nil ? "só local" : b.sumiu ? "apagada no origin" : nil,
                                      b.frente > 0 ? "↑\(b.frente)" : nil, b.atras > 0 ? "↓\(b.atras)" : nil,
                                      b.entrou ? "já entrou na \(d?.base?.replacingOccurrences(of: "origin/", with: "") ?? "base")" : nil,
                                      relativo(b.quando)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !b.atual { Button("Trocar") { branch("trocar", b.nome) }.disabled(d?.taskRodando == true) }
                            if b.entrou && !b.atual { Button("Excluir") { branch("excluir", b.nome) }.help("Só a local, e só porque já entrou: git branch -d") }
                        }
                        .padding(.vertical, 2)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("WORKTREES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Limpar órfãos") { worktree("limpar") }.disabled(!(d?.worktrees.contains(where: \.orfao) ?? false))
                    }
                    Text("O jfy cria um worktree quando uma task pega um repositório que outra já está usando.").font(.caption).foregroundStyle(.secondary)
                    ForEach(d?.worktrees ?? []) { w in
                        HStack(spacing: 8) {
                            Image(systemName: w.principal ? "folder.fill" : "folder").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(w.branch).font(.callout.monospaced()).lineLimit(1)
                                Text((w.principal ? "principal · " : "") + (w.orfao ? "órfão (a pasta sumiu) · " : "")
                                     + (w.mexidos > 0 ? "\(w.mexidos) mexido(s) · " : "") + w.pasta.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Button("Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: w.pasta)) }.disabled(w.orfao)
                            if !w.principal {
                                Button("Terminal livre") { worktree("abrir", w.pasta, irDepois: true) }.disabled(w.orfao)
                                Button("Remover") { removerWt = w.pasta }.disabled(w.mexidos > 0).help(w.mexidos > 0 ? "Tem arquivos mexidos: commite ou descarte antes" : "git worktree remove")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .task { await carregar() }
        .confirmationDialog("Remover o worktree?", isPresented: Binding(get: { removerWt != nil }, set: { if !$0 { removerWt = nil } })) {
            Button("Remover", role: .destructive) { if let w = removerWt { worktree("remover", w) } }
        } message: {
            Text("Apaga a pasta do worktree. A branch continua no repositório.")
        }
    }

    private func carregar() async {
        let (r, msg): (Dados?, String?) = await JFY.ler(["--repo-branches", pasta])
        if let r { d = r }
        aviso = msg
    }

    private func criar() {
        let t = titulo.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        Task {
            aviso = await JFY.fazer(["--repo-branch", pasta, "criar", tipo, t])
            if aviso == nil { titulo = "" }
            await carregar()
            mudou()
        }
    }

    private func branch(_ acao: String, _ nome: String) {
        Task {
            aviso = await JFY.fazer(["--repo-branch", pasta, acao, nome])
            await carregar()
            mudou()
        }
    }

    private func worktree(_ acao: String, _ w: String = "", irDepois: Bool = false) {
        Task {
            aviso = await JFY.fazer(["--worktree", pasta, acao] + (w.isEmpty ? [] : [w]))
            if aviso == nil, irDepois { irParaJFY() }
            await carregar()
        }
    }
}

/// Diff colorido: + verde, − vermelho, @@ azul.
struct Diff: View {
    let texto: String
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(texto.components(separatedBy: "\n").enumerated()), id: \.offset) { _, l in
                let cor: Color? = l.hasPrefix("+") && !l.hasPrefix("+++") ? .green : l.hasPrefix("-") && !l.hasPrefix("---") ? .red
                    : l.hasPrefix("@@") ? .blue : nil
                Text(l.isEmpty ? " " : l).font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(cor ?? .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((cor ?? .clear).opacity(cor == .blue ? 0 : 0.08))
                    .textSelection(.enabled)
            }
        }
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
/// À esquerda, os arquivos mexidos com caixa de marcar e, embaixo deles, a mensagem (título e descrição) e o commit;
/// à direita, o diff do arquivo escolhido na altura inteira. "Gerar com o committer" escreve pelas regras do agente
/// committer; o commit é do jfy, com as travas dele (--repo-mudancas, --repo-diff, --commit-mensagem, --commit-autor,
/// --commit-fazer).
struct CommitPainel: View {
    let pasta: String
    let branch: String
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
    @State private var titulo = ""
    @State private var descricao = ""
    @State private var gerando = false
    @State private var commitando = false
    @State private var aviso: String?
    @State private var feito: String?
    @State private var pedirNome = false
    @State private var nome = ""

    /// O que o committer deixa de fora (segredo e ruído): já vem desmarcado.
    static let ruido = #/(^|/)(\.env(?!\.example)[^/]*|\.DS_Store|[^/]*\.(pem|key)|node_modules/.*|(dist|\.next|build|coverage)/.*)$/#
    private let limiteTitulo = 72  // o assunto inteiro do committer cabe em 72 caracteres

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                listaArquivos
                Divider()
                caixaCommit
            }
            .frame(width: 330)
            Divider()
            painelDiff
        }
        .task { await carregar() }
        .task(id: atual) { await carregarDiff() }
    }

    // ---------- esquerda: arquivos ----------
    @ViewBuilder private var listaArquivos: some View {
        if let d = dados {
            if d.arquivos.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle").font(.system(size: 36)).foregroundStyle(.green)
                    Text("Nada para commitar").font(.headline)
                    Text("Os arquivos que você mexer em \(d.branch) aparecem aqui.").font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Toggle(isOn: Binding(get: { marcados.count == d.arquivos.count },
                                             set: { marcados = $0 ? Set(d.arquivos.map(\.arquivo)) : [] })) {
                            Text("\(d.arquivos.count) arquivo(s) alterado(s)").font(.callout.weight(.medium))
                        }
                        .toggleStyle(.checkbox)
                        Spacer()
                        Button { Task { await carregar() } } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).help("Atualizar")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    Divider()
                    List {
                        ForEach(d.arquivos, id: \.arquivo) { a in
                            HStack(spacing: 6) {
                                Toggle("", isOn: Binding(get: { marcados.contains(a.arquivo) },
                                                         set: { if $0 { marcados.insert(a.arquivo) } else { marcados.remove(a.arquivo) } }))
                                    .toggleStyle(.checkbox).labelsHidden()
                                ArquivoLinha(estado: a.estado, caminho: a.arquivo)
                            }
                            .linhaSouv(atual == a.arquivo) { atual = a.arquivo }
                        }
                    }
                    .listStyle(.plain)
                    .listaSouv()
                }
            }
        } else if let aviso {
            Text(aviso).foregroundStyle(.secondary).padding().frame(maxHeight: .infinity)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // ---------- esquerda, embaixo: a mensagem e o commit ----------
    private var caixaCommit: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let d = dados, !d.gitflow {
                Label("O committer não commita em \(d.branch). Crie uma branch feature/, bugfix/, hotfix/ ou release/ (menu da branch, no topo).",
                      systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
            }
            if let aviso, dados != nil { Label(aviso, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if let feito { Label(feito, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green) }
            if pedirNome {
                HStack {
                    TextField("Seu nome para o [Nome] dos commits", text: $nome).textFieldStyle(.roundedBorder)
                    Button("Salvar") { salvarNome() }.disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            HStack(spacing: 6) {
                TextField("Título (obrigatório)", text: $titulo).textFieldStyle(.roundedBorder)
                Text("\(titulo.count)").font(.caption.monospacedDigit())
                    .foregroundStyle(titulo.count > limiteTitulo ? .orange : .secondary)
                    .help("O committer limita o título a \(limiteTitulo) caracteres")
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $descricao).font(.body).scrollContentBackground(.hidden).padding(4)
                if descricao.isEmpty {
                    Text("Descrição (opcional): o porquê, em 1 a 3 linhas").foregroundStyle(.tertiary).padding(.horizontal, 9).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            Button { gerar() } label: {
                HStack {
                    if gerando { ProgressView().controlSize(.small) } else { Image(systemName: "sparkles") }
                    Text(gerando ? "O committer está escrevendo…" : "Gerar título e descrição com o committer")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(marcados.isEmpty || gerando)
            .help("Pelas regras do agente committer: formato, [Nome] na conta compartilhada, linha Journify. Usa tokens.")
            Button { commitar() } label: {
                HStack {
                    if commitando { ProgressView().controlSize(.small) }
                    Text(marcados.isEmpty ? "Marque os arquivos" : "Commit de \(marcados.count) arquivo(s) em \(branch)").lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!(dados?.gitflow ?? false) || marcados.isEmpty || titulo.trimmingCharacters(in: .whitespaces).isEmpty || commitando)
        }
        .padding(10)
    }

    // ---------- direita: o diff ----------
    private var painelDiff: some View {
        VStack(spacing: 0) {
            if let atual, let a = dados?.arquivos.first(where: { $0.arquivo == atual }) {
                HStack {
                    ArquivoLinha(estado: a.estado, caminho: a.arquivo, inteiro: true)
                    Spacer()
                    Text(marcados.contains(atual) ? "vai no commit" : "fora do commit").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                Divider()
                ScrollView([.vertical, .horizontal]) { Diff(texto: diff).padding(8) }
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                Text(dados?.arquivos.isEmpty == false ? "Escolha um arquivo para ver o diff" : "")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
                titulo = linhas.first ?? ""
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
            let msg = titulo + (descricao.isEmpty ? "" : "\n\n" + descricao)
            let (r, erro): (C?, String?) = await JFY.ler(["--commit-fazer", pasta, msg] + marcados.sorted())
            commitando = false
            aviso = r == nil ? erro : nil
            if let r {
                feito = "Commit \(r.sha): \(r.assunto)"
                titulo = ""
                descricao = ""
                await carregar()
                mudou()
            }
        }
    }
}

/// Um arquivo mexido: o que aconteceu com ele (+ novo, M mudou, − apagado, R renomeado), o nome em destaque e a pasta
/// mais clara, como no GitHub Desktop.
struct ArquivoLinha: View {
    let estado, caminho: String
    var inteiro = false

    var body: some View {
        let e = estado == "??" || estado.contains("A") ? ("+", Color.green) : estado.contains("D") ? ("−", Color.red)
            : estado.contains("R") ? ("R", Color.blue) : ("M", Color.orange)
        let nome = (caminho as NSString).lastPathComponent, pasta = (caminho as NSString).deletingLastPathComponent
        HStack(spacing: 6) {
            Text(e.0).font(.caption.monospaced().bold()).foregroundStyle(.white)
                .frame(width: 16, height: 16).background(RoundedRectangle(cornerRadius: 4).fill(e.1))
            Text(nome).lineLimit(1).layoutPriority(1)  // o nome inteiro; quem encolhe é a pasta
            if !pasta.isEmpty { Text(pasta).foregroundStyle(.secondary).lineLimit(1).truncationMode(inteiro ? .middle : .head) }
        }
        .help(caminho)
    }
}
