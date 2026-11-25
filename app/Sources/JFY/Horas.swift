import SwiftUI

/// As horas do dia para o minhas-horas, a mesma tabela do `h` do jfy: o que foi medido (tasks, terminal livre,
/// reuniões), com os seus ajustes. Quem lê e grava é o jfy (`--horas-json`, `--horas-ajuste`, `--horas-lancar`).
struct HorasTela: View {
    let ativa: Bool
    let irParaJFY: () -> Void

    struct Horas: Decodable {
        struct Item: Decodable, Identifiable {
            let kid: String
            let pid, projeto, cor: String?
            let cat, desc: String
            let med, lanc: Int
            let fixo: Int?
            let fora, reuniao, palpite: Bool
            var id: String { kid }
        }
        struct Projeto: Decodable, Identifiable {
            let id, nome: String
            let cor: String?
        }
        let medido, pelaRegra, total: Int
        let fator: Double
        let itens: [Item]
        let projetos: [Projeto]
        let categorias: [String]
    }

    /// Projeto ou categoria fora da lista: o nome é digitado num alerta.
    private struct PedidoOutro {
        let item: Horas.Item
        let campo: String
    }

    @State private var dia = Calendar.current.startOfDay(for: Date())
    @State private var horas: Horas?
    @State private var aviso: String?
    @State private var rascunho: [String: String] = [:]  // o que está sendo digitado, por "linha|campo"
    @FocusState private var focado: String?
    @State private var outro: PedidoOutro?
    @State private var textoOutro = ""
    @State private var confirmar = false

    private var hoje: Date { Calendar.current.startOfDay(for: Date()) }
    private var iso: String { dia.formatted(.iso8601.year().month().day()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            cabecalho
            if let horas { conteudo(horas) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .padding(24)
        .task(id: "\(ativa)|\(iso)") { if ativa { await carregar() } }
        .onChange(of: focado) { antigo, _ in if let antigo { salvar(antigo) } }  // saiu do campo: salva o que ficou
        .alert(outro?.campo == "p" ? "Projeto no Journify" : "Categoria", isPresented: Binding(
            get: { outro != nil }, set: { if !$0 { outro = nil } })) {
            TextField(outro?.campo == "p" ? "ex.: Souv" : "ex.: Pesquisa", text: $textoOutro)
            Button("OK") {
                if let o = outro, !textoOutro.isEmpty { ajustar(o.item, o.campo, textoOutro) }
                outro = nil
            }
            Button("Cancelar", role: .cancel) { outro = nil }
        }
        .confirmationDialog("Lançar \(fmt(horas?.total ?? 0)) de \(dia.formatted(.dateTime.day().month(.twoDigits))) no Journify?",
                            isPresented: $confirmar) {
            Button("Lançar") { lancar() }
        } message: {
            Text("O Claude abre numa aba do jfy e preenche o minhas-horas pelo Chrome, um lançamento por linha. Esse passo usa tokens.")
        }
    }

    // ---------- topo: o dia ----------
    private var cabecalho: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Horas").font(.largeTitle.bold())
                Text(dia.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "pt_BR"))))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { mudar(-1) } label: { Image(systemName: "chevron.left") }.help("Dia anterior")
            DatePicker("Dia", selection: $dia, in: ...hoje, displayedComponents: .date).labelsHidden().datePickerStyle(.field)
            Button { mudar(1) } label: { Image(systemName: "chevron.right") }.help("Próximo dia").disabled(dia >= hoje)
            Button("Hoje") { dia = hoje }.disabled(dia == hoje)
        }
    }

    private func mudar(_ n: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: n, to: dia), d <= hoje { dia = d }
    }

    // ---------- a tabela ----------
    @ViewBuilder private func conteudo(_ h: Horas) -> some View {
        let vivos = h.itens.filter { !$0.fora }, fora = h.itens.filter(\.fora)
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lançar").font(.subheadline).foregroundStyle(.secondary)
                Text(fmt(h.total)).font(.title.weight(.semibold)).monospacedDigit()
            }
            if !h.itens.isEmpty {
                Text("medido \(fmt(h.medido)) · fator ×\(h.fator.formatted(.number.locale(Locale(identifier: "pt_BR")))) → \(fmt(h.pelaRegra))"
                     + (h.total != h.pelaRegra ? " · com seus ajustes: \(fmt(h.total))" : ""))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Lançar no Journify…") { confirmar = true }
                .buttonStyle(.borderedProminent).disabled(vivos.isEmpty)
        }
        let semProjeto = vivos.filter { $0.pid == nil }.count
        if semProjeto > 0 {
            Label("\(semProjeto) linha(s) sem projeto: escolha na coluna Projeto, ou o Claude pergunta ao lançar.",
                  systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        if let aviso { Label(aviso, systemImage: "info.circle").foregroundStyle(.secondary).textSelection(.enabled) }
        if h.itens.isEmpty {
            Text("Nada medido nesse dia: nenhuma task ou terminal livre pelo jfy e nenhuma reunião na agenda.")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(vivos) {
                TableColumn("Projeto") { it in projeto(h, it) }.width(min: 140, ideal: 180)
                TableColumn("Categoria") { it in categoria(h, it) }.width(min: 130, ideal: 160)
                TableColumn("Horas") { it in
                    HStack(spacing: 4) {
                        campo(it, "min", atual: hm(it.lanc), dica: "1:20")
                        if it.fixo != nil {
                            Image(systemName: "hand.raised").foregroundStyle(.secondary)
                                .help("Horas à mão. Apague e salve para voltar à regra.")
                        }
                    }
                    .help("Medido: \(hm(it.med)). Enter, clicar fora ou o ✓ salva; vazio volta para a regra; Esc desfaz.")
                }
                .width(min: 70, ideal: 90, max: 110)
                TableColumn("Descrição") { it in campo(it, "desc", atual: it.desc, dica: "descrição") }
                TableColumn("") { it in
                    Button { ajustar(it, "fora", "1") } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help("Remover desse dia")
                }
                .width(28)
            }
            if !fora.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Removidas desse dia").font(.caption).foregroundStyle(.secondary)
                    ForEach(fora) { it in
                        HStack {
                            Text("\(it.projeto ?? "?") · \(it.desc)").foregroundStyle(.secondary).lineLimit(1)
                            Button("Restaurar") { ajustar(it, "fora", "") }.buttonStyle(.link)
                        }
                    }
                }
            }
        }
    }

    private func projeto(_ h: Horas, _ it: Horas.Item) -> some View {
        Menu {
            ForEach(h.projetos) { p in Button(p.nome) { ajustar(it, "p", p.id) } }
            Divider()
            Button("Outro nome no Journify…") { textoOutro = ""; outro = PedidoOutro(item: it, campo: "p") }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: it.cor)).frame(width: 8, height: 8)
                Text(it.projeto ?? "sem projeto").foregroundStyle(it.pid == nil ? Color.orange : .primary)
                if it.palpite { Text("pelo título").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .menuStyle(.borderlessButton)
    }

    private func categoria(_ h: Horas, _ it: Horas.Item) -> some View {
        Menu {
            ForEach(Array(Set(h.categorias + [it.cat])).sorted(), id: \.self) { c in Button(c) { ajustar(it, "cat", c) } }
            Divider()
            Button("Outra…") { textoOutro = ""; outro = PedidoOutro(item: it, campo: "cat") }
        } label: { Text(it.cat) }
        .menuStyle(.borderlessButton)
    }

    /// Campo editável da tabela. Salva com Enter, ao sair do campo ou no ✓ que aparece enquanto há algo não salvo; Esc
    /// desfaz. Antes só o Enter salvava, e dentro da tabela do macOS ele nem sempre chega ao campo.
    private func campo(_ it: Horas.Item, _ campo: String, atual: String, dica: String) -> some View {
        let k = it.kid + "|" + campo
        let pendente = rascunho[k].map { $0 != atual } ?? false
        return HStack(spacing: 4) {
            TextField(dica, text: Binding(get: { rascunho[k] ?? atual }, set: { rascunho[k] = $0 }))
                .textFieldStyle(.plain)
                .focused($focado, equals: k)
                .onSubmit { salvar(k) }
                .onExitCommand {
                    rascunho[k] = nil
                    focado = nil
                }
            if pendente {
                Button { salvar(k) } label: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    .buttonStyle(.borderless).help("Salvar (Enter). Esc desfaz.")
            }
        }
    }

    /// Grava o que foi digitado num campo ("linha|campo"), se mudou.
    private func salvar(_ k: String) {
        guard let v = rascunho.removeValue(forKey: k), let i = k.lastIndex(of: "|"),
              let it = horas?.itens.first(where: { $0.kid == String(k[..<i]) }) else { return }
        let campo = String(k[k.index(after: i)...])
        if v != (campo == "min" ? hm(it.lanc) : it.desc) { ajustar(it, campo, v) }
    }

    // ---------- jfy ----------
    private func carregar() async {
        let r = await JFY.rodar(["--horas-json", iso])
        let erro = r.erro.trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.status == 0 else {
            aviso = erro.isEmpty ? "jfy --horas-json falhou (código \(r.status))" : erro
            return
        }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        do {
            horas = try d.decode(Horas.self, from: Data(r.saida.utf8))
            aviso = erro.isEmpty ? nil : erro  // ex.: agenda fora, as reuniões não entraram
        } catch {
            aviso = "Não entendi a resposta do jfy --horas-json: \(error)"
        }
    }

    private func ajustar(_ it: Horas.Item, _ campo: String, _ valor: String) {
        Task {
            let r = await JFY.rodar(["--horas-ajuste", iso, it.kid, campo, valor])
            await carregar()
            if r.status != 0 { aviso = r.erro.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }

    private func lancar() {
        Task {
            let r = await JFY.rodar(["--horas-lancar", iso])
            if r.status == 0 { irParaJFY() } else { aviso = r.erro.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }

    // ---------- formatos ----------
    private func hm(_ m: Int) -> String { "\(m / 60):" + String(format: "%02d", m % 60) }
    private func fmt(_ m: Int) -> String { m >= 60 ? "\(m / 60)h " + String(format: "%02d", m % 60) + "min" : "\(m)min" }
}
