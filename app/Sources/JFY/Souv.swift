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
    /// A barra lateral: o fundo da Souv um pouco transparente, sobre o material do macOS (ou a mesa, em tela cheia).
    static let barraLateral = Color(nsColor: NSColor(name: nil) { ap in
        ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 10 / 255, green: 14 / 255, blue: 45 / 255, alpha: 0.82)
            : NSColor(srgbRed: 238 / 255, green: 240 / 255, blue: 247 / 255, alpha: 0.85)
    })

    /// Títulos: Lexend fina, como no manual.
    static func titulo(_ tamanho: CGFloat = 28) -> Font { .custom("Lexend", size: tamanho).weight(.light) }
    /// Texto: Roboto.
    static func corpo(_ tamanho: CGFloat = 13) -> Font { .custom("Roboto", size: tamanho) }

    /// O símbolo da Souv, que vem dentro do app. Vai como molde: pinte com Souv.destaque (ciano no escuro, Vivid Blue no
    /// claro, onde o ciano some no branco).
    static let simbolo = molde("souv-simbolo")
    /// O nome "souv." do logotipo, também como molde (pinte com Souv.texto).
    static let nome = molde("souv-nome")

    private static func molde(_ nome: String) -> NSImage? {
        let img = Bundle.main.url(forResource: nome, withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        img?.isTemplate = true
        return img
    }
}

/// A marca na barra superior: o símbolo e o nome da Souv, e JFY.
struct MarcaJFY: View {
    var body: some View {
        HStack(spacing: 8) {
            if let s = Souv.simbolo {
                Image(nsImage: s).resizable().interpolation(.high).foregroundStyle(Souv.destaque).frame(width: 20, height: 20)
            }
            if let n = Souv.nome {  // 458 × 124 no desenho
                Image(nsImage: n).resizable().interpolation(.high).foregroundStyle(Souv.texto).frame(width: 52, height: 14)
            }
            Rectangle().fill(Souv.borda).frame(width: 1, height: 16)
            Text("JFY").font(.custom("Lexend", size: 15).weight(.medium)).tracking(2).foregroundStyle(Souv.texto)
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("souv JFY")
    }
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
        var foto: URL?  // a foto da conta (GitHub), redonda, no lugar da bolinha
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
    @State private var busca = ""

    private var atual: Opcao? { opcoes.first { $0.valor == selecionado } }
    /// Lista longa (os 36 projetos do Journify) ganha a busca; sem acento e sem maiúscula.
    private var comBusca: Bool { opcoes.count > 12 }
    private var visiveis: [Opcao] {
        let b = busca.trimmingCharacters(in: .whitespaces)
        return b.isEmpty ? opcoes : opcoes.filter { $0.rotulo.range(of: b, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private func pegar(_ o: Opcao) {
        aberto = false
        if o.valor != selecionado { escolher(o.valor) }
    }

    var body: some View {
        Button { busca = ""; aberto.toggle() } label: {
            HStack(spacing: 6) {
                if let c = atual?.cor ?? (atual == nil && rotuloLivre != nil ? corLivre : nil) { Circle().fill(c).frame(width: 8, height: 8) }
                if let f = atual?.foto { FotoConta(url: f) }
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
            VStack(spacing: 0) {
                if comBusca {
                    TextField("Buscar", text: $busca).textFieldStyle(.roundedBorder)
                        .onSubmit { if let o = visiveis.first { pegar(o) } }  // Enter escolhe o primeiro
                        .padding([.horizontal, .top], 8)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(visiveis) { o in
                            LinhaSelect(cor: o.cor, rotulo: o.rotulo, marcado: o.valor == selecionado, foto: o.foto) { pegar(o) }
                        }
                        if visiveis.isEmpty { Text("Nada com \"\(busca)\"").foregroundStyle(Souv.texto2).padding(10) }
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
            }
            .frame(minWidth: 240, maxHeight: 380)
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
    var foto: URL?
    var icone: String?
    let acao: () -> Void
    @State private var sobre = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 8) {
                if let cor { Circle().fill(cor).frame(width: 8, height: 8) }
                if let foto { FotoConta(url: foto) }
                if let icone { Image(systemName: icone).foregroundStyle(Souv.destaque).frame(width: 16) }
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

/// A foto redonda de uma conta (github.com/<login>.png), com um círculo vazio enquanto carrega.
struct FotoConta: View {
    let url: URL
    var tamanho: CGFloat = 18

    var body: some View {
        AsyncImage(url: url) { $0.resizable() } placeholder: { Circle().fill(Souv.superficie2) }
            .frame(width: tamanho, height: tamanho).clipShape(Circle())
    }
}

/// O menu do clique direito na identidade da Souv: as linhas do select num popover, aberto onde você clicou. O
/// .contextMenu do SwiftUI é o menu do macOS, que não segue as cores do app.
struct MenuSouv: ViewModifier {
    struct Item {
        let rotulo, icone: String
        let acao: () -> Void
    }
    let itens: [Item]
    @State private var onde: UnitPoint?

    func body(content: Content) -> some View {
        content
            .overlay(CliqueDireito { onde = $0 })
            .popover(isPresented: Binding(get: { onde != nil }, set: { if !$0 { onde = nil } }),
                     attachmentAnchor: .point(onde ?? .center), arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(itens.indices, id: \.self) { i in
                        LinhaSelect(cor: nil, rotulo: itens[i].rotulo, marcado: false, icone: itens[i].icone) {
                            onde = nil
                            itens[i].acao()
                        }
                    }
                }
                .padding(6).frame(minWidth: 200).background(Souv.superficie)
            }
    }
}

/// Pega só o clique direito (e o Control-clique) e diz onde foi, de 0 a 1 na view; o clique normal passa por baixo.
struct CliqueDireito: NSViewRepresentable {
    let acao: (UnitPoint) -> Void

    func makeNSView(context: Context) -> Alvo { Alvo() }
    func updateNSView(_ v: Alvo, context: Context) { v.acao = acao }

    final class Alvo: NSView {
        var acao: ((UnitPoint) -> Void)?

        private func direito(_ e: NSEvent?) -> Bool {
            e?.type == .rightMouseDown || (e?.type == .leftMouseDown && e?.modifierFlags.contains(.control) == true)
        }
        override func hitTest(_ p: NSPoint) -> NSView? { direito(NSApp.currentEvent) ? super.hitTest(p) : nil }
        override func rightMouseDown(with e: NSEvent) { abrir(e) }
        override func mouseDown(with e: NSEvent) { if direito(e) { abrir(e) } }

        private func abrir(_ e: NSEvent) {
            let p = convert(e.locationInWindow, from: nil)
            guard bounds.width > 0, bounds.height > 0 else { return }
            acao?(UnitPoint(x: p.x / bounds.width, y: isFlipped ? p.y / bounds.height : 1 - p.y / bounds.height))
        }
    }
}

extension View {
    /// O clique direito abre o menu da Souv com estes itens (veja MenuSouv).
    func menuSouv(_ itens: [MenuSouv.Item]) -> some View { modifier(MenuSouv(itens: itens)) }

    /// Uma linha de lista na identidade da Souv: o clique escolhe; a escolhida ganha o fundo Vivid Blue suave e a
    /// barrinha de destaque, e o mouse por cima, um realce leve. Fica no lugar da seleção do List, que pinta com a cor
    /// de destaque do macOS (e cinza fora de foco), não com a do app.
    func linhaSouv(_ marcada: Bool, _ escolher: @escaping () -> Void) -> some View {
        modifier(LinhaSouv(marcada: marcada, escolher: escolher))
    }

    /// Lista sem o fundo do sistema, sobre uma cor da Souv (as colunas laterais na superfície; o meio da tela no fundo).
    func listaSouv(_ fundo: Color = Souv.superficie) -> some View {
        scrollContentBackground(.hidden).background(fundo)
    }
}

struct LinhaSouv: ViewModifier {
    let marcada: Bool
    let escolher: () -> Void
    @State private var sobre = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: escolher)
            .onHover { sobre = $0 }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 8)
                    .fill(marcada ? Souv.primaria.opacity(0.22) : sobre ? Souv.texto.opacity(0.05) : .clear)
                    .overlay(alignment: .leading) {
                        if marcada { Capsule().fill(Souv.destaque).frame(width: 3).padding(.vertical, 7) }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 1))
    }
}
