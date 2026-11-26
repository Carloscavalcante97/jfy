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
- instala a fonte **JFY Mono** (a Maple Mono com os ícones em pixel art dos temas) e oferece já deixar ela como fonte do terminal: no Terminal do macOS vale na hora; no Warp, feche e abra ele (⌘Q). Em outro terminal, escolha "JFY Mono" nas preferências. `jfy --fonte` faz isso de novo;
- pergunta, um por um, se você quer os extras. Responda `n` em todos para ficar só com o menu de tasks. O que você já ligou antes não é perguntado de novo:
  - **uso da IA na barra**: muda o `statusLine` do `~/.claude/settings.json`;
  - **aviso do Claude no macOS**: dois hooks no `~/.claude/settings.json` (valem para todo Claude Code) e o `terminal-notifier`;
  - **ícone do jfy na barra de cima do Mac**: instala o [SwiftBar](https://swiftbar.app) (Homebrew) e um plugin dele;
  - **notificação das 7h**: um LaunchAgent.

### 2. Rodar

```bash
jfy
```

Na primeira vez, antes do menu, o jfy te guia por **primeiros passos**, um de cada vez. Ele confere cada um de verdade e só pergunta o que falta:

1. **Journify**: abre as Configurações do Journify; em *Conectar meu Claude*, clique em *Gerar token* e cole o token no jfy (ele não aparece na tela). O jfy configura o MCP `journify` no seu Claude Code.
2. **Notificações**: manda uma notificação de teste. Se o macOS bloquear, abre Ajustes do Sistema > Notificações para você ligar o **terminal-notifier** e testa de novo.
3. **Agenda e Gmail**: login do Google (só leitura). O jfy abre o JSON do app no Drive da empresa: baixe e arraste o arquivo para o terminal.
4. **Seus projetos**: para cada projeto com task sua, escolha a pasta do repositório.
5. **Tema e fonte**: o jfy instala a fonte JFY Mono, se faltar; escolha ela no terminal e um tema.

`Enter` faz o passo, `p` pula e `0` deixa para depois. Para voltar a eles quando quiser: `jfy --comecar`.

## Como usar

Nos menus, a tecla certa já basta, sem Enter: o número abre o item (com 10 ou mais opções, o `1` espera um instante pelo segundo dígito), e letras (`l`, `r`, `h`, `t`, `s`, `p`, `w`...) e o `0` (volta) valem na hora, sem Enter. No menu principal e na tela do projeto, Enter atualiza as tasks (as duas guardam a lista por 1 min, para voltar de uma task sem esperar o Journify). Toda tela termina com a mesma linha de ações: a tecla em destaque e o que ela faz, e o `0` no fim.

**Menu principal**: três seções. **Foco**: tasks de todos os projetos com prazo vencido ou nos próximos 7 dias e as de prioridade crítica, da mais urgente para a menos; o número abre a task direto. **Projetos**: os que têm tasks suas, com a contagem. **Sem task**: os configurados sem task aberta (manutenção: terminal livre ou sessão quando surgir algo). O repositório de cada projeto aparece no `c` da tela do projeto.
- `j` abre o Journify no navegador.
- `jfy --hoje` imprime as reuniões de hoje e o foco, sem abrir o menu.
- Na primeira vez em cada projeto, o jfy pede a pasta do repositório (navegador de pastas: número entra, `..` sobe, `s` escolhe, ou cole o caminho) e um nome. Projeto com mais de um repositório (front e back, por exemplo): responda `s` em "Mais um repositório" e escolha o próximo. Na hora da task, o jfy pergunta quais ela usa (número = só esse, Enter = todos); o Claude abre no primeiro e enxerga os outros, e a branch da task é criada em cada um. Projeto sem repositório (só estudo ou teste): `n` no navegador de pastas e dê um nome, que aparece no lugar do id; o Claude abre numa pasta só dele, `~/.jfy/sem-repo/<id>`, onde fica o `handoff.md`.
- `l` abre um **terminal livre**: Claude com `--dangerously-skip-permissions` numa pasta que você escolhe, sem task.
- `r` **reuniões de hoje**: escolha uma pelo número e diga o projeto (Enter aceita o palpite pelo título; ou escreva o nome do projeto no Journify, como `Souv`, se ele não estiver no jfy) e, se quiser, uma linha de contexto (ex.: "alinhamento de infra das duas Plastamps"). O jfy só grava: nada de Claude, nada de task. Nas horas, a reunião vai para esse projeto com o contexto como descrição. `p` + número abre a preparação com o Claude (opcional): o que avançou, o que espera alguém, bloqueios e perguntas.
- `h` **horas**: abre a tabela de hoje para o [minhas-horas](https://journify.souv.tech/minhas-horas), uma linha por lançamento (veja [Horas](#horas)). `l` chama o Claude para lançar pelo Chrome. Também dá para rodar `jfy --horas -1` (ontem) ou `jfy --horas 20/11`.

**Tela do projeto**: suas tasks em seções, na ordem do que pede ação sua primeiro: **Urgente** (prazo vencido, nos próximos 7 dias ou crítica; mostra o status no fim da linha), **Em andamento**, **A fazer**, **Esperando alguém** (revisão, teste ou validação) e **Bloqueadas**. Seção vazia não aparece.
- Número abre a task. A tela cabe no terminal, nesta ordem: projeto e título; status, prioridade, pontos e prazo (avisa se passar de 8 pontos, o teto de um PR); **O que fazer** (o começo da descrição, já limpa: sem markdown cru, e cada imagem vira `▣ imagem a3`, o número do anexo); anexos (imagens agrupadas, documentos pelo nome); o último comentário; e as ações:
  - `1` **implementar (/pipeline)**: para task de código (testes, implementação, revisão, commit e PR com a sua aprovação). Se você não estiver numa branch gitflow, o jfy cria `feature/`, `bugfix/` (a partir da `develop` atualizada) ou `hotfix/` (a partir da `main`) com o título da task. Se você já estiver numa, o jfy soma os pontos da task com os das tasks já commitadas nela: passando de 8, o teto de um PR, ele oferece abrir uma branch nova para a task.
  - `2` **conversar com o Claude**: para estudo, análise, documento, preparação de reunião. Nada vai para o Journify sem você aprovar.
  - `d` **descrição inteira**: a task toda, com todos os comentários, para ler com espaço e setas (`q` volta).
  - `a` + número abre o anexo no navegador pelo link (ex.: `a3`). Nada é baixado para o disco.
  - `p` **prazo**: grava o prazo no Journify. Aceita `25/11`, `25/11/2026` ou `+3` (daqui a 3 dias).
  - `w` abre a task no Journify (navegador).
  - Depois de escolher, o jfy pergunta **"Algo a mais para o Claude?"**. Digite ou cole instruções extras e arraste arquivos (prints, PDFs, planilhas) para o terminal. Eles vão junto com a descrição da task. Linha vazia continua; Enter direto pula.
- `s` **sessão**: um chat só para várias tasks, uma atrás da outra. O Claude lista as tasks, você escolhe, ele faz e no fim pergunta se segue com outra. No `/exit`, o jfy registra o tempo das tasks que ficaram abertas e garante o `handoff.md` de todas as tasks trabalhadas.
- `l` **terminal livre** direto no repositório do projeto.
- `c` troca os repositórios do projeto.
- `w` abre o projeto no Journify.

### Abas

Cada task abre numa aba nova, com a cor do projeto. Abrir de novo algo que já tem aba (a mesma task, reunião, pasta ou as horas) só leva você até ela. A barra fica embaixo.

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
| 📅 reunião | contagem regressiva quando falta 1h ou menos para a próxima reunião do Google Agenda; vermelho a 5 min. **Clique** para entrar na chamada |
| ✉ 3 | emails não lidos (no Gmail, só a aba Principal). Quando chega um novo, a barra destaca remetente e assunto por 5 min e o macOS notifica. **Clique no ✉** para ler num popup: abre direto o que acabou de chegar, ou a lista com hora, remetente e assunto (número lê, `o` + número abre no Gmail, `t` marca todos como lidos, `q` volta da leitura, `0` fecha) |
| IA ▰▰▱▱ 23% | quanto você já usou do limite de 5h do Claude (e até que horas), e da semana; laranja a 50%, vermelho a 80% |
| ⏱ 3h 12min / 8h | cronômetro da jornada: liga sozinho na primeira vez que você usa o jfy no dia, fica verde e notifica ao chegar a 8h |
| 14:32 | relógio |

| Atalho | Faz |
|---|---|
| `Ctrl-b` `c` | mostra todos os comandos do jfy (menus, atalhos e linha de comando). Substitui o "nova janela" do tmux |
| `Ctrl-b` `m` | entra na chamada (Meet, Zoom, Teams) da reunião que está rolando ou da próxima. 5 min antes de cada reunião chega uma notificação |
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

Os ícones em pixel art só aparecem com a fonte **JFY Mono** no terminal (o `install.sh` instala). O Padrão usa caracteres comuns e funciona com qualquer fonte. Para mudar ou criar um ícone, edite o desenho em `fonte/icones.txt` e gere a fonte de novo (o comando está no topo de `fonte/patch.py`).

### Google: agenda e Gmail

Rode `jfy --login`. Na primeira vez ele abre no navegador o [JSON do app jfy da Souv](https://drive.google.com/file/d/12zl0qgv3LfCi5dNgVzhNtyvpgUzZOS8a/view?usp=sharing), no Drive da empresa: baixe e arraste o arquivo para o terminal. O JSON só identifica o app; cada pessoa autoriza a própria conta e o acesso fica no Chaves do Mac dela. Depois abre o login do Google no navegador. Você entra com a conta da empresa e autoriza:
- **agenda**: só leitura de eventos. Reuniões recusadas, eventos de dia inteiro e ausências ficam de fora;
- **Gmail**: `gmail.modify`: o jfy lê os emails para o popup do ✉ e marca como lidos quando você aperta `t` (todos os não lidos da Principal); não apaga e não envia. Quem fez login antes dessa mudança precisa rodar `jfy --login` uma vez para o `t` funcionar (ler continua funcionando sem isso).

O acesso fica no Chaves do macOS. O jfy olha a agenda a cada 30 s (e o ícone da barra de cima, toda vez que você abre o menu) e o Gmail a cada 30 s (um email novo aparece na barra em até ~45 s). Se a barra mostrar `✉ erro`, rode `jfy --login` de novo.

### Portas abertas (`o`)

No menu principal, `o` lista as portas abertas por programas de desenvolvimento, uma linha por processo (ou por container do Docker): o que é (Next, Vite, Node, Expo, Firebase, Python, Java, Docker, Postgres, MySQL, Redis, Mongo, Ruby), cada um com seu ícone, de que projeto é, se tem Claude aberto naquele repositório (e em que aba do jfy) e se foi o Claude que subiu o servidor. O número encerra (pede para sair e, se em 3 s não saiu, força; container é parado com `docker stop`). Fica de fora o que não é de desenvolvimento (Figma, CleanMyMac, o próprio macOS). `jfy --portas` abre direto. Banco instalado pelo Homebrew (`brew services`) volta sozinho depois de encerrado: pare com `brew services stop <nome>`.

### Ícone na barra de cima do Mac

Com o extra do SwiftBar, o jfy ganha um ícone (a chama) ao lado do relógio do Mac, que abre junto com o Mac. A até 1h de uma reunião, a chama vira o ícone de reunião do tema, que esquenta (laranja a 15 min, vermelho a 5): o nome e a contagem ficam na primeira linha do menu, com "Entrar na chamada". A 5 min chega a notificação, mesmo com o jfy fechado; clicar nela entra na chamada. O ícone nunca leva texto: em Mac com notch, o que fica largo some atrás dele. O menu tem: abrir o jfy (traz o terminal dele, ou abre um com o jfy), abrir o Journify, pausar/retomar a jornada, as próximas reuniões (clique entra na chamada), as tasks no foco (clique abre no Journify), as portas abertas com "Encerrar" em cada uma e os emails não lidos. Atualiza a cada minuto e quando você abre o menu.

### Notificação das 7h

De segunda a sexta, às 7h, chega uma notificação do macOS com as reuniões do dia e as tasks no foco. Se o Mac estiver dormindo, ela chega quando ele acordar. Se a notificação não aparecer, libere as notificações do **Editor de Scripts** em Ajustes do Sistema > Notificações.

### Aviso do Claude

Quando um Claude responde ou pede permissão, chega uma notificação do macOS com o nome da aba (ou da pasta). **Clicar nela traz o terminal já na aba daquele Claude.** O clique também funciona na notificação de email (abre o leitor) e na de reunião (abre a chamada). Isso usa o `terminal-notifier`, que o `install.sh` (se você aceitar o aviso) ou o passo **Notificações** dos primeiros passos instala; libere **terminal-notifier** em Ajustes do Sistema > Notificações. Sem ele, ou sem a permissão, a notificação sai pelo Editor de Scripts e o clique abre o Editor de Scripts em vez do terminal. Vale para todo Claude Code, dentro e fora do jfy. Ela não aparece se você já está olhando: terminal na frente e, dentro do jfy, a aba daquele Claude aberta. O `install.sh` liga isso com dois hooks (`Stop` e `Notification`) no `~/.claude/settings.json`.

Para a aba também ficar vermelha, no Claude rode `/config` e ponha **Notifications** em **Terminal Bell**.

### Horas

O jfy anota cada trabalho do dia em `~/.jfy/horas/AAAA-MM-DD.jsonl`: tasks (no `/exit` ou no `--fim` da sessão), terminal livre e preparação de reunião. As reuniões vêm da agenda, com o projeto e o contexto que você deu no `r` (sem isso, o projeto sai do apelido no título, marcado "projeto pelo título"). Sessões do Claude abertas fora do jfy não entram.

A tabela do `h` mostra só o que vai para o Journify: uma linha por lançamento, com projeto, categoria, horas e descrição, e o total no topo. O medido e a regra ficam no rodapé.

| Na tabela | Faz |
|---|---|
| número | edita a linha: `p` projeto, `c` categoria, `h` horas, `d` descrição, `x` remove. Vale só para aquele dia. Numa reunião, projeto e descrição ficam iguais aos do `r` |
| número de uma linha removida | restaura |
| `-` / `+` | dia anterior / próximo |
| `d` | vai para outra data (`20/11`, `-1` = ontem) |
| `l` | o Claude lança pelo Chrome |

Hora mudada à mão (`h`) substitui a da regra só naquela linha, e as outras não mudam. A linha fica marcada como "horas à mão" e, com `h` e Enter vazio, volta para a regra.

Por padrão o jfy lança o medido, arredondado para múltiplos de 5 min. Se o seu gestor combinou um fator para cobrir o que o cronômetro não vê (entender a task, ler, conversar), ponha em `~/.jfy/config.json`:

```json
"horas": {"fator": 1.2}
```

O fator multiplica só as linhas de trabalho; reunião fica com a duração da agenda. Ele aparece no rodapé da tabela, junto do medido. Sessões do Claude abertas fora do jfy não entram no log.

### Ao encerrar uma task (`/exit`)

Ao abrir, a task já tinha ido para `em_progresso`. No `/exit`, o jfy pergunta:
1. pronta, vai para **em teste**;
2. pronta, vai para **em revisão**;
3. pronta, vai para **fechado**: pede o link do vídeo do teste ou, sem vídeo, o motivo (o Journify exige um dos dois para fechar);
4. não pronta: só comenta o tempo (Enter);
5. não registrar nada.

De 1 a 3, comenta o tempo gasto e muda o status. Na sessão de várias tasks, o Claude pergunta o mesmo e roda `jfy --fim <id> --status em_teste|em_revisao|fechado`.

O tempo vem do relógio (da abertura até o `/exit`, sem as reuniões da agenda que caíram no meio) e você pode corrigir (`80`, `1h20`, `1:20`). Ele vai como comentário porque o MCP do Journify não tem campo de tempo, e também para o log de [horas](#horas).

Depois o Claude atualiza o `handoff.md` na raiz do repositório (ou cria do zero, se não existir) e a memória do projeto, em segundo plano: a aba já pode ser fechada. O `handoff.md` fica como alteração não commitada: commite junto com a task. Se a task rodou num worktree, ele fica em `~/.jfy/worktrees/` com o `handoff.md`: depois do merge, apague com `git worktree remove <pasta>`.

## Onde ficam as coisas

| O quê | Onde |
|---|---|
| projetos e repositórios configurados | `~/.jfy/config.json` |
| domínio do Journify que você usa (padrão `https://journify.souv.tech`) | `"journify"` no `~/.jfy/config.json` |
| memória de cada projeto (máx. 40 linhas, o Claude lê antes de tudo) | `~/.jfy/memoria/<projectId>.md` |
| worktrees de tasks paralelas | `~/.jfy/worktrees/` |
| cronômetro da jornada de hoje | `~/.jfy/dia.json` |
| horas medidas por dia e a regra do lançamento | `~/.jfy/horas/` e `"horas"` no `~/.jfy/config.json` |
| client OAuth do Google e reuniões de hoje | `~/.jfy/config.json` e `~/.jfy/agenda.json` |
| projeto e contexto de cada reunião (base das horas) | `~/.jfy/reunioes.json` |
| ajustes que você fez na tabela de horas de um dia | `~/.jfy/horas/AAAA-MM-DD.ajustes.json` |
| notificação das 7h | `~/Library/LaunchAgents/jfy.dia.plist` |
| ícone na barra de cima | plugin em `~/.jfy/swiftbar/jfy.1m.sh` (ou na pasta de plugins do seu SwiftBar); abre com o Mac por `~/Library/LaunchAgents/jfy.swiftbar.plist` |
| acesso ao Google | Chaves do macOS, item `jfy-google` |

**Duas tasks no mesmo repositório ao mesmo tempo**: a segunda roda num `git worktree` separado, com branch própria, para os pipelines não mexerem nos mesmos arquivos. O worktree recebe uma cópia dos `.env`, mas não as dependências (`node_modules`, venv); o Claude instala se precisar.

## Atualizar

```bash
cd ~/jfy && git pull
```

Para atualizar também a pipeline, rode `~/jfy/install.sh` de novo: ele dá `git pull` na pipeline oficial e liga arquivos novos.

## Problemas comuns

- **"MCP 'journify' não configurado"** ou token recusado: rode `jfy --comecar` e cole um token novo.
- **O `/pipeline` para dizendo que a branch está errada**: ele só roda em `feature/`, `bugfix/`, `hotfix/` ou `release/`. Escolha o tipo quando o jfy oferecer criar a branch.
- **O `/pipeline` diz que a task não é de código**: use a opção `2` (conversar com o Claude).
- **Um projeto não aparece no menu**: o menu mostra os projetos configurados e os que têm tasks abertas atribuídas a você. Um projeto novo, sem task sua, só aparece depois de configurado (ou quando chegar uma task).
- **Ícones do tema não aparecem (espaço vazio ou quadradinho)**: o terminal não está com a fonte JFY Mono, ou não foi reiniciado depois de instalá-la. Escolha "JFY Mono" e feche o terminal com ⌘Q. Depois de um `git pull` que trouxe ícones novos, rode o `./install.sh` (ele copia a fonte nova) e reinicie o terminal.
- **O ícone da barra de cima não aparece**: abra o jfy (ele reabre o SwiftBar) ou rode `open /Applications/SwiftBar.app`. Em Mac com notch, o macOS esconde atrás do notch os ícones que não cabem (o mais novo é o primeiro a sumir): segure ⌘ e arraste a chama para perto do relógio, ou tire da barra um ícone que você não usa.

## Desinstalar

```bash
rm "$(command -v jfy)"
find ~/.claude/commands ~/.claude/agents ~/.claude/hooks -type l -lname "*pipeline-Claude/*" -delete
launchctl bootout gui/$(id -u)/jfy.dia; rm ~/Library/LaunchAgents/jfy.dia.plist
launchctl bootout gui/$(id -u)/jfy.swiftbar; rm ~/Library/LaunchAgents/jfy.swiftbar.plist
brew uninstall --cask swiftbar  # se você só usava ele para o jfy
security delete-generic-password -s jfy-google
rm -rf ~/.jfy ~/jfy
# e tire o "tee ~/.jfy/claude-status.json | " do statusLine e os hooks "jfy --avisar" em ~/.claude/settings.json
```
