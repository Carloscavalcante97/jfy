import AppKit
import SwiftUI

/// Quem fez o jfy, e por quê. A foto vem dentro do app (app/Marca/creditos.jpg); os números saem do git do próprio
/// repositório (jfy --creditos-json).
struct CreditosTela: View {
    let ativa: Bool

    struct Numeros: Decodable {
        let inicio: String?
        let total, jose, antonio: Int
    }

    @State private var numeros: Numeros?
    private let foto = Bundle.main.url(forResource: "creditos", withExtension: "jpg").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        ScrollView { conteudo }
            .task(id: ativa) {
                guard ativa, numeros == nil else { return }
                let (n, _): (Numeros?, String?) = await JFY.ler(["--creditos-json"])
                numeros = n
            }
    }

    var conteudo: some View {
            VStack(spacing: 36) {
                HStack(alignment: .center, spacing: 44) {
                    polaroide
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Créditos").font(Souv.titulo(34)).foregroundStyle(Souv.texto)
                        Text("O jfy nasceu no terminal, criado por **José Carlos Paiva** para ligar o Journify ao Claude Code: abrir a task, deixar o Claude trabalhar e registrar o tempo, sem sair do fluxo.")
                        Text("**Antonio Cavalcante** trouxe a versão app e as melhorias: o jfy ganhou janela, a cara da Souv, e passou a juntar projetos, GitHub, horas, agenda, emails e notificações num lugar só.")
                        Text("Tudo para deixar o dia a dia de trabalho na Souv mais leve: menos abas, menos copiar e colar, mais tempo para o que importa.")
                    }
                    .font(Souv.corpo(15))
                    .foregroundStyle(Souv.texto)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460, alignment: .leading)
                }
                HStack(spacing: 16) {
                    pessoa("José Carlos Paiva", "criou o jfy", numeros.map { "\($0.jose) commits" })
                    pessoa("Antonio Cavalcante", "versão app e melhorias", numeros.map { "\($0.antonio) commits" })
                    pessoa("desde \(desde)", "feito na Souv", numeros.map { "\($0.total) commits no total" })
                }
                .frame(maxWidth: 900)
                VStack(spacing: 10) {
                    Text("FEITO COM").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Souv.texto2)
                    HStack(spacing: 8) {
                        ForEach(["Journify", "Claude Code", "Google", "GitHub", "tmux", "Python", "SwiftUI"], id: \.self) { t in
                            Text(t).font(Souv.corpo(12)).padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(Souv.superficie2)).overlay(Capsule().strokeBorder(Souv.borda))
                        }
                    }
                }
                VStack(spacing: 14) {
                    if let s = Souv.simbolo {
                        Image(nsImage: s).resizable().interpolation(.high).foregroundStyle(Souv.destaque).frame(width: 44, height: 44)
                    }
                    Text("WE WERE HERE.").font(Souv.titulo(64)).tracking(6).foregroundStyle(Souv.destaque)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12).padding(.bottom, 40)
            }
            .padding(40)
            .frame(maxWidth: .infinity)
    }

    /// A foto como uma polaroide: moldura branca, legenda embaixo, levemente torta.
    private var polaroide: some View {
        VStack(spacing: 10) {
            Group {
                if let foto { Image(nsImage: foto).resizable().scaledToFill() } else { Souv.superficie2 }
            }
            .frame(width: 340, height: 255).clipped()
            Text("José Carlos Paiva e Antonio Cavalcante").font(Souv.corpo(13)).foregroundStyle(Color(white: 0.2))
                .padding(.bottom, 6)
        }
        .padding([.top, .horizontal], 14).padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.98)))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .rotationEffect(.degrees(-3))
    }

    private func pessoa(_ nome: String, _ papel: String, _ numero: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(nome).font(Souv.titulo(20)).foregroundStyle(Souv.texto).lineLimit(1)
            Text(papel).foregroundStyle(Souv.texto2)
            Text(numero ?? " ").font(.caption).foregroundStyle(Souv.destaque)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Souv.superficie))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Souv.borda))
    }

    private var desde: String {
        guard let i = numeros?.inicio, let d = dataLocal(i) else { return "2026" }
        return d.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "pt_BR")))
    }
}
