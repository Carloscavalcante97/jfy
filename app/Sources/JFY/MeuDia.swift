import AppKit
import SwiftUI

/// A tela de entrada: o que pede você hoje, de todas as abas num lugar só. Os Claudes que pediram resposta, as
/// reuniões que faltam, as tasks no foco, os PRs esperando sua revisão, os importantes não lidos e a jornada.
/// Cada bloco carrega sozinho, com os mesmos comandos das abas (--agenda-json, --projetos-json, --github-json,
/// --emails-json), e o clique leva à aba certa, já no item.
struct MeuDiaTela: View {
    let ativa: Bool
    @ObservedObject var nav: Navegacao
    @ObservedObject var abas: AbasTmux

    enum Estado<T> { case carregando, pronto(T), erro(String) }

    @State private var reunioes: Estado<[ReunioesTela.Evento]> = .carregando
    @State private var foco: Estado<[ProjetosTela.Resumo]> = .carregando
    @State private var prs: Estado<[GithubTela.PR]> = .carregando
    @State private var emails: Estado<[EmailsTela.Lista.Item]> = .carregando
    @State private var recarga = 0

    static let meta = 8 * 60  // a JORNADA do jfy, em minutos
    static let arquivoDia = URL(fileURLWithPath: NSHomeDirectory() + "/.jfy/dia.json")

    private var chave: String { "\(ativa)|\(recarga)" }

    var body: some View {
        // a cada 30 s: a jornada anda e o "em 10 min" da reunião se atualiza, sem ir à rede
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let agora = ctx.date.timeIntervalSince1970
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    cabecalho(ctx.date)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 16, alignment: .top)], spacing: 16) {
                        claudes
                        cartaoReunioes(agora)
                        cartaoFoco
                        cartaoPRs
                        cartaoEmails
                        cartaoJornada(agora)
                    }
                }
                .padding(24)
            }
        }
        .task(id: chave) {
            guard ativa else { return }
            let hoje = diaLocal(Date())
            reunioes = await Self.ler(["--agenda-json", hoje, hoje]) { (a: ReunioesTela.Agenda) in
                a.eventos.filter { !$0.diaInteiro && !$0.recusado }.sorted { $0.ini < $1.ini }
            }
        }
        .task(id: chave) {
            guard ativa else { return }
            foco = await Self.ler(["--projetos-json"]) { (p: ProjetosTela.Projetos) in p.foco }
        }
        .task(id: chave) {
            guard ativa else { return }
            prs = await Self.ler(["--github-json"]) { (d: GithubTela.Dados) in d.revisar }
        }
        .task(id: chave) {
            guard ativa else { return }
            emails = await Self.ler(["--emails-json", "importantes"]) { (l: EmailsTela.Lista) in l.emails.filter { $0.lido == false } }
        }
    }

    private func cabecalho(_ hoje: Date) -> some View {
        let data = hoje.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR")))
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meu dia").font(Souv.titulo(30))
                Text(data.prefix(1).uppercased() + data.dropFirst()).foregroundStyle(.secondary)  // "Quinta-feira, 26 de novembro"
            }
            Spacer()
            Button { recarga += 1 } label: { Image(systemName: "arrow.clockwise") }.help("Atualizar")
        }
    }

    // ---------- os blocos ----------
    private var claudes: some View {
        let esperando = abas.itens.filter(\.sino)
        return CartaoDia(titulo: "Claudes esperando você", icone: "bell", total: esperando.count) {
            if esperando.isEmpty {
                Text("Nenhum Claude pediu resposta.").foregroundStyle(.secondary)
            } else {
                ForEach(esperando) { a in
                    LinhaDia({ abas.ir(a); nav.tela = .terminal }) {
                        HStack(spacing: 8) {
                            Circle().fill(.red).frame(width: 7, height: 7)
                            Text(a.nome).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func cartaoReunioes(_ agora: Double) -> some View {
        let faltam = reunioes.mapa { $0.filter { $0.fim > agora } }
        return CartaoDia(titulo: "Reuniões de hoje", icone: "calendar", total: faltam.total,
                      mais: ("Agenda", { nav.tela = .reunioes })) {
            bloco(faltam, vazio: "Nenhuma reunião pela frente hoje.", limite: 4) { (ev: ReunioesTela.Evento) in
                HStack {
                    LinhaDia({ nav.abrirEvento = ev.id; nav.tela = .reunioes }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.titulo).lineLimit(1)
                            Text("\(ev.inicio.formatted(date: .omitted, time: .shortened))–\(ev.termino.formatted(date: .omitted, time: .shortened))"
                                 + Self.falta(ev.ini, agora))
                                .font(.caption).foregroundStyle(ev.ini - agora <= 5 * 60 ? Souv.destaque : .secondary)
                        }
                    }
                    if let l = ev.link, let u = URL(string: l) {
                        Link("Entrar", destination: u).buttonStyle(.souvPrimario).help(l)
                    }
                }
            }
        }
    }

    private var cartaoFoco: some View {
        CartaoDia(titulo: "Foco", icone: "scope", total: foco.total,
               mais: ("Ver todas", { nav.abrirProjeto = ProjetosTela.foco; nav.tela = .projetos })) {
            bloco(foco, vazio: "Nenhuma task com prazo perto ou crítica.") { (t: ProjetosTela.Resumo) in
                LinhaDia({ nav.abrirTask = .init(pid: t.pid, tid: t.id); nav.tela = .projetos }) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.titulo).lineLimit(2)
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: t.cor)).frame(width: 6, height: 6)
                            Text(t.projeto ?? "")
                            StatusChip(status: t.status, dias: t.dias)
                            if let p = t.prazoTxt, !p.isEmpty { Text(p).foregroundStyle((t.dias ?? 99) <= 0 ? .red : .secondary) }
                        }
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private var cartaoPRs: some View {
        CartaoDia(titulo: "PRs esperando sua revisão", icone: "arrow.triangle.branch", total: prs.total,
               mais: ("GitHub", { nav.tela = .github })) {
            bloco(prs, vazio: "Nenhum PR pedindo sua revisão.") { (p: GithubTela.PR) in
                LinhaDia({ nav.abrirPR = p.ref; nav.tela = .github }) { LinhaPR(p: p, comRepo: true) }
            }
        }
    }

    private var cartaoEmails: some View {
        CartaoDia(titulo: "Importantes não lidos", icone: "envelope", total: emails.total, mais: ("Emails", { nav.tela = .emails })) {
            bloco(emails, vazio: "Nenhum email importante esperando.") { (e: EmailsTela.Lista.Item) in
                LinhaDia({ nav.abrirEmail = e.id; nav.tela = .emails }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.assunto.isEmpty ? "(sem assunto)" : e.assunto).fontWeight(.medium).lineLimit(1)
                        Text("\(e.de) · \(Date(timeIntervalSince1970: e.ts).formatted(.relative(presentation: .named).locale(Locale(identifier: "pt_BR"))))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private func cartaoJornada(_ agora: Double) -> some View {
        let (m, rodando) = Self.jornada(agora)
        return CartaoDia(titulo: "Jornada", icone: "clock", mais: ("Horas", { nav.tela = .horas })) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(m / 60)h" + String(format: "%02d", m % 60)).font(Souv.titulo(28)).monospacedDigit()
                Text("de \(Self.meta / 60)h").foregroundStyle(.secondary)
                Spacer()
                Label(rodando ? "rodando" : "pausada", systemImage: rodando ? "play.fill" : "pause.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(min(m, Self.meta)), total: Double(Self.meta)).tint(m >= Self.meta ? .green : Souv.primaria)
        }
    }

    // ---------- ajudantes ----------
    /// Lista de um bloco: carregando, o erro do jfy, o vazio ou as primeiras linhas.
    @ViewBuilder private func bloco<T, V: View>(_ e: Estado<[T]>, vazio: String, limite: Int = 5,
                                                 @ViewBuilder _ linha: @escaping (T) -> V) -> some View {
        switch e {
        case .carregando: ProgressView().controlSize(.small)
        case .erro(let m): Label(m, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).lineLimit(3)
        case .pronto(let xs) where xs.isEmpty: Text(vazio).foregroundStyle(.secondary)
        case .pronto(let xs):
            ForEach(Array(xs.prefix(limite).enumerated()), id: \.offset) { linha($0.element) }
            if xs.count > limite { Text("e mais \(xs.count - limite)").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private static func ler<T: Decodable, R>(_ args: [String], _ pegar: (T) -> R) async -> Estado<R> {
        let (d, msg): (T?, String?) = await JFY.ler(args)
        return d.map { .pronto(pegar($0)) } ?? .erro(msg ?? "O jfy não respondeu.")
    }

    /// " · agora", " · em 25 min", " · em 2h10"; vazio depois de 3 h.
    static func falta(_ ini: Double, _ agora: Double) -> String {
        let m = Int((ini - agora) / 60)
        return m <= 0 ? " · agora" : m < 60 ? " · em \(m) min" : m <= 180 ? " · em \(m / 60)h" + String(format: "%02d", m % 60) : ""
    }

    /// Minutos de hoje no cronômetro da jornada (o mesmo da barra do tmux: blocos [início, fim ou nulo]) e se está rodando.
    static func jornada(_ agora: Double) -> (Int, Bool) {
        struct Dia: Decodable { let data: String; let blocos: [[Double?]] }
        guard let d = try? JSONDecoder().decode(Dia.self, from: Data(contentsOf: arquivoDia)), d.data == diaLocal(Date()) else { return (0, false) }
        let s = d.blocos.reduce(0.0) { soma, b in soma + ((b.count > 1 ? b[1] : nil) ?? agora) - (b.first.flatMap { $0 } ?? agora) }
        let rodando = d.blocos.last.map { $0.count < 2 || $0[1] == nil } ?? false
        return (max(0, Int(s / 60)), rodando)
    }
}

extension MeuDiaTela.Estado where T: Collection {
    /// Quantos itens, para o número no título (nil enquanto carrega ou com erro).
    var total: Int? {
        if case .pronto(let xs) = self { return xs.count }
        return nil
    }
}

extension MeuDiaTela.Estado {
    func mapa<U>(_ f: (T) -> U) -> MeuDiaTela.Estado<U> {
        switch self {
        case .carregando: .carregando
        case .pronto(let x): .pronto(f(x))
        case .erro(let m): .erro(m)
        }
    }
}

/// Um bloco da Meu dia: título com o número, o atalho para a aba e o conteúdo, num cartão da Souv.
private struct CartaoDia<C: View>: View {
    let titulo, icone: String
    var total: Int?
    var mais: (String, () -> Void)?
    @ViewBuilder let conteudo: C

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icone).foregroundStyle(Souv.destaque)
                Text(titulo).font(Souv.titulo(17))
                if let total, total > 0 {
                    Text("\(total)").font(.caption2.bold()).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Souv.primaria))
                }
                Spacer()
                if let mais { Button(mais.0, action: mais.1).buttonStyle(.souvLink) }
            }
            conteudo
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Souv.superficie))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Souv.borda))
    }
}

/// Uma linha clicável do cartão, que acende ao passar o mouse.
private struct LinhaDia<C: View>: View {
    let acao: () -> Void
    @ViewBuilder let conteudo: C
    @State private var sobre = false

    init(_ acao: @escaping () -> Void, @ViewBuilder _ conteudo: () -> C) {
        self.acao = acao
        self.conteudo = conteudo()
    }

    var body: some View {
        conteudo
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(sobre ? Souv.texto.opacity(0.06) : .clear))
            .contentShape(Rectangle())
            .onTapGesture(perform: acao)
            .onHover { sobre = $0 }
    }
}
