// Tela "Chat" (app/Sources/JFY/Chat.swift no Mac): o chat do time do Journify. A tela só desenha; quem fala com o
// Journify (pelo MCP) é o jfy: `--chat` (conversas), `--chat <id>` (mensagens; abrir marca como lida),
// `--chat <id> <texto> [ids marcados]` (envia) e `--chat-ia` (melhora a mensagem pelo Claude). Mensagem nova vira
// notificação pelo vigia, e o clique abre a conversa aqui.
import { useEffect, useRef, useState } from 'react'
import { CircleAlert, CircleArrowUp, Copy, Eye, MessagesSquare, Reply, Smile, Sparkles, SpellCheck, Star, StarOff } from 'lucide-react'
import { api, ler } from '../jfy'
import { atendido, loja, nav } from '../estado'
import { Avatar as AvatarPessoa } from '../avatar'
import { Aviso, Botao, Caixa, Carregando, Flutuante, Linha, Segmentos, Selo, fmtHora, menuContexto } from '../souv'
import './Chat.css'

type Mensagem = { id: string; autor: string; autor_id?: string | null; texto: string; quando?: string; minha?: boolean }
type Conversa = {
  id: string; nome: string; tipo?: string; nao_lidas?: number
  membro?: boolean // false: um canal que você vê sem participar, só leitura
  ultima?: { autor?: string | null; texto: string; quando?: string } | null
}
type Resultado = { status: number; saida: string; erro: string }
type Tipo = 'direta' | 'canal'
type Pessoa = { id: string; nome: string }
type Favoritas = { diretas: string[]; grupos: string[] }

const tipoDe = (c: Conversa): Tipo => (c.tipo === 'canal' ? 'canal' : 'direta')
const abaLembrada = loja<Tipo>('direta', 'chat.aba')
// as fixadas no topo, na ordem em que foram fixadas. A que sumiu da lista fica guardada (volta quando ela voltar) e
// não conta na vaga, senão prenderia uma das 3 sem ter como tirar
const MAX_FIXAS = 3
const favoritas = loja<Favoritas>({ diretas: [], grupos: [] }, 'chat.favoritas')
const chaveFav = (t: Tipo) => (t === 'canal' ? 'grupos' : 'diretas')
const EMOJIS = ['👍', '🙏', '😂', '✅', '🎉', '❤️', '👀', '🚀', '🔥', '😅', '🤝', '💡']
// passar o corretor ao apertar Enter: com correção, ela aparece no campo e o próximo Enter envia
const CORRIGIR_AO_ENVIAR = loja(false, 'chat.corrigirAoEnviar')

const semAcento = (s: string) => s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase()
const escapar = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
// "@Ana" não vale dentro de "@Anabela": depois do nome, nada de letra ou número
const depoisDoNome = '(?![\\p{L}\\p{N}])'

// o --chat não passa pelo app() do motor: o erro pode vir com o traceback, e o que interessa é a última linha
const motivo = (r: Resultado) => r.erro.trim().split('\n').at(-1) || `jfy --chat falhou (código ${r.status})`
function decodificar<T>(s: string): T | null {
  try {
    return JSON.parse(s) as T
  } catch {
    return null
  }
}

/** "14:05" hoje, "24/11" antes. */
function hora(iso?: string) {
  const d = iso ? new Date(iso) : null
  if (!d || isNaN(+d)) return ''
  return d.toDateString() === new Date().toDateString() ? fmtHora(d) : d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })
}

/** As conversas da aba: as fixadas (as que estão na lista) primeiro, e o resto. */
function separar(lista: Conversa[], aba: Tipo, fav: Favoritas) {
  const daAba = lista.filter((c) => tipoDe(c) === aba)
  const ids = fav[chaveFav(aba)]
  const fixadas = ids.map((id) => daAba.find((c) => c.id === id)).filter((c): c is Conversa => !!c)
  return { fixadas, resto: daAba.filter((c) => !ids.includes(c.id)) }
}

export default function Chat({ ativa }: { ativa: boolean }) {
  const { abrirConversa } = nav.use()
  const aba = abaLembrada.use()
  const fav = favoritas.use()
  const [conversas, setConversas] = useState<Conversa[] | null>(null)
  const [selecionada, setSelecionada] = useState<string | null>(null)
  const [mensagens, setMensagens] = useState<Mensagem[]>([])
  const [texto, setTexto] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [erroEnvio, setErroEnvio] = useState<string | null>(null)
  const [erro, setErro] = useState<string | null>(null) // a lista não veio (sem rede, sem o Journify)
  const [avisoFixa, setAvisoFixa] = useState<string | null>(null)
  // o @ sendo digitado: de onde até onde vai no campo, o que vem depois do @ e a sugestão marcada (↑/↓)
  const [mencao, setMencao] = useState<{ inicio: number; fim: number; busca: string; idx: number } | null>(null)
  // quem foi escolhido no @. Não precisa zerar: o id só vai se o "@Nome" ainda estiver no texto
  const [marcados, setMarcados] = useState<Pessoa[]>([])
  const [melhorando, setMelhorando] = useState(false)
  const [antes, setAntes] = useState<string | null>(null) // o texto de antes do Claude (ou do corretor), para o Desfazer
  // quem mexeu no texto: o Claude (Melhorar) ou o corretor (Corrigir, com quantas correções)
  const [quemMexeu, setQuemMexeu] = useState<{ claude: true } | { correcoes: number }>({ claude: true })
  const [corretorOk, setCorretorOk] = useState(false) // o LanguageTool está instalado neste computador?
  const [corrigindo, setCorrigindo] = useState(false)
  const corrigirAoEnviar = CORRIGIR_AO_ENVIAR.use()
  const [erroIa, setErroIa] = useState<string | null>(null)
  const [paleta, setPaleta] = useState<HTMLElement | null>(null) // os emojis abertos, presos ao botão
  const sel = useRef(selecionada)
  sel.current = selecionada
  const campo = useRef<HTMLTextAreaElement>(null)
  const rolagem = useRef<HTMLDivElement>(null)

  async function carregarConversas() {
    const r = await api.jfy(['--chat'])
    const lista = r.status === 0 ? decodificar<Conversa[]>(r.saida) : null
    // falhou: a lista que já estava fica, com o aviso; a próxima volta tenta de novo
    if (!lista) return setErro(r.status === 0 ? 'Não entendi a lista de conversas do jfy --chat.' : motivo(r))
    setErro(null)
    setConversas(lista)
    setSelecionada((s) => {
      if (s && lista.some((c) => c.id === s)) return s
      const { fixadas, resto } = separar(lista, abaLembrada.get(), favoritas.get()) // a primeira da aba, como aparece
      return (fixadas[0] ?? resto[0] ?? lista[0])?.id ?? null
    })
  }

  async function carregarMensagens(cid: string) {
    const r = await api.jfy(['--chat', cid])
    const lista = r.status === 0 ? decodificar<Mensagem[]>(r.saida) : null
    if (!lista || sel.current !== cid) return
    // igual não troca: não redesenha nem rola
    setMensagens((m) => (JSON.stringify(m) === JSON.stringify(lista) ? m : lista))
    // o jfy marcou como lida no Journify: o selo some já, sem esperar a lista
    setConversas((l) => l && l.map((x) => (x.id === cid ? { ...x, nao_lidas: 0 } : x)))
  }

  // ponytail: busca de tempos em tempos (conversas a cada 15 s, mensagens a cada 5 s, só com a tela à vista); tempo
  // real (SSE ou websocket) se o MCP do Journify oferecer
  useEffect(() => {
    carregarConversas()
    if (!ativa) return
    const t = setInterval(carregarConversas, 15_000)
    return () => clearInterval(t)
  }, [ativa])

  // só com a tela à vista: ler as mensagens marca a conversa como lida no Journify
  useEffect(() => {
    if (!selecionada || !ativa) return
    carregarMensagens(selecionada)
    const t = setInterval(() => carregarMensagens(selecionada), 5_000)
    return () => clearInterval(t)
  }, [selecionada, ativa])

  // o clique na notificação de mensagem nova
  useEffect(() => {
    if (!abrirConversa) return
    setSelecionada(abrirConversa)
    atendido('abrirConversa')
  }, [abrirConversa])
  useEffect(() => setMensagens([]), [selecionada]) // a conversa nova não mostra as mensagens da outra enquanto carrega

  const c = conversas?.find((x) => x.id === selecionada)
  // a conversa aberta por fora (o clique na notificação) aparece na aba dela; trocar de aba à mão não fecha a aberta
  const tipoAberta = c && tipoDe(c)
  useEffect(() => void (tipoAberta && abaLembrada.set(tipoAberta)), [selecionada, !conversas])

  // a última à vista quando chega uma nova (o scrollTop, não o scrollIntoView, que rolaria a janela toda)
  useEffect(() => {
    const r = rolagem.current
    if (r) r.scrollTop = r.scrollHeight
  }, [mensagens.at(-1)?.id])
  useEffect(() => void (ativa && campo.current?.focus()), [selecionada, ativa])

  const soLeitura = c?.membro === false
  const podeEnviar = !enviando && !melhorando && !!texto.trim() && !soLeitura

  // ponytail: o MCP do Journify não lista os membros da conversa; o @ sugere quem escreveu nas mensagens carregadas (as
  // 100 últimas), da mais recente para a mais antiga. Os membros de verdade quando o MCP der a lista
  const pessoas: Pessoa[] = []
  for (const m of [...mensagens].reverse())
    if (m.autor_id && !m.minha && !pessoas.some((p) => p.id === m.autor_id)) pessoas.push({ id: m.autor_id, nome: m.autor })
  const sugestoes = mencao ? pessoas.filter((p) => semAcento(p.nome).includes(semAcento(mencao.busca))).slice(0, 8) : []
  // com gente para sugerir mas nada batendo, a lista some (é só um @ no meio do texto)
  const listaMencao = !!mencao && (sugestoes.length > 0 || pessoas.length === 0)
  const idx = Math.min(mencao?.idx ?? 0, sugestoes.length - 1)

  // as "@Nome" dos autores conhecidos ficam em destaque nas mensagens (a mais comprida primeiro: "@Ana Souza" antes de "@Ana")
  const nomes = [...new Set(mensagens.map((m) => m.autor))].filter((n) => n && n !== '?').sort((a, b) => b.length - a.length)
  const reMencao = nomes.length ? new RegExp(`(@(?:${nomes.map(escapar).join('|')}))${depoisDoNome}`, 'gu') : null

  /** O que a pessoa digita: o Desfazer do Claude some na primeira edição. */
  function editar(t: string) {
    setTexto(t)
    setAntes(null)
  }

  /** Muda o campo por código (menção, emoji, citação) e devolve o foco com o cursor em `cursor`. Com o Claude
   * trabalhando, não: o texto dele chegaria por cima. */
  function trocar(t: string, cursor: number) {
    if (melhorando) return
    editar(t)
    requestAnimationFrame(() => campo.current && (campo.current.focus(), campo.current.setSelectionRange(cursor, cursor)))
  }

  /** Um @ logo antes do cursor (no começo ou depois de espaço: email não conta) abre as sugestões. */
  function verMencao(el: HTMLTextAreaElement) {
    const ate = el.selectionStart
    const m = ate === el.selectionEnd ? el.value.slice(0, ate).match(/(?:^|\s)@([^\s@]*)$/) : null
    setMencao((a) => (m ? { inicio: ate - m[1].length - 1, fim: ate, busca: m[1], idx: a?.busca === m[1] ? a.idx : 0 } : null))
  }

  function escolher(p: Pessoa) {
    if (!mencao) return
    const nome = `@${p.nome} `
    trocar(texto.slice(0, mencao.inicio) + nome + texto.slice(mencao.fim), mencao.inicio + nome.length)
    setMarcados((l) => (l.some((x) => x.id === p.id) ? l : [...l, p]))
    setMencao(null)
  }

  function porEmoji(e: string) {
    const el = campo.current
    const [a, b] = el ? [el.selectionStart, el.selectionEnd] : [texto.length, texto.length]
    trocar(texto.slice(0, a) + e + texto.slice(b), a + e.length)
    setPaleta(null)
  }

  // o MCP do Journify ainda não tem resposta em thread: a resposta cita a mensagem no começo do texto
  function responder(m: Mensagem) {
    const trecho = [...m.texto.split('\n').filter((l) => !l.startsWith('> ')).join(' ').replace(/\s+/g, ' ').trim()]
    const cit = `> ${m.autor}: ${trecho.length > 80 ? trecho.slice(0, 79).join('').trimEnd() + '…' : trecho.join('')}\n\n`
    const novo = cit + texto.replace(/^(> .*\n)+\n?/, '') // responder de novo troca a citação, não empilha
    trocar(novo, novo.length)
  }

  useEffect(() => {
    if (ativa) ler<{ instalado: boolean }>(['--corretor-json']).then(([r]) => setCorretorOk(!!r?.instalado))
  }, [ativa])

  /** O Corrigir, sem IA e sem tokens: o LanguageTool deste computador (ortografia, acentos, crase, concordância,
   * mas/mais). Devolve quantas correções fez (0: nada para corrigir; null: deu erro). */
  async function corrigir(): Promise<number | null> {
    const t = texto
    if (!t.trim() || corrigindo || melhorando || enviando) return null
    setCorrigindo(true)
    setErroIa(null)
    const [r, msg] = await ler<{ texto: string; correcoes: unknown[] }>(['--corrigir'], t)
    setCorrigindo(false)
    if (!r) return setErroIa(msg ?? 'O corretor não respondeu.'), null
    if (r.correcoes.length) {
      setTexto(r.texto)
      setAntes(t)
      setQuemMexeu({ correcoes: r.correcoes.length })
    } else setErroIa(null)
    campo.current?.focus()
    return r.correcoes.length
  }

  async function melhorar() {
    const t = texto
    if (!t.trim() || melhorando || enviando) return
    setMelhorando(true)
    setErroIa(null)
    const [r, msg] = await ler<{ texto: string }>(['--chat-ia'], t)
    setMelhorando(false)
    if (!r?.texto) return setErroIa(msg ?? 'O Claude não devolveu texto.')
    setTexto(r.texto)
    setAntes(t)
    setQuemMexeu({ claude: true })
    campo.current?.focus()
  }

  function alternarFixa(x: Conversa) {
    const k = chaveFav(tipoDe(x))
    const ids = favoritas.get()[k]
    if (ids.includes(x.id)) return favoritas.set((f) => ({ ...f, [k]: f[k].filter((i) => i !== x.id) }))
    if (ids.filter((i) => conversas?.some((y) => y.id === i)).length >= MAX_FIXAS)
      return setAvisoFixa(
        k === 'grupos'
          ? 'Até 3 conversas fixas em grupos (e 3 em diretas): tire uma para fixar esta.'
          : 'Até 3 conversas fixas em diretas (e 3 em grupos): tire uma para fixar esta.'
      )
    setAvisoFixa(null)
    favoritas.set((f) => ({ ...f, [k]: [...f[k], x.id] }))
  }

  async function enviar() {
    const t = texto.trim()
    const cid = selecionada
    if (!cid || !t || enviando || melhorando || corrigindo || soLeitura) return
    // corrigir ao enviar: com correções, elas vão para o campo e o próximo Enter envia (nada sai sem você ver)
    if (corrigirAoEnviar && corretorOk && antes === null && (await corrigir())) return
    // os marcados cujo "@Nome" ainda está no texto: o Journify avisa cada um, como no app
    const ids = marcados.filter((p) => new RegExp(`@${escapar(p.nome)}${depoisDoNome}`, 'u').test(t)).map((p) => p.id)
    setEnviando(true)
    setErroEnvio(null)
    setTexto('')
    setAntes(null)
    setMencao(null)
    const r = await api.jfy(['--chat', cid, t, ...(ids.length ? [ids.join(',')] : [])])
    setEnviando(false)
    const m = r.status === 0 ? decodificar<Mensagem>(r.saida) : null
    if (m) {
      if (sel.current === cid) setMensagens((l) => [...l, m])
    } else {
      setTexto(t) // não perde o que foi escrito
      setErroEnvio(motivo(r))
    }
  }

  function teclas(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (e.nativeEvent.isComposing) return
    if (listaMencao) {
      if (e.key === 'Escape') return e.preventDefault(), setMencao(null)
      if (sugestoes.length && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
        e.preventDefault()
        const n = (idx + (e.key === 'ArrowDown' ? 1 : -1) + sugestoes.length) % sugestoes.length
        return setMencao((a) => a && { ...a, idx: n })
      }
      if (sugestoes.length && (e.key === 'Enter' || e.key === 'Tab')) return e.preventDefault(), escolher(sugestoes[idx])
    }
    // Enter envia; Shift+Enter quebra a linha
    if (e.key === 'Enter' && !e.shiftKey) (e.preventDefault(), enviar())
  }

  if (!conversas)
    return (
      <div className="ch-fora">
        {erro ? (
          <>
            <MessagesSquare size={40} strokeWidth={1.5} className="ch-apagado" />
            <h2>Chat do time</h2>
            <span className="texto2 selecionavel">{erro}</span>
            <Botao onClick={() => (setErro(null), carregarConversas())}>Tentar de novo</Botao>
          </>
        ) : (
          <Carregando tamanho={20} />
        )}
      </div>
    )

  const { fixadas, resto } = separar(conversas, aba, fav)
  const naoLidas = (t: Tipo) => conversas.filter((x) => tipoDe(x) === t).reduce((s, x) => s + (x.nao_lidas ?? 0), 0)
  const rotulo = (t: Tipo, nome: string) => (naoLidas(t) ? `${nome} · ${naoLidas(t)}` : nome)

  const linha = (x: Conversa) => {
    const fixa = fav[chaveFav(tipoDe(x))].includes(x.id)
    const acao = fixa ? 'Tirar do topo' : 'Fixar no topo'
    return (
      <Linha
        key={x.id}
        marcada={selecionada === x.id}
        className="ch-linha"
        onClick={() => setSelecionada(x.id)}
        onContextMenu={menuContexto(() => [{ rotulo: acao, icone: fixa ? <StarOff size={13} /> : <Star size={13} />, acao: () => alternarFixa(x) }])}
      >
        <Avatar nome={x.nome} canal={x.tipo === 'canal'} />
        <div className="ch-resumo">
          <div className="linha-h">
            <span className={`ch-nome ${(x.nao_lidas ?? 0) > 0 ? 'forte' : ''}`}>{x.nome}</span>
            <span className="espaco" />
            <button type="button" className={`ch-estrela ${fixa ? 'fixa' : ''}`} title={acao} onClick={(e) => (e.stopPropagation(), alternarFixa(x))}>
              <Star size={12} fill={fixa ? 'currentColor' : 'none'} />
            </button>
            <span className="texto2 ch-mini">{hora(x.ultima?.quando)}</span>
          </div>
          <div className="linha-h">
            <span className="texto2 ch-ultima">{x.ultima ? (x.ultima.autor ? `${x.ultima.autor}: ` : '') + x.ultima.texto : ''}</span>
            <span className="espaco" />
            <Selo n={x.nao_lidas ?? 0} />
          </div>
        </div>
      </Linha>
    )
  }

  return (
    <div className="colunas">
      <div className="coluna ch-lista">
        <div className="ch-abas">
          <Segmentos
            cheio
            valor={aba}
            mudar={abaLembrada.set}
            opcoes={[
              { valor: 'direta', rotulo: rotulo('direta', 'Diretas') },
              { valor: 'canal', rotulo: rotulo('canal', 'Grupos') }
            ]}
          />
        </div>
        {erro && <div className="ch-aviso"><Aviso texto={erro} fechar={() => setErro(null)} /></div>}
        {avisoFixa && <div className="ch-aviso"><Aviso tipo="info" texto={avisoFixa} fechar={() => setAvisoFixa(null)} /></div>}
        <div className="lista">
          {fixadas.length > 0 && (
            <>
              <div className="secao-titulo">Fixadas</div>
              {fixadas.map(linha)}
              {resto.length > 0 && <div className="secao-titulo">Conversas</div>}
            </>
          )}
          {resto.map(linha)}
          {!fixadas.length && !resto.length && (
            <div className="texto2 ch-nenhuma">{aba === 'canal' ? 'Nenhum grupo.' : 'Nenhuma conversa direta.'}</div>
          )}
        </div>
      </div>
      {c ? (
        <div className="painel ch-conversa">
          <div className="cabecalho">
            <Avatar nome={c.nome} canal={c.tipo === 'canal'} />
            <strong className="ch-titulo">{c.nome}</strong>
          </div>
          <div ref={rolagem} className="rolavel ch-mensagens">
            {mensagens.map((m, i) => (
              <Balao
                key={m.id}
                m={m}
                // o nome do autor só na primeira de uma sequência dele
                mostrarAutor={!m.minha && (i === 0 || mensagens[i - 1].autor !== m.autor)}
                reMencao={reMencao}
                menu={menuContexto(() => [
                  ...(soLeitura ? [] : [{ rotulo: 'Responder', icone: <Reply size={13} />, acao: () => responder(m) }]),
                  { rotulo: 'Copiar texto', icone: <Copy size={13} />, acao: () => api.copiar(m.texto) }
                ])}
              />
            ))}
          </div>
          {erroEnvio && (
            <span className="texto2 pequeno-texto linha-h ch-erro">
              <CircleAlert size={12} /> {erroEnvio}
            </span>
          )}
          {erroIa && <div className="ch-aviso-campo"><Aviso texto={erroIa} fechar={() => setErroIa(null)} /></div>}
          {antes !== null && !melhorando && !corrigindo && (
            <span className="texto2 pequeno-texto linha-h ch-nota">
              {'claude' in quemMexeu ? (
                <><Sparkles size={12} /> Melhorada pelo Claude.</>
              ) : (
                <><SpellCheck size={12} /> {quemMexeu.correcoes === 1 ? '1 correção' : `${quemMexeu.correcoes} correções`} do corretor
                  {corrigirAoEnviar ? ': Enter de novo envia.' : '.'}</>
              )}
              <Botao tipo="link" onClick={() => trocar(antes, antes.length)}>Desfazer</Botao>
            </span>
          )}
          {soLeitura ? (
            <div className="ch-escrever ch-so-leitura texto2">
              <Eye size={14} /> Você não participa desta conversa: só leitura.
            </div>
          ) : (
            <div className="ch-escrever">
              {listaMencao && (
                <div className="ch-sugestoes">
                  {sugestoes.length ? (
                    sugestoes.map((p, i) => (
                      // mousedown, não click: o campo não perde o foco (nem o cursor)
                      <button type="button" key={p.id} className={i === idx ? 'marcada' : ''} onMouseDown={(e) => (e.preventDefault(), escolher(p))}>
                        {/* o Journify não dá o email: o nome faz o papel dele (iniciais, cor e title) */}
                        <AvatarPessoa email={p.nome} tamanho={20} />
                        <span>{p.nome}</span>
                      </button>
                    ))
                  ) : (
                    <span className="texto2">Ninguém para sugerir: só aparece quem já escreveu nesta conversa</span>
                  )}
                </div>
              )}
              <textarea
                ref={campo}
                rows={Math.min(6, texto.split('\n').length)}
                placeholder={`Mensagem para ${c.nome}`}
                value={texto}
                readOnly={melhorando} // o texto do Claude não atropela o que fosse digitado enquanto ele trabalha
                onChange={(e) => (editar(e.target.value), verMencao(e.target))}
                onSelect={(e) => verMencao(e.currentTarget)}
                onBlur={() => setMencao(null)}
                onKeyDown={teclas}
              />
              <Botao tipo="icone" title="Emoji (Win+. abre o seletor do sistema)" disabled={melhorando} onClick={(e) => setPaleta(paleta ? null : e.currentTarget)}>
                <Smile size={20} />
              </Botao>
              {paleta && (
                <Flutuante ancora={paleta} fechar={() => setPaleta(null)}>
                  <div className="ch-emojis">
                    {EMOJIS.map((e) => (
                      <button type="button" key={e} onClick={() => porEmoji(e)}>{e}</button>
                    ))}
                  </div>
                </Flutuante>
              )}
              <Botao
                tipo="icone"
                title={corretorOk ? 'Corrige o português sem IA, neste computador (crase, concordância, acentos)' : 'Corrigir o português: instale o corretor em Configurações'}
                disabled={!corretorOk || !texto.trim() || corrigindo || melhorando || enviando}
                onClick={corrigir}
              >
                {corrigindo ? <Carregando tamanho={20} /> : <SpellCheck size={20} />}
              </Botao>
              <Botao tipo="icone" title="Melhora a mensagem com o Claude (usa tokens)" disabled={!texto.trim() || melhorando || corrigindo || enviando} onClick={melhorar}>
                {melhorando ? <Carregando tamanho={20} /> : <Sparkles size={20} />}
              </Botao>
              <button type="button" className={`ch-enviar ${podeEnviar ? 'pode' : ''}`} disabled={!podeEnviar} title="Enviar (Enter)" onClick={enviar}>
                {enviando ? <Carregando /> : <CircleArrowUp size={24} />}
              </button>
            </div>
          )}
          {!soLeitura && corretorOk && (
            <span className="ch-nota">
              <Caixa marcado={corrigirAoEnviar} mudar={CORRIGIR_AO_ENVIAR.set}>
                <span className="texto2 pequeno-texto">Corrigir ao enviar (sem IA)</span>
              </Caixa>
            </span>
          )}
        </div>
      ) : (
        <div className="painel">
          <div className="vazio">Escolha uma conversa</div>
        </div>
      )}
    </div>
  )
}

/** As "@Nome" conhecidas em destaque, o resto como veio. */
const realcar = (s: string, re: RegExp | null) =>
  re ? s.split(re).map((p, i) => (i % 2 ? <span key={i} className="ch-mencao">{p}</span> : p)) : s

function Balao({ m, mostrarAutor, reMencao, menu }: {
  m: Mensagem
  mostrarAutor: boolean
  reMencao: RegExp | null
  menu: (e: React.MouseEvent) => void
}) {
  return (
    <div className={`ch-msg ${m.minha ? 'minha' : ''}`}>
      {mostrarAutor && <span className="texto2 ch-autor">{m.autor}</span>}
      <div className="ch-bolha-linha">
        <div className="bolha selecionavel" onContextMenu={menu}>
          {/* uma linha por div: as que começam com "> " são a citação de uma resposta */}
          {m.texto.split('\n').map((l, i) =>
            l.startsWith('> ') ? (
              <div key={i} className="ch-citacao">{l.slice(2)}</div>
            ) : (
              <div key={i}>{l ? realcar(l, reMencao) : <br />}</div>
            )
          )}
        </div>
        <span className="ch-mini ch-hora">{hora(m.quando)}</span>
      </div>
    </div>
  )
}

// as cores das séries (SERIES em Uso.swift): cor estável pelo nome, a mesma do Mac
const SERIES = ['#257DE0', '#F47230', '#00B894', '#F2A600', '#EE7FAC', '#008A17']

function Avatar({ nome, canal }: { nome: string; canal: boolean }) {
  const iniciais = canal ? '#' : nome.split(' ').filter(Boolean).slice(0, 2).map((p) => [...p][0]).join('').toUpperCase()
  let soma = 0
  for (const ch of nome) soma += ch.codePointAt(0)!
  return (
    <span className="ch-avatar" style={{ background: SERIES[soma % SERIES.length] }}>
      {iniciais}
    </span>
  )
}
