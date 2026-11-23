# jfy

Menu no terminal que puxa as suas tasks do Journify, organiza por projeto e manda cada uma para o Claude Code fazer: pelo `/pipeline` (código) ou num chat livre (estudo, análise, documento). Ao encerrar, registra o tempo e o status no Journify e atualiza o `handoff.md` do repositório.

Cada task roda numa aba própria (tmux), então dá para tocar várias ao mesmo tempo e navegar entre elas.

## Instalação

Precisa de macOS e do [Claude Code](https://docs.claude.com/claude-code) instalado e logado.

### 1. Clonar e instalar

```bash
git clone https://github.com/beater27032001/jfy.git ~/jfy
~/jfy/install.sh
```

O `install.sh`:
- instala o `tmux` pelo Homebrew, se faltar;
- coloca o comando `jfy` no PATH;
- baixa a pipeline oficial do time ([pipeline-Claude](https://github.com/Carloscavalcante97/pipeline-Claude)) em `~/.jfy/pipeline-Claude` e liga o `/pipeline`, os agentes (planner, builder, verifier, e2e-tester, committer, pr-creator) e os hooks no seu `~/.claude`. Se você já tem um arquivo com o mesmo nome e conteúdo diferente, ele mantém o seu e avisa;
- confere se o MCP do Journify está configurado e roda um autoteste;
- pergunta, um por um, se você quer os extras. Responda `n` em todos para ficar só com o menu de tasks. O que você já ligou antes não é perguntado de novo:
  - **uso da IA na barra**: muda o `statusLine` do `~/.claude/settings.json`;
  - **aviso do Claude no macOS**: dois hooks no `~/.claude/settings.json` (valem para todo Claude Code) e o `terminal-notifier`;
  - **fonte JFY Mono** (a Maple Mono com os ícones em pixel art dos temas). Escolha "JFY Mono" como fonte do seu terminal (no Warp: Settings > Appearance) e reinicie o terminal com ⌘Q;

### 2. Conectar o Journify

Gere o seu token MCP no Journify e rode, trocando `SEU_TOKEN`:

```bash
claude mcp add --transport http journify https://journify.souv.tech/api/mcp/journify/mcp \
  --header "Authorization: Bearer SEU_TOKEN" --scope user
```

Use `--scope user` e o nome `journify`: é ali que o jfy procura o token. O token é pessoal, não mande print dele para ninguém.

### 3. Rodar

```bash
jfy
```

## Como usar

Número + Enter abre o item. Letras (`l`, `t`, `s`, `p`, `w`...) e o `0` (volta) valem na hora, sem Enter. No menu principal e na tela do projeto, Enter atualiza as tasks (as duas guardam a lista por 1 min, para voltar de uma task sem esperar o Journify). Toda tela termina com a mesma linha de ações: a tecla em destaque e o que ela faz, e o `0` no fim.

**Menu principal**: três seções. **Foco**: tasks de todos os projetos com prazo vencido ou nos próximos 7 dias e as de prioridade crítica, da mais urgente para a menos; o número abre a task direto. **Projetos**: os que têm tasks suas, com a contagem. **Sem task**: os configurados sem task aberta (manutenção: terminal livre ou sessão quando surgir algo). O repositório de cada projeto aparece no `c` da tela do projeto.
- Na primeira vez em cada projeto, o jfy pede a pasta do repositório (navegador de pastas: número entra, `..` sobe, `s` escolhe, ou cole o caminho) e um nome.
- `l` abre um **terminal livre**: Claude com `--dangerously-skip-permissions` numa pasta que você escolhe, sem task.

**Tela do projeto**: suas tasks em seções, na ordem do que pede ação sua primeiro: **Urgente** (prazo vencido, nos próximos 7 dias ou crítica; mostra o status no fim da linha), **Em andamento**, **A fazer**, **Esperando alguém** (revisão, teste ou validação) e **Bloqueadas**. Seção vazia não aparece.
- Número abre a task. A tela cabe no terminal, nesta ordem: projeto e título; status, prioridade, pontos e prazo (avisa se passar de 8 pontos, o teto do fluxo); **O que fazer** (o começo da descrição, já limpa: sem markdown cru, e cada imagem vira `▣ imagem a3`, o número do anexo); anexos (imagens agrupadas, documentos pelo nome); o último comentário; e as ações:
  - `1` **implementar (/pipeline)**: para task de código (testes, implementação, revisão, commit e PR com a sua aprovação). Se você não estiver numa branch gitflow, o jfy cria `feature/`, `bugfix/` (a partir da `develop` atualizada) ou `hotfix/` (a partir da `main`) com o título da task.
  - `2` **conversar com o Claude**: para estudo, análise, documento, preparação de reunião. Nada vai para o Journify sem você aprovar.
  - `d` **descrição inteira**: a task toda, com todos os comentários, para ler com espaço e setas (`q` volta).
  - `a` + número abre o anexo no navegador pelo link (ex.: `a3` + Enter). Nada é baixado para o disco.
  - `p` **prazo**: grava o prazo no Journify. Aceita `25/11`, `25/11/2026` ou `+3` (daqui a 3 dias).
  - `w` abre a task no Journify (navegador).
  - Depois de escolher, o jfy pergunta **"Algo a mais para o Claude?"**. Digite ou cole instruções extras e arraste arquivos (prints, PDFs, planilhas) para o terminal. Eles vão junto com a descrição da task. Linha vazia continua; Enter direto pula.
- `s` **sessão**: um chat só para várias tasks, uma atrás da outra. O Claude lista as tasks, você escolhe, ele faz e no fim pergunta se segue com outra. No `/exit`, o jfy registra o tempo das tasks que ficaram abertas e garante o `handoff.md` de todas as tasks trabalhadas.
- `l` **terminal livre** direto no repositório do projeto.
- `c` troca o repositório do projeto.

### Abas

Cada task abre numa aba nova, com a cor do projeto. Abrir de novo algo que já tem aba (a mesma task ou pasta) só leva você até ela. A barra fica embaixo.

| Para | Faça |
|---|---|
| voltar ao menu | clique em `0 menu` ou `Ctrl-b` e depois `0` |
| ir para outra aba | clique nela, ou `Ctrl-b` e o número |
| ver todas com prévia | `Ctrl-b` e depois `w` |
| encerrar a task | `/exit` no Claude |
| sair do jfy com tasks rodando | `0` no menu principal; `jfy` volta para elas |

### Barra de baixo, à direita

| O quê | Como funciona |
|---|---|
| IA ▰▰▱▱ 23% | quanto você já usou do limite de 5h do Claude (e até que horas), e da semana; laranja a 50%, vermelho a 80% |
| ⏱ 3h 12min / 8h | cronômetro da jornada: liga sozinho na primeira vez que você usa o jfy no dia, fica verde e notifica ao chegar a 8h |
| 14:32 | relógio |

| Atalho | Faz |
|---|---|
| `Ctrl-b` `c` | mostra todos os comandos do jfy (menus, atalhos e linha de comando). Substitui o "nova janela" do tmux |
| `Ctrl-b` `p` | pausa / retoma a jornada (almoço, intervalo). Substitui o "aba anterior" do tmux |
| `Ctrl-b` `r` | zera a jornada e começa de novo agora (pede confirmação) |

O uso da IA vem do statusline do Claude Code (o `install.sh` faz ele gravar uma cópia em `~/.jfy/claude-status.json`) e atualiza enquanto algum Claude estiver aberto.

### Temas

`t` no menu principal escolhe o tema: **Padrão**, **Dracula**, **Monokai**, **Cyberpunk**, **Élfico** (dourado e prata sobre verde-floresta), **Anão** (ouro e forja sobre bronze), **Mordor** (fogo e cinzas sobre preto), **GTA** (neon de fim de tarde e verde-dinheiro sobre roxo) ou **Aço** (azul-metálico e prata sobre azul-marinho). Muda as cores do menu e da barra na hora, sem reiniciar, e cada tema tem seus ícones em pixel art e seu desenho na barra de uso da IA. Quase todos têm também alguém andando e empurrando a barra: vampiro (Dracula), corredor com rastro de velocidade (Cyberpunk), elfo arqueiro (Élfico), anão de machado (Anão), viatura com giroflex (GTA), lorde de armadura (Mordor) e robô de quatro patas (Aço). Para isso a barra da direita é um `jfy --relogio` que fica rodando e manda uma linha por segundo; quando o `jfy` muda, ele sai e o tmux sobe o novo em até 15s. Cada pessoa tem o seu, salvo em `~/.jfy/config.json`.

| Tema | Reunião | Email | Jornada | 8h fechadas | Pausa | Barra da IA |
|---|---|---|---|---|---|---|
| Padrão | 📅 | ✉ | ⏱ | ✓ | ⏸ | `▰▱` |
| Dracula | morcego | carta | lua | taça | caixão | corações |
| Monokai | λ | @ | café | check | pausa | blocos |
| Cyberpunk | raio | sinal | bateria | disquete | pausa | scanlines |
| Élfico | folha | pergaminho | ramo | estrela | lua | brilhos |
| Anão | martelo | corvo | machado | caneca | zz | gemas |
| GTA | mira | celular | nota de dinheiro | saco de dinheiro | palmeira | estrelas de procurado |
| Mordor | vulcão | lobo | chama | o Anel | caveira | o Olho |

Os ícones em pixel art só aparecem com a fonte **JFY Mono** no terminal (o `install.sh` instala, se você aceitar). O Padrão usa caracteres comuns e funciona com qualquer fonte. Para mudar ou criar um ícone, edite o desenho em `fonte/icones.txt` e gere a fonte de novo (o comando está no topo de `fonte/patch.py`).

### Aviso do Claude

Quando um Claude responde ou pede permissão, chega uma notificação do macOS com o nome da aba (ou da pasta). **Clicar nela traz o terminal já na aba daquele Claude.** Isso usa o `terminal-notifier`, que o `install.sh` instala se você aceitar o aviso; libere **terminal-notifier** em Ajustes do Sistema > Notificações. Sem ele, a notificação aparece, mas o clique não faz nada. Vale para todo Claude Code, dentro e fora do jfy. Ela não aparece se você já está olhando: terminal na frente e, dentro do jfy, a aba daquele Claude aberta. O `install.sh` liga isso com dois hooks (`Stop` e `Notification`) no `~/.claude/settings.json`.

Para a aba também ficar vermelha, no Claude rode `/config` e ponha **Notifications** em **Terminal Bell**.

### Ao encerrar uma task (`/exit`)

O jfy pergunta:
1. pronta: comenta o tempo gasto na task e move para `finalizado_validacao`;
2. não pronta: só comenta o tempo;
3. não registrar nada.

O tempo vem do relógio (da abertura até o `/exit`) e você pode corrigir (`80`, `1h20`, `1:20`). Ele vai como comentário porque o MCP do Journify não tem campo de tempo.

Depois o Claude atualiza o `handoff.md` na raiz do repositório (ou cria do zero, se não existir) e a memória do projeto, em segundo plano: a aba já pode ser fechada. O `handoff.md` fica como alteração não commitada: commite junto com a task. Se a task rodou num worktree, ele fica em `~/.jfy/worktrees/` com o `handoff.md`: depois do merge, apague com `git worktree remove <pasta>`.

## Onde ficam as coisas

| O quê | Onde |
|---|---|
| projetos e repositórios configurados | `~/.jfy/config.json` |
| domínio do Journify que você usa (padrão `https://journify.souv.tech`) | `"journify"` no `~/.jfy/config.json` |
| memória de cada projeto (máx. 40 linhas, o Claude lê antes de tudo) | `~/.jfy/memoria/<projectId>.md` |
| worktrees de tasks paralelas | `~/.jfy/worktrees/` |
| cronômetro da jornada de hoje | `~/.jfy/dia.json` |

**Duas tasks no mesmo repositório ao mesmo tempo**: a segunda roda num `git worktree` separado, com branch própria, para os pipelines não mexerem nos mesmos arquivos. O worktree recebe uma cópia dos `.env`, mas não as dependências (`node_modules`, venv); o Claude instala se precisar.

## Atualizar

```bash
cd ~/jfy && git pull
```

Para atualizar também a pipeline, rode `~/jfy/install.sh` de novo: ele dá `git pull` na pipeline oficial e liga arquivos novos.

## Problemas comuns

- **"MCP 'journify' não configurado"**: faça o passo 2.
- **O `/pipeline` para dizendo que a branch está errada**: ele só roda em `feature/`, `bugfix/`, `hotfix/` ou `release/`. Escolha o tipo quando o jfy oferecer criar a branch.
- **O `/pipeline` diz que a task não é de código**: use a opção `2` (conversar com o Claude).
- **Um projeto não aparece no menu**: o menu mostra os projetos configurados e os que têm tasks abertas atribuídas a você. Um projeto novo, sem task sua, só aparece depois de configurado (ou quando chegar uma task).
- **Ícones do tema não aparecem (espaço vazio ou quadradinho)**: o terminal não está com a fonte JFY Mono, ou não foi reiniciado depois de instalá-la. Escolha "JFY Mono" e feche o terminal com ⌘Q.

## Desinstalar

```bash
rm "$(command -v jfy)"
find ~/.claude/commands ~/.claude/agents ~/.claude/hooks -type l -lname "*pipeline-Claude/*" -delete
rm -rf ~/.jfy ~/jfy
# e tire o "tee ~/.jfy/claude-status.json | " do statusLine e os hooks "jfy --avisar" em ~/.claude/settings.json
```
