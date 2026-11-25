import SwiftUI

/// Chat com o Journify. O app só desenha: quem envia é o `jfy --chat <texto>`, então ligar o chat de verdade
/// é mexer numa função só, a chat() do jfy, quando o chat do Journify sair no MCP.
struct ChatTela: View {
    struct Mensagem: Identifiable {
        enum Autor { case eu, journify, aviso }
        let id = UUID()
        let autor: Autor
        let texto: String
    }

    @State private var mensagens: [Mensagem] = []
    @State private var texto = ""
    @State private var enviando = false
    @State private var conectado: Bool?
    @State private var motivo = ""
    @FocusState private var focado: Bool

    var body: some View {
        VStack(spacing: 0) {
            if conectado == false {
                Label(motivo.isEmpty ? "O chat do Journify ainda não está conectado." : motivo, systemImage: "bolt.horizontal.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.08))
                    .foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if mensagens.isEmpty { vazio }
                        ForEach(mensagens) { Bolha(m: $0).id($0.id) }
                        if enviando { ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                    .padding(20)
                }
                .onChange(of: mensagens.count) {
                    if let u = mensagens.last { withAnimation { proxy.scrollTo(u.id, anchor: .bottom) } }
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Pergunte ao Journify", text: $texto, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($focado)
                    .onSubmit(enviar)
                Button(action: enviar) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .buttonStyle(.plain)
                    .foregroundStyle(podeEnviar ? Color.accentColor : .secondary)
                    .disabled(!podeEnviar)
                    .help("Enviar (Enter)")
            }
            .padding(14)
        }
        .task {
            let r = await JFY.rodar(["--chat"])
            conectado = r.status == 0
            motivo = r.erro.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .onAppear { focado = true }
    }

    private var podeEnviar: Bool { !enviando && !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var vazio: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("Converse com o Journify").font(.title3.weight(.semibold))
            Text("Tasks, prazos, horas e reuniões dos seus projetos.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func enviar() {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !enviando else { return }
        texto = ""
        mensagens.append(Mensagem(autor: .eu, texto: t))
        enviando = true
        Task {
            let r = await JFY.rodar(["--chat", t])
            enviando = false
            let saida = r.saida.trimmingCharacters(in: .whitespacesAndNewlines)
            let erro = r.erro.trimmingCharacters(in: .whitespacesAndNewlines)
            mensagens.append(r.status == 0
                ? Mensagem(autor: .journify, texto: saida.isEmpty ? "(sem resposta)" : saida)
                : Mensagem(autor: .aviso, texto: erro.isEmpty ? "jfy --chat falhou (código \(r.status))" : erro))
        }
    }

    private struct Bolha: View {
        let m: Mensagem
        var body: some View {
            switch m.autor {
            case .aviso:
                Label(m.texto, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            case .eu, .journify:
                let eu = m.autor == .eu
                HStack {
                    if eu { Spacer(minLength: 80) }
                    Text(eu ? AttributedString(m.texto) : (try? AttributedString(markdown: m.texto, options:
                        .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(m.texto))
                        .textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .foregroundStyle(eu ? Color.white : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 16).fill(eu ? Color.accentColor : Color.secondary.opacity(0.12)))
                    if !eu { Spacer(minLength: 80) }
                }
            }
        }
    }
}
