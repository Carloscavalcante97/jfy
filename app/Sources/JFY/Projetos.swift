import AppKit
import SwiftUI

/// Gestão das tasks: projetos, as tasks em seções (a mesma ordem da tela do projeto no jfy) e a task inteira, com
/// status, prioridade e prazo por clique, anexos e comentários. Quem fala com o Journify é o jfy
/// (--projetos-json, --tasks-json, --task-json, --task-mudar, --task-abrir).
struct ProjetosTela: View {
    let ativa: Bool
    let irParaJFY: () -> Void

    struct Resumo: Decodable, Identifiable, Hashable {
        let id, titulo, status, etapa, pid: String
        let prioridade, prazo, prazoTxt, projeto, cor: String?
        let dias: Int?
        let pontos: Double?
        let etapaN: Int
    }

    struct Projetos: Decodable {
        struct Projeto: Decodable, Identifiable {
            let id: String
            let nome, cor, exemplo: String?
            let tasks: Int
        }
        let foco: [Resumo]
        let projetos: [Projeto]
    }

    static let foco = "foco"  // o item "Foco" da lista de projetos

    @State private var dados: Projetos?
    @State private var projeto: String?
    @State private var todas = false
    @State private var tasks: [Resumo] = []
    @State private var task: String?
    @State private var carregando = false
    @State private var aviso: String?

    var body: some View {
        HStack(spacing: 0) {
            listaProjetos.frame(width: 210)
            Divider()
            listaTasks.frame(width: 340)
            Divider()
            if let task {
                TaskDetalhe(tid: task, irParaJFY: irParaJFY, mudou: { Task { await carregarTasks() } }).id(task)
            } else {
                Text(projeto == nil ? "Escolha um projeto" : "Escolha uma task").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: ativa) { if ativa, dados == nil { await carregarProjetos() } }
        .task(id: "\(projeto ?? "")|\(todas)") { await carregarTasks() }
    }

    // ---------- projetos ----------
    private var listaProjetos: some View {
        List(selection: $projeto) {
            if let d = dados {
                if !d.foco.isEmpty {
                    Label("Foco (\(d.foco.count))", systemImage: "flame").tag(Self.foco)
                }
                Section("Projetos") {
                    ForEach(d.projetos.filter { $0.tasks > 0 }) { linhaProjeto($0) }
                }
                Section("Sem task sua") {
                    ForEach(d.projetos.filter { $0.tasks == 0 }) { linhaProjeto($0) }
                }
            } else if let aviso {
                Text(aviso).foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button { Task { await carregarProjetos() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                .buttonStyle(.borderless).padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func linhaProjeto(_ p: Projetos.Projeto) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: p.cor)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.nome ?? "sem nome").lineLimit(1).foregroundStyle(p.nome == nil ? .secondary : .primary)
                if let ex = p.exemplo { Text("configure no menu do jfy · ex.: \(ex)").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if p.tasks > 0 { Text("\(p.tasks)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
        }
        .tag(p.id)
    }

    // ---------- tasks ----------
    private var listaTasks: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tituloProjeto).font(.headline).lineLimit(1)
                Spacer()
                if projeto != Self.foco && projeto != nil {
                    Picker("Tasks", selection: $todas) {
                        Text("Minhas").tag(false)
                        Text("Todas").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            .padding(12)
            Divider()
            if carregando && tasks.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tasks.isEmpty {
                Text(projeto == nil ? "" : aviso ?? "Nenhuma task aqui.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
                List(selection: $task) {
                    ForEach(secoes, id: \.0) { nome, itens in
                        Section(nome) {
                            ForEach(itens) { linhaTask($0) }
                        }
                    }
                }
                .opacity(carregando ? 0.5 : 1)
            }
        }
    }

    private var tituloProjeto: String {
        projeto == Self.foco ? "Foco: prazo perto ou crítica" : dados?.projetos.first { $0.id == projeto }?.nome ?? ""
    }

    private var secoes: [(String, [Resumo])] {
        var out: [(String, [Resumo])] = []
        for t in tasks {
            if out.last?.0 == t.etapa { out[out.count - 1].1.append(t) } else { out.append((t.etapa, [t])) }
        }
        return out
    }

    private func linhaTask(_ t: Resumo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t.titulo).lineLimit(2)
            HStack(spacing: 6) {
                if projeto == Self.foco { Circle().fill(Color(hex: t.cor)).frame(width: 6, height: 6); Text(t.projeto ?? "") }
                StatusChip(status: t.status, dias: t.dias)
                if let p = t.prazoTxt, !p.isEmpty { Text(p).foregroundStyle((t.dias ?? 99) <= 0 ? .red : .secondary) }
                if let pts = t.pontos { Text("\(pts.formatted()) pts") }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .tag(t.id)
    }

    // ---------- jfy ----------
    private func carregarProjetos() async {
        let (d, msg): (Projetos?, String?) = await JFY.ler(["--projetos-json"])
        if let d { dados = d }
        aviso = msg
        if projeto == nil { projeto = d?.foco.isEmpty == false ? Self.foco : d?.projetos.first?.id }
    }

    private func carregarTasks() async {
        guard let projeto else { return }
        carregando = true
        defer { carregando = false }
        if projeto == Self.foco {
            let (d, msg): (Projetos?, String?) = await JFY.ler(["--projetos-json"])
            tasks = d?.foco ?? []
            aviso = msg
        } else {
            let (d, msg): ([Resumo]?, String?) = await JFY.ler(["--tasks-json", projeto] + (todas ? ["todas"] : []))
            tasks = d ?? []
            aviso = msg
        }
        if let task, !tasks.contains(where: { $0.id == task }) { self.task = nil }
    }
}

// ---------- a task ----------
struct TaskDetalhe: View {
    let tid: String
    let irParaJFY: () -> Void
    let mudou: () -> Void

    struct Detalhe: Decodable {
        struct Anexo: Decodable, Identifiable {
            let n: Int
            let nome, tipo: String
            let url: String?
            let imagem: Bool
            var id: Int { n }
        }
        struct Comentario: Decodable, Identifiable {
            let autor: String?
            let texto: String
            let quando: String?
            var id: String { (quando ?? "") + texto.prefix(20) }
        }
        let titulo, status, pid, url, descricao: String
        let prioridade, prazo, projeto, cor, epico: String?
        let dias: Int?
        let pontos: Double?
        let configurado: Bool
        let statusApp, pedeVideo: [String]
        let anexos: [Anexo]
        let comentarios: [Comentario]
    }

    @State private var d: Detalhe?
    @State private var aviso: String?
    @State private var ocupado = false
    @State private var comentario = ""
    @State private var fechandoEm: String?  // status que pede o vídeo do teste
    @State private var video = ""

    var body: some View {
        Group {
            if let d { conteudo(d) } else if let aviso { Text(aviso).foregroundStyle(.secondary).padding() } else { ProgressView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await carregar() }
        .alert("Vídeo do teste", isPresented: Binding(get: { fechandoEm != nil }, set: { if !$0 { fechandoEm = nil } })) {
            TextField("link do vídeo, ou por que não tem", text: $video)
            Button("Mover") {
                if let s = fechandoEm, video.trimmingCharacters(in: .whitespaces).count >= 3 { mudar("status", s, video) }
                fechandoEm = nil
            }
            Button("Cancelar", role: .cancel) { fechandoEm = nil }
        } message: {
            Text("O Journify só move a task para \(rotulo(fechandoEm ?? "")) com o link do vídeo do teste ou o motivo de não ter vídeo.")
        }
    }

    private func conteudo(_ d: Detalhe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: d.cor)).frame(width: 9, height: 9)
                    Text(d.projeto ?? "projeto sem nome").foregroundStyle(.secondary)
                    if let e = d.epico { Text("· \(e)").foregroundStyle(.secondary) }
                    Spacer()
                    Link(destination: URL(string: d.url)!) { Label("Abrir no Journify", systemImage: "arrow.up.right.square") }
                }
                .font(.callout)
                Text(d.titulo).font(.title2.weight(.semibold)).textSelection(.enabled)
                controles(d)
                if let aviso { Label(aviso, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
                HStack {
                    Button { abrir("pipeline") } label: { Label("Implementar (/pipeline)", systemImage: "hammer") }
                        .buttonStyle(.borderedProminent)
                    Button { abrir("livre") } label: { Label("Conversar com o Claude", systemImage: "bubble.left") }
                }
                .disabled(!d.configurado)
                .help(d.configurado ? "Abre numa aba do jfy" : "Configure o projeto no menu do jfy antes")

                Secao("O que fazer") {
                    if d.descricao.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("(sem descrição)").foregroundStyle(.secondary)
                    } else {
                        Markdown(texto: d.descricao)
                    }
                }
                if !d.anexos.isEmpty { Secao("Anexos (\(d.anexos.count))") { anexos(d.anexos) } }
                Secao("Comentários (\(d.comentarios.count))") { comentarios(d.comentarios) }
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .opacity(ocupado ? 0.6 : 1)
    }

    private func controles(_ d: Detalhe) -> some View {
        HStack(spacing: 14) {
            Menu {
                ForEach(d.statusApp, id: \.self) { s in
                    Button(rotulo(s)) {
                        if d.pedeVideo.contains(s) { video = ""; fechandoEm = s } else { mudar("status", s) }
                    }
                }
            } label: { StatusChip(status: d.status, dias: d.dias) }
            .menuStyle(.borderlessButton).fixedSize()
            Menu {
                ForEach(["baixa", "media", "alta", "critica"], id: \.self) { p in Button(rotuloPrioridade(p)) { mudar("prioridade", p) } }
            } label: { Label(rotuloPrioridade(d.prioridade ?? "sem prioridade"), systemImage: "flag") }
            .menuStyle(.borderlessButton).fixedSize()
            DatePicker("Prazo", selection: Binding(
                get: { d.prazo.flatMap { try? Date($0, strategy: .iso8601.year().month().day()) } ?? Date() },
                set: { mudar("prazo", $0.formatted(.iso8601.year().month().day())) }), displayedComponents: .date)
                .fixedSize()
            if d.prazo == nil { Text("sem prazo").font(.caption).foregroundStyle(.secondary) }
            if let pts = d.pontos {
                Text("\(pts.formatted()) pts").foregroundStyle(pts > 8 ? .red : .secondary)
                    .help(pts > 8 ? "Acima de 8 pontos: não cabe num PR, divida a task" : "")
            }
        }
    }

    private func anexos(_ lista: [Detalhe.Anexo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let imgs = lista.filter(\.imagem), docs = lista.filter { !$0.imagem }
            if !imgs.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(imgs) { a in
                        Button { abrirURL(a.url) } label: {
                            AsyncImage(url: a.url.flatMap(URL.init(string:))) { img in
                                img.resizable().scaledToFill()
                            } placeholder: { Color.secondary.opacity(0.1).overlay(ProgressView().controlSize(.small)) }
                            .frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .bottomLeading) {
                                Text("a\(a.n)").font(.caption2.bold()).padding(4).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4)).padding(4)
                            }
                        }
                        .buttonStyle(.plain).help(a.nome)
                    }
                }
            }
            ForEach(docs) { a in
                Button { abrirURL(a.url) } label: {
                    Label { Text("a\(a.n)  \(a.nome)") } icon: { Image(systemName: icone(a.tipo)) }
                }
                .buttonStyle(.link).help("Abrir \(a.nome)")
            }
        }
    }

    private func comentarios(_ lista: [Detalhe.Comentario]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(lista) { c in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(c.autor ?? "?").font(.callout.weight(.semibold))
                        Text(quando(c.quando)).font(.caption).foregroundStyle(.secondary)
                    }
                    Markdown(texto: c.texto)
                }
            }
            HStack(alignment: .bottom) {
                TextField("Comentar", text: $comentario, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                Button("Enviar") { mudar("comentario", comentario); comentario = "" }
                    .disabled(comentario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ocupado)
            }
        }
    }

    // ---------- jfy ----------
    private func carregar() async {
        let (r, msg): (Detalhe?, String?) = await JFY.ler(["--task-json", tid])
        if let r { d = r }
        aviso = msg
    }

    private func mudar(_ campo: String, _ valor: String, _ extra: String = "") {
        Task {
            ocupado = true
            let erro = await JFY.fazer(["--task-mudar", tid, campo, valor] + (extra.isEmpty ? [] : [extra]))
            await carregar()
            ocupado = false
            aviso = erro
            if erro == nil, campo != "comentario" { mudou() }
        }
    }

    private func abrir(_ modo: String) {
        Task {
            if let erro = await JFY.fazer(["--task-abrir", tid, modo]) { aviso = erro } else { irParaJFY() }
        }
    }

    private func abrirURL(_ s: String?) {
        if let s, let u = URL(string: s) { NSWorkspace.shared.open(u) }  // só o link, como no jfy: nada é baixado
    }

    private func icone(_ tipo: String) -> String {
        tipo.contains("pdf") ? "doc.richtext" : tipo.contains("sheet") || tipo.contains("excel") || tipo.contains("csv") ? "tablecells"
            : tipo.hasPrefix("video/") ? "film" : tipo.contains("zip") ? "doc.zipper" : "doc"
    }

    private func quando(_ iso: String?) -> String {
        guard let iso, let d = try? Date(iso, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))
        else { return "" }
        return d.formatted(.dateTime.day().month(.twoDigits).hour().minute().locale(Locale(identifier: "pt_BR")))
    }
}

// ---------- peças ----------
func rotulo(_ status: String) -> String {
    ["em_revisao": "em revisão", "pendente_validacao": "pendente validação", "finalizado_validacao": "finalizado validação"][status]
        ?? status.replacingOccurrences(of: "_", with: " ")
}
func rotuloPrioridade(_ p: String) -> String {
    ["media": "média", "critica": "crítica"][p] ?? p
}

/// Cor da bolinha de cada status: uma para cada, para bater o olho na lista.
let CORES_STATUS: [String: Color] = [
    "em_aberto": .gray,
    "criando_escopo": .teal,
    "priorizado": Color(red: 0.0, green: 0.3, blue: 1.0),  // azul bem forte
    "em_progresso": .green,
    "em_revisao": .yellow,
    "em_teste": .purple,
    "pendente_validacao": Color(red: 1.0, green: 0.48, blue: 0.78),  // rosa claro: longe do vermelho de atrasada
    "bloqueado": .orange,
    "finalizado_validacao": .brown,
    "fechado": Color(claro: 0x3A3A3C, escuro: 0xC7C7CC),  // grafite: não some no fundo escuro
]

/// A bolinha do status, sempre com o nome escrito. Prazo vencido numa task ainda aberta pinta de vermelho e
/// escreve "atrasada": atrasada não é um status do Journify, é o prazo.
struct StatusChip: View {
    let status: String
    var dias: Int?

    var body: some View {
        let atrasada = (dias ?? 0) < 0 && !["fechado", "finalizado_validacao"].contains(status)
        HStack(spacing: 4) {
            Group {
                if status == "em_aberto" && !atrasada {
                    Circle().strokeBorder(Color.gray, lineWidth: 1.5)  // vazada: ainda não começou
                } else {
                    Circle().fill(atrasada ? .red : CORES_STATUS[status] ?? .gray)
                }
            }
            .frame(width: 8, height: 8)
            Text(rotulo(status) + (atrasada ? " · atrasada" : ""))
        }
    }
}

private struct Secao<C: View>: View {
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

/// O markdown que o jfy devolve (doc_texto: títulos, listas, **negrito**, ![](imagem), ``` código), bloco a bloco:
/// o Text do SwiftUI só entende o markdown de dentro da linha.
struct Markdown: View {
    let texto: String

    private enum Bloco: Hashable {
        case titulo(Int, String), item(Int, String), imagem(String), codigo(String), paragrafo(String), espaco
    }

    private var blocos: [Bloco] {
        var out: [Bloco] = [], codigo: [String]?
        for linha in texto.components(separatedBy: "\n") {
            if linha.hasPrefix("```") {
                if let c = codigo { out.append(.codigo(c.joined(separator: "\n"))); codigo = nil } else { codigo = [] }
                continue
            }
            if codigo != nil { codigo!.append(linha); continue }
            let limpa = linha.trimmingCharacters(in: .whitespaces)
            let recuo = (linha.count - linha.drop { $0 == " " }.count) / 2
            if limpa.isEmpty {
                if out.last != .espaco { out.append(.espaco) }
            } else if let m = limpa.wholeMatch(of: #/!\[[^\]]*\]\(([^)]+)\)/#) {
                out.append(.imagem(String(m.1)))
            } else if let m = limpa.firstMatch(of: #/^(#{1,6})\s+(.*)/#) {
                out.append(.titulo(m.1.count, String(m.2)))
            } else if let m = limpa.firstMatch(of: #/^[-*•]\s+(.*)/#) {
                out.append(.item(recuo, String(m.1)))
            } else {
                out.append(.paragrafo(limpa))
            }
        }
        if let c = codigo { out.append(.codigo(c.joined(separator: "\n"))) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocos.enumerated()), id: \.offset) { _, b in
                switch b {
                case let .titulo(n, t): linha(t).font(n <= 1 ? .title3.bold() : n == 2 ? .headline : .subheadline.bold()).padding(.top, 4)
                case let .item(recuo, t):
                    HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); linha(t) }.padding(.leading, CGFloat(recuo) * 16)
                case let .imagem(u):
                    AsyncImage(url: URL(string: u)) { $0.resizable().scaledToFit() } placeholder: { ProgressView().controlSize(.small) }
                        .frame(maxHeight: 320).onTapGesture { if let url = URL(string: u) { NSWorkspace.shared.open(url) } }
                case let .codigo(c):
                    Text(c).font(.system(.callout, design: .monospaced)).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                case let .paragrafo(t): linha(t)
                case .espaco: Spacer().frame(height: 2)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func linha(_ t: String) -> some View {
        Text((try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t))
            .fixedSize(horizontal: false, vertical: true)  // parágrafo longo quebra linha, não corta com "…"
    }
}
