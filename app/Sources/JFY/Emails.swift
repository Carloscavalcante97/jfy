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
        .onChange(of: caixa.naoLidos) { if ativa { Task { await carregar() } } }  // chegou email com a aba aberta
        .confirmationDialog("Marcar todos os não lidos da Principal como lidos no Gmail?", isPresented: $confirmarTodos) {
            Button("Marcar todos") { agir(["--emails-lidos"]) }
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
                }
                .padding(24)
                .frame(maxWidth: 820, alignment: .leading)
            }
        } else {
            Text(selecao == nil ? "Escolha um email" : "").foregroundStyle(.secondary)
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
