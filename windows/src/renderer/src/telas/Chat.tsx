// Tela "Chat" (app/Sources/JFY/Chat.swift no Mac): o chat do time do Journify. A tela só desenha; quem fala com o
// Journify é o jfy: `--chat` (conversas), `--chat <id>` (mensagens), `--chat <id> <texto>` (envia). Enquanto o MCP
// do Journify não tiver o chat, o jfy responde com o motivo e a tela mostra isso.
import { useEffect, useRef, useState } from 'react'
import { CircleAlert, CircleArrowUp, MessagesSquare } from 'lucide-react'
import { api } from '../jfy'
import { Botao, Carregando, Linha, Selo, fmtHora } from '../souv'
import './Chat.css'

type Mensagem = { id: string; autor: string; texto: string; quando?: string; minha?: boolean }
type Conversa = { id: string; nome: string; tipo?: string; nao_lidas?: number; ultima?: { autor: string; texto: string; quando?: string } | null }
type Resultado = { status: number; saida: string; erro: string }

const motivo = (r: Resultado) => r.erro.trim() || `jfy --chat falhou (código ${r.status})`
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
  const [conversas, setConversas] = useState<Conversa[]>([])
  const [selecionada, setSelecionada] = useState<string | null>(null)
  const [mensagens, setMensagens] = useState<Mensagem[]>([])
  const [texto, setTexto] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [erroEnvio, setErroEnvio] = useState<string | null>(null)
  const [fora, setFora] = useState<string | null>(null) // por que o chat não está disponível
  const sel = useRef(selecionada)
  sel.current = selecionada
  const campo = useRef<HTMLTextAreaElement>(null)
  const rolagem = useRef<HTMLDivElement>(null)

  async function carregarConversas() {
    const r = await api.jfy(['--chat'])
    const lista = r.status === 0 ? decodificar<Conversa[]>(r.saida) : null
    if (!lista) return setFora(r.status === 0 ? 'Não entendi a lista de conversas do jfy --chat.' : motivo(r))
    setFora(null)
    setConversas(lista)
    setSelecionada((s) => (s && lista.some((c) => c.id === s) ? s : lista[0]?.id ?? null))
  }

  async function carregarMensagens(cid: string) {
    const r = await api.jfy(['--chat', cid])
    const lista = r.status === 0 ? decodificar<Mensagem[]>(r.saida) : null
    // igual não troca: não redesenha nem rola
    if (lista && sel.current === cid) setMensagens((m) => (JSON.stringify(m) === JSON.stringify(lista) ? m : lista))
  }

  // ponytail: busca de tempos em tempos (conversas a cada 15 s, mensagens a cada 5 s, só com a tela à vista); tempo
  // real (SSE ou websocket) se o MCP do Journify oferecer
  useEffect(() => {
    if (fora) return
    carregarConversas()
    if (!ativa) return
    const t = setInterval(carregarConversas, 15_000)
    return () => clearInterval(t)
  }, [ativa, fora])

  useEffect(() => {
    if (!selecionada) return
    carregarMensagens(selecionada)
    if (!ativa) return
    const t = setInterval(() => carregarMensagens(selecionada), 5_000)
    return () => clearInterval(t)
  }, [selecionada, ativa])

  // a última à vista quando chega uma nova (o scrollTop, não o scrollIntoView, que rolaria a janela toda)
  useEffect(() => {
    const r = rolagem.current
    if (r) r.scrollTop = r.scrollHeight
  }, [mensagens.at(-1)?.id])
  useEffect(() => void (ativa && campo.current?.focus()), [selecionada, ativa])

  const podeEnviar = !enviando && !!texto.trim()

  async function enviar() {
    const t = texto.trim()
    const cid = selecionada
    if (!cid || !t || enviando) return
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

  if (fora)
    return (
      <div className="ch-fora">
        <MessagesSquare size={40} strokeWidth={1.5} className="ch-apagado" />
        <h2>Chat do time</h2>
        <span className="texto2">{fora}</span>
        <Botao onClick={() => setFora(null)}>Tentar de novo</Botao>
      </div>
    )

  const c = conversas.find((x) => x.id === selecionada)
  return (
    <div className="colunas">
      <div className="coluna ch-lista">
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
                  <span className="texto2 ch-ultima">{x.ultima ? `${x.ultima.autor}: ${x.ultima.texto}` : ''}</span>
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
