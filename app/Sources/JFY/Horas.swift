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
            let med, lanc, trabalhado: Int
            let fixo: Int?
            let fora, reuniao, palpite: Bool
            var id: String { kid }
        }
        struct Projeto: Decodable, Identifiable {
            let id, nome: String
            let cor: String?
        }
        let medido, pelaRegra, total, corrigidas: Int
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
    @State private var salvando: Set<String> = []  // "linha|campo" gravando agora
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
                Text("trabalhado \(fmt(h.medido))" + (h.corrigidas > 0 ? " (\(h.corrigidas) corrigida\(h.corrigidas == 1 ? "" : "s") à mão)" : "")
                     + " · fator ×\(h.fator.formatted(.number.locale(Locale(identifier: "pt_BR")))) → \(fmt(h.pelaRegra))")
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
            // linhas próprias, não Table: dentro da Table do macOS (uma NSTableView) o Enter dos campos não chega a eles
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Projeto").frame(width: 190, alignment: .leading)
                        Text("Categoria").frame(width: 150, alignment: .leading)
                        Text("Trabalhado").frame(width: 140, alignment: .leading)
                        Text("Lança").frame(width: 70, alignment: .leading)
                        Text("Descrição").frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 22, height: 1)
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    Divider()
                    ForEach(Array(vivos.enumerated()), id: \.element.id) { i, it in
                        HStack(spacing: 12) {
                            projeto(h, it).frame(width: 190, alignment: .leading)
                            categoria(h, it).frame(width: 150, alignment: .leading)
                            HStack(spacing: 4) {
                                campo(it, "min", atual: hm(it.trabalhado), dica: "1:20").frame(width: 92)
                                if it.fixo != nil {
                                    Image(systemName: "hand.raised").foregroundStyle(.secondary)
                                        .help("Corrigida à mão (o medido era \(hm(it.med))). Apague e salve para voltar ao medido.")
                                }
                            }
                            .frame(width: 140, alignment: .leading)
                            .help("O tempo trabalhado (medido: \(hm(it.med))). Corrija se o medido estiver errado: o fator vale em cima. Enter, clicar fora ou o ✓ salva; vazio volta ao medido; Esc desfaz.")
                            Text(hm(it.lanc)).monospacedDigit().fontWeight(.semibold).frame(width: 70, alignment: .leading)
                                .help("O que vai para o Journify: o trabalhado com a regra (fator, múltiplos de 5)")
                            campo(it, "desc", atual: it.desc, dica: "descrição").frame(maxWidth: .infinity, alignment: .leading)
                            Button { ajustar(it, "fora", "1") } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).help("Remover desse dia").frame(width: 22)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(i % 2 == 1 ? Color.secondary.opacity(0.05) : Color.clear)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.15)))
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
                .textFieldStyle(.roundedBorder)
                .focused($focado, equals: k)
                .onSubmit { salvar(k) }
                .onExitCommand {
                    rascunho[k] = nil
                    focado = nil
                }
            if salvando.contains(k) {
                ProgressView().controlSize(.small).help("Salvando…")
            } else if pendente {
                Button { salvar(k) } label: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    .buttonStyle(.borderless).help("Salvar (Enter). Esc desfaz.")
            }
        }
    }

    /// Grava o que foi digitado num campo ("linha|campo"), se mudou. O campo segue mostrando o que você digitou até o
    /// jfy devolver o dia recarregado (antes voltava ao valor antigo nesse meio-tempo e parecia que não tinha salvo);
    /// se o jfy recusar, o texto fica para você corrigir, com o aviso.
    private func salvar(_ k: String) {
        guard !salvando.contains(k), let v = rascunho[k], let i = k.lastIndex(of: "|"),
              let it = horas?.itens.first(where: { $0.kid == String(k[..<i]) }) else { return }
        let campo = String(k[k.index(after: i)...])
        guard v != (campo == "min" ? hm(it.trabalhado) : it.desc) else {
            rascunho[k] = nil
            return
        }
        salvando.insert(k)
        Task {
            let r = await JFY.rodar(["--horas-ajuste", iso, it.kid, campo, v])
            await carregar()
            salvando.remove(k)
            if r.status == 0 {
                if rascunho[k] == v { rascunho[k] = nil }  // agora o valor vem do jfy
            } else {
                aviso = r.erro.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
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
