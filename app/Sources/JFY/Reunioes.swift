import AppKit
import SwiftUI

/// As reuniões de hoje, como o r do jfy: projeto e contexto que vão para as horas, entrar na chamada e preparar
/// com o Claude. Quem lê e grava é o jfy (--reunioes-json, --reuniao-ajuste, --reuniao-preparar).
struct ReunioesTela: View {
    let ativa: Bool
    let irParaJFY: () -> Void

    struct Dados: Decodable {
        struct Reuniao: Decodable, Identifiable {
            let ini, fim: Double
            let titulo, estado: String
            let link, p, projeto, cor, contexto: String?
            let palpite: Bool
            var id: String { "\(ini)|\(titulo)" }
        }
        struct Projeto: Decodable, Identifiable {
            let id, nome: String
            let cor: String?
        }
        let reunioes: [Reuniao]
        let projetos: [Projeto]
    }

    @State private var dados: Dados?
    @State private var aviso: String?
    @State private var rascunho: [String: String] = [:]
    @State private var outroNome: Dados.Reuniao?
    @State private var textoOutro = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reuniões de hoje").font(.largeTitle.bold())
                    Text("O projeto e o contexto de cada reunião vão para as horas.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await carregar() } } label: { Image(systemName: "arrow.clockwise") }.help("Atualizar")
            }
            if let aviso { Label(aviso, systemImage: "info.circle").foregroundStyle(.secondary) }
            if let d = dados {
                if d.reunioes.isEmpty {
                    Text("Nenhuma reunião hoje.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 10) { ForEach(d.reunioes) { cartao(d, $0) } }
                    }
                }
            } else if aviso == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .task(id: ativa) { if ativa { await carregar() } }
        .alert("Projeto no Journify", isPresented: Binding(get: { outroNome != nil }, set: { if !$0 { outroNome = nil } })) {
            TextField("ex.: Souv", text: $textoOutro)
            Button("OK") {
                if let r = outroNome, !textoOutro.isEmpty { gravar(r, p: textoOutro, contexto: r.contexto ?? "") }
                outroNome = nil
            }
            Button("Cancelar", role: .cancel) { outroNome = nil }
        }
    }

    private func cartao(_ d: Dados, _ r: Dados.Reuniao) -> some View {
        let hora = { (t: Double) in Date(timeIntervalSince1970: t).formatted(.dateTime.hour().minute()) }
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hora(r.ini)).font(.title3.weight(.semibold)).monospacedDigit()
                Text(hora(r.fim)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(r.titulo).font(.headline)
                    estado(r)
                }
                HStack(spacing: 12) {
                    Menu {
                        ForEach(d.projetos) { p in Button(p.nome) { gravar(r, p: p.id, contexto: r.contexto ?? "") } }
                        Divider()
                        Button("Outro nome no Journify…") { textoOutro = ""; outroNome = r }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: r.cor)).frame(width: 8, height: 8)
                            Text(r.projeto ?? "sem projeto").foregroundStyle(r.p == nil ? Color.orange : .primary)
                            if r.palpite { Text("pelo título").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    TextField("contexto (vira a descrição nas horas)", text: Binding(
                        get: { rascunho[r.id] ?? r.contexto ?? "" }, set: { rascunho[r.id] = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if let v = rascunho.removeValue(forKey: r.id), let p = r.p { gravar(r, p: p, contexto: v) }
                        }
                        .disabled(r.p == nil)
                        .help(r.p == nil ? "Escolha o projeto antes" : "Enter salva")
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let l = r.link, let u = URL(string: l), r.estado != "foi" {
                    Button("Entrar na chamada") { NSWorkspace.shared.open(u) }.buttonStyle(.borderedProminent)
                }
                Button("Preparar com o Claude") { preparar(r) }.disabled(r.p == nil).help("Abre numa aba do jfy")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
        .opacity(r.estado == "foi" ? 0.7 : 1)
    }

    @ViewBuilder private func estado(_ r: Dados.Reuniao) -> some View {
        switch r.estado {
        case "agora": Text("agora").font(.caption.bold()).foregroundStyle(.red)
        case "foi": Text("já foi").font(.caption).foregroundStyle(.secondary)
        default:
            Text("em \(Int(max(0, r.ini - Date().timeIntervalSince1970) / 60)) min").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func carregar() async {
        let (d, msg): (Dados?, String?) = await JFY.ler(["--reunioes-json"])
        if let d { dados = d }
        aviso = msg
    }

    private func gravar(_ r: Dados.Reuniao, p: String, contexto: String) {
        Task {
            aviso = await JFY.fazer(["--reuniao-ajuste", String(r.ini), r.titulo, p, contexto])
            await carregar()
        }
    }

    private func preparar(_ r: Dados.Reuniao) {
        Task {
            if let erro = await JFY.fazer(["--reuniao-preparar", String(r.ini), r.titulo]) { aviso = erro } else { irParaJFY() }
        }
    }
}
