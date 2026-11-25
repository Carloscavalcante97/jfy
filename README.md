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
  - **notificação das 7h**: um LaunchAgent;
  - **app do jfy para o Mac**: monta o `jfy.app` em `/Applications` (precisa do Xcode). Veja [App do Mac](#app-do-mac).

### 2. Rodar

```bash
jfy
```

Na primeira vez, antes do menu, o jfy te guia por **primeiros passos**, um de cada vez. Ele confere cada um de verdade e só pergunta o que falta:

1. **Journify**: abre as Configurações do Journify; em *Conectar meu Claude*, clique em *Gerar token* e cole o token no jfy (ele não aparece na tela). O jfy configura o MCP `journify` no seu Claude Code.
2. **Notificações**: manda uma notificação de teste. Se o macOS bloquear, abre Ajustes do Sistema > Notificações para você ligar o **terminal-notifier** e testa de novo.
3. **Agenda e Gmail**: login do Google (só leitura). O jfy abre o JSON do app no Drive da empresa: baixe e arraste o arquivo para o terminal.
4. **Seus projetos**: para cada projeto com task sua, escolha a pasta do repositório.
5. **Fonte**: o jfy instala a fonte JFY Mono, se faltar, e põe ela no terminal (os ícones do jfy precisam dela). O tema se escolhe no [app](#app-do-mac).

`Enter` faz o passo, `p` pula e `0` deixa para depois. Para voltar a eles quando quiser: `jfy --comecar`.

## Como usar

Nos menus, a tecla certa já basta, sem Enter: o número abre o item (com 10 ou mais opções, o `1` espera um instante pelo segundo dígito), e letras (`l`, `o`, `j`, `s`, `p`, `w`...) e o `0` (volta) valem na hora, sem Enter. No menu principal e na tela do projeto, Enter atualiza as tasks (as duas guardam a lista por 1 min, para voltar de uma task sem esperar o Journify). Toda tela termina com a mesma linha de ações: a tecla em destaque e o que ela faz, e o `0` no fim.

**Menu principal**: três seções. **Foco**: tasks de todos os projetos com prazo vencido ou nos próximos 7 dias e as de prioridade crítica, da mais urgente para a menos; o número abre a task direto. **Projetos**: os que têm tasks suas, com a contagem. **Sem task**: os configurados sem task aberta (manutenção: terminal livre ou sessão quando surgir algo). O repositório de cada projeto aparece no `c` da tela do projeto.
- `j` abre o Journify no navegador.
- `jfy --hoje` imprime as reuniões de hoje e o foco, sem abrir o menu.
- Na primeira vez em cada projeto, o jfy pede a pasta do repositório (navegador de pastas: número entra, `..` sobe, `s` escolhe, ou cole o caminho) e um nome. Projeto com mais de um repositório (front e back, por exemplo): responda `s` em "Mais um repositório" e escolha o próximo. Na hora da task, o jfy pergunta quais ela usa (número = só esse, Enter = todos); o Claude abre no primeiro e enxerga os outros, e a branch da task é criada em cada um. Projeto sem repositório (só estudo ou teste): `n` no navegador de pastas e dê um nome, que aparece no lugar do id; o Claude abre numa pasta só dele, `~/.jfy/sem-repo/<id>`, onde fica o `handoff.md`.
- `l` abre um **terminal livre**: Claude com `--dangerously-skip-permissions` numa pasta que você escolhe, sem task.
- Reuniões, horas e tema ficam no [app do Mac](#app-do-mac) (abas Reuniões, Horas e Temas). O terminal fica com as tasks, as sessões do Claude e as portas.

**Tela do projeto**: suas tasks em seções, na ordem do que pede ação sua primeiro: **Urgente** (prazo vencido, nos próximos 7 dias ou crítica; mostra o status no fim da linha), **Em andamento**, **A fazer**, **Esperando alguém** (revisão, teste ou validação) e **Bloqueadas**. Seção vazia não aparece.
- Número abre a task. A tela cabe no terminal, nesta ordem: projeto e título; status, prioridade, pontos e prazo (avisa se passar de 8 pontos, o teto do fluxo); **O que fazer** (o começo da descrição, já limpa: sem markdown cru, e cada imagem vira `▣ imagem a3`, o número do anexo); anexos (imagens agrupadas, documentos pelo nome); o último comentário; e as ações:
  - `1` **implementar (/pipeline)**: para task de código (testes, implementação, revisão, commit e PR com a sua aprovação). Se você não estiver numa branch gitflow, o jfy cria `feature/`, `bugfix/` (a partir da `develop` atualizada) ou `hotfix/` (a partir da `main`) com o título da task.
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

A aba Temas do [app](#app-do-mac) escolhe o tema: **Padrão**, **Dracula**, **Monokai**, **Cyberpunk**, **Élfico** (dourado e prata sobre verde-floresta), **Anão** (ouro e forja sobre bronze), **Mordor** (fogo e cinzas sobre preto), **GTA** (neon de fim de tarde e verde-dinheiro sobre roxo) ou **Aço** (azul-metálico e prata sobre azul-marinho). Muda as cores do menu e da barra na hora, sem reiniciar, e cada tema tem seus ícones em pixel art e seu desenho na barra de uso da IA. Quase todos têm também alguém andando e empurrando a barra: vampiro (Dracula), corredor com rastro de velocidade (Cyberpunk), elfo arqueiro (Élfico), anão de machado (Anão), viatura com giroflex (GTA), lorde de armadura (Mordor) e robô de quatro patas (Aço). Para isso a barra da direita é um `jfy --relogio` que fica rodando e manda uma linha por segundo; quando o `jfy` muda, ele sai e o tmux sobe o novo em até 15s. Cada pessoa tem o seu, salvo em `~/.jfy/config.json`.

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
- **agenda**: lê, cria e edita eventos (`calendar.events`), pela aba Agenda do app. Reuniões recusadas, eventos de dia inteiro e ausências ficam de fora;
- **Gmail**: `gmail.modify`: o jfy lê os emails para o popup do ✉ e marca como lidos quando você aperta `t` (todos os não lidos da Principal); não apaga, e só envia quando você aperta Enviar na aba Emails do app. Quem fez login antes dessa mudança precisa rodar `jfy --login` uma vez para o `t` funcionar (ler continua funcionando sem isso).

O acesso fica no Chaves do macOS. O jfy olha a agenda a cada 30 s (e o ícone da barra de cima, toda vez que você abre o menu) e o Gmail a cada 30 s (um email novo aparece na barra em até ~45 s). Se a barra mostrar `✉ erro`, rode `jfy --login` de novo.

### Portas abertas (`o`)

No menu principal, `o` lista as portas abertas por programas de desenvolvimento, uma linha por processo (ou por container do Docker): o que é (Next, Vite, Node, Expo, Firebase, Python, Java, Docker, Postgres, MySQL, Redis, Mongo, Ruby), cada um com seu ícone, de que projeto é, se tem Claude aberto naquele repositório (e em que aba do jfy) e se foi o Claude que subiu o servidor. O número encerra (pede para sair e, se em 3 s não saiu, força; container é parado com `docker stop`). Fica de fora o que não é de desenvolvimento (Figma, CleanMyMac, o próprio macOS). `jfy --portas` abre direto. Banco instalado pelo Homebrew (`brew services`) volta sozinho depois de encerrado: pare com `brew services stop <nome>`.

### Ícone na barra de cima do Mac

Com o extra do SwiftBar, o jfy ganha um ícone (a chama) ao lado do relógio do Mac, que abre junto com o Mac. A até 1h de uma reunião, a chama vira o ícone de reunião do tema, que esquenta (laranja a 15 min, vermelho a 5): o nome e a contagem ficam na primeira linha do menu, com "Entrar na chamada". A 5 min chega a notificação, mesmo com o jfy fechado; clicar nela entra na chamada. O ícone nunca leva texto: em Mac com notch, o que fica largo some atrás dele. O menu tem: o uso do Claude (5 h e semana, com quando renova), abrir o jfy (traz o terminal dele, ou abre um com o jfy), abrir o Journify, pausar/retomar a jornada, as próximas reuniões (clique entra na chamada), as tasks no foco (clique abre no Journify), as portas abertas com "Encerrar" em cada uma e os emails não lidos. Atualiza a cada minuto e quando você abre o menu.

### App do Mac

O `jfy.app` é o jfy numa janela própria, com ícone no Dock e no Spotlight. Fechar a janela não fecha o app: o jfy segue rodando em segundo plano (o número de notificações novas aparece no ícone do Dock) e volta igual clicando no ícone ou em Janela > jfy. ⌘Q sai de verdade. No topo da janela, em qualquer aba, fica o uso dos limites do Claude (5 h e semana, com quando renova): o mesmo da barra do jfy no terminal e do ícone na barra de cima, para não precisar estar numa sessão do Claude para ver. Em tela cheia, a barra lateral mostra a imagem da mesa desfocada, como fora dela. Na barra lateral (⌘1 a ⌘9 para as nove primeiras). O jfy no terminal continua igual; o app é a interface de gestão em cima dele:

- **jfy**: o menu de sempre, num terminal embutido. Embaixo de "jfy", na barra lateral, aparecem as abas abertas (o menu, cada task, revisão de PR…); o clique leva o terminal até ela, e a bolinha vermelha marca a aba em que o Claude pediu atenção. O terminal já vem com a JFY Mono (não precisa configurar fonte). As tasks continuam no tmux: fechar o app não encerra nenhuma, e abrir de novo volta para o mesmo lugar. Dá para usar o app e um terminal ao mesmo tempo. Com o app aberto, "Abrir o jfy" na barra de cima e o clique nas notificações trazem o app.
- **Projetos**: a estrela favorita até 4 projetos, que aparecem na barra lateral embaixo de Projetos (o clique abre o projeto). Os projetos (e o Foco: prazo perto ou crítica), as tasks nas mesmas seções da tela do projeto (só as suas, ou todas do projeto com as 30 encerradas mais recentes) e a task inteira: a descrição formatada com as imagens, os anexos (clique abre pelo link; nada é baixado), os comentários e um campo para comentar. Status, prioridade e prazo mudam por clique; mover para `fechado` ou `finalizado validação` pede o link do vídeo do teste ou o motivo, como o Journify exige. "Implementar (/pipeline)" e "Conversar com o Claude" abrem a mesma aba do `1` e do `2` e levam você ao terminal.
- **GitHub**: pelo `gh` e a conta ativa dele (um menu troca a conta ou conecta outra). À esquerda: "Pedem sua revisão", "Seus PRs" e cada repositório dos projetos, com a branch, o número de PRs abertos e o que falta subir (↑), baixar (↓) ou commitar (●). Escolhido um repositório, o topo traz a branch (o clique troca ou cria outra), um botão de sincronizar que muda com o estado, como no GitHub Desktop (**Pull ↓** quando tem o que baixar, **Push ↑** quando tem o que subir, **Publicar branch** quando ela ainda não está no origin, **Fetch** quando está em dia; as outras no menu ao lado), e **Abrir PR**: o Claude abre o PR numa aba do jfy pelas regras do agente pr-creator (template, tasks pelas linhas `Journify:` dos commits, plano de testes, link do PR nas tasks), pedindo a sua aprovação antes de criar e de comentar. Embaixo, as abas:
  - **Alterações**, como no GitHub Desktop: marque os arquivos (já vem desmarcado o que o committer deixa de fora: `.env`, `.DS_Store`, chaves, `node_modules`, saída de build), veja o diff de cada um à direita e, embaixo da lista, escreva o **título** (com o contador do limite de 72 do committer) e a descrição à mão, ou use **Gerar título e descrição com o committer** (as regras do agente committer, lidas do `committer.md` na hora, no modelo dele: formato, prefixo `[Nome]` na conta compartilhada, linha `Journify:` das tasks da branch). O commit é do jfy, com as travas do committer: nada em `main`, `master` ou `develop` nem fora do gitflow, nada no meio de merge ou rebase, varredura de segredos antes do `git add`, só os arquivos marcados e nunca `Co-Authored-By`.
  - **Histórico**: os commits da branch; o clique mostra a mensagem inteira e o diff.
  - **PRs**: os abertos do repositório, com descrição, checks, commits, revisões e comentários; merge (pelos métodos que o repo aceita), aprovar, comentar e fechar sem merge, com confirmação. **Revisar com o Claude** abre uma aba com o `/code-review` do PR (ele não comenta no GitHub sem você pedir). O PR mostra as tasks do Journify ligadas a ele, e o clique abre a task na aba Projetos; a task mostra os PRs citados nela, e o clique abre o PR aqui.
  - **Branches e worktrees**: nova branch no padrão gitflow (feature e bugfix saem da `develop` atualizada, ou da `developer` onde ela tem esse nome; hotfix e release da `main`), trocar, excluir só a que já entrou na base (`git branch -d`). Os worktrees que o jfy criou para tasks em paralelo: abrir no Finder ou num terminal livre, remover (só sem arquivo mexido) e limpar os órfãos. Com uma task do jfy rodando no repositório, trocar e criar branch ficam bloqueados.
- **Horas**: a tabela do que vai para o [minhas-horas](https://journify.souv.tech/minhas-horas) (veja [Horas](#horas)): projeto e categoria por menu (ou um nome livre), horas e descrição editáveis (salva com Enter, ao clicar fora ou no ✓; Esc desfaz; horas como 1:20, 1h20, 80 ou 1,5; vazio volta para a regra), remover e restaurar, e a troca de dia. "Lançar no Journify…" abre o Claude numa aba do jfy para lançar pelo Chrome (esse passo usa tokens).
- **Agenda**: a sua agenda do Google em **dia, semana e mês** (◀ Hoje ▶), com a linha de agora. Clicar num horário vazio cria um evento ali; **Novo evento** também. O evento abre com horário, local, **Entrar na chamada**, convidados (com a resposta de cada um) e descrição; **Editar** e **Apagar** aparecem quando você pode editar (em recorrente, vale só para aquela ocorrência). Ao criar ou editar: título, dia inteiro, início e fim, local, descrição, convidados, a chamada do Google Meet e se manda o convite (ou a atualização) por email. Cada reunião tem também o **para as horas**: o projeto (menu, ou um nome livre) e o contexto que vão para a aba Horas, e **Preparar com o Claude**. Criar e editar pedem o escopo `calendar.events` no app do Google: quem fez login antes precisa rodar `jfy --login` uma vez.
- **Emails**: os não lidos da caixa Principal, com o total no selo da barra lateral (o mesmo número do ✉ da barra do tmux, que sobe quando chega um). Ler não marca como lido; dá para marcar como lido ou não lido, marcar todos e abrir no Gmail na sua conta. **Responder**: escreva a resposta, ou peça ao Claude para **gerar** (do email e de um contexto seu, opcional), **corrigir** (só os erros do seu texto) ou **melhorar** (o seu texto como base); depois salve como rascunho no Gmail ou envie, na mesma conversa (enviar pede confirmação). O Claude só escreve no campo, sem ferramentas, e não segue instruções que venham dentro do email; gerar, corrigir e melhorar usam tokens.
- **Portas**: o que está rodando (as portas de desenvolvimento do `o`), com o projeto, se foi o Claude que subiu, "Abrir" no navegador, "Encerrar" e "Encerrar todas" (pede para sair; se em 3 s não saiu, força; container do Docker com `docker stop`). Atualiza sozinha e o número de portas abertas fica no selo.
- **Uso da IA**: quanto o Claude Code gastou neste Mac, lido das conversas em `~/.claude/projects` (hoje, 7 dias, 30 dias ou tudo). Mostra o custo em US$ pelo preço da API (na assinatura é o valor equivalente, não a conta), os tokens, as sessões e os limites de 5 h e semanal; o custo por dia de cada projeto (passe o mouse num dia para ver o detalhe); para onde foi o custo (leitura e escrita de cache, saída); e os rankings por projeto, task do Journify (clique abre a task), modelo, ferramenta e sessão, com o maior contexto de cada uma. `jfy --uso [dias]` dá o mesmo em JSON.
- **Chat**: o chat do time do Journify (as conversas entre colaboradores), com a lista de conversas, as mensagens e o envio; busca mensagens novas a cada 5 s com a tela aberta. Ainda não está ligado: o MCP do Journify ainda não tem o chat. Quando tiver, é trocar o corpo das três funções `chat_conversas`, `chat_mensagens` e `chat_enviar` do `jfy` por chamadas ao MCP, devolvendo o formato descrito em cada uma; o app não muda. `jfy --chat [conversa [texto]]` dá o mesmo em JSON.

- **Notificações**: o histórico do que o jfy avisou, por dia, com o número de novas na barra lateral e no ícone do Dock. Com o app instalado, **o clique na notificação do macOS abre o app já na aba certa**: email novo (o email, em Emails), PR pedindo a sua revisão (o PR, em GitHub), evento adicionado, remarcado ou cancelado por outra pessoa (o evento, em Agenda), Claude que precisa de você ou respondeu (a aba dele, no terminal), horas registradas no Journify ou erro ao registrar, fim do lançamento de horas, jornada fechada e o resumo das 7h. Reunião em 5 min continua entrando direto na chamada. PRs e agenda são olhados a cada 2 min, em segundo plano (`jfy --vigiar`, que o relógio da barra dispara); na primeira vez só guarda o que já existia, sem avisar. O clique numa linha da aba faz o mesmo. Fica em `~/.jfy/notificacoes.jsonl`; "Limpar" apaga.
- **Temas**: as cores e os ícones de cada tema (veja [Temas](#temas)); um clique troca.

Precisa do macOS 15 ou mais novo. Para montar ou atualizar depois de um `git pull`: `./app/build.sh` (o `./install.sh` já faz isso se o app estiver instalado). A assinatura é local, vale para este Mac.

### Notificação das 7h

De segunda a sexta, às 7h, chega uma notificação do macOS com as reuniões do dia e as tasks no foco. Se o Mac estiver dormindo, ela chega quando ele acordar. Se a notificação não aparecer, libere as notificações do **Editor de Scripts** em Ajustes do Sistema > Notificações.

### Aviso do Claude

Quando um Claude responde ou pede permissão, chega uma notificação do macOS com o nome da aba (ou da pasta). **Clicar nela traz o terminal já na aba daquele Claude.** O clique também funciona na notificação de email (abre o leitor) e na de reunião (abre a chamada). Isso usa o `terminal-notifier`, que o `install.sh` (se você aceitar o aviso) ou o passo **Notificações** dos primeiros passos instala; libere **terminal-notifier** em Ajustes do Sistema > Notificações. Sem ele, ou sem a permissão, a notificação sai pelo Editor de Scripts e o clique abre o Editor de Scripts em vez do terminal. Vale para todo Claude Code, dentro e fora do jfy. Ela não aparece se você já está olhando: terminal na frente e, dentro do jfy, a aba daquele Claude aberta. O `install.sh` liga isso com dois hooks (`Stop` e `Notification`) no `~/.claude/settings.json`.

Para a aba também ficar vermelha, no Claude rode `/config` e ponha **Notifications** em **Terminal Bell**.

### Horas

O jfy anota cada trabalho do dia em `~/.jfy/horas/AAAA-MM-DD.jsonl`: tasks (no `/exit` ou no `--fim` da sessão), terminal livre e preparação de reunião. As reuniões vêm da agenda, com o projeto e o contexto que você deu na aba Reuniões ou Horas do app (sem isso, o projeto sai do apelido no título, marcado "projeto pelo título"). Sessões do Claude abertas fora do jfy não entram.

A aba Horas do app mostra só o que vai para o Journify: uma linha por lançamento, com projeto, categoria, horas e descrição, e o total no topo; o medido e a regra ficam ao lado. Cada mudança vale só para aquele dia; numa reunião, projeto e descrição vão para o mesmo registro da aba Reuniões.

A coluna **Trabalhado** é o tempo da linha: o medido, ou a sua correção quando o medido está errado (uma sessão esquecida aberta, por exemplo). A correção entra no lugar do medido e a regra vale em cima dela, como nas outras linhas; a coluna **Lança** mostra o resultado. A linha corrigida fica marcada com a mão e, apagando o valor e salvando, volta ao medido. O botão de calendário da linha a **leva para outro dia** (hoje ou antes): o trabalhado vai junto e, se lá já existe a mesma linha, os dois somam. O jfy guarda os arquivos dos dois dias antes e confere a soma do trabalhado depois; se não fechar, volta tudo como estava. Reunião fica no dia em que aconteceu. **Lançar no Journify** deixa o dia igual à tabela: lançamento que já existe com outro valor é editado (não duplicado); um que não corresponde a nenhuma linha, o Claude mostra e pergunta antes de apagar.

Por padrão o jfy lança o medido, arredondado para múltiplos de 5 min. Se o seu gestor combinou um fator para cobrir o que o cronômetro não vê (entender a task, ler, conversar), ponha em `~/.jfy/config.json`:

```json
"horas": {"fator": 1.2}
```

O fator multiplica só as linhas de trabalho; reunião fica com a duração da agenda. Ele aparece no topo da tabela, junto do medido. Sessões do Claude abertas fora do jfy não entram no log.

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
| histórico de notificações | `~/.jfy/notificacoes.jsonl` (a aba Notificações do app) |
| app do Mac | `/Applications/jfy.app`, montado por `app/build.sh` a partir de `app/` |
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
rm -rf /Applications/jfy.app
security delete-generic-password -s jfy-google
rm -rf ~/.jfy ~/jfy
# e tire o "tee ~/.jfy/claude-status.json | " do statusLine e os hooks "jfy --avisar" em ~/.claude/settings.json
```
