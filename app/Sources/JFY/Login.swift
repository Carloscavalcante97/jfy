import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// O login do app: só entra quem está conectado ao Google com uma conta @souv.tech, o mesmo login da Agenda e do Gmail.
/// O jfy confere a sessão (--sessao-json) e recusa conta de fora no próprio login (--login), antes de guardar qualquer
/// coisa. Desconectar o Google nas Configurações volta para cá.
@MainActor final class Sessao: ObservableObject {
    struct Info: Decodable {
        let conectado, permitido, cliente: Bool
        let conta, arquivoCliente, erro: String?
        let dominio: String
    }

    enum Estado { case verificando, fora(Info?), dentro(String) }

    @Published private(set) var estado: Estado = .verificando
    /// Quem mexe na conta do Google (Configurações) avisa por aqui, e o app confere a sessão de novo.
    static let mudou = Notification.Name("jfy.sessao")

    private var timer: Timer?
    private var conferidaEm = Date()

    init() {
        Task { await verificar() }
        NotificationCenter.default.addObserver(forName: Self.mudou, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.verificar() }
        }
        // a cada 20 min, e quando o app volta para a frente (no máximo a cada 5 min), o Google é consultado de novo: conta
        // desligada ou suspensa na Souv perde o acesso e o app volta para o login
        timer = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.verificar(forcar: true) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, Date().timeIntervalSince(self.conferidaEm) > 5 * 60 else { return }
                await self.verificar(forcar: true)
            }
        }
    }

    func verificar(forcar: Bool = false) async {
        conferidaEm = Date()
        let (i, _): (Info?, String?) = await JFY.ler(["--sessao-json"] + (forcar ? ["forcar"] : []))
        if let i, i.conectado, i.permitido, let conta = i.conta { estado = .dentro(conta) } else { estado = .fora(i) }
    }
}

/// Mostra o app só com a sessão da Souv; antes, a tela de login.
struct Portao<Conteudo: View>: View {
    @ObservedObject var sessao: Sessao
    @ViewBuilder let conteudo: () -> Conteudo
    @AppStorage("primeirosPassos.estado") private var passos = ""  // "" nunca feito, "feito", "refazer"

    var body: some View {
        switch sessao.estado {
        case .dentro where passos != "feito":
            PrimeirosPassos(automatico: passos.isEmpty) { passos = "feito" }.frame(minWidth: 1040, minHeight: 640)
        case .dentro: conteudo()
        case .verificando:
            ZStack { Souv.fundo.ignoresSafeArea(); ProgressView() }.frame(minWidth: 1040, minHeight: 640)
        case .fora(let info):
            LoginTela(sessao: sessao, info: info).frame(minWidth: 1040, minHeight: 640)
        }
    }
}

struct LoginTela: View {
    @ObservedObject var sessao: Sessao
    let info: Sessao.Info?
    @State private var entrando = false
    @State private var aviso: String?

    private var dominio: String { info?.dominio ?? "souv.tech" }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(claro: 0xEEF0F7, escuro: 0x0A0E2D), Color(claro: 0xFFFFFF, escuro: 0x12183A)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                if let s = Souv.simbolo {
                    Image(nsImage: s).resizable().interpolation(.high).foregroundStyle(Souv.destaque).frame(width: 104, height: 104)
                }
                HStack(spacing: 20) {
                    if let n = Souv.nome {
                        Image(nsImage: n).resizable().interpolation(.high).foregroundStyle(Souv.texto).frame(width: 148, height: 40)
                    }
                    Rectangle().fill(Souv.borda).frame(width: 2, height: 40)
                    Text("JFY").font(.custom("Lexend", size: 44).weight(.medium)).tracking(6).foregroundStyle(Souv.texto)
                }
                Text("Seu dia de trabalho num lugar só").font(Souv.titulo(24)).foregroundStyle(Souv.texto2)
                VStack(spacing: 14) {
                    if info?.cliente == false { primeiroAcesso }
                    Button(action: entrar) {
                        HStack(spacing: 10) {
                            Image(systemName: "g.circle.fill").font(.title2)
                            Text(entrando ? "Entrando…" : "Entrar com Google").font(Souv.corpo(16).weight(.medium))
                        }
                        .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.14))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.12)))
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                        .opacity(entrando || info?.cliente == false ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(entrando || info?.cliente == false)
                    .keyboardShortcut(.defaultAction)
                    Text("Use a sua conta @\(dominio). Ela também liga a Agenda e o Gmail do jfy.")
                        .font(.caption).foregroundStyle(Souv.texto2).multilineTextAlignment(.center)
                    if entrando {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Termine o login no navegador que abriu.").font(.callout).foregroundStyle(Souv.texto2)
                        }
                    }
                    if let i = info, i.conectado, !i.permitido, let conta = i.conta {
                        Label("\(conta) não é uma conta @\(dominio).", systemImage: "person.crop.circle.badge.xmark")
                            .foregroundStyle(.orange)
                        Button("Desconectar essa conta") { desconectar() }.buttonStyle(.souvLink)
                    }
                    if let aviso { Label(aviso, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        .multilineTextAlignment(.center).textSelection(.enabled) }
                }
                .frame(width: 380)
            }
            .padding(40)
        }
        .toolbar(removing: .title)
    }

    /// Primeiro acesso neste Mac: falta o arquivo do app jfy da Souv (o client do login, no Drive da empresa).
    private var primeiroAcesso: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Primeiro acesso neste Mac").fontWeight(.semibold).foregroundStyle(Souv.texto)
            Text("Baixe o arquivo do app jfy da Souv no Drive da empresa e escolha ele aqui. Ele só identifica o app; quem entra é você, com a sua conta.")
                .font(.callout).foregroundStyle(Souv.texto2).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Abrir no Drive") { if let u = info?.arquivoCliente.flatMap(URL.init(string:)) { NSWorkspace.shared.open(u) } }
                Button("Escolher o arquivo…") { escolherArquivo() }.buttonStyle(.souvPrimario)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Souv.superficie))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Souv.borda))
    }

    private func entrar() {
        Task {
            entrando = true
            aviso = nil
            let erro = await JFY.fazer(["--login"])  // abre o Google no navegador e espera (até 5 min)
            entrando = false
            await sessao.verificar()
            if case .fora = sessao.estado { aviso = erro ?? "O login não terminou. Tente de novo." }
        }
    }

    private func desconectar() {
        Task {
            if let e = await JFY.fazer(["--google-sair"]) { aviso = e }
            await sessao.verificar()
        }
    }

    private func escolherArquivo() {
        let painel = NSOpenPanel()
        painel.allowedContentTypes = [.json]
        painel.prompt = "Usar este arquivo"
        painel.message = "Escolha o JSON do app jfy da Souv que você baixou do Drive."
        painel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard painel.runModal() == .OK, let url = painel.url else { return }
        Task {
            if let e = await JFY.fazer(["--login-cliente", url.path]) { aviso = e } else { aviso = nil }
            await sessao.verificar()
        }
    }
}
