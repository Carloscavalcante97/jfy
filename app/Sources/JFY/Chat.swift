import AppKit
import SwiftUI

/// Chat do time do Journify: as conversas entre colaboradores. O app só desenha; quem fala com o Journify (pelo MCP) é
/// o jfy: `--chat` (conversas), `--chat <id>` (mensagens; abrir marca como lida lá), `--chat <id> <texto> [ids]` (envia,
/// avisando quem foi marcado com @), `--chat-ia` (o Melhorar, pelo Claude) e `--corrigir` (o corretor, nos bastidores).
struct ChatTela: View {
    /// Só busca com a tela à vista: abrir uma conversa marca como lida no Journify, e ninguém leu nada com a tela escondida.
    let ativa: Bool
    @ObservedObject var nav: Navegacao

    struct Mensagem: Decodable, Identifiable, Equatable {
        let id, autor, texto: String
        let autorId: String?  // a que você acabou de mandar não tem
        let quando: String?
        let minha: Bool?
    }

    struct Conversa: Decodable, Identifiable, Hashable {
        struct Ultima: Decodable, Hashable {
            let autor: String?  // o MCP não diz quem mandou a última
            let texto: String
            let quando: String?
        }
        let id, nome: String
        let tipo: String?
        let naoLidas: Int?
        let membro: Bool?  // false: canal que você vê sem participar (só leitura)
        let ultima: Ultima?
    }

    /// Quem dá para marcar com @.
    struct Pessoa: Identifiable, Hashable { let id, nome: String }

    /// O `jfy --corrigir`: o texto corrigido e as palavras trocadas (descartada: a correção mudou demais e não vale).
    struct Correcao: Decodable {
        struct Troca: Decodable { let de, para: String }
        let texto: String
        let trocas: [Troca]
        var descartada: Bool? = nil
    }

    private static let maxFixas = 3  // por tipo: 3 diretas e 3 grupos
    private static let emojis = ["👍", "🙏", "😂", "✅", "🎉", "❤️", "👀", "🚀", "🔥", "😅", "🤝", "💡"]

    @AppStorage("chat.aba") private var aba = "direta"  // "direta" ou "canal" (os grupos)
    @AppStorage("chat.favoritas") private var fixasTxt = ""  // ids das fixadas, um por linha, na ordem em que foram fixadas
    @State private var conversas: [Conversa] = []
    @State private var selecionada: String?
    @State private var mensagens: [Mensagem] = []
    @State private var texto = ""
    @State private var enviando = false
    @State private var melhorando = false
    @State private var desfazer: (antes: String, depois: String, nota: String)?  // o Desfazer do Melhorar e do Corrigir
    @State private var corrigindo = false  // o botão Corrigir esperando o corretor
    @State private var pronta: (de: String, c: Correcao)?  // a correção que o corretor devolveu e o texto que foi para ele
    @State private var dispensada: String?  // o texto em que a faixa da correção foi fechada (volta quando o texto muda)
    @State private var aguardando: String?  // o envio esperando a correção (o Corrigir ao enviar), no máximo 5 s
    @State private var nota: String?  // "Nada para corrigir.", por uns segundos
    @AppStorage("chat.corrigirAoEnviar") private var corrigirAoEnviar = false
    @State private var marcados: [Pessoa] = []  // escolhidos na sugestão do @
    @State private var fechadaEm: String?  // o texto quando o Esc fechou a sugestão do @ (reabre quando o texto muda)
    @State private var paleta = false
    @State private var sobre: String?  // a conversa com o mouse em cima: mostra a estrela
    @State private var avisoFixa: String?
    @State private var erro: String?
    @State private var fora: String?  // por que o chat não carregou (sem rede, MCP sem token…)
    @FocusState private var focado: Bool

    var body: some View {
        Group {
            if let fora {
                desconectado(fora)
            } else {
                GeometryReader { g in
                HStack(spacing: 0) {
                    lista.frame(width: min(270, max(210, g.size.width * 0.28)))
                    Divider()
                    if let c = conversas.first(where: { $0.id == selecionada }) {
                        conversa(c)
                    } else {
                        Text("Escolha uma conversa").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                }
            }
        }
        // ponytail: busca de tempos em tempos (conversas a cada 15 s, mensagens a cada 5 s); tempo real
        // (SSE ou websocket) se o MCP do Journify oferecer
        .task(id: ativa) {
            while ativa && !Task.isCancelled {
                await carregarConversas()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .task(id: "\(selecionada ?? "")|\(ativa)") {
            guard let cid = selecionada, ativa else { return }
            JFY.aquecerCorretor()  // a primeira correção já acha o Claude aberto
            while !Task.isCancelled {
                await carregarMensagens(cid)
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .task(id: nav.abrirConversa) {  // o clique na notificação de mensagem nova
            guard let cid = nav.abrirConversa else { return }
            nav.abrirConversa = nil
            selecionada = cid
            await carregarConversas()
            if let c = conversas.first(where: { $0.id == cid }) { aba = tipo(c) }  // para ela aparecer na lista
        }
    }

    // ---------- lista de conversas ----------
    private func tipo(_ c: Conversa) -> String { c.tipo == "canal" ? "canal" : "direta" }
    private var fixas: [String] { fixasTxt.split(separator: "\n").map(String.init) }

    /// As da aba: as fixadas primeiro (na ordem em que foram fixadas) e o resto na ordem do Journify. Fixada que sumiu
    /// da lista fica guardada e só não aparece.
    private var daAba: (fixadas: [Conversa], resto: [Conversa]) {
        let doTipo = conversas.filter { tipo($0) == aba }
        let fixadas = Array(fixas.compactMap { id in doTipo.first { $0.id == id } }.prefix(Self.maxFixas))
        return (fixadas, doTipo.filter { !fixadas.contains($0) })
    }

    private func rotulo(_ nome: String, _ t: String) -> String {
        let n = conversas.filter { tipo($0) == t }.reduce(0) { $0 + ($1.naoLidas ?? 0) }
        return n > 0 ? "\(nome) · \(n)" : nome
    }

    private var lista: some View {
        let (fixadas, resto) = daAba
        return VStack(alignment: .leading, spacing: 6) {
            Segmentos(selecao: $aba, opcoes: [.init(valor: "direta", rotulo: rotulo("Diretas", "direta")),
                                              .init(valor: "canal", rotulo: rotulo("Grupos", "canal"))], cheio: true)
                .padding([.horizontal, .top], 10)
            if let avisoFixa {
                Text(avisoFixa).font(.caption).foregroundStyle(Souv.texto2).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            List {
                if fixadas.isEmpty {
                    ForEach(resto) { linha($0) }
                } else {
                    Section("Fixadas") { ForEach(fixadas) { linha($0) } }
                    Section("Conversas") { ForEach(resto) { linha($0) } }
                }
            }
            .listStyle(.sidebar)
            .listaSouv()
        }
        .background(Souv.superficie)
        .onChange(of: aba) { avisoFixa = nil }
    }

    private func linha(_ c: Conversa) -> some View {
        let fixa = fixas.contains(c.id)
        return HStack(alignment: .top, spacing: 10) {
            Avatar(nome: c.nome, canal: c.tipo == "canal")
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(c.nome).fontWeight((c.naoLidas ?? 0) > 0 ? .semibold : .regular).lineLimit(1)
                    Spacer(minLength: 4)
                    if fixa || sobre == c.id {
                        Button { alternarFixa(c) } label: {
                            Image(systemName: fixa ? "star.fill" : "star").foregroundStyle(fixa ? Souv.destaque : Souv.texto2)
                        }
                        .buttonStyle(.souvIcone).font(.caption)
                        .help(fixa ? "Tirar do topo" : "Fixar no topo (até 3 diretas e 3 grupos)")
                    }
                    Text(hora(c.ultima?.quando)).font(.caption2).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(c.ultima.map { ($0.autor.map { "\($0): " } ?? "") + $0.texto } ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    if let n = c.naoLidas, n > 0 {
                        Text("\(n)").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Souv.primaria))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onHover { sobre = $0 ? c.id : sobre == c.id ? nil : sobre }
        .linhaSouv(selecionada == c.id) { selecionada = c.id }
        .menuSouv {
            Button(fixa ? "Tirar do topo" : "Fixar no topo", systemImage: fixa ? "star.slash" : "star") { alternarFixa(c) }
        }
    }

    private func alternarFixa(_ c: Conversa) {
        var f = fixas
        if let i = f.firstIndex(of: c.id) {
            f.remove(at: i)
        } else if conversas.filter({ tipo($0) == tipo(c) && f.contains($0.id) }).count >= Self.maxFixas {
            // só contam as que estão na lista: uma fixada que sumiu não ocupa a vaga
            avisoFixa = tipo(c) == "canal" ? "Até 3 conversas fixas em grupos (e 3 em diretas): tire uma para fixar esta."
                : "Até 3 conversas fixas em diretas (e 3 em grupos): tire uma para fixar esta."
            return
        } else {
            f.append(c.id)
        }
        avisoFixa = nil
        fixasTxt = f.joined(separator: "\n")
    }

    // ---------- uma conversa ----------
    private func conversa(_ c: Conversa) -> some View {
        // quem escreveu na conversa: o "@Nome" deles fica em destaque nas mensagens
        let nomes = Set(mensagens.filter { $0.autorId != nil }.map(\.autor)).sorted { $0.count > $1.count }
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Avatar(nome: c.nome, canal: c.tipo == "canal")
                Text(c.nome).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(mensagens.enumerated()), id: \.element.id) { i, m in
                            // o nome do autor só na primeira de uma sequência dele
                            Linha(m: m, mostrarAutor: m.minha != true && (i == 0 || mensagens[i - 1].autor != m.autor), nomes: nomes)
                                .id(m.id)
                                .menuSouv {
                                    if c.membro != false {
                                        Button("Responder", systemImage: "arrowshape.turn.up.left") { responder(m) }
                                    }
                                    Button("Copiar texto", systemImage: "doc.on.doc") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(m.texto, forType: .string)
                                    }
                                }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: mensagens.last?.id) {
                    if let u = mensagens.last { proxy.scrollTo(u.id, anchor: .bottom) }
                }
            }
            if let erro {
                Label(erro, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
            }
            Divider()
            if c.membro == false {
                Label("Você não participa desta conversa: só leitura.", systemImage: "eye")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(14)
            } else {
                escrever(c)
            }
        }
        .onAppear { focado = true }
    }

    private func escrever(_ c: Conversa) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if consulta != nil { sugestoes }
            if melhorando {
                Text("O Claude está melhorando a mensagem…").font(.caption).foregroundStyle(Souv.texto2)
            } else if let d = desfazer, d.depois == texto {
                HStack(spacing: 6) {
                    Text(d.nota).foregroundStyle(Souv.texto2)
                    // dispensada: a faixa não volta oferecendo a correção que você acabou de desfazer
                    Button("Desfazer") { texto = d.antes; dispensada = d.antes; desfazer = nil; focado = true }.buttonStyle(.souvLink)
                }
                .font(.caption)
            } else if let c = faixa {
                faixaCorrecao(c)
            } else if let nota {
                Text(nota).font(.caption).foregroundStyle(Souv.texto2)
            }
            HStack(alignment: .bottom, spacing: 10) {
                Button { paleta.toggle() } label: { Label("Emojis", systemImage: "face.smiling").labelStyle(.iconOnly).font(.title3) }
                    .buttonStyle(.souvIcone).disabled(melhorando).help("Emojis")
                    .popover(isPresented: $paleta, arrowEdge: .top) { paletaEmojis }
                TextField("Mensagem para \(c.nome)", text: $texto, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...6).focused($focado).disabled(melhorando || corrigindo || aguardando != nil)
                    .onSubmit { if let p = sugeridas.first { mencionar(p) } else { enviar() } }  // Enter: escolhe a sugestão do @ ou envia
                    .onKeyPress(.return, phases: .down) { k in
                        // Shift+Enter quebra a linha onde está o cursor; o Enter sozinho segue para o onSubmit
                        guard k.modifiers.contains(.shift) else { return .ignored }
                        NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        guard consulta != nil else { return .ignored }
                        fechadaEm = texto
                        return .handled
                    }
                    .onKeyPress(.tab) {  // com a faixa da correção à vista, o Tab aplica
                        guard let c = faixa else { return .ignored }
                        aplicar(c)
                        return .handled
                    }
                Button { Task { await corrigir() } } label: {
                    if corrigindo { ProgressView().controlSize(.small) } else {
                        Label("Corrigir o português", systemImage: "textformat.abc.dottedunderline").labelStyle(.iconOnly).font(.title3)
                    }
                }
                .buttonStyle(.souvIcone)
                .disabled(!podeMelhorar)
                .help("Corrige o português com o Claude (Haiku, quase sem custo)")
                Button(action: melhorar) {
                    if melhorando { ProgressView().controlSize(.small) } else {
                        Label("Melhorar com o Claude", systemImage: "sparkles").labelStyle(.iconOnly).font(.title3)
                    }
                }
                .buttonStyle(.souvIcone)
                .disabled(!podeMelhorar)
                .help("Melhora a mensagem com o Claude (usa tokens)")
                Button(action: enviar) {
                    if aguardando != nil {
                        HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Corrigindo…").font(.caption) }
                    } else if enviando {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(podeEnviar ? Souv.primaria : .secondary)
                .disabled(!podeEnviar)
                .help("Enviar (Enter; Shift+Enter quebra a linha)")
            }
            Toggle("Corrigir ao enviar", isOn: $corrigirAoEnviar).font(.caption).foregroundStyle(Souv.texto2)
        }
        .padding(14)
        .task(id: texto) {  // nos bastidores: 1,5 s depois de parar de digitar, sem carregando e sem erro na tela
            let t = texto
            guard pronta?.de != t, palavras(t) >= 3 else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { _ = await correcao(t) }
        }
    }

    /// A faixa acima do campo quando a correção dos bastidores achou algo: "✓ 2 correções · de → para · Aplicar".
    private func faixaCorrecao(_ c: Correcao) -> some View {
        let n = c.trocas.count
        return HStack(spacing: 8) {
            Label(n == 1 ? "1 correção" : "\(n) correções", systemImage: "checkmark").foregroundStyle(Souv.destaque)
            Text(c.trocas.prefix(3).map { "\($0.de) → \($0.para)" }.joined(separator: " · ") + (n > 3 ? " +\(n - 3)" : ""))
                .foregroundStyle(Souv.texto2).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Button("Aplicar") { aplicar(c) }.buttonStyle(.souvLink)
            Text("Tab aplica").foregroundStyle(.tertiary)
            Button { dispensada = texto } label: { Image(systemName: "xmark") }.buttonStyle(.souvIcone).help("Dispensar")
        }
        .font(.caption)
    }

    private var paletaEmojis: some View {
        // ponytail: o emoji vai para o fim do texto (o TextField do SwiftUI não diz onde está o cursor). Reagir a uma
        // mensagem com emoji não existe no MCP do Journify ainda.
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 2), count: 6), spacing: 2) {
            ForEach(Self.emojis, id: \.self) { e in
                Button { texto += e; paleta = false; focado = true } label: {
                    Text(e).font(.title2).frame(width: 34, height: 34).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Souv.superficie)
    }

    // ---------- @ ----------
    /// Quem dá para marcar com @, quem falou por último primeiro. ponytail: o MCP do Journify não lista os membros da
    /// conversa, então são os que escreveram nas mensagens carregadas (as 100 últimas), sem você; os membros de verdade
    /// quando o MCP listar.
    private var pessoas: [Pessoa] {
        var vistos = Set<String>()
        return mensagens.reversed().compactMap { m in
            guard m.minha != true, let id = m.autorId, vistos.insert(id).inserted else { return nil }
            return Pessoa(id: id, nome: m.autor)
        }
    }

    private func bate(_ nome: String, _ q: String) -> Bool {
        q.isEmpty || nome.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// O que vem depois do último @ do campo enquanto ainda pode ser um nome: o @ no começo ou depois de um espaço (um
    /// email não abre a lista), sem quebra de linha e, com espaço, só se ainda bate com alguém ("@Ana Pa").
    private var consulta: String? {
        guard texto != fechadaEm, let i = texto.lastIndex(of: "@"),
              i == texto.startIndex || texto[texto.index(before: i)].isWhitespace else { return nil }
        let q = String(texto[texto.index(after: i)...])
        guard !q.contains(where: \.isNewline) else { return nil }
        return !q.contains(where: \.isWhitespace) || pessoas.contains(where: { bate($0.nome, q) }) ? q : nil
    }

    private var sugeridas: [Pessoa] { consulta.map { q in pessoas.filter { bate($0.nome, q) } } ?? [] }

    @ViewBuilder private var sugestoes: some View {
        if pessoas.isEmpty {
            Label("Ninguém para sugerir: só aparece quem já escreveu nesta conversa", systemImage: "at")
                .font(.caption).foregroundStyle(Souv.texto2)
        } else if !sugeridas.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(sugeridas.prefix(6)) { p in
                    LinhaSelect(cor: Avatar.cor(p.nome), rotulo: p.nome, marcado: false) { mencionar(p) }
                }
            }
            .padding(4)
            .frame(maxWidth: 280, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Souv.superficie))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Souv.borda))
        }
    }

    /// Troca o "@texto" do fim do campo por "@Nome ".
    private func mencionar(_ p: Pessoa) {
        guard let i = texto.lastIndex(of: "@") else { return }
        texto = String(texto[..<i]) + "@\(p.nome) "
        if !marcados.contains(p) { marcados.append(p) }
        focado = true
    }

    // ---------- responder, melhorar ----------
    /// O MCP do Journify ainda não responde em thread: a resposta leva a mensagem citada ("> Autor: trecho") no começo.
    private func responder(_ m: Mensagem) {
        let corpo = m.texto.split(separator: "\n").filter { !$0.hasPrefix("> ") }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let trecho = corpo.count > 80 ? corpo.prefix(80).trimmingCharacters(in: .whitespaces) + "…" : corpo
        texto = "> \(m.autor): \(trecho)\n\n" + texto
        focado = true
    }

    private var podeMelhorar: Bool { !melhorando && !corrigindo && !enviando && !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func palavras(_ t: String) -> Int { t.split(whereSeparator: \.isWhitespace).count }

    /// A correção da faixa, se ela vale para o texto do campo agora.
    private var faixa: Correcao? {
        guard let p = pronta, p.de == texto, !p.c.trocas.isEmpty, dispensada != texto else { return nil }
        return p.c
    }

    /// A correção do Claude para `t`: a pronta, se é deste texto, ou pede ao corretor (texto repetido volta de lá na hora).
    /// Só guarda se o campo ainda tem `t`: resposta de um texto que já mudou não vale.
    private func correcao(_ t: String) async -> (Correcao?, String?) {
        if let p = pronta, p.de == t { return (p.c, nil) }
        let (r, msg): (Correcao?, String?) = await JFY.ler(["--corrigir"], entrada: t)
        if let r, texto == t { pronta = (t, r) }
        return (r, msg)
    }

    /// Troca o texto pelo corrigido, com o Desfazer. O corrigido já fica com a correção pronta (vazia): não volta ao corretor.
    private func aplicar(_ c: Correcao) {
        let antes = texto, n = c.trocas.count
        texto = c.texto
        pronta = (c.texto, Correcao(texto: c.texto, trocas: []))
        desfazer = (antes, c.texto, (n == 1 ? "1 correção" : "\(n) correções") + " do Claude.")
        focado = true
    }

    /// O botão Corrigir: corrige já e aplica (a correção dos bastidores, se já chegou, sai na hora).
    private func corrigir() async {
        guard podeMelhorar else { return }
        let antes = texto
        corrigindo = true
        erro = nil
        let (r, msg) = await correcao(antes)
        corrigindo = false
        DispatchQueue.main.async { focado = true }
        guard texto == antes else { return }  // o campo mudou no meio: não pisa no que está lá
        guard let r else { erro = msg; return }
        if !r.trocas.isEmpty { return aplicar(r) }
        let n = r.descartada == true ? "O Claude mudou demais: ficou como estava." : "Nada para corrigir."
        nota = n
        Task { try? await Task.sleep(for: .seconds(2.5)); if nota == n { nota = nil } }
    }

    private func melhorar() {
        guard podeMelhorar else { return }
        let antes = texto
        melhorando = true
        erro = nil
        Task {
            struct Texto: Decodable { let texto: String }
            let (r, msg): (Texto?, String?) = await JFY.ler(["--chat-ia"], entrada: antes)
            melhorando = false
            DispatchQueue.main.async { focado = true }  // depois de o campo voltar a ficar ativo
            guard texto == antes else { return }  // o campo mudou no meio (Responder): não pisa no que está lá
            if let r {
                texto = r.texto
                desfazer = (antes, r.texto, "Melhorada pelo Claude.")
            } else {
                erro = msg
            }
        }
    }

    private func desconectado(_ motivo: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("Chat do time").font(.title2.weight(.semibold))
            Text(motivo).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button("Tentar de novo") { Task { fora = nil; await carregarConversas() } }.padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ---------- jfy --chat ----------
    private var podeEnviar: Bool {
        !enviando && !melhorando && !corrigindo && aguardando == nil && !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func carregarConversas() async {
        let r = await JFY.rodar(["--chat"])
        guard r.status == 0, let lista: [Conversa] = decodificar(r.saida) else {
            // com a lista na tela, uma falha passageira (rede) não tira a lista: a próxima busca tenta de novo
            if conversas.isEmpty { fora = r.status == 0 ? "Não entendi a lista de conversas do jfy --chat." : motivo(r) }
            return
        }
        fora = nil
        conversas = lista
        if selecionada == nil || !lista.contains(where: { $0.id == selecionada }) {
            let (fixadas, resto) = daAba
            selecionada = (fixadas + resto).first?.id
        }
    }

    private func carregarMensagens(_ cid: String) async {
        let r = await JFY.rodar(["--chat", cid])
        if r.status == 0, let lista: [Mensagem] = decodificar(r.saida), lista != mensagens, selecionada == cid {
            mensagens = lista
        }
    }

    /// Com o Corrigir ao enviar, vai o texto corrigido: na hora, se a correção dos bastidores já chegou; senão espera por
    /// ela até 5 s ("Corrigindo…") e, passado o prazo ou com erro, vai como está. Nunca segura o envio.
    private func enviar() {
        let t = texto, cid = selecionada
        guard podeEnviar else { return }
        guard corrigirAoEnviar, palavras(t) >= 3 else { return enviarAgora() }
        if let p = pronta, p.de == t { texto = p.c.texto; return enviarAgora() }
        aguardando = t
        func fim(_ corrigido: String?) {
            guard aguardando == t else { return }  // a correção ou o prazo já resolveu
            aguardando = nil
            DispatchQueue.main.async { focado = true }
            guard selecionada == cid else { return }  // trocou de conversa no meio: o texto fica no campo
            if let corrigido { texto = corrigido }
            enviarAgora()
        }
        Task { fim(await correcao(t).0?.texto) }
        Task { try? await Task.sleep(for: .seconds(5)); fim(nil) }
    }

    private func enviarAgora() {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cid = selecionada, !t.isEmpty, !enviando, !melhorando, !corrigindo,
              conversas.first(where: { $0.id == cid })?.membro != false else { return }
        // avisa quem foi escolhido no @, se o "@Nome" ainda está no texto e a pessoa é desta conversa
        let ids = marcados.filter { t.contains("@" + $0.nome) && pessoas.contains($0) }.map(\.id)
        enviando = true
        erro = nil
        desfazer = nil
        texto = ""
        Task {
            let r = await JFY.rodar(["--chat", cid, t] + (ids.isEmpty ? [] : [ids.joined(separator: ",")]))
            enviando = false
            if r.status == 0, let m: Mensagem = decodificar(r.saida) {
                marcados = []
                if selecionada == cid { mensagens.append(m) }
            } else {
                texto = t  // não perde o que foi escrito
                erro = motivo(r)
            }
        }
    }

    private func motivo(_ r: (status: Int32, saida: String, erro: String)) -> String {
        let e = r.erro.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? "jfy --chat falhou (código \(r.status))" : e
    }

    private func decodificar<T: Decodable>(_ s: String) -> T? {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try? d.decode(T.self, from: Data(s.utf8))
    }

    // ---------- peças ----------
    private struct Linha: View {
        let m: Mensagem
        let mostrarAutor: Bool
        let nomes: [String]  // os "@Nome" que ficam em destaque
        var body: some View {
            let minha = m.minha == true
            VStack(alignment: minha ? .trailing : .leading, spacing: 2) {
                if mostrarAutor {
                    Text(m.autor).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
                }
                HStack(alignment: .bottom, spacing: 6) {
                    if minha { Spacer(minLength: 80); Text(hora(m.quando)).font(.caption2).foregroundStyle(.tertiary) }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(blocos.enumerated()), id: \.offset) { _, b in
                            if b.citacao {
                                HStack(spacing: 6) {
                                    Capsule().fill(minha ? Color.white.opacity(0.6) : Souv.destaque).frame(width: 3)
                                    Text(b.texto).foregroundStyle(minha ? Color.white.opacity(0.8) : Souv.texto2)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(destacado(b.texto, minha: minha))
                            }
                        }
                    }
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(minha ? Color.white : Color.primary)
                    .background(RoundedRectangle(cornerRadius: 14).fill(minha ? Souv.primaria : Color.secondary.opacity(0.12)))
                    if !minha { Text(hora(m.quando)).font(.caption2).foregroundStyle(.tertiary); Spacer(minLength: 80) }
                }
            }
            .frame(maxWidth: .infinity, alignment: minha ? .trailing : .leading)
        }

        /// As linhas que começam com "> " (a citação do Responder) num bloco à parte; o resto, o texto.
        private var blocos: [(citacao: Bool, texto: String)] {
            var r: [(citacao: Bool, texto: String)] = []
            for l in m.texto.split(separator: "\n", omittingEmptySubsequences: false) {
                let c = l.hasPrefix("> "), t = String(c ? l.dropFirst(2) : l)
                if r.last?.citacao == c { r[r.count - 1].texto += "\n" + t } else { r.append((c, t)) }
            }
            let limpos = r.map { (citacao: $0.citacao, texto: $0.texto.trimmingCharacters(in: .newlines)) }.filter { !$0.texto.isEmpty }
            return limpos.isEmpty ? [(false, m.texto)] : limpos
        }

        /// O "@Nome" de quem escreveu na conversa em destaque. Na sua bolha (Vivid Blue) a cor de destaque sumiria no
        /// claro: lá fica só o semibold.
        private func destacado(_ s: String, minha: Bool) -> AttributedString {
            var a = AttributedString(s)
            for n in nomes {
                var de = a.startIndex
                while de < a.endIndex, let r = a[de...].range(of: "@" + n) {
                    a[r].font = .body.weight(.semibold)
                    if !minha { a[r].foregroundColor = Souv.destaque }
                    de = r.upperBound
                }
            }
            return a
        }
    }

    private struct Avatar: View {
        let nome: String
        let canal: Bool

        /// Cor estável pelo nome (o hashValue do Swift muda a cada execução).
        static func cor(_ nome: String) -> Color { SERIES[nome.unicodeScalars.reduce(0) { $0 + Int($1.value) } % SERIES.count] }

        var body: some View {
            let iniciais = canal ? "#" : nome.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
            Text(iniciais).font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Circle().fill(Self.cor(nome)))
        }
    }
}

/// "14:05" hoje, "24/11" antes.
private func hora(_ iso: String?) -> String {
    guard let iso, let d = (try? Date(iso, strategy: .iso8601)) ??
        (try? Date(iso, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))) else { return "" }
    let br = Locale(identifier: "pt_BR")
    return Calendar.current.isDateInToday(d) ? d.formatted(.dateTime.hour().minute().locale(br))
        : d.formatted(.dateTime.day().month(.twoDigits).locale(br))
}
