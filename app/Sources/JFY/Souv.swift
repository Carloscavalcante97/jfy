import AppKit
import SwiftUI

/// A identidade visual da Souv (manual "Identidade Visual Souv" v1, GLV Brands, 2024): a paleta do manual nos dois modos
/// do macOS, as fontes (Lexend fina nos títulos, Roboto no texto, embutidas no app) e o select. No escuro, como os
/// produtos da Souv: fundo Midnight Blue, destaque Eletric Cyan. No claro, fundo Cloud White e destaque Vivid Blue (o
/// ciano some no branco). Os botões principais são Vivid Blue nos dois.
enum Souv {
    static let fundo = Color(claro: 0xF7F7F7, escuro: 0x0A0E2D)        // Cloud White / Midnight Blue
    static let superficie = Color(claro: 0xFFFFFF, escuro: 0x12183A)   // cartões
    static let superficie2 = Color(claro: 0xEEF0F7, escuro: 0x1C244A)  // campos, selects
    static let borda = Color(claro: 0xDCE0EC, escuro: 0x272F53)
    static let texto = Color(claro: 0x0A0E2D, escuro: 0xF7F7F7)
    static let texto2 = Color(claro: 0x616161, escuro: 0xB0B0B0)       // Slate Gray / Silver Gray
    static let primaria = Color(claro: 0x2054E1, escuro: 0x2054E1)     // Vivid Blue
    static let destaque = Color(claro: 0x2054E1, escuro: 0x61FAFA)     // foco e seleção: Vivid Blue / Eletric Cyan
    static let indigo = Color(claro: 0x0D2369, escuro: 0x0D2369)       // Indigo Blue

    /// Títulos: Lexend fina, como no manual.
    static func titulo(_ tamanho: CGFloat = 28) -> Font { .custom("Lexend", size: tamanho).weight(.light) }
    /// Texto: Roboto.
    static func corpo(_ tamanho: CGFloat = 13) -> Font { .custom("Roboto", size: tamanho) }

    /// O símbolo da Souv, que vem dentro do app. Vai como molde: pinte com Souv.destaque (ciano no escuro, Vivid Blue no
    /// claro, onde o ciano some no branco).
    static let simbolo: NSImage? = {
        let img = Bundle.main.url(forResource: "souv-simbolo", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        img?.isTemplate = true
        return img
    }()
}

extension Color {
    /// Uma cor para o modo claro e outra para o escuro, que troca sozinha com o macOS.
    init(claro: UInt32, escuro: UInt32) {
        self.init(nsColor: NSColor(name: nil) { ap in
            let h = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? escuro : claro
            return NSColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255,
                           blue: CGFloat(h & 255) / 255, alpha: 1)
        })
    }
}

/// O select da Souv: o valor escolhido (com a bolinha de cor, quando tem) num campo arredondado; o clique abre a lista,
/// com a marca no escolhido. `extra` é uma ação no fim da lista ("Outro nome…"); `rotuloLivre` aparece quando o valor
/// atual não está entre as opções (um nome livre, por exemplo).
struct SouvSelect<Valor: Hashable>: View {
    struct Opcao: Identifiable {
        let valor: Valor
        let rotulo: String
        var cor: Color?
        var id: Valor { valor }
    }

    let opcoes: [Opcao]
    let selecionado: Valor?
    var vazio = "Escolher"
    var rotuloLivre: String?
    var corLivre: Color?
    var extra: (String, () -> Void)?
    let escolher: (Valor) -> Void

    @State private var aberto = false

    private var atual: Opcao? { opcoes.first { $0.valor == selecionado } }

    var body: some View {
        Button { aberto.toggle() } label: {
            HStack(spacing: 6) {
                if let c = atual?.cor ?? (atual == nil && rotuloLivre != nil ? corLivre : nil) { Circle().fill(c).frame(width: 8, height: 8) }
                Text(atual?.rotulo ?? rotuloLivre ?? vazio)
                    .foregroundStyle(atual == nil && rotuloLivre == nil ? Souv.texto2 : Souv.texto).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(Souv.texto2)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Souv.superficie2))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(aberto ? Souv.destaque : Souv.borda, lineWidth: aberto ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $aberto, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(opcoes) { o in
                        LinhaSelect(cor: o.cor, rotulo: o.rotulo, marcado: o.valor == selecionado) {
                            aberto = false
                            if o.valor != selecionado { escolher(o.valor) }
                        }
                    }
                    if let extra {
                        Divider().padding(.vertical, 3)
                        LinhaSelect(cor: nil, rotulo: extra.0, marcado: false, apagado: true) {
                            aberto = false
                            extra.1()
                        }
                    }
                }
                .padding(6)
            }
            .frame(minWidth: 220, maxHeight: 340)
            .background(Souv.superficie)
        }
    }
}

/// Uma linha da lista do select, com o realce da Souv ao passar o mouse.
struct LinhaSelect: View {
    let cor: Color?
    let rotulo: String
    let marcado: Bool
    var apagado = false
    let acao: () -> Void
    @State private var sobre = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 8) {
                if let cor { Circle().fill(cor).frame(width: 8, height: 8) }
                Text(rotulo).foregroundStyle(apagado ? Souv.texto2 : Souv.texto).lineLimit(1)
                Spacer(minLength: 12)
                if marcado { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Souv.destaque) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(sobre ? Souv.primaria.opacity(0.14) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sobre = $0 }
    }
}
