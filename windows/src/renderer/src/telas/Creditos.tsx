// Tela "Créditos" (app/Sources/JFY/Creditos.swift): quem fez o jfy, e por quê. A foto e a música vêm da marca
// (app/Marca/creditos.jpg e creditos.aac). A música toca em loop com a tela aberta e para ao sair dela; o botão pausa.
import { useEffect, useRef, useState } from 'react'
import { Volume2, VolumeX } from 'lucide-react'
import foto from '@marca/creditos.jpg'
import musica from '@marca/creditos.aac'
import simbolo from '@marca/souv-simbolo.svg'
import { Botao } from '../souv'
import './Creditos.css'

export default function Creditos({ ativa }: { ativa: boolean }) {
  const audio = useRef<HTMLAudioElement>(null)
  const [pausada, setPausada] = useState(false)

  useEffect(() => {
    const a = audio.current
    if (!a) return
    if (ativa && !pausada) a.play().catch(() => {}) // sem som no sistema, só não toca
    else a.pause()
  }, [ativa, pausada])

  return (
    // o botão da música fica parado no canto enquanto o texto rola (o overlay do Swift)
    <div className="cr-casca">
      <audio ref={audio} src={musica} loop />
      <Botao className="cr-musica" title={pausada ? 'Tocar a música' : 'Pausar a música'} onClick={() => setPausada(!pausada)}>
        {pausada ? <VolumeX size={14} /> : <Volume2 size={14} />}
        {pausada ? 'Tocar' : 'Pausar'}
      </Botao>
      <div className="cr-tela">
        <div className="cr-topo">
          <figure className="cr-polaroide">
            <img src={foto} alt="" />
            <figcaption>José Carlos Paiva e Antonio Cavalcante</figcaption>
          </figure>
          <div className="cr-texto">
            <h1>Créditos</h1>
            <p>O jfy nasceu no pensamento de facilitar a vida centralizando as ferramentas de trabalhos.</p>
            <p>
              <strong>José (Pagode) Paiva</strong> criou e idealizou o jfy. Levou essa ideia para o terminal: abrir a task do Journify, deixar o
              Claude trabalhar nela e registrar o tempo, tudo sem sair dali.
            </p>
            <p>
              <strong>Antonio Cavalcante</strong> levou a mesma ideia para fora do terminal. Trouxe a versão app, com a cara da Souv, e foi
              juntando o que ainda ficava espalhado: projetos e tasks, GitHub, horas, agenda, emails e notificações.
            </p>
            <p>Tudo para deixar o dia a dia de trabalho na Souv mais leve: menos abas, menos copiar e colar, mais tempo para o que importa.</p>
          </div>
        </div>
        <div className="cr-pessoas">
          <span>José Carlos Paiva</span>
          <span>Antonio Cavalcante</span>
        </div>
        <div className="cr-fim">
          <span className="cr-simbolo" style={{ ['--svg' as string]: `url("${simbolo}")` }} />
          <h2>WE WERE HERE.</h2>
        </div>
      </div>
    </div>
  )
}
