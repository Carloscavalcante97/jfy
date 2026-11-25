import AppKit
import SwiftUI

/// Os temas do jfy (o t do menu): cores e ícones de cada um; um clique troca. Muda o jfy no terminal e a barra do
/// tmux na hora, abas abertas inclusive. Quem lê e grava é o jfy (--temas-json, --tema).
struct TemasTela: View {
    let ativa: Bool

    struct Tema: Decodable, Identifiable {
        let nome: String
        let atual: Bool
        let cores, projetos, icones: [String]
        var id: String { nome }
    }

    @State private var temas: [Tema] = []
    @State private var aviso: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Temas").font(.largeTitle.bold())
                    Text("Cores e ícones do jfy no terminal e na barra de baixo. A troca vale na hora, inclusive nas abas abertas.")
                        .foregroundStyle(.secondary)
                }
                if let aviso { Label(aviso, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(temas) { cartao($0) }
                }
            }
            .padding(24)
        }
        .task(id: ativa) { if ativa, temas.isEmpty { await carregar() } }
    }

    private func cartao(_ t: Tema) -> some View {
        Button { usar(t) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(t.nome).font(.headline)
                    Spacer()
                    if t.atual { Label("em uso", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Color.accentColor) }
                }
                HStack(spacing: 4) {
                    ForEach(Array(t.cores.enumerated()), id: \.offset) { _, h in
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: h)).frame(height: 18)
                    }
                }
                HStack(spacing: 3) {
                    ForEach(Array(t.projetos.enumerated()), id: \.offset) { _, h in Circle().fill(Color(hex: h)).frame(width: 10, height: 10) }
                }
                HStack(spacing: 10) {
                    ForEach(Array(t.icones.enumerated()), id: \.offset) { _, b64 in
                        if let data = Data(base64Encoded: b64), let img = NSImage(data: data) {
                            Image(nsImage: img).interpolation(.none).resizable().frame(width: 22, height: 22)  // pixel art: sem suavizar
                        }
                    }
                    if t.icones.isEmpty { Text("ícones do Padrão").font(.caption).foregroundStyle(.secondary) }
                }
                .frame(height: 24)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(t.atual ? Color.accentColor : Color.secondary.opacity(0.15),
                                                                     lineWidth: t.atual ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(t.atual ? "Tema em uso" : "Usar o tema \(t.nome)")
    }

    private func carregar() async {
        let (d, msg): ([Tema]?, String?) = await JFY.ler(["--temas-json"])
        if let d { temas = d }
        aviso = msg
    }

    private func usar(_ t: Tema) {
        guard !t.atual else { return }
        Task {
            aviso = await JFY.fazer(["--tema", t.nome])
            await carregar()
        }
    }
}
