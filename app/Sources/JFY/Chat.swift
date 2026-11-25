import SwiftUI

/// Chat do time do Journify: as conversas entre colaboradores. O app só desenha; quem fala com o Journify é o jfy:
/// `--chat` (conversas), `--chat <id>` (mensagens), `--chat <id> <texto>` (envia). Enquanto o MCP do Journify não
/// tiver o chat, o jfy responde com o motivo e a tela mostra isso.
struct ChatTela: View {
    /// Só busca mensagens novas com a tela à vista.
    let ativa: Bool

    struct Mensagem: Decodable, Identifiable, Equatable {
        let id, autor, texto: String
        let quando: String?
        let minha: Bool?
    }

    struct Conversa: Decodable, Identifiable, Hashable {
        struct Ultima: Decodable, Hashable {
            let autor, texto: String
            let quando: String?
        }
        let id, nome: String
        let tipo: String?
        let naoLidas: Int?
        let ultima: Ultima?
    }

    @State private var conversas: [Conversa] = []
    @State private var selecionada: String?
    @State private var mensagens: [Mensagem] = []
    @State private var texto = ""
    @State private var enviando = false
    @State private var erroEnvio: String?
    @State private var fora: String?  // por que o chat não está disponível
    @FocusState private var focado: Bool

    var body: some View {
        Group {
            if let fora {
                desconectado(fora)
            } else {
                HStack(spacing: 0) {
                    lista.frame(width: 270)
                    Divider()
                    if let c = conversas.first(where: { $0.id == selecionada }) {
                        conversa(c)
                    } else {
                        Text("Escolha uma conversa").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        // ponytail: busca de tempos em tempos (conversas a cada 15 s, mensagens a cada 5 s); tempo real
        // (SSE ou websocket) se o MCP do Journify oferecer
        .task(id: ativa) {
            repeat {
                await carregarConversas()
                try? await Task.sleep(for: .seconds(15))
            } while ativa && fora == nil && !Task.isCancelled
        }
        .task(id: "\(selecionada ?? "")|\(ativa)") {
            guard let cid = selecionada else { return }
            while !Task.isCancelled {
                await carregarMensagens(cid)
                guard ativa else { break }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // ---------- lista de conversas ----------
    private var lista: some View {
        List(conversas, selection: $selecionada) { c in
            HStack(alignment: .top, spacing: 10) {
                Avatar(nome: c.nome, canal: c.tipo == "canal")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(c.nome).fontWeight((c.naoLidas ?? 0) > 0 ? .semibold : .regular).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(hora(c.ultima?.quando)).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(c.ultima.map { "\($0.autor): \($0.texto)" } ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 4)
                        if let n = c.naoLidas, n > 0 {
                            Text("\(n)").font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor))
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .tag(c.id)
        }
        .listStyle(.sidebar)
    }

    // ---------- uma conversa ----------
    private func conversa(_ c: Conversa) -> some View {
        VStack(spacing: 0) {
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
                            Linha(m: m, mostrarAutor: m.minha != true && (i == 0 || mensagens[i - 1].autor != m.autor))
                                .id(m.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: mensagens.last?.id) {
                    if let u = mensagens.last { proxy.scrollTo(u.id, anchor: .bottom) }
                }
            }
            if let erroEnvio {
                Label(erroEnvio, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
            }
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Mensagem para \(c.nome)", text: $texto, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...6).focused($focado).onSubmit(enviar)
                Button(action: enviar) {
                    if enviando { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(podeEnviar ? Color.accentColor : .secondary)
                .disabled(!podeEnviar)
                .help("Enviar (Enter)")
            }
            .padding(14)
        }
        .onAppear { focado = true }
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
    private var podeEnviar: Bool { !enviando && !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func carregarConversas() async {
        let r = await JFY.rodar(["--chat"])
        guard r.status == 0, let lista: [Conversa] = decodificar(r.saida) else {
            fora = r.status == 0 ? "Não entendi a lista de conversas do jfy --chat." : motivo(r)
            return
        }
        fora = nil
        conversas = lista
        if selecionada == nil || !lista.contains(where: { $0.id == selecionada }) { selecionada = lista.first?.id }
    }

    private func carregarMensagens(_ cid: String) async {
        let r = await JFY.rodar(["--chat", cid])
        if r.status == 0, let lista: [Mensagem] = decodificar(r.saida), lista != mensagens, selecionada == cid {
            mensagens = lista
        }
    }

    private func enviar() {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cid = selecionada, !t.isEmpty, !enviando else { return }
        enviando = true
        erroEnvio = nil
        texto = ""
        Task {
            let r = await JFY.rodar(["--chat", cid, t])
            enviando = false
            if r.status == 0, let m: Mensagem = decodificar(r.saida) {
                if selecionada == cid { mensagens.append(m) }
            } else {
                texto = t  // não perde o que foi escrito
                erroEnvio = motivo(r)
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
        var body: some View {
            let minha = m.minha == true
            VStack(alignment: minha ? .trailing : .leading, spacing: 2) {
                if mostrarAutor {
                    Text(m.autor).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
                }
                HStack(alignment: .bottom, spacing: 6) {
                    if minha { Spacer(minLength: 80); Text(hora(m.quando)).font(.caption2).foregroundStyle(.tertiary) }
                    Text(m.texto)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(minha ? Color.white : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 14).fill(minha ? Color.accentColor : Color.secondary.opacity(0.12)))
                    if !minha { Text(hora(m.quando)).font(.caption2).foregroundStyle(.tertiary); Spacer(minLength: 80) }
                }
            }
            .frame(maxWidth: .infinity, alignment: minha ? .trailing : .leading)
        }
    }

    private struct Avatar: View {
        let nome: String
        let canal: Bool
        var body: some View {
            let iniciais = canal ? "#" : nome.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
            // cor estável pelo nome (o hashValue do Swift muda a cada execução)
            let cor = SERIES[nome.unicodeScalars.reduce(0) { $0 + Int($1.value) } % SERIES.count]
            Text(iniciais).font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Circle().fill(cor))
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
