// Tela "Chat" (app/Sources/JFY/Chat.swift no Mac): o chat do time do Journify. A tela só desenha; quem fala com o
// Journify (pelo MCP) é o jfy: `--chat` (conversas), `--chat <id>` (mensagens; abrir marca como lida),
// `--chat <id> <texto>` (envia). Mensagem nova vira notificação pelo vigia, e o clique abre a conversa aqui.
import { useEffect, useRef, useState } from 'react'
import { CircleAlert, CircleArrowUp, Eye, MessagesSquare } from 'lucide-react'
import { api } from '../jfy'
import { atendido, nav } from '../estado'
import { Aviso, Botao, Carregando, Linha, Selo, fmtHora } from '../souv'
import './Chat.css'

type Mensagem = { id: string; autor: string; texto: string; quando?: string; minha?: boolean }
type Conversa = {
  id: string; nome: string; tipo?: string; nao_lidas?: number
  membro?: boolean // false: um canal que você vê sem participar, só leitura
  ultima?: { autor?: string | null; texto: string; quando?: string } | null
}
type Resultado = { status: number; saida: string; erro: string }

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

export default function Chat({ ativa }: { ativa: boolean }) {
  const { abrirConversa } = nav.use()
  const [conversas, setConversas] = useState<Conversa[] | null>(null)
  const [selecionada, setSelecionada] = useState<string | null>(null)
  const [mensagens, setMensagens] = useState<Mensagem[]>([])
  const [texto, setTexto] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [erroEnvio, setErroEnvio] = useState<string | null>(null)
  const [erro, setErro] = useState<string | null>(null) // a lista não veio (sem rede, sem o Journify)
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
    setSelecionada((s) => (s && lista.some((c) => c.id === s) ? s : lista[0]?.id ?? null))
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

  // a última à vista quando chega uma nova (o scrollTop, não o scrollIntoView, que rolaria a janela toda)
  useEffect(() => {
    const r = rolagem.current
    if (r) r.scrollTop = r.scrollHeight
  }, [mensagens.at(-1)?.id])
  useEffect(() => void (ativa && campo.current?.focus()), [selecionada, ativa])

  const c = conversas?.find((x) => x.id === selecionada)
  const soLeitura = c?.membro === false
  const podeEnviar = !enviando && !!texto.trim() && !soLeitura

  async function enviar() {
    const t = texto.trim()
    const cid = selecionada
    if (!cid || !t || enviando || soLeitura) return
    setEnviando(true)
    setErroEnvio(null)
    setTexto('')
    const r = await api.jfy(['--chat', cid, t])
    setEnviando(false)
    const m = r.status === 0 ? decodificar<Mensagem>(r.saida) : null
    if (m) {
      if (sel.current === cid) setMensagens((l) => [...l, m])
    } else {
      setTexto(t) // não perde o que foi escrito
      setErroEnvio(motivo(r))
    }
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

  return (
    <div className="colunas">
      <div className="coluna ch-lista">
        {erro && <div className="ch-aviso"><Aviso texto={erro} fechar={() => setErro(null)} /></div>}
        <div className="lista">
          {conversas.map((x) => (
            <Linha key={x.id} marcada={selecionada === x.id} className="ch-linha" onClick={() => setSelecionada(x.id)}>
              <Avatar nome={x.nome} canal={x.tipo === 'canal'} />
              <div className="ch-resumo">
                <div className="linha-h">
                  <span className={`ch-nome ${(x.nao_lidas ?? 0) > 0 ? 'forte' : ''}`}>{x.nome}</span>
                  <span className="espaco" />
                  <span className="texto2 ch-mini">{hora(x.ultima?.quando)}</span>
                </div>
                <div className="linha-h">
                  <span className="texto2 ch-ultima">{x.ultima ? (x.ultima.autor ? `${x.ultima.autor}: ` : '') + x.ultima.texto : ''}</span>
                  <span className="espaco" />
                  <Selo n={x.nao_lidas ?? 0} />
                </div>
              </div>
            </Linha>
          ))}
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
              // o nome do autor só na primeira de uma sequência dele
              <Balao key={m.id} m={m} mostrarAutor={!m.minha && (i === 0 || mensagens[i - 1].autor !== m.autor)} />
            ))}
          </div>
          {erroEnvio && (
            <span className="texto2 pequeno-texto linha-h ch-erro">
              <CircleAlert size={12} /> {erroEnvio}
            </span>
          )}
          {soLeitura ? (
            <div className="ch-escrever ch-so-leitura texto2">
              <Eye size={14} /> Você não participa desta conversa: só leitura.
            </div>
          ) : (
            <div className="ch-escrever">
              <textarea
                ref={campo}
                rows={Math.min(6, texto.split('\n').length)}
                placeholder={`Mensagem para ${c.nome}`}
                value={texto}
                onChange={(e) => setTexto(e.target.value)}
                // Enter envia; Shift+Enter quebra a linha
                onKeyDown={(e) => e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing && (e.preventDefault(), enviar())}
              />
              <button type="button" className={`ch-enviar ${podeEnviar ? 'pode' : ''}`} disabled={!podeEnviar} title="Enviar (Enter)" onClick={enviar}>
                {enviando ? <Carregando /> : <CircleArrowUp size={24} />}
              </button>
            </div>
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

function Balao({ m, mostrarAutor }: { m: Mensagem; mostrarAutor: boolean }) {
  return (
    <div className={`ch-msg ${m.minha ? 'minha' : ''}`}>
      {mostrarAutor && <span className="texto2 ch-autor">{m.autor}</span>}
      <div className="ch-bolha-linha">
        <span className="bolha selecionavel">{m.texto}</span>
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
