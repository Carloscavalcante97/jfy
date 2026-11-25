import AppKit
import Charts
import SwiftUI

// ---------- dados: a saída do `jfy --uso [dias]` ----------
struct Uso: Decodable {
    struct Tipos: Decodable { let entrada, saida, cacheEscrita, cacheLeitura: Double }
    struct Limite: Decodable { let usedPercentage: Double; let resetsAt: Double? }
    struct Limites: Decodable { let fiveHour, sevenDay: Limite? }
    struct Sub: Decodable { let principal, subagentes: Double }
    struct DiaProjeto: Decodable, Identifiable {
        let dia, projeto: String
        let custo: Double
        var id: String { dia + projeto }
    }
    struct Ferramenta: Decodable, Identifiable {
        let nome: String
        let chamadas, resultadoTokens: Int
        var id: String { nome }
    }

    let total: Linha
    let economiaCache: Double
    let semPreco: [String]
    let custoPorTipo: Tipos
    let limites: Limites
    let subagentes: Sub
    let porDia: [Linha]
    let porDiaProjeto: [DiaProjeto]
    let porProjeto, porModelo, porTask, sessoes: [Linha]
    let ferramentas: [Ferramenta]
}

struct Linha: Decodable, Identifiable {
    let nome: String?
    let custo: Double
    let entrada, saida, cacheEscrita, cacheLeitura, respostas, sessoes: Int
    let titulo, projeto, url, branch, task, inicio: String?
    let contextoMax: Int?
    var id: String { nome ?? "total" }
    var tokens: Int { entrada + saida + cacheEscrita + cacheLeitura }
}

// ---------- formatos ----------
private let br = Locale(identifier: "pt_BR")
private func dinheiro(_ v: Double) -> String { v.formatted(.currency(code: "USD").locale(br)) }
private func tok(_ n: Int) -> String { n.formatted(.number.notation(.compactName).locale(br)) }
private func pct(_ v: Double) -> String { v.formatted(.percent.precision(.fractionLength(0)).locale(br)) }
private func dia(_ s: String) -> Date {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.date(from: s) ?? .distantPast
}
private func quando(_ iso: String?) -> String {
    guard let iso, let d = try? Date(iso, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))
    else { return "" }
    return d.formatted(.dateTime.day().month(.twoDigits).hour().minute().locale(br))
}

// ---------- cores: paleta categórica de referência, com o passo do modo escuro ----------

/// Ordem fixa: a cor segue o projeto pela posição no ranking do período, e os 6 primeiros têm cor própria.
let SERIES: [Color] = [
    Color(claro: 0x257DE0, escuro: 0x338CED), Color(claro: 0xF47230, escuro: 0xE76624),
    Color(claro: 0x00B894, escuro: 0x00A888), Color(claro: 0xF2A600, escuro: 0xD28E05),
    Color(claro: 0xEE7FAC, escuro: 0xE24D8B), Color(claro: 0x008A17, escuro: 0x0AAC23),
]
private let OUTROS = Color(claro: 0xB4B4B4, escuro: 0x5A5A5A)
private let UMA = Souv.primaria  // ranking de uma série só: o Vivid Blue da Souv

// ---------- tela ----------
struct UsoTela: View {
    @State private var dias = 30  // 0 = tudo
    @State private var uso: Uso?
    @State private var erro: String?
    @State private var carregando = false
    @State private var avaliacao: Avaliacao?
    @State private var avaliando = false
    @State private var erroAvaliacao: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                cabecalho
                if avaliando {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("O Claude está lendo os seus pedidos e os sinais de atrito do período. Leva uns 2 minutos.")
                            .foregroundStyle(Souv.texto2)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Souv.superficie))
                }
                if let erroAvaliacao { Label(erroAvaliacao, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
                if let a = avaliacao, a.resumo != nil, !avaliando { CartaoAvaliacao(a: a) }
                if let erro {
                    Label(erro, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let uso {
                    Conteudo(uso: uso, dias: dias).opacity(carregando ? 0.5 : 1)
                } else if carregando {
                    ProgressView("Lendo as conversas do Claude Code…").frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(24)
        }
        .task(id: dias) {
            avaliacao = nil
            erroAvaliacao = nil
            let (a, _): (Avaliacao?, String?) = await JFY.ler(["--uso-avaliar", String(dias), "ver"])  // a última, sem gastar
            avaliacao = a
            await carregar()
        }
    }

    /// O Claude avalia o período: o que já funciona, onde está o atrito e como melhorar (com exemplos seus).
    private func avaliar() {
        Task {
            avaliando = true
            erroAvaliacao = nil
            let (a, msg): (Avaliacao?, String?) = await JFY.ler(["--uso-avaliar", String(dias)])
            avaliando = false
            if let a { avaliacao = a } else { erroAvaliacao = msg }
        }
    }

    private var cabecalho: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Uso da IA").font(Souv.titulo(30))
                Text("Claude Code neste Mac. Custo em US$ pelo preço da API: na assinatura é o valor equivalente, não a conta.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Período", selection: $dias) {
                Text("Hoje").tag(1)
                Text("7 dias").tag(7)
                Text("30 dias").tag(30)
                Text("Tudo").tag(0)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Button(action: avaliar) {
                Label(avaliacao?.resumo == nil ? "Avaliar este período" : "Avaliar de novo", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent).disabled(avaliando)
            .help("O Claude lê os seus pedidos e os sinais de atrito do período e diz como usar melhor (usa tokens)")
            Button { Task { await carregar() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Atualizar").disabled(carregando)
        }
    }

    private func carregar() async {
        carregando = true
        defer { carregando = false }
        let r = await JFY.rodar(["--uso"] + (dias > 0 ? [String(dias)] : []))
        guard r.status == 0 else {
            erro = r.erro.isEmpty ? "jfy --uso falhou (código \(r.status))" : r.erro
            return
        }
        do {
            let d = JSONDecoder()
            d.keyDecodingStrategy = .convertFromSnakeCase
            uso = try d.decode(Uso.self, from: Data(r.saida.utf8))
            erro = nil
        } catch {
            erro = "Não entendi a resposta do jfy --uso: \(error)"
        }
    }
}

private struct Conteudo: View {
    let uso: Uso
    let dias: Int
    @State private var diaEmFoco: Date?

    private var t: Linha { uso.total }
    /// Os 6 projetos de maior custo têm cor; o resto vira "outros" (o jfy --uso já agrupa assim por dia).
    private var dominio: [String] {
        Array(uso.porProjeto.prefix(6).map { $0.nome ?? "" })
            + (uso.porDiaProjeto.contains { $0.projeto == "outros" } ? ["outros"] : [])
    }
    private func cor(_ projeto: String?) -> Color {
        guard let i = uso.porProjeto.prefix(6).firstIndex(where: { $0.nome == projeto }) else { return OUTROS }
        return SERIES[i]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            kpis
            Cartao("Custo por dia, por projeto") { grafico }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), alignment: .top)],
                      spacing: 16) {
                Cartao("Para onde foi o custo") { tipos }
                Cartao("Por projeto") { ranking(uso.porProjeto, cor: { cor($0.nome) }) }
                Cartao("Tasks do Journify") { tasks }
                Cartao("Por modelo") { ranking(uso.porModelo, cor: { _ in UMA }) }
                Cartao("Ferramentas mais usadas") { ferramentas }
                Cartao("Principal × subagentes") { subagentes }
            }
            Cartao("Sessões mais caras") { sessoes }
            if !uso.semPreco.isEmpty {
                Text("Modelos sem preço na tabela do jfy (contam US$ 0): \(uso.semPreco.joined(separator: ", ")).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // ---------- números do topo ----------
    private var kpis: some View {
        let entradas = Double(t.entrada + t.cacheEscrita + t.cacheLeitura)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            Kpi("Custo equivalente", dinheiro(t.custo), "o cache poupou \(dinheiro(uso.economiaCache))")
            Kpi("Tokens", tok(t.tokens),
                "\(tok(t.saida)) de saída · \(pct(entradas > 0 ? Double(t.cacheLeitura) / entradas : 0)) da entrada veio do cache")
            Kpi("Sessões", "\(t.sessoes)",
                "\(t.respostas.formatted(.number.locale(br))) respostas · \(dinheiro(t.sessoes > 0 ? t.custo / Double(t.sessoes) : 0)) por sessão")
            limite("Limite de 5 h", uso.limites.fiveHour, .dateTime.hour().minute())
            limite("Limite semanal", uso.limites.sevenDay, .dateTime.weekday(.abbreviated).hour().minute())
        }
    }

    private func limite(_ titulo: String, _ l: Uso.Limite?, _ fmt: Date.FormatStyle) -> some View {
        guard let l else { return Kpi(titulo, "—", "sem leitura: abra uma sessão do Claude pelo jfy") }
        let renova = l.resetsAt.map { "renova \(Date(timeIntervalSince1970: $0).formatted(fmt.locale(br)))" } ?? ""
        return Kpi(titulo, pct(l.usedPercentage / 100), renova, fracao: l.usedPercentage / 100)
    }

    // ---------- gráfico ----------
    private var grafico: some View {
        let porDia = Dictionary(grouping: uso.porDiaProjeto) { $0.dia }
        return Chart {
            ForEach(uso.porDiaProjeto) { p in
                BarMark(x: .value("Dia", dia(p.dia), unit: .day), y: .value("Custo", p.custo))
                    .foregroundStyle(by: .value("Projeto", p.projeto))
                    .cornerRadius(2)
            }
            if let d = diaEmFoco {
                let chave = diaLocal(d)
                let itens = (porDia[chave] ?? []).sorted { $0.custo > $1.custo }
                RuleMark(x: .value("Dia", d, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                    .lineStyle(StrokeStyle(lineWidth: 14))
                    .annotation(position: .top, alignment: .center, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        if !itens.isEmpty { Dica(dia: d, itens: itens, cor: cor) }
                    }
            }
        }
        .chartForegroundStyleScale(domain: dominio, range: dominio.map { cor($0 == "outros" ? nil : $0) })
        .chartXSelection(value: $diaEmFoco)
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel { if let x = v.as(Double.self) { Text(x.formatted(.currency(code: "USD").precision(.fractionLength(0)).locale(br))) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: dias == 0 || dias > 14 ? 7 : 1)) {
                AxisValueLabel(format: .dateTime.day().month(.twoDigits).locale(br))
            }
        }
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: 260)
    }

    // ---------- rankings ----------
    private func ranking(_ linhas: [Linha], cor: @escaping (Linha) -> Color) -> some View {
        let maior = linhas.first?.custo ?? 1
        return VStack(spacing: 10) {
            ForEach(linhas.prefix(10)) { l in
                Barra(nome: l.nome ?? "", valor: dinheiro(l.custo),
                      detalhe: "\(tok(l.tokens)) tokens · \(l.sessoes) \(l.sessoes == 1 ? "sessão" : "sessões")",
                      fracao: maior > 0 ? l.custo / maior : 0, cor: cor(l))
            }
        }
    }

    private var tipos: some View {
        let p = uso.custoPorTipo
        let itens = [("Leitura de cache", p.cacheLeitura, "o contexto relido a cada resposta"),
                     ("Escrita de cache", p.cacheEscrita, "contexto novo: arquivos lidos, resultados de comandos"),
                     ("Saída", p.saida, "o que o Claude escreveu, com o raciocínio"),
                     ("Entrada sem cache", p.entrada, "")]
        let soma = max(itens.map(\.1).reduce(0, +), 0.000001)
        return VStack(spacing: 10) {
            ForEach(itens, id: \.0) { nome, v, det in
                Barra(nome: nome, valor: "\(dinheiro(v)) · \(pct(v / soma))", detalhe: det.isEmpty ? nil : det,
                      fracao: v / (itens.map(\.1).max() ?? 1), cor: UMA)
            }
        }
    }

    private var tasks: some View {
        let maior = uso.porTask.first?.custo ?? 1
        return VStack(spacing: 10) {
            if uso.porTask.isEmpty {
                Text("Nenhuma task aberta pelo jfy neste período.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(uso.porTask.prefix(10)) { l in
                Barra(nome: l.titulo ?? l.nome ?? "", valor: dinheiro(l.custo),
                      detalhe: [l.projeto, "\(l.sessoes) \(l.sessoes == 1 ? "sessão" : "sessões")"].compactMap { $0 }.joined(separator: " · "),
                      fracao: maior > 0 ? l.custo / maior : 0, cor: cor(l.projeto), url: l.url.flatMap(URL.init(string:)))
            }
        }
    }

    private var ferramentas: some View {
        let maior = Double(uso.ferramentas.first?.chamadas ?? 1)
        return VStack(spacing: 10) {
            ForEach(uso.ferramentas.prefix(10)) { f in
                Barra(nome: f.nome, valor: "\(f.chamadas.formatted(.number.locale(br))) chamadas",
                      detalhe: "trouxe ≈ \(tok(f.resultadoTokens)) tokens para o contexto",
                      fracao: Double(f.chamadas) / maior, cor: UMA)
            }
        }
    }

    private var subagentes: some View {
        let s = uso.subagentes, soma = max(s.principal + s.subagentes, 0.000001)
        return VStack(spacing: 10) {
            Barra(nome: "Conversa principal", valor: "\(dinheiro(s.principal)) · \(pct(s.principal / soma))", fracao: s.principal / soma, cor: UMA)
            Barra(nome: "Subagentes (pipeline, buscas)", valor: "\(dinheiro(s.subagentes)) · \(pct(s.subagentes / soma))",
                  fracao: s.subagentes / soma, cor: UMA)
        }
    }

    private var sessoes: some View {
        VStack(spacing: 0) {
            ForEach(Array(uso.sessoes.prefix(15).enumerated()), id: \.element.id) { i, l in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Circle().fill(cor(l.projeto)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.titulo ?? "(sem título)").lineLimit(1)
                        Text([l.projeto, l.branch, quando(l.inicio), "\(l.respostas) respostas",
                              l.contextoMax.map { "contexto máx. \(tok($0))" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(dinheiro(l.custo)).monospacedDigit()
                }
                .padding(.vertical, 8)
                if i < min(uso.sessoes.count, 15) - 1 { Divider() }
            }
        }
    }
}

// ---------- peças ----------
private struct Cartao<C: View>: View {
    let titulo: String
    @ViewBuilder let conteudo: C
    init(_ titulo: String, @ViewBuilder _ conteudo: () -> C) {
        self.titulo = titulo
        self.conteudo = conteudo()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(titulo).font(.headline)
            conteudo
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Souv.superficie))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Souv.borda))
    }
}

private struct Kpi: View {
    let titulo, valor, detalhe: String
    var fracao: Double?
    init(_ titulo: String, _ valor: String, _ detalhe: String, fracao: Double? = nil) {
        (self.titulo, self.valor, self.detalhe, self.fracao) = (titulo, valor, detalhe, fracao)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo).font(.subheadline).foregroundStyle(.secondary)
            Text(valor).font(.title.weight(.semibold)).monospacedDigit()
            if let fracao {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(UMA).frame(width: max(3, g.size.width * min(max(fracao, 0), 1)))
                    }
                }
                .frame(height: 6)
            }
            Text(detalhe).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Souv.superficie))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Souv.borda))
    }
}

private struct Barra: View {
    let nome, valor: String
    var detalhe: String?
    let fracao: Double
    let cor: Color
    var url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(nome).lineLimit(1)
                if url != nil { Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary).imageScale(.small) }
                Spacer()
                Text(valor).monospacedDigit()
            }
            if let detalhe { Text(detalhe).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            GeometryReader { g in
                Capsule().fill(cor).frame(width: max(3, g.size.width * min(max(fracao, 0), 1)))
            }
            .frame(height: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { if let url { NSWorkspace.shared.open(url) } }
        .help(url == nil ? "" : "Abrir no Journify")
    }
}

private struct Dica: View {
    let dia: Date
    let itens: [Uso.DiaProjeto]
    let cor: (String?) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dia.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(br))).font(.caption.bold())
            ForEach(itens) { p in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(cor(p.projeto == "outros" ? nil : p.projeto)).frame(width: 8, height: 8)
                    Text(p.projeto).font(.caption)
                    Spacer(minLength: 12)
                    Text(dinheiro(p.custo)).font(.caption).monospacedDigit()
                }
            }
            Divider()
            HStack {
                Text("Total").font(.caption.bold())
                Spacer()
                Text(dinheiro(itens.map(\.custo).reduce(0, +))).font(.caption.bold()).monospacedDigit()
            }
        }
        .padding(10)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Souv.borda))
    }
}

// ---------- o uso dos limites do Claude no topo da janela ----------
/// O uso dos limites do Claude (janela de 5 h e semana), do mesmo arquivo que o statusline do Claude Code grava e que a
/// barra do tmux e o SwiftBar leem (~/.jfy/claude-status.json, ou a última leitura boa no .ok). Janela que já renovou
/// conta 0%, como lá. Olha a cada 15 s.
final class LimitesIA: ObservableObject {
    struct Janela: Equatable {
        let pct: Int
        let renova: Date?
    }

    @Published private(set) var cinco: Janela?
    @Published private(set) var semana: Janela?
    private var timer: Timer?

    init() {
        ler()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.ler() }
    }

    func ler() {
        let base = NSHomeDirectory() + "/.jfy/claude-status.json"
        for arq in [base, base + ".ok"] {
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: arq)),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let rl = j["rate_limits"] as? [String: Any] else { continue }
            func janela(_ k: String) -> Janela? {
                guard let x = rl[k] as? [String: Any] else { return nil }
                let r = (x["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                let viva = r.map { $0 > Date() } ?? false
                return Janela(pct: viva ? Int(((x["used_percentage"] as? Double) ?? 0).rounded()) : 0, renova: viva ? r : nil)
            }
            let c = janela("five_hour"), s = janela("seven_day")
            if c != cinco { cinco = c }
            if s != semana { semana = s }
            return
        }
    }
}

struct BarraUsoIA: View {
    @ObservedObject var limites: LimitesIA

    var body: some View {
        if let c = limites.cinco {
            HStack(spacing: 16) {
                medidor("5 h", c, c.renova.map { "renova " + $0.formatted(.dateTime.hour().minute()) })
                if let s = limites.semana {
                    medidor("Semana", s, s.renova.map {
                        let dia = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"][Calendar.current.component(.weekday, from: $0) - 1]
                        return "renova \(dia) " + $0.formatted(.dateTime.hour().minute())
                    })
                }
            }
            .help("Uso dos limites do Claude: o mesmo da barra do jfy no terminal e do ícone na barra de cima do Mac")
        }
    }

    private func medidor(_ nome: String, _ j: LimitesIA.Janela, _ renova: String?) -> some View {
        let cor: Color = j.pct >= 80 ? .red : j.pct >= 50 ? .orange : .green
        return HStack(spacing: 6) {
            Text(nome).font(.caption).foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(cor).frame(width: max(3, 70 * CGFloat(min(j.pct, 100)) / 100))
            }
            .frame(width: 70, height: 6)
            Text("\(j.pct)%").font(.caption.monospacedDigit().weight(.semibold))
            if let renova { Text(renova).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

// ---------- a avaliação do Claude ----------
struct Avaliacao: Decodable {
    struct Problema: Decodable, Hashable { let titulo, detalhe: String; let exemplo: String? }
    struct Recomendacao: Decodable, Hashable { let titulo, como: String; let antes, depois: String? }
    let resumo: String?
    let nota: Double?
    let acertos: [String]?
    let problemas: [Problema]?
    let recomendacoes: [Recomendacao]?
    let economia: [String]?
    let gerado: Double?
    let pedidos: Int?
}

/// O resultado da avaliação: nota e diagnóstico, o que já funciona, onde está o atrito (com um pedido seu de exemplo),
/// como melhorar (com o antes e o depois) e onde dá para gastar menos. Recolhe pela setinha.
struct CartaoAvaliacao: View {
    let a: Avaliacao
    @State private var aberto = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { withAnimation(.snappy(duration: 0.2)) { aberto.toggle() } } label: {
                HStack(alignment: .center, spacing: 14) {
                    nota
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Avaliação do Claude").font(Souv.titulo(20)).foregroundStyle(Souv.texto)
                        Text(rodape).font(.caption).foregroundStyle(Souv.texto2)
                    }
                    Spacer()
                    Image(systemName: "chevron.down").foregroundStyle(Souv.texto2).rotationEffect(.degrees(aberto ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let r = a.resumo { Text(r).font(Souv.corpo(14)).foregroundStyle(Souv.texto).fixedSize(horizontal: false, vertical: true) }
            if aberto {
                if let xs = a.acertos, !xs.isEmpty {
                    secao("O que já funciona", "checkmark.seal.fill", .green) {
                        ForEach(xs, id: \.self) { item($0) }
                    }
                }
                if let ps = a.problemas, !ps.isEmpty {
                    secao("Onde está o atrito", "exclamationmark.triangle.fill", .orange) {
                        ForEach(ps, id: \.self) { p in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(p.titulo).fontWeight(.semibold).foregroundStyle(Souv.texto)
                                Text(p.detalhe).foregroundStyle(Souv.texto2).fixedSize(horizontal: false, vertical: true)
                                if let e = p.exemplo, !e.isEmpty { citacao(e, cor: .orange) }
                            }
                        }
                    }
                }
                if let rs = a.recomendacoes, !rs.isEmpty {
                    secao("Como melhorar", "lightbulb.fill", Souv.destaque) {
                        ForEach(rs, id: \.self) { r in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(r.titulo).fontWeight(.semibold).foregroundStyle(Souv.texto)
                                Text(r.como).foregroundStyle(Souv.texto2).fixedSize(horizontal: false, vertical: true)
                                if let antes = r.antes, !antes.isEmpty { citacao(antes, cor: .red, rotulo: "Antes") }
                                if let depois = r.depois, !depois.isEmpty { citacao(depois, cor: .green, rotulo: "Depois") }
                            }
                        }
                    }
                }
                if let es = a.economia, !es.isEmpty {
                    secao("Para gastar menos", "dollarsign.circle.fill", Souv.primaria) {
                        ForEach(es, id: \.self) { item($0) }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Souv.superficie))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Souv.primaria.opacity(0.45)))
        .textSelection(.enabled)
    }

    private var nota: some View {
        let n = a.nota ?? 0, cor: Color = n >= 8 ? .green : n >= 5 ? .orange : .red
        return ZStack {
            Circle().stroke(cor.opacity(0.2), lineWidth: 5)
            Circle().trim(from: 0, to: n / 10).stroke(cor, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(n.formatted(.number.precision(.fractionLength(0...1)))).font(Souv.titulo(20)).foregroundStyle(Souv.texto)
        }
        .frame(width: 52, height: 52)
        .help("Nota de 0 a 10 para a eficiência do uso no período")
    }

    private var rodape: String {
        var partes: [String] = []
        if let g = a.gerado {
            partes.append("avaliado em " + Date(timeIntervalSince1970: g).formatted(.dateTime.day().month(.twoDigits).hour().minute()))
        }
        if let p = a.pedidos { partes.append("\(p) pedidos lidos") }
        partes.append("usa tokens")
        return partes.joined(separator: " · ")
    }

    private func secao(_ titulo: String, _ icone: String, _ cor: Color, @ViewBuilder _ conteudo: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(titulo.uppercased(), systemImage: icone).font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(cor)
            conteudo()
        }
    }

    private func item(_ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Souv.texto2).frame(width: 4, height: 4).offset(y: -3)
            Text(t).foregroundStyle(Souv.texto).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Um pedido seu (o exemplo, o antes ou o depois), com a barrinha da cor.
    private func citacao(_ t: String, cor: Color, rotulo: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(cor).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                if let rotulo { Text(rotulo.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(cor) }
                Text(t).font(.system(size: 12, design: .monospaced)).foregroundStyle(Souv.texto).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6).padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(cor.opacity(0.07)))
    }
}
