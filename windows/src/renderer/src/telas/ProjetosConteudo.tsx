// As seções de um projeto, como no Journify (app/Sources/JFY/ProjetoConteudo.swift): Tasks (a tela de sempre),
// Documentos e Reuniões (pelo MCP), Arquivos (os anexos das tasks) e Formulários (esperando o MCP). Enviar arquivo e
// criar documento também esperam o MCP.
import { useEffect, useState, type ReactNode } from 'react'
import {
  ArrowUpRight, ClipboardList, File, FileText, FileUp, Folder, Hourglass, Image, Link, ListChecks, Lock, Plus,
  RefreshCw, Sheet, TextAlignStart, Users, type LucideIcon
} from 'lucide-react'
import { api, ler } from '../jfy'
import { Botao, BotaoContexto, Campo, Carregando, Linha, Segmentos, TextoRico, itemMenuContexto, menuContexto } from '../souv'

export const SECOES: { nome: string; icone: LucideIcon }[] = [
  { nome: 'Tasks', icone: ListChecks },
  { nome: 'Documentos', icone: FileText },
  { nome: 'Reuniões', icone: Users },
  { nome: 'Arquivos', icone: Folder },
  { nome: 'Formulários', icone: ClipboardList }
]

export function ProjetoConteudo({ secao, pid, abrirTask }: { secao: string; pid: string; abrirTask: (tid: string) => void }) {
  if (secao === 'Documentos') return <DocumentosProjeto pid={pid} />
  if (secao === 'Reuniões') return <ReunioesProjeto pid={pid} />
  if (secao === 'Arquivos') return <ArquivosProjeto pid={pid} abrirTask={abrirTask} />
  return (
    <AguardandoMCP titulo="Formulários e respostas">
      Os formulários do projeto e as respostas aparecem aqui quando o MCP do Journify tiver listar_formularios, obter_formulario e listar_respostas.
    </AguardandoMCP>
  )
}

/** O que a plataforma já desenhou mas o MCP do Journify ainda não entrega. */
function AguardandoMCP({ titulo, children }: { titulo: string; children: ReactNode }) {
  return (
    <div className="pj-aguardando">
      <Hourglass size={34} className="destaque" />
      <h2>{titulo}</h2>
      <span className="texto2">{children}</span>
      <span className="pj-selo-mcp">Aguardando o MCP</span>
    </div>
  )
}

/** Botão de algo que espera o MCP (Enviar arquivos, Novo documento): aparece, mas desligado, com o porquê. */
function BotaoAguardando({ ferramenta, children, primario }: { ferramenta: string; children: ReactNode; primario?: boolean }) {
  // o title fica no span: botão desligado não mostra a dica
  return (
    <span title={`Aguardando o MCP do Journify (${ferramenta})`}>
      <Botao tipo={primario ? 'primario' : 'secundario'} disabled>
        {children}
      </Botao>
    </span>
  )
}

// ---------- datas ----------
function dataISO(iso?: string | null) {
  const d = iso ? new Date(iso) : null
  return d && !isNaN(+d) ? d : null
}
const rtf = new Intl.RelativeTimeFormat('pt-BR', { style: 'short' })
/** "há 3 dias", como o RelativeDateTimeFormatter do macOS: a maior unidade que cabe. */
export function relativo(iso?: string | null) {
  const d = dataISO(iso)
  if (!d) return ''
  const s = (d.getTime() - Date.now()) / 1000, a = Math.abs(s)
  const [n, u]: [number, Intl.RelativeTimeFormatUnit] =
    a < 60 ? [s, 'second'] : a < 3600 ? [s / 60, 'minute'] : a < 86400 ? [s / 3600, 'hour'] : a < 7 * 86400 ? [s / 86400, 'day']
    : a < 30 * 86400 ? [s / (7 * 86400), 'week'] : a < 365 * 86400 ? [s / (30 * 86400), 'month'] : [s / (365 * 86400), 'year']
  return rtf.format(Math.trunc(n), u)
}

// ---------- documentos ----------
type Doc = { id: string; titulo: string; atualizado?: string | null; sensivel: boolean }

function DocumentosProjeto({ pid }: { pid: string }) {
  const [docs, setDocs] = useState<Doc[] | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)
  const [busca, setBusca] = useState('')
  const [aberto, setAberto] = useState<string | null>(null)
  const [conteudo, setConteudo] = useState<{ titulo: string; texto: string } | null>(null)
  const [carregando, setCarregando] = useState(false)
  const [revelado, setRevelado] = useState<Set<string>>(new Set()) // sensíveis que a pessoa pediu para ver

  useEffect(() => {
    ler<Doc[]>(['--docs-json', pid]).then(([d, msg]) => {
      setDocs(d)
      setAviso(msg)
      setAberto((a) => a ?? d?.find((x) => !x.sensivel)?.id ?? null)
    })
  }, [])

  const doc = docs?.find((x) => x.id === aberto)
  const liberado = !!doc && (!doc.sensivel || revelado.has(doc.id))
  useEffect(() => {
    setConteudo(null)
    if (!doc || !liberado) return
    let vivo = true // trocou de documento antes de chegar: não mostra o velho
    setCarregando(true)
    ler<{ titulo: string; texto: string }>(['--doc-json', doc.id]).then(([c, msg]) => {
      if (!vivo) return
      setCarregando(false)
      setConteudo(c)
      setAviso(msg)
    })
    return () => void (vivo = false)
  }, [aberto, liberado])

  const b = busca.toLowerCase()
  const filtrados = (docs ?? []).filter((d) => !b || d.titulo.toLowerCase().includes(b))
  const item = (d: Doc) => ({ tipo: 'documento' as const, ref: d.id, titulo: d.titulo, pid })

  return (
    <div className="colunas">
      <div className="coluna pj-col-300">
        <div className="linha-h pj-pad10">
          <Campo placeholder="Buscar documento" value={busca} onChange={(e) => setBusca(e.target.value)} />
          <BotaoAguardando ferramenta="criar_documento">
            <Plus size={14} />
          </BotaoAguardando>
        </div>
        {docs && !docs.length ? (
          <div className="pj-centro texto2">{aviso ?? 'Nenhum documento neste projeto.'}</div>
        ) : !docs ? (
          <div className="pj-centro texto2">{aviso ?? <Carregando />}</div>
        ) : (
          <div className="lista">
            {filtrados.map((d) => (
              <Linha
                key={d.id}
                marcada={aberto === d.id}
                onClick={() => setAberto(d.id)}
                onContextMenu={menuContexto(() => (d.sensivel ? [] : [itemMenuContexto(item(d))]))}
              >
                {d.sensivel ? <Lock size={14} className="pj-laranja" /> : <FileText size={14} className="texto2" />}
                <span className="pilha pj-gap2 pj-min0">
                  <span className="pj-corta">{d.titulo}</span>
                  <span className="texto2 pequeno-texto">{relativo(d.atualizado)}</span>
                </span>
              </Linha>
            ))}
          </div>
        )}
      </div>
      <div className="painel pj-fundo">
        {!doc ? (
          <div className="pj-centro texto2">Escolha um documento</div>
        ) : doc.sensivel && !revelado.has(doc.id) ? (
          <div className="pj-aguardando">
            <Lock size={34} className="pj-laranja" />
            <strong>{doc.titulo}</strong>
            <span className="texto2">
              Pelo título, este documento parece guardar credenciais. O conteúdo fica escondido até você pedir, e segredo não deveria morar em documento do projeto.
            </span>
            <Botao onClick={() => setRevelado(new Set([...revelado, doc.id]))}>Mostrar o conteúdo</Botao>
          </div>
        ) : conteudo ? (
          <div className="pj-leitor">
            <div className="linha-h pj-leitor-topo">
              <h2 className="pj-titulo24 selecionavel">{conteudo.titulo}</h2>
              <span className="espaco" />
              {!doc.sensivel && <BotaoContexto item={item(doc)} />}
            </div>
            <span className="texto2 pequeno-texto">Atualizado {relativo(doc.atualizado)}</span>
            <TextoRico texto={conteudo.texto} />
          </div>
        ) : carregando ? (
          <div className="pj-centro"><Carregando /></div>
        ) : (
          aviso && <div className="pj-centro texto2">{aviso}</div>
        )}
      </div>
    </div>
  )
}

// ---------- reuniões ----------
type Reuniao = { id: string; titulo: string; data?: string | null; resumo: boolean }
type DetalheReuniao = { titulo: string; data?: string | null; participantes: string[]; resumo: string }

function ReunioesProjeto({ pid }: { pid: string }) {
  const [reunioes, setReunioes] = useState<Reuniao[] | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)
  const [aberta, setAberta] = useState<string | null>(null)
  const [detalhe, setDetalhe] = useState<DetalheReuniao | null>(null)

  useEffect(() => {
    ler<Reuniao[]>(['--reunioes-projeto-json', pid]).then(([r, msg]) => {
      setReunioes(r)
      setAviso(msg)
      setAberta(r?.[0]?.id ?? null)
    })
  }, [])

  useEffect(() => {
    setDetalhe(null)
    if (!aberta) return
    let vivo = true
    ler<DetalheReuniao>(['--reuniao-json', aberta]).then(([d, msg]) => {
      if (!vivo) return
      setDetalhe(d)
      if (!d) setAviso(msg)
    })
    return () => void (vivo = false)
  }, [aberta])

  if (!reunioes) return <div className="pj-centro texto2 pj-fundo">{aviso ?? <Carregando />}</div>
  if (!reunioes.length)
    return (
      <div className="pj-aguardando">
        <Users size={34} className="texto2" />
        <span className="texto2">{aviso ?? 'Nenhuma reunião registrada neste projeto no Journify.'}</span>
      </div>
    )
  const quando = dataISO(detalhe?.data)
  return (
    <div className="colunas">
      <div className="coluna pj-col-300">
        <div className="lista">
          {reunioes.map((r) => {
            const d = dataISO(r.data)
            return (
              <Linha key={r.id} marcada={aberta === r.id} onClick={() => setAberta(r.id)}>
                <span className="pilha pj-gap2 pj-min0">
                  <span className="pj-corta">{r.titulo}</span>
                  <span className="linha-h texto2 pequeno-texto">
                    {d && d.toLocaleString('pt-BR', { dateStyle: 'medium', timeStyle: 'short' })}
                    {r.resumo && (
                      <span className="linha-h pj-gap4">
                        <TextAlignStart size={11} /> resumo
                      </span>
                    )}
                  </span>
                </span>
              </Linha>
            )
          })}
        </div>
      </div>
      <div className="painel pj-fundo">
        {detalhe ? (
          <div className="pj-leitor">
            <div className="linha-h pj-leitor-topo">
              <h2 className="pj-titulo24 selecionavel">{detalhe.titulo}</h2>
              <span className="espaco" />
              {aberta && <BotaoContexto item={{ tipo: 'reuniao', ref: aberta, titulo: detalhe.titulo, pid }} />}
            </div>
            {quando && <span className="texto2">{quando.toLocaleString('pt-BR', { dateStyle: 'full', timeStyle: 'short' })}</span>}
            {detalhe.participantes.length > 0 && (
              <span className="linha-h texto2 selecionavel">
                <Users size={14} /> {detalhe.participantes.join(', ')}
              </span>
            )}
            <hr className="pj-divisor" />
            {detalhe.resumo ? <TextoRico texto={detalhe.resumo} /> : <span className="texto2">Esta reunião ainda não tem resumo.</span>}
          </div>
        ) : aberta ? (
          <div className="pj-centro"><Carregando /></div>
        ) : (
          <div className="pj-centro texto2">Escolha uma reunião</div>
        )}
      </div>
    </div>
  )
}

// ---------- arquivos ----------
type Arquivo = {
  id: string
  nome: string
  tipo: string
  categoria: string
  task: string
  url?: string | null
  por?: string | null
  quando?: string | null
  task_titulo?: string | null
  tamanho?: number | null
}
type RespostaArquivos = { arquivos: Arquivo[]; tasks: number; lidas: number; lido?: number | null }
const CATEGORIAS = ['Todas', 'Documentos', 'Planilhas', 'Imagens', 'Outros']
const ICONE_CATEGORIA: Record<string, LucideIcon> = { Imagens: Image, Planilhas: Sheet, Documentos: FileText }

/** O tamanho como o Finder escreve (base 1000): "512 bytes", "12 KB", "1,2 MB". */
function tamanho(n: number) {
  const u = ['bytes', 'KB', 'MB', 'GB', 'TB']
  let i = 0
  while (n >= 1000 && i < u.length - 1) (n /= 1000), i++
  return `${n.toLocaleString('pt-BR', { maximumFractionDigits: i && n < 10 ? 1 : 0 })} ${u[i]}`
}

function ArquivosProjeto({ pid, abrirTask }: { pid: string; abrirTask: (tid: string) => void }) {
  const [r, setR] = useState<RespostaArquivos | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)
  const [carregando, setCarregando] = useState(false)
  const [categoria, setCategoria] = useState('Todas')
  const [busca, setBusca] = useState('')

  async function carregar(forcar = false) {
    setCarregando(true)
    const [x, msg] = await ler<RespostaArquivos>(['--arquivos-json', pid, ...(forcar ? ['forcar'] : [])])
    setCarregando(false)
    if (x) (setR(x), setAviso(null))
    else if (!r) setAviso(msg) // o ↻ que falha mantém a lista que já estava
  }
  useEffect(() => void carregar(), [])

  const b = busca.toLowerCase()
  const filtrados = (r?.arquivos ?? []).filter(
    (a) => (categoria === 'Todas' || a.categoria === categoria) && (!b || a.nome.toLowerCase().includes(b) || (a.task_titulo ?? '').toLowerCase().includes(b))
  )
  const abrir = (a: Arquivo) => a.url && api.abrirLink(a.url) // só o link: nada é baixado

  function rodape(r: RespostaArquivos) {
    const n = `${r.arquivos.length} anexo${r.arquivos.length === 1 ? '' : 's'} em ${r.tasks} task${r.tasks === 1 ? '' : 's'}.`
      + (r.lido != null ? ` Lido ${relativo(new Date(r.lido * 1000).toISOString())}.` : '')
    const faltou = r.lidas < r.tasks ? ` O Journify não deixou ler ${r.tasks - r.lidas} delas agora; tente de novo em instantes.` : ''
    return n + faltou + ' Arquivos enviados direto no projeto ainda não vêm pelo MCP.'
  }

  return (
    <div className="pj-arquivos pj-fundo">
      <div className="linha-h pj-pad12 pj-borda-baixo">
        <Segmentos valor={categoria} opcoes={CATEGORIAS.map((c) => ({ valor: c, rotulo: c }))} mudar={setCategoria} />
        <span className="espaco" />
        <Campo placeholder="Buscar arquivo" value={busca} onChange={(e) => setBusca(e.target.value)} style={{ maxWidth: 240 }} />
        <Botao tipo="icone" title="Ler de novo do Journify (fica guardado por 24 h)" disabled={carregando} onClick={() => carregar(true)}>
          {carregando && r ? <Carregando /> : <RefreshCw size={15} />}
        </Botao>
        <BotaoAguardando ferramenta="enviar_arquivo" primario>
          <FileUp size={14} /> Enviar arquivos
        </BotaoAguardando>
      </div>
      {r ? (
        <>
          {!filtrados.length ? (
            <div className="pj-centro texto2">{r.arquivos.length ? 'Nenhum arquivo com esse filtro.' : 'Nenhuma task deste projeto tem anexo.'}</div>
          ) : (
            <div className="lista">
              {filtrados.map((a) => {
                const Icone = ICONE_CATEGORIA[a.categoria] ?? File
                return (
                  <Linha
                    key={a.id}
                    title="Abrir o arquivo"
                    onClick={() => abrir(a)}
                    onContextMenu={menuContexto(() => [
                      { rotulo: 'Abrir o arquivo', icone: <ArrowUpRight size={13} />, acao: () => abrir(a) },
                      { rotulo: 'Abrir a task', icone: <ListChecks size={13} />, acao: () => abrirTask(a.task) },
                      ...(a.url
                        ? [
                            itemMenuContexto({ tipo: 'arquivo', ref: a.url, titulo: a.nome, origem: a.task_titulo, pid }),
                            { rotulo: 'Copiar o link', icone: <Link size={13} />, acao: () => api.copiar(a.url!) }
                          ]
                        : [])
                    ])}
                  >
                    <Icone size={18} className="destaque" />
                    <span className="pilha pj-gap2 pj-min0 espaco">
                      <span className="pj-corta">{a.nome}</span>
                      <span className="texto2 pequeno-texto pj-corta">
                        {[a.task_titulo, a.por, relativo(a.quando)].filter(Boolean).join(' · ')}
                      </span>
                    </span>
                    {a.tamanho != null && <span className="texto2 pequeno-texto">{tamanho(a.tamanho)}</span>}
                  </Linha>
                )
              })}
            </div>
          )}
          <div className="texto2 pequeno-texto pj-pad8">{rodape(r)}</div>
        </>
      ) : aviso ? (
        <div className="pj-centro texto2">{aviso}</div>
      ) : (
        <div className="pj-aguardando">
          <Carregando tamanho={20} />
          <span className="texto2">
            Lendo os anexos de cada task. Num projeto grande, a leitura leva até uns 2 minutos; depois fica guardada por 24 h (o ↻ lê de novo).
          </span>
        </div>
      )}
    </div>
  )
}
