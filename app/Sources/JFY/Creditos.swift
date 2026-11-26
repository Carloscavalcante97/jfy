import AVFoundation
import AppKit
import SwiftUI

/// A música dos créditos vem dentro do app (app/Marca/creditos.aac), como a foto.
/// Toca em loop enquanto a aba está aberta e para ao sair dela; o botão pausa. Sem o arquivo, sem música e sem botão.
@MainActor final class MusicaCreditos: ObservableObject {
    static let arquivo = Bundle.main.url(forResource: "creditos", withExtension: "aac")
    @Published private(set) var pausada = false
    let existe = arquivo != nil
    private lazy var player: AVAudioPlayer? = {
        let p = Self.arquivo.flatMap { try? AVAudioPlayer(contentsOf: $0) }
        p?.numberOfLoops = -1
        return p
    }()

    func aba(_ aberta: Bool) {
        guard existe else { return }
        if aberta && !pausada { player?.play() } else { player?.pause() }
    }

    func alternar() {
        pausada.toggle()
        aba(true)
    }
}

/// Quem fez o jfy, e por quê. A foto vem dentro do app (app/Marca/creditos.jpg).
struct CreditosTela: View {
    let ativa: Bool
    private let foto = Bundle.main.url(forResource: "creditos", withExtension: "jpg").flatMap(NSImage.init(contentsOf:))
    @StateObject private var musica = MusicaCreditos()

    var body: some View {
        ScrollView { conteudo }
            .overlay(alignment: .topTrailing) {
                if musica.existe {
                    Button { musica.alternar() } label: {
                        Label(musica.pausada ? "Tocar" : "Pausar", systemImage: musica.pausada ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .help(musica.pausada ? "Tocar a música" : "Pausar a música")
                    .padding(16)
                }
            }
            .onChange(of: ativa, initial: true) { musica.aba(ativa) }
    }

    var conteudo: some View {
        VStack(spacing: 36) {
            HStack(alignment: .center, spacing: 44) {
                polaroide
                VStack(alignment: .leading, spacing: 16) {
                    Text("Créditos").font(Souv.titulo(34)).foregroundStyle(Souv.texto)
                    Text("O jfy nasceu no pensamento de facilitar a vida centralizando as ferramentas de trabalhos.")
                    Text("**José (Pagode) Paiva** criou e idealizou o jfy. Levou essa ideia para o terminal: abrir a task do Journify, deixar o Claude trabalhar nela e registrar o tempo, tudo sem sair dali.")
                    Text("**Antonio Cavalcante** levou a mesma ideia para fora do terminal. Trouxe a versão app, com a cara da Souv, e foi juntando o que ainda ficava espalhado: projetos e tasks, GitHub, horas, agenda, emails e notificações.")
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
