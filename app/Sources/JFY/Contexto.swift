import AppKit
import SwiftUI

/// A cesta de contexto: tasks, documentos, reuniões, arquivos, links, emails e PRs marcados pelo app inteiro, montados
/// pelo jfy numa pasta (CONTEXTO.md e os arquivos) e mandados ao Claude: conversa nova no projeto, uma aba aberta ou o
/// /pipeline de uma task. Fica guardada até ser enviada ou limpa.
struct ItemContexto: Codable, Hashable, Identifiable {
    var tipo, ref, titulo: String  // tipo: task, documento, reuniao, arquivo, link, email, pr; ref: o id, o link ou repo#n
    var origem: String?  // de onde veio (projeto, task, remetente), só para mostrar
    var pid: String?
    var nota = ""
    var id: String { tipo + "|" + ref }

    static let rotulos = ["task": "Tasks", "documento": "Documentos", "reuniao": "Reuniões", "arquivo": "Arquivos",
                          "link": "Links", "email": "Emails", "pr": "Pull requests"]
    static let icones = ["task": "checklist", "documento": "doc.text", "reuniao": "person.2", "arquivo": "paperclip",
                         "link": "link", "email": "envelope", "pr": "arrow.triangle.pull"]
}

@MainActor final class Cesta: ObservableObject {
    static let shared = Cesta()
    @Published var itens: [ItemContexto] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(itens), forKey: "contexto.itens") }
    }

    private init() {
        itens = UserDefaults.standard.data(forKey: "contexto.itens").flatMap { try? JSONDecoder().decode([ItemContexto].self, from: $0) } ?? []
    }

    func tem(_ i: ItemContexto) -> Bool { itens.contains { $0.id == i.id } }
    func alternar(_ i: ItemContexto) { if tem(i) { itens.removeAll { $0.id == i.id } } else { itens.append(i) } }
}

/// "+ Contexto" no topo de uma task, documento, reunião, email ou PR.
struct BotaoContexto: View {
    let item: ItemContexto
    @ObservedObject private var cesta = Cesta.shared
    var body: some View {
        let dentro = cesta.tem(item)
        Button { cesta.alternar(item) } label: {
            Label(dentro ? "No contexto" : "Contexto", systemImage: dentro ? "checkmark.circle.fill" : "plus.circle")
        }
        .help(dentro ? "Tirar da cesta de contexto" : "Pôr na cesta de contexto, para mandar ao Claude")
    }
}

/// O mesmo, no botão direito (linhas de arquivo, link, documento).
struct MenuContexto: View {
    let item: ItemContexto
    @ObservedObject private var cesta = Cesta.shared
    var body: some View {
        Button(cesta.tem(item) ? "Tirar do contexto" : "Adicionar ao contexto") { cesta.alternar(item) }
    }
}

struct ContextoTela: View {
    let ativa: Bool
    let irParaJFY: () -> Void
    @ObservedObject var abas: AbasTmux
    @ObservedObject private var cesta = Cesta.shared

    struct Projetos: Decodable {
        struct Projeto: Decodable { let id: String; let nome: String? }
        let projetos: [Projeto]
    }
    struct Montado: Decodable, Identifiable {
        struct Item: Decodable { let titulo, tipo: String; let tokens: Int; let aviso: String? }
        let pasta, pedido: String
        let pid, projeto: String?
        let tokens, arquivos: Int
        let itens: [Item]
        let quando: Double
        var id: String { pasta }
    }

    @AppStorage("contexto.pedido") private var pedido = ""
    @State private var destino = "conversa"  // conversa, aba ou pipeline
    @State private var pid = ""
    @State private var aba = ""
    @State private var tarefa = ""
    @State private var projetos: [Projetos.Projeto] = []
    @State private var montado: Montado?
    @State private var historico: [Montado] = []
    @State private var ocupado = false
    @State private var aviso: String?

    private var abasClaude: [AbasTmux.Aba] { abas.itens.filter { $0.nome != "menu" } }
    private var tasksNaCesta: [ItemContexto] { cesta.itens.filter { $0.tipo == "task" } }
    private var podeEnviar: Bool {
        switch destino {
        case "aba": abasClaude.contains { $0.id == aba }
        case "pipeline": !tarefa.isEmpty
        default: !pid.isEmpty
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            lista.frame(maxWidth: .infinity)
            Divider()
            painel.frame(width: 380).background(Souv.superficie)
        }
        .background(Souv.fundo)
        .task(id: ativa) {
            guard ativa else { return }
            await lerHistorico()
            if projetos.isEmpty, let p: Projetos = await JFY.ler(["--projetos-json"]).0 { projetos = p.projetos.filter { $0.nome != nil } }
            if pid.isEmpty { pid = cesta.itens.compactMap(\.pid).first(where: { p in projetos.contains { $0.id == p } }) ?? projetos.first?.id ?? "" }
            if tarefa.isEmpty { tarefa = tasksNaCesta.first?.ref ?? "" }
        }
        .onChange(of: cesta.itens) { montado = nil }
    }

    // ---------- a cesta ----------
    private var lista: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cesta de contexto").font(Souv.titulo(24)).foregroundStyle(Souv.texto)
                Text("\(cesta.itens.count)").foregroundStyle(Souv.texto2)
                Spacer()
                if !cesta.itens.isEmpty { Button("Limpar") { cesta.itens = [] } }
            }
            .padding(20)
            if cesta.itens.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray").font(.largeTitle).foregroundStyle(Souv.texto2)
                    Text("Marque tasks, documentos, reuniões, arquivos, links, emails e PRs com o botão Contexto (ou o botão direito). Eles se juntam aqui até você mandar para o Claude.")
                        .foregroundStyle(Souv.texto2).multilineTextAlignment(.center).frame(maxWidth: 440)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(ItemContexto.rotulos.keys.sorted { ordem($0) < ordem($1) }, id: \.self) { tipo in
                        let doTipo = cesta.itens.filter { $0.tipo == tipo }
                        if !doTipo.isEmpty {
                            Section(ItemContexto.rotulos[tipo] ?? tipo) { ForEach(doTipo) { linha($0) } }
                        }
                    }
                }
                .listaSouv(Souv.fundo)
            }
            if !historico.isEmpty { enviados }
        }
    }

    private func ordem(_ tipo: String) -> Int { ["task", "documento", "reuniao", "arquivo", "link", "email", "pr"].firstIndex(of: tipo) ?? 9 }

    private func linha(_ i: ItemContexto) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ItemContexto.icones[i.tipo] ?? "doc").foregroundStyle(Souv.destaque).frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(i.titulo).lineLimit(1)
                if let o = i.origem { Text(o).font(.caption).foregroundStyle(Souv.texto2).lineLimit(1) }
                TextField("nota para o Claude (opcional)", text: Binding(
                    get: { i.nota },
                    set: { n in if let k = cesta.itens.firstIndex(where: { $0.id == i.id }) { cesta.itens[k].nota = n } }))
                    .campoSouv().font(.callout)
            }
            Button { cesta.alternar(i) } label: { Image(systemName: "xmark") }.buttonStyle(.souvIcone).help("Tirar da cesta")
        }
        .padding(.vertical, 4)
    }

    private var enviados: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ENVIADOS").font(.caption.weight(.semibold)).foregroundStyle(Souv.texto2)
            ForEach(historico.prefix(5)) { h in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(h.pedido.isEmpty ? h.itens.map(\.titulo).joined(separator: ", ") : h.pedido).lineLimit(1)
                        Text("\(Date(timeIntervalSince1970: h.quando).formatted(date: .abbreviated, time: .shortened)) · \(h.itens.count) itens · ~\(mil(h.tokens)) tokens"
                             + (h.projeto.map { " · \($0)" } ?? ""))
                            .font(.caption).foregroundStyle(Souv.texto2)
                    }
                    Spacer()
                    Button("Mandar de novo") { enviar(h.pasta) }.disabled(!podeEnviar || ocupado)
                        .help("Manda esta cesta, como foi montada, para o destino escolhido ao lado")
                }
            }
        }
        .padding(16)
        .background(Souv.superficie)
    }

    // ---------- pedido, destino e envio ----------
    private var painel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("O que você quer que o Claude faça").font(.headline)
                TextEditor(text: $pedido).font(Souv.corpo(14)).frame(height: 110).campoSouv()
                Text("Mandar para").font(.headline)
                Segmentos(selecao: $destino, opcoes: [.init(valor: "conversa", rotulo: "Conversa nova"), .init(valor: "aba", rotulo: "Aba aberta"),
                                                     .init(valor: "pipeline", rotulo: "Pipeline")], cheio: true)
                switch destino {
                case "aba":
                    if abasClaude.isEmpty { Text("Nenhuma aba aberta no jfy.").foregroundStyle(Souv.texto2) }
                    else { SouvSelect(opcoes: abasClaude.map { .init(valor: $0.id, rotulo: $0.nome) }, selecionado: aba, vazio: "Escolha a aba") { aba = $0 } }
                    Text("O pedido é escrito na aba, como se você digitasse.").font(.caption).foregroundStyle(Souv.texto2)
                case "pipeline":
                    if tasksNaCesta.isEmpty { Text("Ponha a task na cesta para mandar pelo /pipeline dela.").foregroundStyle(Souv.texto2) }
                    else { SouvSelect(opcoes: tasksNaCesta.map { .init(valor: $0.ref, rotulo: $0.titulo) }, selecionado: tarefa, vazio: "Escolha a task") { tarefa = $0 } }
                    Text("Abre o /pipeline da task com o contexto nas notas (se a aba dela já existe, escreve nela).")
                        .font(.caption).foregroundStyle(Souv.texto2)
                default:
                    SouvSelect(opcoes: projetos.map { .init(valor: $0.id, rotulo: $0.nome ?? $0.id) }, selecionado: pid, vazio: "Escolha o projeto") { pid = $0 }
                    Text("Uma aba nova com o Claude na pasta do projeto.").font(.caption).foregroundStyle(Souv.texto2)
                }
                Button { Task { await montar() } } label: {
                    Label(ocupado && montado == nil ? "Montando…" : "Montar o contexto", systemImage: "shippingbox").frame(maxWidth: .infinity)
                }
                .buttonStyle(.souvPrimario).disabled(cesta.itens.isEmpty || ocupado)
                if let montado { revisao(montado) }
                if let aviso { Label(aviso, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
            }
            .padding(20)
        }
    }

    private func revisao(_ m: Montado) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("~\(mil(m.tokens)) tokens · \(m.arquivos) arquivo\(m.arquivos == 1 ? "" : "s") baixado\(m.arquivos == 1 ? "" : "s")").font(.headline)
            if m.tokens > 150_000 {
                Label("Ficou grande: o Claude perde detalhe com contexto demais. Tire o que não importa.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.callout)
            }
            ForEach(Array(m.itens.enumerated()), id: \.offset) { _, i in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: i.aviso == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(i.aviso == nil ? .green : .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(i.titulo).lineLimit(1)
                        if let a = i.aviso { Text(a).font(.caption).foregroundStyle(.orange) }
                    }
                    Spacer()
                    Text(mil(i.tokens)).font(.caption).foregroundStyle(Souv.texto2)
                }
            }
            HStack {
                Button("Abrir a pasta") { NSWorkspace.shared.open(URL(fileURLWithPath: m.pasta)) }
                Spacer()
                Button("Enviar") { enviar(m.pasta) }.buttonStyle(.souvPrimario).disabled(!podeEnviar || ocupado)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Souv.fundo))
    }

    private func mil(_ n: Int) -> String { n >= 1000 ? String(format: "%.1fk", Double(n) / 1000).replacingOccurrences(of: ".", with: ",") : "\(n)" }

    private func montar() async {
        ocupado = true
        aviso = nil
        montado = nil
        struct Pedido: Encodable { let itens: [ItemContexto]; let pedido, pid: String }
        let corpo = (try? JSONEncoder().encode(Pedido(itens: cesta.itens, pedido: pedido, pid: pid)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let (m, msg): (Montado?, String?) = await JFY.ler(["--contexto-montar"], entrada: corpo)
        montado = m
        aviso = msg
        ocupado = false
    }

    private func enviar(_ pasta: String) {
        Task {
            ocupado = true
            let alvo = destino == "aba" ? aba : destino == "pipeline" ? tarefa : ""
            aviso = await JFY.fazer(["--contexto-enviar", pasta, destino] + (alvo.isEmpty ? [] : [alvo]))
            ocupado = false
            guard aviso == nil else { return }
            if montado?.pasta == pasta { cesta.itens = []; pedido = ""; montado = nil }  // enviada: a cesta esvazia (fica no histórico)
            await lerHistorico()
            irParaJFY()
        }
    }

    private func lerHistorico() async {
        if let h: [Montado] = await JFY.ler(["--contexto-historico"]).0 { historico = h }
    }
}
