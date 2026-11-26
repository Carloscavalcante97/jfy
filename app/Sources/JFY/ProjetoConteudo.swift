import AppKit
import SwiftUI

/// As seções de um projeto, como no Journify: Tasks (a tela de sempre), Documentos e Reuniões (pelo MCP), Arquivos (os
/// anexos das tasks) e Formulários (esperando o MCP). Enviar arquivo e criar documento também esperam o MCP.
enum SecaoProjeto: String, CaseIterable {
    case tasks = "Tasks", documentos = "Documentos", reunioes = "Reuniões", arquivos = "Arquivos", formularios = "Formulários"
    var icone: String {
        switch self {
        case .tasks: "checklist"
        case .documentos: "doc.text"
        case .reunioes: "person.2"
        case .arquivos: "folder"
        case .formularios: "list.bullet.clipboard"
        }
    }
}

struct ProjetoConteudo: View {
    let secao: SecaoProjeto
    let pid: String
    let abrirTask: (String) -> Void

    var body: some View {
        switch secao {
        case .documentos: DocumentosProjeto(pid: pid)
        case .reunioes: ReunioesProjeto(pid: pid)
        case .arquivos: ArquivosProjeto(pid: pid, abrirTask: abrirTask)
        default:
            AguardandoMCP(titulo: "Formulários e respostas",
                          texto: "Os formulários do projeto e as respostas aparecem aqui quando o MCP do Journify tiver listar_formularios, obter_formulario e listar_respostas.")
        }
    }
}

/// O que a plataforma já desenhou mas o MCP do Journify ainda não entrega.
struct AguardandoMCP: View {
    let titulo, texto: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hourglass").font(.largeTitle).foregroundStyle(Souv.destaque)
            Text(titulo).font(Souv.titulo(20)).foregroundStyle(Souv.texto)
            Text(texto).foregroundStyle(Souv.texto2).multilineTextAlignment(.center).frame(maxWidth: 420)
            Text("Aguardando o MCP").font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Souv.primaria.opacity(0.18))).foregroundStyle(Souv.primaria)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Souv.fundo)
    }
}

/// Botão de algo que espera o MCP (Enviar arquivos, Novo documento): aparece, mas desligado, com o porquê.
private func botaoAguardando(_ titulo: String, _ icone: String, _ ferramenta: String) -> some View {
    Button {} label: { Label(titulo, systemImage: icone) }
        .disabled(true)
        .help("Aguardando o MCP do Journify (\(ferramenta))")
}

/// Texto de documento ou resumo do Journify: uns vêm em markdown, outros em HTML. O HTML passa pelo leitor do próprio
/// macOS (títulos, listas, links, código), sem as cores dele, para seguir o tema do app.
struct TextoJournify: View {
    let texto: String
    @State private var rico: AttributedString?

    private var html: Bool { texto.range(of: #"<(p|h[1-6]|ul|ol|li|div|br|pre|table)\b"#, options: .regularExpression) != nil }

    var body: some View {
        Group {
            if !html { Markdown(texto: texto) }
            else if let rico { Text(rico).foregroundStyle(Souv.texto).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            else { ProgressView() }
        }
        .task(id: texto) {
            guard html else { return }
            let css = "<style>body{font-family:Roboto,-apple-system;font-size:14px;line-height:1.5}h1{font-size:22px}h2{font-size:18px}"
                + "h3{font-size:15px}code,pre{font-family:Menlo;font-size:12px}</style>"
            guard let dados = (css + texto).data(using: .utf8),
                  let ns = try? NSMutableAttributedString(data: dados, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                                 .characterEncoding: String.Encoding.utf8.rawValue],
                                                          documentAttributes: nil)
            else { rico = AttributedString(texto); return }
            ns.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: ns.length))
            rico = (try? AttributedString(ns, including: \.appKit)) ?? AttributedString(ns.string)
        }
    }
}

// ---------- documentos ----------
private struct DocumentosProjeto: View {
    let pid: String
    struct Doc: Decodable, Identifiable { let id, titulo: String; let atualizado: String?; let sensivel: Bool }
    struct Conteudo: Decodable { let titulo, texto: String }

    @State private var docs: [Doc]?
    @State private var aviso: String?
    @State private var busca = ""
    @State private var aberto: String?
    @State private var conteudo: Conteudo?
    @State private var carregando = false
    @State private var revelado: Set<String> = []  // sensíveis que a pessoa pediu para ver

    private var filtrados: [Doc] {
        (docs ?? []).filter { busca.isEmpty || $0.titulo.localizedCaseInsensitiveContains(busca) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    TextField("Buscar documento", text: $busca).campoSouv()
                    botaoAguardando("Novo", "plus", "criar_documento").labelStyle(.iconOnly)
                }
                .padding(10)
                if let docs, docs.isEmpty {
                    Text(aviso ?? "Nenhum documento neste projeto.").foregroundStyle(.secondary).frame(maxHeight: .infinity)
                } else if docs == nil {
                    Group { if let aviso { Text(aviso).foregroundStyle(.secondary).padding() } else { ProgressView() } }.frame(maxHeight: .infinity)
                } else {
                    List(filtrados) { d in
                        HStack(spacing: 8) {
                            Image(systemName: d.sensivel ? "lock.fill" : "doc.text").foregroundStyle(d.sensivel ? .orange : Souv.texto2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.titulo).lineLimit(1)
                                Text(relativo(d.atualizado)).font(.caption).foregroundStyle(Souv.texto2)
                            }
                        }
                        .linhaSouv(aberto == d.id) { aberto = d.id }
                        .menuSouv(se: !d.sensivel) { MenuContexto(item: .init(tipo: "documento", ref: d.id, titulo: d.titulo, pid: pid)) }
                    }
                    .listaSouv()
                }
            }
            .frame(width: 300)
            .background(Souv.superficie)
            Divider()
            leitor.frame(maxWidth: .infinity, maxHeight: .infinity).background(Souv.fundo)
        }
        .task { await carregar() }
        .task(id: "\(aberto ?? "")|\(revelado.count)") { await abrir() }
    }

    @ViewBuilder private var leitor: some View {
        if let id = aberto, let d = docs?.first(where: { $0.id == id }) {
            if d.sensivel && !revelado.contains(id) {
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.orange)
                    Text(d.titulo).font(.headline)
                    Text("Pelo título, este documento parece guardar credenciais. O conteúdo fica escondido até você pedir, e segredo não deveria morar em documento do projeto.")
                        .foregroundStyle(Souv.texto2).multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button("Mostrar o conteúdo") { revelado.insert(id) }
                }
            } else if let conteudo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(conteudo.titulo).font(Souv.titulo(24)).foregroundStyle(Souv.texto)
                            Spacer()
                            if !d.sensivel { BotaoContexto(item: .init(tipo: "documento", ref: d.id, titulo: d.titulo, pid: pid)) }
                        }
                        Text("Atualizado \(relativo(d.atualizado))").font(.caption).foregroundStyle(Souv.texto2)
                        TextoJournify(texto: conteudo.texto)
                    }
                    .padding(28)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if carregando {
                ProgressView()
            } else if let aviso {
                Text(aviso).foregroundStyle(.secondary)
            }
        } else {
            Text("Escolha um documento").foregroundStyle(.secondary)
        }
    }

    private func carregar() async {
        let (d, msg): ([Doc]?, String?) = await JFY.ler(["--docs-json", pid])
        docs = d
        aviso = msg
        if aberto == nil { aberto = d?.first(where: { !$0.sensivel })?.id }
    }

    private func abrir() async {
        conteudo = nil
        guard let id = aberto, let d = docs?.first(where: { $0.id == id }), !d.sensivel || revelado.contains(id) else { return }
        carregando = true
        let (c, msg): (Conteudo?, String?) = await JFY.ler(["--doc-json", id])
        carregando = false
        if aberto == id { conteudo = c; aviso = msg }
    }
}

// ---------- reuniões ----------
private struct ReunioesProjeto: View {
    let pid: String
    struct Reuniao: Decodable, Identifiable { let id, titulo: String; let data: String?; let resumo: Bool }
    struct Detalhe: Decodable { let titulo: String; let data: String?; let participantes: [String]; let resumo: String }

    @State private var reunioes: [Reuniao]?
    @State private var aviso: String?
    @State private var aberta: String?
    @State private var detalhe: Detalhe?

    var body: some View {
        Group {
            if let reunioes, reunioes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2").font(.largeTitle).foregroundStyle(Souv.texto2)
                    Text(aviso ?? "Nenhuma reunião registrada neste projeto no Journify.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let reunioes {
                HStack(spacing: 0) {
                    List(reunioes) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.titulo).lineLimit(1)
                            HStack(spacing: 6) {
                                Text(dataISO(r.data).map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "").font(.caption)
                                if r.resumo { Label("resumo", systemImage: "text.alignleft").font(.caption2) }
                            }
                            .foregroundStyle(Souv.texto2)
                        }
                        .linhaSouv(aberta == r.id) { aberta = r.id }
                    }
                    .listaSouv()
                    .frame(width: 300)
                    Divider()
                    Group {
                        if let detalhe {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(detalhe.titulo).font(Souv.titulo(24)).foregroundStyle(Souv.texto)
                                        Spacer()
                                        if let a = aberta { BotaoContexto(item: .init(tipo: "reuniao", ref: a, titulo: detalhe.titulo, pid: pid)) }
                                    }
                                    if let d = dataISO(detalhe.data) {
                                        Text(d.formatted(date: .complete, time: .shortened)).foregroundStyle(Souv.texto2)
                                    }
                                    if !detalhe.participantes.isEmpty {
                                        Label(detalhe.participantes.joined(separator: ", "), systemImage: "person.2").foregroundStyle(Souv.texto2)
                                    }
                                    Divider()
                                    if detalhe.resumo.isEmpty { Text("Esta reunião ainda não tem resumo.").foregroundStyle(.secondary) }
                                    else { TextoJournify(texto: detalhe.resumo) }
                                }
                                .padding(28)
                                .frame(maxWidth: 820, alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if aberta != nil { ProgressView() } else { Text("Escolha uma reunião").foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Group { if let aviso { Text(aviso).foregroundStyle(.secondary) } else { ProgressView() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Souv.fundo)
        .task {
            let (r, msg): ([Reuniao]?, String?) = await JFY.ler(["--reunioes-projeto-json", pid])
            reunioes = r
            aviso = msg
            aberta = r?.first?.id
        }
        .task(id: aberta) {
            detalhe = nil
            guard let id = aberta else { return }
            let (d, msg): (Detalhe?, String?) = await JFY.ler(["--reuniao-json", id])
            if aberta == id { detalhe = d; if d == nil { aviso = msg } }
        }
    }
}

// ---------- arquivos ----------
private struct ArquivosProjeto: View {
    let pid: String
    let abrirTask: (String) -> Void
    struct Arquivo: Decodable, Identifiable {
        let id, nome, tipo, categoria, task: String
        let url, por, quando, taskTitulo: String?
        let tamanho: Double?
    }
    struct Resposta: Decodable { let arquivos: [Arquivo]; let tasks, lidas: Int; let lido: Double? }
    static let categorias = ["Todas", "Documentos", "Planilhas", "Imagens", "Outros"]

    @State private var r: Resposta?
    @State private var aviso: String?
    @State private var carregando = false
    @State private var categoria = "Todas"
    @State private var busca = ""

    private var filtrados: [Arquivo] {
        (r?.arquivos ?? []).filter {
            (categoria == "Todas" || $0.categoria == categoria)
                && (busca.isEmpty || $0.nome.localizedCaseInsensitiveContains(busca) || ($0.taskTitulo ?? "").localizedCaseInsensitiveContains(busca))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Segmentos(selecao: $categoria, opcoes: Self.categorias.map { .init(valor: $0, rotulo: $0) })
                Spacer(minLength: 8)
                TextField("Buscar arquivo", text: $busca).campoSouv().frame(maxWidth: 240)
                Button { Task { await carregar(forcar: true) } } label: {
                    if carregando && r != nil { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .help("Ler de novo do Journify (fica guardado por 24 h)").disabled(carregando)
                botaoAguardando("Enviar arquivos", "arrow.up.doc", "enviar_arquivo").buttonStyle(.souvPrimario)
            }
            .padding(12)
            Divider()
            if let r {
                if filtrados.isEmpty {
                    Text(r.arquivos.isEmpty ? "Nenhuma task deste projeto tem anexo." : "Nenhum arquivo com esse filtro.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtrados) { a in linha(a) }.listaSouv(Souv.fundo)
                }
                Text(rodape(r)).font(.caption).foregroundStyle(Souv.texto2).padding(8).frame(maxWidth: .infinity, alignment: .leading)
            } else if let aviso {
                Text(aviso).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Lendo os anexos de cada task. Num projeto grande, a leitura leva até uns 2 minutos; depois fica guardada por 24 h (o ↻ lê de novo).")
                        .font(.callout).foregroundStyle(Souv.texto2).multilineTextAlignment(.center).frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Souv.fundo)
        .task { await carregar() }
    }

    private func linha(_ a: Arquivo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icone(a.categoria)).font(.title3).foregroundStyle(Souv.destaque).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.nome).lineLimit(1)
                Text([a.taskTitulo, a.por, relativo(a.quando)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Souv.texto2).lineLimit(1)
            }
            Spacer()
            if let t = a.tamanho { Text(ByteCountFormatter.string(fromByteCount: Int64(t), countStyle: .file)).font(.caption).foregroundStyle(Souv.texto2) }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { abrir(a) }
        .help("Abrir o arquivo")
        .menuSouv {
            Button("Abrir o arquivo", systemImage: "arrow.up.forward.square") { abrir(a) }
            Button("Abrir a task", systemImage: "checklist") { abrirTask(a.task) }
            if let u = a.url { MenuContexto(item: .init(tipo: "arquivo", ref: u, titulo: a.nome, origem: a.taskTitulo, pid: pid)) }
            if let u = a.url { Button("Copiar o link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(u, forType: .string) } }
        }
    }

    private func rodape(_ r: Resposta) -> String {
        let n = "\(r.arquivos.count) anexo\(r.arquivos.count == 1 ? "" : "s") em \(r.tasks) task\(r.tasks == 1 ? "" : "s")."
            + (r.lido.map { " Lido \(relativo(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0))))." } ?? "")
        let faltou = r.lidas < r.tasks ? " O Journify não deixou ler \(r.tasks - r.lidas) delas agora; tente de novo em instantes." : ""
        return n + faltou + " Arquivos enviados direto no projeto ainda não vêm pelo MCP."
    }

    private func icone(_ c: String) -> String {
        switch c {
        case "Imagens": "photo"
        case "Planilhas": "tablecells"
        case "Documentos": "doc.richtext"
        default: "doc"
        }
    }

    private func abrir(_ a: Arquivo) {
        if let u = a.url.flatMap(URL.init(string:)) { NSWorkspace.shared.open(u) }
    }

    private func carregar(forcar: Bool = false) async {
        carregando = true
        let (x, msg): (Resposta?, String?) = await JFY.ler(["--arquivos-json", pid] + (forcar ? ["forcar"] : []))
        carregando = false
        if let x { r = x; aviso = nil } else if r == nil { aviso = msg }
    }
}
