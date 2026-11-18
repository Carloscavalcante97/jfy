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
- liga o `/pipeline` e os agentes dele (planner, builder, verifier, e2e-tester, committer, pr-creator) no seu `~/.claude`. Se você já tem um arquivo com o mesmo nome e conteúdo diferente, ele mantém o seu e avisa;
- confere se o MCP do Journify está configurado e roda um autoteste.

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

Tudo é por número: digite e dê Enter. `0` sempre volta.

**Menu principal**: os projetos em que você tem tasks abertas.
- Na primeira vez em cada projeto, o jfy pede a pasta do repositório (navegador de pastas: número entra, `..` sobe, `s` escolhe, ou cole o caminho) e um nome.
- `l` abre um **terminal livre**: Claude com `--dangerously-skip-permissions` numa pasta que você escolhe, sem task.

**Tela do projeto**: suas tasks, ordenadas por status.
- Número abre a task (descrição e comentários) com duas opções:
  - `1` **/pipeline**: para task de código (testes, implementação, revisão, commit e PR com a sua aprovação). O jfy oferece criar a branch `feature/<titulo>` se você não estiver numa branch gitflow.
  - `2` **Claude livre**: para estudo, análise, documento, preparação de reunião. Nada vai para o Journify sem você aprovar.
- `s` **sessão**: um chat só para várias tasks, uma atrás da outra. O Claude lista as tasks, você escolhe, ele faz e no fim pergunta se segue com outra.
- `l` **terminal livre** direto no repositório do projeto.
- `c` troca o repositório do projeto.

### Abas

Cada task abre numa aba nova, com a cor do projeto. A barra fica embaixo.

| Para | Faça |
|---|---|
| voltar ao menu | clique em `0 menu` ou `Ctrl-b` e depois `0` |
| ir para outra aba | clique nela, ou `Ctrl-b` e o número |
| ver todas com prévia | `Ctrl-b` e depois `w` |
| encerrar a task | `/exit` no Claude |
| sair do jfy com tasks rodando | `0` no menu principal; `jfy` volta para elas |

Para a aba ficar vermelha quando o Claude estiver esperando você, no Claude rode `/config` e ponha **Notifications** em **Terminal Bell**.

### Ao encerrar uma task (`/exit`)

O jfy pergunta:
1. pronta: comenta o tempo gasto na task e move para `finalizado_validacao`;
2. não pronta: só comenta o tempo;
3. não registrar nada.

O tempo vem do relógio (da abertura até o `/exit`) e você pode corrigir. Ele vai como comentário porque o MCP do Journify não tem campo de tempo.

Depois o Claude atualiza o `handoff.md` na raiz do repositório (ou cria do zero, se não existir) e a memória do projeto. O `handoff.md` fica como alteração não commitada: commite junto com a task.

## Onde ficam as coisas

| O quê | Onde |
|---|---|
| projetos e repositórios configurados | `~/.jfy/config.json` |
| memória de cada projeto (máx. 40 linhas, o Claude lê antes de tudo) | `~/.jfy/memoria/<projectId>.md` |
| worktrees de tasks paralelas | `~/.jfy/worktrees/` |

**Duas tasks no mesmo repositório ao mesmo tempo**: a segunda roda num `git worktree` separado, com branch própria, para os pipelines não mexerem nos mesmos arquivos. O worktree recebe uma cópia dos `.env`, mas não as dependências (`node_modules`, venv); o Claude instala se precisar.

## Atualizar

```bash
cd ~/jfy && git pull
```

O `/pipeline` e os agentes são links para o repositório, então atualizam junto. Rode o `install.sh` de novo se algum arquivo novo entrar em `claude/`.

## Problemas comuns

- **"MCP 'journify' não configurado"**: faça o passo 2.
- **O `/pipeline` para dizendo que a branch está errada**: ele só roda em `feature/`, `bugfix/`, `hotfix/` ou `release/`. Responda `s` quando o jfy oferecer a branch.
- **O `/pipeline` diz que a task não é de código**: use a opção `2` (Claude livre).
- **Um projeto não aparece no menu**: o menu mostra só projetos com tasks abertas atribuídas a você.

## Desinstalar

```bash
rm "$(command -v jfy)"
find ~/.claude/commands ~/.claude/agents -type l -lname "*jfy/claude/*" -delete
rm -rf ~/.jfy ~/jfy
```
