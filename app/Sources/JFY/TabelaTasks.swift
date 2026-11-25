import SwiftUI

/// A segunda forma de ver as tasks, como no ClickUp: uma tabela agrupada (status, prazo, prioridade, etapa ou
/// responsável), com grupos que recolhem, busca e filtros. Status, prioridade e vencimento mudam ali mesmo (clique na
/// célula); a bolinha da esquerda marca para mudar em lote; o clique no resto da linha abre a task ao lado. As colunas
/// que não cabem somem, das menos importantes para as mais. Só tem o que o MCP do Journify devolve.
struct TabelaTasks: View {
    let tasks: [ProjetosTela.Resumo]
    let statusOrdem: [String]
    let comProjeto: Bool  // no Foco, as tasks são de vários projetos
    let pontos: [String: Double]
    @Binding var marcadas: Set<String>
    @Binding var aberta: String?
    /// (task, campo, valor, extra): campo status, prioridade ou prazo; extra = link do vídeo do teste (ou o motivo)
    let mudar: (String, String, String, String) -> Void

    enum Grupo: String, CaseIterable {
        case status = "Status", prazo = "Prazo", prioridade = "Prioridade", etapa = "Etapa", responsavel = "Responsável", nenhum = "Sem grupo"
    }

    /// As colunas, na ordem de importância: quando falta espaço, a última some primeiro.
    enum Coluna: CaseIterable {
        case status, vencimento, projeto, prioridade, resp, pontos, etapa
        var largura: CGFloat {
            switch self {
            case .status: 150
            case .vencimento: 112
            case .projeto: 130
            case .prioridade: 92
            case .resp: 56
            case .pontos: 56
            case .etapa: 120
            }
        }
        var titulo: String {
            switch self {
            case .status: "STATUS"
            case .vencimento: "VENCIMENTO"
            case .projeto: "PROJETO"
            case .prioridade: "PRIOR."
            case .resp: "RESP."
            case .pontos: "PTS"
            case .etapa: "ETAPA"
            }
        }
    }

    @AppStorage("tabela.grupo") private var grupo: Grupo = .status
    @State private var busca = ""
    @State private var filtroStatus: Set<String> = []
    @State private var filtroPrioridade: Set<String> = []
    @State private var filtroPrazo: Set<String> = []
    @State private var recolhidos: Set<String> = []
    @State private var pedidoVideo: (tid: String, status: String)?
    @State private var video = ""

    private static let prioridades = ["critica", "alta", "media", "baixa"]
    private static let faixasPrazo = ["Atrasadas", "Hoje", "Próximos 7 dias", "Depois", "Sem prazo", "Encerradas"]
    private static let pedeVideo: Set<String> = ["fechado", "finalizado_validacao"]

    var body: some View {
        GeometryReader { g in
            let cols = colunas(g.size.width)
            VStack(spacing: 0) {
                filtros.padding(.horizontal, 12).padding(.bottom, 8)
                cabecalho(cols)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(grupos, id: \.chave) { gr in
                            Section {
                                if !recolhidos.contains(gr.chave) { ForEach(gr.itens) { linha($0, cols) } }
                            } header: { cabecalhoGrupo(gr) }
                        }
                        if grupos.isEmpty {
                            Text("Nenhuma task com esses filtros.").foregroundStyle(Souv.texto2).padding(30)
                        }
                    }
                }
            }
        }
        .alert("Vídeo do teste", isPresented: Binding(get: { pedidoVideo != nil }, set: { if !$0 { pedidoVideo = nil } })) {
            TextField("link do vídeo, ou por que não tem", text: $video)
            Button("Mover") {
                if let p = pedidoVideo, video.trimmingCharacters(in: .whitespaces).count >= 3 { mudar(p.tid, "status", p.status, video) }
                pedidoVideo = nil
            }
            Button("Cancelar", role: .cancel) { pedidoVideo = nil }
        } message: {
            Text("O Journify só move a task para \(rotulo(pedidoVideo?.status ?? "")) com o link do vídeo do teste ou o motivo de não ter vídeo.")
        }
    }

    /// As colunas que cabem: o nome fica com pelo menos 220; o resto entra na ordem do enum.
    private func colunas(_ largura: CGFloat) -> [Coluna] {
        var sobra = largura - 24 - 18 - 12 - 220
        var out: [Coluna] = []
        for c in Coluna.allCases where c != .projeto || comProjeto {
            if sobra >= c.largura + 12 { out.append(c); sobra -= c.largura + 12 }
        }
        return [.projeto, .status, .prioridade, .resp, .pontos, .vencimento, .etapa].filter(out.contains)  // a ordem na tela
    }

    // ---------- filtros ----------
    private var filtros: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Souv.texto2)
                TextField("Buscar task", text: $busca).textFieldStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Souv.superficie2))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Souv.borda))
            .frame(minWidth: 120, maxWidth: 260)
            FiltroMulti(titulo: "Status", opcoes: statusOrdem.filter { s in tasks.contains { $0.status == s } }
                .map { ($0, rotulo($0), CORES_STATUS[$0] ?? .gray) }, marcados: $filtroStatus)
            FiltroMulti(titulo: "Prioridade", opcoes: Self.prioridades.map { ($0, rotuloPrioridade($0), corPrioridade($0)) },
                        marcados: $filtroPrioridade)
            FiltroMulti(titulo: "Prazo", opcoes: Self.faixasPrazo.map { ($0, $0, nil) }, marcados: $filtroPrazo)
            if !(filtroStatus.isEmpty && filtroPrioridade.isEmpty && filtroPrazo.isEmpty && busca.isEmpty) {
                Button("Limpar") { filtroStatus = []; filtroPrioridade = []; filtroPrazo = []; busca = "" }.buttonStyle(.link)
            }
            Spacer(minLength: 4)
            SouvSelect(opcoes: Grupo.allCases.map { .init(valor: $0, rotulo: $0.rawValue) }, selecionado: grupo) { grupo = $0; recolhidos = [] }
                .frame(width: 130)
                .help("Agrupar por")
        }
        .lineLimit(1)
    }

    private var filtradas: [ProjetosTela.Resumo] {
        tasks.filter { t in
            (busca.isEmpty || t.titulo.range(of: busca, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
                && (filtroStatus.isEmpty || filtroStatus.contains(t.status))
                && (filtroPrioridade.isEmpty || filtroPrioridade.contains(t.prioridade ?? ""))
                && (filtroPrazo.isEmpty || filtroPrazo.contains(faixaPrazo(t)))
        }
    }

    // ---------- grupos ----------
    struct G {
        let chave, titulo: String
        let cor: Color?
        let itens: [ProjetosTela.Resumo]
    }

    private var grupos: [G] {
        let ts = filtradas
        func juntar(_ ordem: [String], _ chave: (ProjetosTela.Resumo) -> String, _ titulo: (String) -> String, _ cor: (String) -> Color?) -> [G] {
            let porChave = Dictionary(grouping: ts, by: chave)
            let chaves = ordem.filter { porChave[$0] != nil } + porChave.keys.filter { !ordem.contains($0) }.sorted()
            return chaves.map { G(chave: $0, titulo: titulo($0), cor: cor($0), itens: porChave[$0]!) }
        }
        switch grupo {
        case .status: return juntar(statusOrdem, \.status, rotulo) { CORES_STATUS[$0] ?? .gray }
        case .prazo: return juntar(Self.faixasPrazo, faixaPrazo, { $0 }) { $0 == "Atrasadas" ? .red : $0 == "Hoje" ? .orange : nil }
        case .prioridade: return juntar(Self.prioridades + [""], { $0.prioridade ?? "" }, { $0.isEmpty ? "Sem prioridade" : rotuloPrioridade($0) }, corPrioridade)
        case .etapa:
            let ordem = Dictionary(ts.map { ($0.etapa, $0.etapaN) }, uniquingKeysWith: min).sorted { $0.value < $1.value }.map(\.key)
            return juntar(ordem, \.etapa, { $0 }) { _ in nil }
        case .responsavel:
            return juntar(["Você", "Outras pessoas", "Sem responsável"],
                          { $0.eu == true ? "Você" : ($0.resp ?? 0) > 0 ? "Outras pessoas" : "Sem responsável" }, { $0 }) { _ in nil }
        case .nenhum: return ts.isEmpty ? [] : [G(chave: "todas", titulo: "Todas", cor: nil, itens: ts)]
        }
    }

    private func faixaPrazo(_ t: ProjetosTela.Resumo) -> String {
        if Self.pedeVideo.contains(t.status) { return "Encerradas" }
        guard let d = t.dias else { return "Sem prazo" }
        return d < 0 ? "Atrasadas" : d == 0 ? "Hoje" : d <= 7 ? "Próximos 7 dias" : "Depois"
    }

    private func cabecalhoGrupo(_ g: G) -> some View {
        let fechado = recolhidos.contains(g.chave), ids = Set(g.itens.map(\.id))
        return HStack(spacing: 8) {
            Button { marcadas = ids.isSubset(of: marcadas) ? marcadas.subtracting(ids) : marcadas.union(ids) } label: {
                Image(systemName: ids.isSubset(of: marcadas) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(ids.isSubset(of: marcadas) ? Souv.destaque : Souv.texto2)
            }
            .buttonStyle(.plain).help("Marcar o grupo todo")
            Button {
                if fechado { recolhidos.remove(g.chave) } else { recolhidos.insert(g.chave) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Souv.texto2)
                        .rotationEffect(.degrees(fechado ? -90 : 0))
                    HStack(spacing: 5) {
                        if let c = g.cor { Circle().fill(c).frame(width: 7, height: 7) }
                        Text(g.titulo.uppercased()).font(.caption.weight(.semibold)).tracking(0.5).lineLimit(1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill((g.cor ?? Souv.texto2).opacity(0.16)))
                    Text("\(g.itens.count)").font(.caption).foregroundStyle(Souv.texto2)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Souv.fundo)
    }

    // ---------- colunas ----------
    private func cabecalho(_ cols: [Coluna]) -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 18, height: 1)
            Text("NOME").frame(maxWidth: .infinity, alignment: .leading)
            ForEach(cols, id: \.self) { c in Text(c.titulo).frame(width: c.largura, alignment: .leading) }
        }
        .font(.caption2.weight(.semibold)).foregroundStyle(Souv.texto2).tracking(0.5).lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func linha(_ t: ProjetosTela.Resumo, _ cols: [Coluna]) -> some View {
        LinhaTabela(aberta: aberta == t.id, marcada: marcadas.contains(t.id), abrir: { aberta = t.id }) {
            HStack(spacing: 12) {
                Button {
                    if marcadas.contains(t.id) { marcadas.remove(t.id) } else { marcadas.insert(t.id) }
                } label: {
                    Image(systemName: marcadas.contains(t.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(marcadas.contains(t.id) ? Souv.destaque : Souv.texto2)
                }
                .buttonStyle(.plain).frame(width: 18)
                Text(t.titulo).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading).help(t.titulo)
                ForEach(cols, id: \.self) { c in celula(c, t).frame(width: c.largura, alignment: .leading) }
            }
        }
    }

    @ViewBuilder private func celula(_ c: Coluna, _ t: ProjetosTela.Resumo) -> some View {
        switch c {
        case .status:
            CelulaMenu(opcoes: statusOrdem.map { ($0, rotulo($0), CORES_STATUS[$0] ?? .gray) }, atual: t.status) { s in
                if Self.pedeVideo.contains(s) { video = ""; pedidoVideo = (t.id, s) } else { mudar(t.id, "status", s, "") }
            } rotulo: { StatusChip(status: t.status, dias: t.dias) }
            .help("Mudar o status")
        case .prioridade:
            CelulaMenu(opcoes: Self.prioridades.map { ($0, rotuloPrioridade($0), corPrioridade($0)) }, atual: t.prioridade) {
                mudar(t.id, "prioridade", $0, "")
            } rotulo: {
                HStack(spacing: 4) {
                    Image(systemName: "flag.fill").foregroundStyle(corPrioridade(t.prioridade ?? "") ?? Souv.texto2.opacity(0.4))
                    Text(t.prioridade.map(rotuloPrioridade) ?? "—").font(.caption).foregroundStyle(Souv.texto2)
                }
            }
            .help("Mudar a prioridade")
        case .vencimento:
            CelulaPrazo(prazo: t.prazo, atrasada: (t.dias ?? 0) < 0 && faixaPrazo(t) != "Encerradas") { mudar(t.id, "prazo", $0, "") }
        case .projeto:
            HStack(spacing: 5) {
                Circle().fill(Color(hex: t.cor)).frame(width: 7, height: 7)
                Text(t.projeto ?? "—").lineLimit(1)
            }
        case .resp:
            if t.eu == true {
                Text("você").font(.caption2.bold()).foregroundStyle(Souv.destaque)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Souv.primaria.opacity(0.18)))
            } else if let r = t.resp, r > 0 {
                Label("\(r)", systemImage: "person.fill").font(.caption).foregroundStyle(Souv.texto2)
            } else {
                Image(systemName: "person.badge.plus").foregroundStyle(Souv.texto2.opacity(0.6)).help("Sem responsável")
            }
        case .pontos:
            Text(pontos[t.id].map { "\($0.formatted()) pts" } ?? "—").font(.caption).monospacedDigit()
                .foregroundStyle(pontos[t.id] == nil ? Souv.texto2.opacity(0.6) : Souv.texto)
                .help("Os pontos mudam no Journify: o MCP não grava a estimativa")
        case .etapa:
            Text(t.etapa).font(.caption).foregroundStyle(Souv.texto2).lineLimit(1)
                .help("A etapa segue o status: mude o status para a task mudar de etapa")
        }
    }
}

func corPrioridade(_ p: String) -> Color? {
    ["critica": .red, "alta": .orange, "media": Souv.primaria, "baixa": .gray][p]
}

/// Uma célula que edita no lugar: mostra o valor; o mouse por cima mostra que dá para mudar; o clique abre a lista no
/// estilo do select da Souv.
private struct CelulaMenu<Rotulo: View>: View {
    let opcoes: [(String, String, Color?)]  // valor, rótulo, cor
    let atual: String?
    let escolher: (String) -> Void
    @ViewBuilder let rotulo: () -> Rotulo
    @State private var aberto = false
    @State private var sobre = false

    var body: some View {
        Button { aberto = true } label: {
            HStack(spacing: 4) {
                rotulo()
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(Souv.texto2).opacity(sobre ? 1 : 0)
            }
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(sobre || aberto ? Souv.texto.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sobre = $0 }
        .popover(isPresented: $aberto, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(opcoes, id: \.0) { valor, texto, cor in
                    LinhaSelect(cor: cor, rotulo: texto, marcado: valor == atual) {
                        aberto = false
                        if valor != atual { escolher(valor) }
                    }
                }
            }
            .padding(6).frame(minWidth: 200).background(Souv.superficie)
        }
    }
}

/// O vencimento que muda no lugar: o clique abre o calendário.
private struct CelulaPrazo: View {
    let prazo: String?
    let atrasada: Bool
    let mudar: (String) -> Void
    @State private var aberto = false
    @State private var sobre = false
    @State private var data = Date()

    var body: some View {
        Button {
            data = prazo.flatMap(dataLocal) ?? Date()
            aberto = true
        } label: {
            Group {
                if let p = prazo, let d = dataLocal(p) {
                    Label(d.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year()), systemImage: "calendar")
                        .foregroundStyle(atrasada ? .red : Souv.texto)
                } else {
                    Label("Venc.", systemImage: "calendar").foregroundStyle(Souv.texto2.opacity(0.6))
                }
            }
            .font(.caption).monospacedDigit().lineLimit(1)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(sobre || aberto ? Souv.texto.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sobre = $0 }
        .help("Mudar o vencimento")
        .popover(isPresented: $aberto, arrowEdge: .bottom) {
            VStack(alignment: .trailing, spacing: 8) {
                DatePicker("Vencimento", selection: $data, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
                Button("Usar este dia") {
                    aberto = false
                    if diaLocal(data) != prazo { mudar(diaLocal(data)) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
    }
}

/// Uma linha da tabela: realce ao passar o mouse, a aberta e as marcadas em Vivid Blue suave; o clique abre a task.
private struct LinhaTabela<Conteudo: View>: View {
    let aberta, marcada: Bool
    let abrir: () -> Void
    @ViewBuilder let conteudo: () -> Conteudo
    @State private var sobre = false

    var body: some View {
        conteudo()
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(aberta || marcada ? Souv.primaria.opacity(aberta ? 0.22 : 0.12) : sobre ? Souv.texto.opacity(0.05) : .clear)
            .overlay(alignment: .leading) { if aberta { Rectangle().fill(Souv.destaque).frame(width: 3) } }
            .overlay(alignment: .bottom) { Rectangle().fill(Souv.borda.opacity(0.6)).frame(height: 1) }
            .contentShape(Rectangle())
            .onTapGesture(perform: abrir)
            .onHover { sobre = $0 }
    }
}

/// Um filtro de várias escolhas no estilo do select da Souv: o botão diz quantas estão ligadas; a lista marca e desmarca.
struct FiltroMulti: View {
    let titulo: String
    let opcoes: [(String, String, Color?)]
    @Binding var marcados: Set<String>
    @State private var aberto = false

    var body: some View {
        Button { aberto.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease").font(.caption)
                Text(marcados.isEmpty ? titulo : "\(titulo) · \(marcados.count)").lineLimit(1)
            }
            .foregroundStyle(marcados.isEmpty ? Souv.texto : Souv.destaque)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(marcados.isEmpty ? Souv.superficie2 : Souv.primaria.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(aberto ? Souv.destaque : Souv.borda))
            .fixedSize()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $aberto, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(opcoes, id: \.0) { valor, rotulo, cor in
                    LinhaSelect(cor: cor, rotulo: rotulo, marcado: marcados.contains(valor)) {
                        if marcados.contains(valor) { marcados.remove(valor) } else { marcados.insert(valor) }
                    }
                }
                if !marcados.isEmpty {
                    Divider().padding(.vertical, 3)
                    LinhaSelect(cor: nil, rotulo: "Limpar", marcado: false, apagado: true) { marcados = [] }
                }
            }
            .padding(6).frame(minWidth: 200).background(Souv.superficie)
        }
    }
}
