import AppKit
import SwiftUI

/// Quem fez o jfy, e por quê. A foto vem dentro do app (app/Marca/creditos.jpg).
struct CreditosTela: View {
    private let foto = Bundle.main.url(forResource: "creditos", withExtension: "jpg").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        ScrollView { conteudo }
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
                pessoa("José Carlos Paiva")
                pessoa("Antonio Cavalcante")
            }
            .frame(maxWidth: 620)
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

    private func pessoa(_ nome: String) -> some View {
        Text(nome).font(Souv.titulo(22)).foregroundStyle(Souv.texto).lineLimit(1)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Souv.superficie))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Souv.borda))
    }
}
