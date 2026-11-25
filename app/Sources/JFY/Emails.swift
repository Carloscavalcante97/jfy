import AppKit
import SwiftUI

/// Quantos não lidos tem a Principal: o mesmo número do ✉ da barra do tmux, que o jfy guarda em ~/.jfy/email.json
/// (olha o Gmail a cada ~25 s). O app lê o arquivo a cada 10 s, sem rodar o jfy: é o selo na barra lateral.
final class CaixaEmail: ObservableObject {
    private struct Estado: Decodable { let ids: [String]? }
    static let arquivo = URL(fileURLWithPath: NSHomeDirectory() + "/.jfy/email.json")
    @Published private(set) var naoLidos = 0
    private var timer: Timer?

    init() {
        ler()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.ler() }
    }

    func ler() {
        let n = (try? JSONDecoder().decode(Estado.self, from: Data(contentsOf: Self.arquivo)))?.ids?.count ?? 0
        if n != naoLidos { naoLidos = n }
    }
}

/// Os não lidos da Principal: ler (continua não lido), marcar como lido ou não lido, marcar todos e abrir no Gmail.
/// Quem fala com o Gmail é o jfy (--emails-json, --email-json, --email-acao, --emails-lidos).
struct EmailsTela: View {
    @ObservedObject var caixa: CaixaEmail
    let ativa: Bool
    @ObservedObject var nav: Navegacao

    struct Lista: Decodable {
        struct Item: Decodable, Identifiable, Hashable {
            let id, de, assunto: String
            let ts: Double
        }
        let conta, url: String?
        let total: Int
        let mais: Bool
        let emails: [Item]
    }

    struct Email: Decodable {
        let id, de, para, data, assunto, texto, link: String
        let anexos: [String]
        let lido: Bool
    }

    @State private var lista: Lista?
    @State private var selecao: String?
    @State private var email: Email?
    @State private var aviso: String?
    @State private var carregando = false
    @State private var confirmarTodos = false
    @State private var resposta = ""
    @State private var contexto = ""
    @State private var escrevendo: String?  // o modo que o Claude está fazendo
    @State private var confirmarEnvio = false
    @State private var feito: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Emails").font(.title2.bold())
                if let l = lista {
                    Text("\(l.total)\(l.mais ? "+" : "") não lido(s) na Principal").foregroundStyle(.secondary)
                    if let c = l.conta { Text("· \(c)").foregroundStyle(.secondary) }
                }
                Spacer()
                if let u = lista?.url.flatMap(URL.init(string:)) { Link("Abrir o Gmail", destination: u) }
                Button("Marcar todos como lidos") { confirmarTodos = true }.disabled((lista?.total ?? 0) == 0)
                Button { Task { await carregar() } } label: { Image(systemName: "arrow.clockwise") }.help("Atualizar").disabled(carregando)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            if let aviso { Label(aviso, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).padding(10).textSelection(.enabled) }
            if let feito { Label(feito, systemImage: "checkmark.circle.fill").foregroundStyle(.green).padding(10) }
            HStack(spacing: 0) {
                List(selection: $selecao) {
                    if let l = lista, l.emails.isEmpty { Text("Caixa zerada: nenhum não lido na Principal.").foregroundStyle(.secondary) }
                    ForEach(lista?.emails ?? []) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(e.de).fontWeight(.semibold).lineLimit(1)
                                Spacer()
                                Text(quando(e.ts)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(e.assunto).lineLimit(2).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .tag(e.id)
                    }
                }
                .frame(width: 360)
                Divider()
                detalhe.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: ativa) { if ativa { await carregar() } }
        .task(id: selecao) { await abrir() }
        .onChange(of: nav.abrirEmail) {  // o clique na notificação de email novo
            guard let id = nav.abrirEmail else { return }
            selecao = id
            nav.abrirEmail = nil
            Task { await carregar() }
        }
        .onChange(of: caixa.naoLidos) { if ativa { Task { await carregar() } } }  // chegou email com a aba aberta
        .confirmationDialog("Marcar todos os não lidos da Principal como lidos no Gmail?", isPresented: $confirmarTodos) {
            Button("Marcar todos") { agir(["--emails-lidos"]) }
        }
        .confirmationDialog("Enviar a resposta para \(email.map { remetente($0.de) } ?? "")?", isPresented: $confirmarEnvio) {
            Button("Enviar") { if let e = email { responderGmail(e, enviar: true) } }
        } message: {
            Text("Sai da sua conta do Gmail, na mesma conversa. Não tem volta pelo app.")
        }
        .onChange(of: selecao) {
            feito = nil
            resposta = ""
            contexto = ""
        }
    }

    @ViewBuilder private var detalhe: some View {
        if let e = email {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(e.assunto).font(.title3.weight(.semibold)).textSelection(.enabled)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("De: \(e.de)")
                        Text("Para: \(e.para)")
                        Text(e.data)
                    }
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Button(e.lido ? "Marcar como não lido" : "Marcar como lido") { agir(["--email-acao", e.id, e.lido ? "nao_lido" : "lido"]) }
                        if let u = URL(string: e.link) { Link("Abrir no Gmail", destination: u) }
                    }
                    if !e.anexos.isEmpty {
                        Label("Anexos: \(e.anexos.joined(separator: ", "))", systemImage: "paperclip").font(.callout).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text(e.texto).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Divider().padding(.top, 8)
                    responder(e)
                }
                .padding(24)
                .frame(maxWidth: 820, alignment: .leading)
            }
        } else {
            Text(selecao == nil ? "Escolha um email" : "").foregroundStyle(.secondary)
        }
    }

    // ---------- responder ----------
    private func responder(_ e: Email) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RESPONDER").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextEditor(text: $resposta)
                .font(.body).frame(minHeight: 140)
                .padding(6).background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)))
                .disabled(escrevendo != nil)
            TextField("Contexto para o Claude (opcional): o que responder, o tom, o que já foi combinado…", text: $contexto, axis: .vertical)
                .lineLimit(1...4).textFieldStyle(.roundedBorder)
            HStack {
                Button { ia(e, "gerar") } label: { Label("Gerar com o Claude", systemImage: "sparkles") }
                Button("Corrigir") { ia(e, "corrigir") }.disabled(vazia).help("Só os erros do seu texto, sem mudar o que ele diz")
                Button("Melhorar") { ia(e, "melhorar") }.disabled(vazia).help("Seu texto como base, mais claro e direto")
                if let m = escrevendo { ProgressView().controlSize(.small); Text("O Claude está \(m == "gerar" ? "escrevendo" : m == "corrigir" ? "corrigindo" : "melhorando")…").foregroundStyle(.secondary) }
                Spacer()
                Button("Salvar rascunho") { responderGmail(e, enviar: false) }.disabled(vazia)
                Button("Enviar") { confirmarEnvio = true }.buttonStyle(.borderedProminent).disabled(vazia)
            }
            .disabled(escrevendo != nil)
            Text("O Claude só escreve aqui; nada sai sem você apertar Enviar. Gerar, corrigir e melhorar usam tokens.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var vazia: Bool { resposta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func remetente(_ de: String) -> String { de.components(separatedBy: " <").first ?? de }

    private func ia(_ e: Email, _ modo: String) {
        Task {
            escrevendo = modo
            struct Texto: Decodable { let texto: String }
            let (r, msg): (Texto?, String?) = await JFY.ler(["--email-ia", e.id, modo, resposta, contexto])
            escrevendo = nil
            if let r { resposta = r.texto }
            aviso = msg
        }
    }

    private func responderGmail(_ e: Email, enviar: Bool) {
        Task {
            struct Feito: Decodable { let para: String }
            let (r, msg): (Feito?, String?) = await JFY.ler(["--email-resposta", e.id, resposta] + (enviar ? ["1"] : []))
            aviso = r == nil ? msg : nil
            feito = r.map { enviar ? "Enviado para \($0.para)." : "Rascunho salvo no Gmail (para \($0.para))." }
            if r != nil, enviar { resposta = "" }
        }
    }

    private func carregar() async {
        carregando = true
        defer { carregando = false }
        let (l, msg): (Lista?, String?) = await JFY.ler(["--emails-json"])
        if let l { lista = l }
        aviso = msg
        caixa.ler()  // o jfy acabou de guardar o total: o selo acompanha
    }

    private func abrir() async {
        guard let id = selecao else { email = nil; return }
        let (e, msg): (Email?, String?) = await JFY.ler(["--email-json", id])
        if selecao == id { email = e; if msg != nil { aviso = msg } }
    }

    private func agir(_ args: [String]) {
        Task {
            aviso = await JFY.fazer(args)
            await carregar()
            await abrir()
        }
    }

    private func quando(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        return Calendar.current.isDateInToday(d) ? d.formatted(.dateTime.hour().minute())
            : d.formatted(.dateTime.day().month(.twoDigits).locale(Locale(identifier: "pt_BR")))
    }
}
