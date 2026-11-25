import AppKit
import SwiftUI

/// O que está rodando: as portas de desenvolvimento abertas (as mesmas do o do jfy e do ícone da barra de cima).
/// Olha a cada 30 s (5 s com a aba aberta): o número vai para o selo da barra lateral.
final class PortasAbertas: ObservableObject {
    struct Porta: Decodable, Identifiable {
        let portas: [Int]
        let tipo, nome, parar: String
        let notas: [String]
        let cor, icone: String?
        var id: String { parar }
    }

    @Published private(set) var itens: [Porta] = []
    @Published var aviso: String?
    var olhando = false { didSet { if olhando { Task { await atualizar() } } } }
    private var timer: Timer?
    private var ultima = Date.distantPast

    init() {
        Task { await atualizar() }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.olhando || Date().timeIntervalSince(self.ultima) >= 30 else { return }
            Task { await self.atualizar() }
        }
    }

    @MainActor func atualizar() async {
        ultima = Date()
        let (l, msg): ([Porta]?, String?) = await JFY.ler(["--portas-json"])
        if let l { itens = l }
        aviso = msg
    }

    @MainActor func encerrar(_ p: Porta) async {
        aviso = await JFY.fazer(["--porta-encerrar", p.parar])
        await atualizar()
    }
}

struct PortasTela: View {
    @ObservedObject var portas: PortasAbertas
    let ativa: Bool
    @State private var encerrando: PortasAbertas.Porta?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portas abertas").font(.largeTitle.bold())
                    Text("Servidores de desenvolvimento rodando neste Mac: de que projeto são, se o Claude subiu, e encerrar.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await portas.atualizar() } } label: { Image(systemName: "arrow.clockwise") }.help("Atualizar")
            }
            if let a = portas.aviso { Label(a, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
            if portas.itens.isEmpty {
                Text("Nenhuma porta de desenvolvimento aberta.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) { ForEach(portas.itens) { linha($0) } }
                }
            }
        }
        .padding(24)
        .onChange(of: ativa) { _, agora in portas.olhando = agora }
        .confirmationDialog("Encerrar \(encerrando?.tipo ?? "") \(encerrando?.nome ?? "") (\(encerrando.map { txt($0.portas) } ?? ""))?",
                            isPresented: Binding(get: { encerrando != nil }, set: { if !$0 { encerrando = nil } })) {
            Button("Encerrar", role: .destructive) { if let p = encerrando { Task { await portas.encerrar(p) } } }
        } message: {
            Text("Pede para o programa sair; se em 3 s ele não saiu, força. Container do Docker é parado com docker stop.")
        }
    }

    private func linha(_ p: PortasAbertas.Porta) -> some View {
        HStack(spacing: 14) {
            Text(txt(p.portas)).font(.title3.monospacedDigit().weight(.semibold)).frame(width: 130, alignment: .leading)
            HStack(spacing: 6) {
                if let b = p.icone, let d = Data(base64Encoded: b), let img = NSImage(data: d) {
                    Image(nsImage: img).interpolation(.none).resizable().frame(width: 18, height: 18)
                }
                Text(p.tipo).foregroundStyle(Color(hex: p.cor))
            }
            .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.nome).fontWeight(.medium)
                Text(p.notas.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let porta = p.portas.first, !["postgres", "mysql", "redis", "mongo"].contains(p.tipo) {  // banco não abre no navegador
                Link("Abrir", destination: URL(string: "http://localhost:\(porta)")!).help("Abre http://localhost:\(porta)")
            }
            Button("Encerrar") { encerrando = p }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.15)))
    }

    private func txt(_ p: [Int]) -> String { p.prefix(3).map(String.init).joined(separator: ", ") + (p.count > 3 ? "…" : "") }
}
