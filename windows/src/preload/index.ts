// A ponte entre a tela e o processo principal: só o que a tela usa, nada de Node solto no renderer.
import { contextBridge, ipcRenderer } from 'electron'

type Resultado = { status: number; saida: string; erro: string }
export type Aba = { id: string; nome: string; chave: string; cor?: string; cwd: string; viva: boolean }

const ouvir = (canal: string, f: (...a: any[]) => void) => {
  const h = (_e: unknown, ...a: any[]) => f(...a)
  ipcRenderer.on(canal, h)
  return () => void ipcRenderer.removeListener(canal, h)
}

const api = {
  jfy: (args: string[], entrada?: string): Promise<Resultado> => ipcRenderer.invoke('jfy', args, entrada),
  caminhos: (): Promise<{ jfy: string; marca: string }> => ipcRenderer.invoke('caminhos'),
  abrirLink: (alvo: string) => ipcRenderer.send('abrir-link', alvo),
  tela: (nome: string) => ipcRenderer.send('tela', nome),
  abas: {
    listar: (): Promise<{ abas: Aba[]; ativa: string }> => ipcRenderer.invoke('abas:listar'),
    saida: (id: string): Promise<{ texto: string; n: number }> => ipcRenderer.invoke('abas:saida', id),
    ir: (id: string) => ipcRenderer.send('abas:ir', id),
    escrever: (id: string, d: string) => ipcRenderer.send('abas:escrever', id, d),
    redimensionar: (cols: number, rows: number) => ipcRenderer.send('abas:redimensionar', cols, rows),
    renomear: (id: string, nome: string) => ipcRenderer.send('abas:renomear', id, nome),
    fechar: (id: string) => ipcRenderer.send('abas:fechar', id),
    abrirMenu: () => ipcRenderer.send('abas:menu')
  },
  ao: {
    dados: (f: (id: string, d: string, n: number) => void) => ouvir('abas:dados', f),
    abasMudou: (f: () => void) => ouvir('abas:mudou', f),
    navegar: (f: (url: string) => void) => ouvir('navegar', f),
    notificacoes: (f: () => void) => ouvir('notificacoes:mudou', f)
  }
}

export type API = typeof api
contextBridge.exposeInMainWorld('jfy', api)
