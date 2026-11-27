// A janela do jfy: a marca em cima, a barra lateral com as telas (e as abas do jfy embaixo de "jfy") e as telas,
// todas montadas, como o app do Mac (ContentView em JFYApp.swift).
import { useCallback, useEffect, useState, type ReactNode } from 'react'
import {
  Bell, BarChart3, Calendar, ChevronRight, Clock, Folder, GitBranch, Heart, Inbox, Mail, MessagesSquare, Network,
  Palette, Settings, Sun, SquareTerminal
} from 'lucide-react'
import simbolo from '@marca/souv-simbolo.svg'
import nome from '@marca/souv-nome.svg'
import { api } from './jfy'
import type { Aba } from '../../preload'
import { TerminalTela, sincronizar, useSinos } from './Terminal'

export const TELAS = [
  ['Meu dia', Sun], ['jfy', SquareTerminal], ['Projetos', Folder], ['Contexto', Inbox], ['GitHub', GitBranch],
  ['Horas', Clock], ['Agenda', Calendar], ['Emails', Mail], ['Portas', Network], ['Uso da IA', BarChart3],
  ['Chat', MessagesSquare], ['Notificações', Bell], ['Temas', Palette], ['Configurações', Settings], ['Créditos', Heart]
] as const
export type Tela = (typeof TELAS)[number][0]

/** jfy://<destino>/<resto>: o clique nas notificações. Mesmo roteiro do app do Mac (Navegacao.abrir). */
function destino(url: string): Tela {
  const [d] = url.replace(/^jfy:\/\//, '').split('/')
  const mapa: Record<string, Tela> = {
    email: 'Emails', emails: 'Emails', pr: 'GitHub', github: 'GitHub', evento: 'Agenda', agenda: 'Agenda',
    aba: 'jfy', horas: 'Horas', notificacoes: 'Notificações'
  }
  return mapa[d] ?? 'jfy'
}

function lembrado<T>(chave: string, padrao: T): [T, (v: T) => void] {
  const [v, setV] = useState<T>(() => JSON.parse(localStorage.getItem(chave) ?? 'null') ?? padrao)
  return [v, (n: T) => (localStorage.setItem(chave, JSON.stringify(n)), setV(n))]
}

function Marca() {
  return (
    <div className="marca" aria-label="souv JFY">
      <span className="simbolo" style={{ ['--svg' as string]: `url("${simbolo}")` }} />
      <span className="nome" style={{ ['--svg' as string]: `url("${nome}")` }} />
      <span className="divisor" />
      <span className="jfy">JFY</span>
    </div>
  )
}

export function Modal(p: { titulo: string; children?: ReactNode; acoes: ReactNode; fechar: () => void }) {
  useEffect(() => {
    const k = (e: KeyboardEvent) => e.key === 'Escape' && p.fechar()
    window.addEventListener('keydown', k)
    return () => window.removeEventListener('keydown', k)
  }, [p.fechar])
  return (
    <div className="veu" onMouseDown={(e) => e.target === e.currentTarget && p.fechar()}>
      <div className="modal" role="dialog" aria-label={p.titulo}>
        <h3>{p.titulo}</h3>
        {p.children}
        <div className="acoes">{p.acoes}</div>
      </div>
    </div>
  )
}

function EmConstrucao({ tela }: { tela: Tela }) {
  return (
    <div className="vazio">
      <h2>{tela}</h2>
      <span>Esta tela ainda está vindo do app do Mac para o Windows.</span>
    </div>
  )
}

export default function App() {
  const [tela, setTela] = lembrado<Tela>('tela', 'Meu dia')
  const [abas, setAbas] = useState<Aba[]>([])
  const [ativa, setAtiva] = useState('@0')
  const [recolhidas, setRecolhidas] = lembrado('barra.abasRecolhidas', false)
  const [menu, setMenu] = useState<{ aba: Aba; x: number; y: number } | null>(null)
  const [renomeando, setRenomeando] = useState<Aba | null>(null)
  const [novoNome, setNovoNome] = useState('')
  const [fechando, setFechando] = useState<Aba | null>(null)
  const sinos = useSinos()

  const atualizar = useCallback(async () => {
    const r = await api.abas.listar()
    setAbas(r.abas)
    setAtiva(r.ativa)
  }, [])

  useEffect(() => {
    atualizar()
    const fora = [api.ao.abasMudou(atualizar), api.ao.navegar((url) => setTela(destino(url)))]
    return () => fora.forEach((f) => f())
  }, [])

  useEffect(() => {
    api.tela(tela)
    sincronizar(abas.map((a) => a.id), ativa, tela === 'jfy')
  }, [abas, ativa, tela])

  // Ctrl+1 a Ctrl+9: as nove primeiras telas (⌘1 a ⌘9 no Mac). Na captura, antes do terminal pegar a tecla
  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      const n = Number(e.key)
      if (e.ctrlKey && !e.shiftKey && !e.altKey && n >= 1 && n <= 9) {
        e.preventDefault()
        e.stopPropagation()
        setTela(TELAS[n - 1][0])
      }
    }
    window.addEventListener('keydown', k, true)
    return () => window.removeEventListener('keydown', k, true)
  }, [])

  useEffect(() => {
    const fechar = () => setMenu(null)
    window.addEventListener('click', fechar)
    return () => window.removeEventListener('click', fechar)
  }, [])

  const menuVivo = abas.find((a) => a.id === '@0')?.viva ?? true
  const algumSino = abas.some((a) => sinos.has(a.id))

  return (
    <div className="app">
      <header className="topo">
        <Marca />
      </header>

      <nav className="lateral">
        {TELAS.map(([t, Icone]) => (
          <div key={t}>
            <div className={`linha ${tela === t ? 'marcada' : ''}`} onClick={() => setTela(t)}>
              <span className="icone">
                {t === 'Meu dia' ? (
                  <span className="marca">
                    <span className="simbolo" style={{ width: 16, height: 16, ['--svg' as string]: `url("${simbolo}")` }} />
                  </span>
                ) : (
                  <Icone size={16} />
                )}
              </span>
              <span className="rotulo">{t}</span>
              {t === 'jfy' && abas.length > 0 && (
                <>
                  {recolhidas && algumSino && <span className="sino" />}
                  <button
                    className={`setinha ${recolhidas ? '' : 'aberta'}`}
                    title={recolhidas ? 'Mostrar as abas do jfy' : 'Recolher as abas do jfy'}
                    onClick={(e) => (e.stopPropagation(), setRecolhidas(!recolhidas))}
                  >
                    <ChevronRight size={12} strokeWidth={3} />
                  </button>
                </>
              )}
            </div>
            {t === 'jfy' &&
              !recolhidas &&
              abas.map((a) => (
                <div
                  key={a.id}
                  className={`linha sub ${tela === 'jfy' && ativa === a.id ? 'marcada' : ''}`}
                  onClick={() => (setTela('jfy'), api.abas.ir(a.id))}
                  onContextMenu={(e) => (e.preventDefault(), a.id !== '@0' && setMenu({ aba: a, x: e.clientX, y: e.clientY }))}
                >
                  <span className="bolinha" style={{ background: a.cor ?? 'var(--texto2)' }} />
                  <span className="rotulo">{a.nome}</span>
                  {sinos.has(a.id) && <span className="sino" />}
                </div>
              ))}
          </div>
        ))}
      </nav>

      <main className="telas">
        {TELAS.map(([t]) => (
          <section key={t} className={`tela ${tela === t ? '' : 'escondida'}`}>
            {t === 'jfy' ? <TerminalTela menuVivo={menuVivo} /> : <EmConstrucao tela={t} />}
          </section>
        ))}
      </main>

      {menu && (
        <div className="menu-contexto" style={{ left: menu.x, top: menu.y }}>
          <div onClick={() => (setNovoNome(menu.aba.nome), setRenomeando(menu.aba))}>Renomear…</div>
          <div className="perigo" onClick={() => setFechando(menu.aba)}>
            Fechar aba…
          </div>
        </div>
      )}
      {renomeando && (
        <Modal
          titulo="Renomear aba"
          fechar={() => setRenomeando(null)}
          acoes={
            <>
              <button className="botao" onClick={() => setRenomeando(null)}>Cancelar</button>
              <button
                className="botao primario"
                disabled={!novoNome.trim() || novoNome.trim() === 'menu'}
                onClick={() => (api.abas.renomear(renomeando.id, novoNome.trim()), setRenomeando(null))}
              >
                Renomear
              </button>
            </>
          }
        >
          <input
            className="campo"
            autoFocus
            value={novoNome}
            onChange={(e) => setNovoNome(e.target.value)}
            onKeyDown={(e) =>
              e.key === 'Enter' && novoNome.trim() && novoNome.trim() !== 'menu' &&
              (api.abas.renomear(renomeando.id, novoNome.trim()), setRenomeando(null))
            }
          />
          <p>"menu" é o nome da aba principal do jfy e não pode ser usado.</p>
        </Modal>
      )}
      {fechando && (
        <Modal
          titulo={`Fechar a aba ${fechando.nome}?`}
          fechar={() => setFechando(null)}
          acoes={
            <>
              <button className="botao" onClick={() => setFechando(null)}>Cancelar</button>
              <button className="botao perigo" onClick={() => (api.abas.fechar(fechando.id), setFechando(null))}>
                Fechar aba
              </button>
            </>
          }
        >
          <p>O que roda nela (o Claude daquela task, um servidor…) é encerrado junto.</p>
        </Modal>
      )}
    </div>
  )
}
