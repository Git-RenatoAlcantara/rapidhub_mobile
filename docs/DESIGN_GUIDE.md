# RapidHub Mobile — Guia de Design para IA

> Documento de referência para uma IA de design (ou designer) recriar / redesenhar
> o aplicativo **RapidHub Mobile**. Descreve **todas as telas, rotas, fluxos de
> navegação, componentes, estados e funções** existentes no código atual
> (Flutter / Material, tema escuro).
>
> Objetivo: dar contexto suficiente para gerar telas (Figma, mockups, protótipos)
> fiéis ao comportamento real do app, **sem precisar ler o código-fonte**.

---

## 1. Visão geral do produto

RapidHub Mobile é um app de **atendimento omnichannel via WhatsApp** (estilo
"inbox de tickets"). O atendente humano:

1. Faz login.
2. Escolhe a organização (empresa) em que vai trabalhar.
3. Vê a lista de conversas/tickets, separadas por estado (IA, Ativos, Departamento, Arquivados).
4. Abre uma conversa, lê o histórico, assume o atendimento (quando está com a IA),
   troca mensagens (texto, áudio, imagem, vídeo, documentos), envia templates,
   agenda follow-ups e arquiva o ticket.

Backend: API REST + streaming em tempo real (SSE) em `https://rapidhub.com.br`.

Plataforma de UI: **Flutter / Material**, **tema escuro fixo** (não há modo claro).

---

## 2. Identidade visual / Design tokens

O app NÃO usa um arquivo de tema central — as cores são aplicadas inline. Abaixo a
paleta consolidada extraída de toda a base de código. **Use estes tokens como
sistema de design oficial.**

### 2.1 Cores de fundo (superfícies)

| Token | Hex | Uso |
|---|---|---|
| `bg/base` | `#0D1117` | Fundo principal de todas as telas (scaffold), fundo dos inputs de texto |
| `surface/1` | `#161B22` | AppBar, cards, barras de seção, sheets de login |
| `surface/2` | `#1E2733` | Bolha de mensagem recebida, chips, botões inativos de aba, cards de follow-up, menu popup |
| `surface/3` | `#11161E` / `#111B26` | Barra de badges no topo do chat; fundo interno dos badges |
| `surface/sheet` | `#0F1722` / `#161B22` | Fundo dos bottom sheets (filtros / templates / follow-up) |

### 2.2 Cores de marca / ação

| Token | Hex / Material | Uso |
|---|---|---|
| `primary` | `Colors.blue` (`#2196F3`) | Botões principais, abas ativas, avatares, bolha de mensagem enviada (`Colors.blue[700]`) |
| `primary/accent` | `Colors.blueAccent` | Bordas de aba ativa, badge de contagem de filtros |
| `danger` | `Colors.redAccent` | Erros, logout, cancelar, gravando, falha de envio |
| `success` | `Colors.green` / `Colors.greenAccent` | Sucesso, contador de não lidas, "Retomar" |
| `warning` | `Colors.orange` / `#F59E0B` | Avisos, janela Meta ativa, "Pausar" |

### 2.3 Cores de texto

| Token | Valor | Uso |
|---|---|---|
| Texto primário | `Colors.white` | Títulos, nome do contato, mensagem própria |
| Texto secundário | `Colors.white70` | Corpo de mensagem, labels |
| Texto terciário | `Colors.white54` / `white38` | Timestamps, hints, placeholders |
| Texto desativado/cinza | `Colors.grey` | Subtítulos, estados vazios |

### 2.4 Cores de acento dos badges (status / metadados)

| Significado | Borda / Ícone | Texto |
|---|---|---|
| Conexão (telefone) | `Colors.tealAccent` | `tealAccent` |
| Atendente (pessoa) | `#3B82F6` | `#93C5FD` |
| Departamento | `#FDE68A` | — |
| Tag de contato | `#A78BFA` | `#D8B4FE` |
| Janela Meta ativa | `#F59E0B` | `#FCD34D` |
| Janela Meta expirada | `#EF4444` | `#FCA5A5` |

### 2.5 Forma / Raio / Espaçamento

- **Raio de borda**: campos de texto `12`; bolhas de mensagem `12` (canto "rabo" = `0`);
  chips/badges/pílulas `999` (totalmente arredondado); botões `10`–`12`; sheets topo `16`–`20`.
- **Avatares**: `CircleAvatar`, fundo `Colors.blue[800]`, com inicial ou ícone `person`.
- **Bottom sheets**: topo arredondado, com "grabber" (barra 40×4, `Colors.white24`, raio 2).
- **Tipografia**: fonte padrão do sistema. Tamanhos: título AppBar ~20, título logo 28,
  corpo 13–14, badges/labels 11–12, timestamps/hints 10–11.

### 2.6 Logo / Marca

- Logo: `assets/icon/logo.png` (100×100 na tela de login).
- **Nome de exibição da marca na UI: "Hubi"** (título do MaterialApp e tela de login).
  Este é o nome que aparece para o usuário e **deve ser mantido** em todas as telas
  (splash, login, cabeçalhos). *(O pacote/ícone do projeto chama-se "RapidHub", mas
  isso é apenas o nome técnico do build — a marca visível é **Hubi**.)*

---

## 3. Mapa de rotas e navegação

A navegação é **imperativa** (`Navigator.push` / `pushReplacement` /
`pushAndRemoveUntil`) — **não há rotas nomeadas**. As telas são empilhadas
diretamente por construtor.

```
main()
 └─ RapidhubApp (MaterialApp, tema escuro)
     └─ [Splash/Gate] FutureBuilder: verifica token em armazenamento seguro
         ├─ token válido ──▶ OrgSelectionScreen
         └─ sem token    ──▶ LoginScreen

Fluxo completo:
LoginScreen ──(login OK)──▶ OrgSelectionScreen ──(escolhe org)──▶ ChatListScreen ──(toca conversa)──▶ ChatScreen
     ▲                              │  ▲                                   │  ▲                              │
     │                              │  └────(trocar organização)──────────┘  │                              │
     └──(logout / 401)──────────────┴─────────────────────────────────────────┘                              │
                                                                                                              │
ChatScreen abre (modais bottom sheet): Enviar Template · Agendar Follow-up · Opções de anexo                  ┘
```

| # | Tela / Componente | Tipo | Como chega |
|---|---|---|---|
| 0 | **Splash/Gate** | Tela (loading) | Inicial. Mostra spinner enquanto checa o token. |
| 1 | **LoginScreen** | Tela | Sem sessão, ou após logout |
| 2 | **OrgSelectionScreen** | Tela | Após login, com sessão ativa, ou ao "Trocar Organização" |
| 3 | **ChatListScreen** | Tela | Após selecionar organização |
| 4 | **ChatScreen** | Tela | Ao tocar numa conversa da lista |
| M1 | **Filtrar Conversas** | Bottom sheet | Ícone de filtro na AppBar da ChatListScreen |
| M2 | **Enviar Template** | Bottom sheet | Menu ⋮ no ChatScreen (só ticket "open") |
| M3 | **Agendar Follow-up** | Bottom sheet | Menu ⋮ no ChatScreen (só ticket "open") |
| M4 | **Opções de Anexo** | Bottom sheet | Clipe 📎 na barra de input do ChatScreen |

---

## 4. Telas (especificação detalhada)

### 4.0 Splash / Gate de autenticação

- **Layout**: tela vazia, `Scaffold` fundo `#0D1117`, `CircularProgressIndicator` azul centralizado.
- **Função**: lê `session_token` do armazenamento seguro; decide para qual tela ir.
- **Estados**: carregando (spinner) → redireciona.

---

### 4.1 LoginScreen — *"Entrar"*

**Função:** autenticar o atendente via email + senha
(`POST /api/auth/sign-in/email`). Em sucesso, salva `session_token` e `user_email`
e vai para a seleção de organização.

**Layout (vertical, centralizado, com scroll):**
1. Logo (100×100).
2. Título **"Hubi"** (marca oficial da UI), 28px, bold, branco.
3. Campo **Email** — input com ícone `email`, fundo `#161B22`, raio 12, label cinza.
4. Campo **Palavra-passe** — input obscurecido com ícone `lock`.
5. Mensagem de erro (vermelho), quando houver.
6. Botão **"Entrar"** — largura total, altura 50, azul, raio 12. Vira spinner durante o login.

**Estados:**
- Vazio (campos não preenchidos) → erro "Preenche o email e a palavra-passe."
- Carregando → botão com spinner, desabilitado.
- Credenciais inválidas → "Email ou palavra-passe incorretos."
- Sem conexão → "Erro de conexão. Verifica a tua internet."

**Microcopy (PT-PT):** "Email", "Palavra-passe", "Entrar".

---

### 4.2 OrgSelectionScreen — *"Escolher Organização"*

**Função:** listar as organizações do usuário
(`GET /api/auth/organization/list`) e ativar a escolhida
(`POST /api/auth/organization/set-active`), indo para a lista de conversas.

**Layout:**
- **AppBar**: título "Escolher Organização", fundo `#161B22`.
- **Corpo**: lista de **cards** (`#161B22`, raio 12, margem inferior 12), cada um:
  - `leading`: avatar circular azul com a inicial do nome.
  - `title`: nome da organização (bold, branco, 16).
  - `subtitle`: slug (cinza, 13).
  - `trailing`: chevron `arrow_forward_ios` (cinza).

**Estados:**
- Carregando → spinner azul centralizado.
- Erro → texto vermelho ("Erro ao carregar organizações." / "Erro de conexão.").
- Lista vazia → "Nenhuma organização encontrada." (cinza).
- `401` → limpa tudo e volta ao Login.

---

### 4.3 ChatListScreen — *"Minhas Conversas"*

**Função:** inbox principal. Lista paginada de conversas/tickets com filtros,
abas por estado, contadores, atualização em tempo real (SSE) e badges de metadados.

**AppBar:**
- Título: **"Minhas Conversas"**.
- Ações (à direita):
  - **Filtro** (`filter_alt_outlined`) — abre o sheet de filtros. Mostra um badge
    numérico (azul) com a quantidade de filtros ativos.
  - **Trocar Organização** (`swap_horiz`, azul) — volta para a OrgSelectionScreen.
  - **Sair** (`logout`, vermelho) — abre diálogo de confirmação de logout.

**Abas (chips horizontais com contador):**
Cada aba é uma pílula (raio 10) com rótulo + badge de contagem. Ativa = azul; inativa = `#1E2733`.
- **IA** — tickets com status `pending` (em atendimento pela IA).
- **Ativos** — tickets com status `open` (assumidos por humano). *(aba padrão ao abrir)*
- **Departamento** — tickets com departamento atribuído e não fechados.

**Barra "ARQUIVADOS":** faixa abaixo das abas (ícone `inventory_2_outlined` +
rótulo "ARQUIVADOS" + contador). Apenas informativa/contador (status `closed`).

**Faixa "Filtros ativos":** aparece só quando há filtros. Mostra os chips dos
filtros aplicados + botão "Limpar".

**Item da lista (ListTile, 3 linhas):**
- `leading`: avatar do contato (foto via URL, ou ícone `person`).
- `title`: nome do contato (bold se houver não lidas).
- `subtitle`:
  - Última mensagem (1 linha, com reticências).
  - Linha de **badges** (Wrap): Conexão (teal, ícone telefone), Atendente (azul,
    ícone pessoa), Departamento (amarelo, ícone prédio), até 2 Tags (roxo, ícone etiqueta).
- `trailing`:
  - Tempo relativo ("agora", "5m", "2h", "3d", "12/05") — verde se há não lidas.
  - Badge circular verde com número de mensagens não lidas (quando > 0).

**Paginação / scroll:** carrega mais ao chegar perto do fim ("infinite scroll").
Indicador "Carregando mais conversas..." no rodapé.

**Estados:**
- Carregando → spinner azul.
- Erro → texto vermelho centralizado.
- Vazio (por aba):
  - IA: "Nenhuma conversa em atendimento por IA."
  - Ativos: "Nenhuma conversa ativa encontrada."
  - Departamento: "Nenhum departamento encontrado."

**Diálogo de logout:** AlertDialog (`#161B22`), título "Terminar Sessao",
texto "Tens a certeza que queres sair da tua conta?", botões "Cancelar" (azul) /
"Sair" (vermelho).

**Tempo real:** SSE `GET /api/chats/stream` — eventos `ticket_update` inserem/atualizam
a conversa no topo da lista.

---

### 4.4 ChatScreen — Conversa

**Função:** exibir e operar uma conversa específica: histórico (mensagens + eventos
de ticket numa única timeline), envio de mensagens/mídia, gravação de áudio, e ações
de ticket (assumir, template, follow-up, arquivar).

**AppBar:**
- Título: nome do contato (ou "Chat").
- Botão voltar (seta branca).
- Menu **⋮** (só aparece quando o ticket está **"open"**), com opções:
  - **Enviar Template** (`send_outlined`) → sheet M2.
  - **Agendar Follow-up** (`schedule_outlined`) → sheet M3.
  - **Arquivar ticket** (`archive_outlined`) → arquiva (`PATCH /api/tickets/{id}` action=archive).

**Barra de badges (topo, scroll horizontal, fundo `#11161E`):**
- Conexão (teal, ícone telefone) — quando identificada.
- Atendente (azul, ícone pessoa) — ou "Sem atendente".
- Até 2 Tags de contato (roxo).
- **Janela Meta** (ícone relógio): contagem regressiva de 24h desde a última mensagem
  recebida. "Meta: 5h 12m" (laranja) ou "Meta: expirada" (vermelho). Regra do WhatsApp:
  janela de 24h para mensagens livres.

**Corpo — Timeline (mensagens + eventos):**
- **Bolha de mensagem**: alinhada à direita se própria (`Colors.blue[700]`), à esquerda
  se recebida (`#1E2733`). Cantos arredondados (12) com "rabo" no canto inferior do lado do remetente.
  - Conteúdo por tipo:
    - **Texto**: texto simples; URLs detectadas viram links clicáveis.
    - **Imagem**: miniatura/preview.
    - **Vídeo**: player embutido (`_VideoPlayerBubble`).
    - **Áudio**: player com play/pause + progresso (`_AudioPlayerBubble`).
    - **Documento**: placeholder/ação para abrir.
    - **Mídia indisponível**: placeholder de erro (`_MediaErrorPlaceholder`).
  - Rodapé da bolha: horário (HH:mm) + **ícone de status** (próprias):
    - `pending` → relógio (`access_time`, cinza).
    - `sent`/`delivered`/`read` → ticks.
    - `failed` → `error_outline` (vermelho).
- **Evento de ticket** (`_buildTimelineEvent`): item de sistema centralizado
  (ex.: transferência, mudança de status), com data/hora completa.
- Carregamento de mais mensagens ao rolar para o topo (paginação reversa), com spinner.

**Estados do corpo:**
- Carregando → spinner azul.
- Vazio → "Sem mensagens ou eventos." (cinza).

**Barra inferior (3 modos mutuamente exclusivos):**

1. **Ticket "pending" (atendido pela IA):** card com texto
   *"Conversa em atendimento por IA."* + botão azul largura total **"Assumir conversa"**
   (vira spinner ao assumir). Não permite digitar.

2. **Gravando áudio:** botão lixeira (cancelar, vermelho) + ponto vermelho pulsante +
   "Gravando... MM:SS" + botão **stop** (círculo vermelho) que envia o áudio.

3. **Normal:** clipe 📎 (anexos) + campo de texto ("Escreve uma mensagem...",
   fundo `#0D1117`, raio 24) + botão **mic** (azul) + botão **enviar** (avião de papel, azul).

**Tempo real:** SSE `GET /api/chats/{id}/stream` — novas mensagens e mudanças de
status chegam ao vivo.

---

## 5. Modais / Bottom Sheets

### M1 — Filtrar Conversas
Bottom sheet rolável (`#0F1722`). Cabeçalho "Filtrar Conversas" + botão "Limpar".
Campos:
- **Busca** (texto) — nome, mensagem, agente...
- Switch **"Buscar em todas as mensagens"**.
- Seções de seleção múltipla (chips/checkbox), opções derivadas das conversas atuais:
  - **Status** (ícone bandeira) — IA / Ativos / Arquivados.
  - **Responsável** (atendente).
  - **Departamento**.
  - **Tags**.
  - **Conexão**.
- **Intervalo de datas**: "De" / "Até" (date pickers).
- Cada seção tem `emptyLabel` quando não há opções (ex.: "Nenhum status encontrado nas conversas.").
- Botão de aplicar no fim (retorna os filtros e recarrega a lista).

### M2 — Enviar Template
Bottom sheet rolável (`#161B22`, `DraggableScrollableSheet`). Dois passos:
1. **Lista de templates** aprovados da conexão (`GET` templates por `connectionId`,
   com cache em memória por conexão). Cada item mostra nome/idioma/categoria.
2. **Formulário** do template selecionado:
   - **PREVIEW**: render do HEADER/BODY/FOOTER do template.
   - **Parâmetros**: um campo por variável `{{nome}}` (rotulado com tipo do componente).
   - Botão **"Enviar Template"** (azul). Erros exibidos em caixa vermelha.
   - Sucesso → fecha e mostra snackbar "Template enviado com sucesso."

### M3 — Agendar Follow-up
Bottom sheet (`DraggableScrollableSheet`, 65% inicial). Cabeçalho com ícone relógio + "Follow-up".
- **Card de follow-up existente** (se houver):
  - Badge de status colorido + rótulo (`pending`/`paused`/etc.) + data agendada.
  - Mensagem do follow-up.
  - Ações conforme status: **Pausar** (laranja), **Retomar** (verde), **Cancelar** (vermelho).
- **Novo follow-up** (formulário):
  - Campo de **mensagem** (multilinha, "Mensagem do follow-up...").
  - Botões **Selecionar data** (`calendar_today`) e **Selecionar hora** (`access_time`).
  - Botão **"Agendar Follow-up"** (azul).
- Erros em caixa vermelha.

### M4 — Opções de Anexo
Bottom sheet (`#1E2733`) com grabber e lista de opções (ícone colorido + label):
- **Galeria (Foto)** — verde, `photo`.
- **Câmera (Foto)** — azul, `camera_alt`.
- **Galeria (Vídeo)** — laranja, `videocam`.
- **Câmera (Vídeo)** — vermelho, `video_camera_back`.
- **Arquivo de Áudio** — roxo, `audio_file`.
- **Documento** — teal, `insert_drive_file`.

---

## 6. Catálogo de funções (comportamento por tela)

> Mapa funcional para a IA entender **o que cada ação faz** ao desenhar fluxos/protótipos.

### LoginScreen
| Função | O que faz |
|---|---|
| `_fazerLogin()` | Valida campos, chama `sign-in/email`, salva token, navega para OrgSelection. Trata erros. |

### OrgSelectionScreen
| Função | O que faz |
|---|---|
| `_loadOrganizations()` | Carrega lista de organizações. 401 → logout. |
| `_selectOrg(id)` | Define org ativa e navega para ChatList. |
| `_logoutAndGoToLogin()` | Limpa storage e volta ao Login. |

### ChatListScreen
| Função | O que faz |
|---|---|
| `_carregarChats({loadMore})` | Carrega/pagina conversas (cursor), extrai contadores das abas. |
| `_startListeningToChatListUpdates()` | SSE: atualiza tickets em tempo real (reconecta em erro). |
| `_upsertChat()` | Insere/atualiza conversa no topo da lista. |
| `_hydrateChatsContactMeta()` | Busca detalhes/contatos faltantes (departamento, tags, conexão). |
| `_visibleChats()` | Filtra por aba ativa + filtros do usuário. |
| `_openFiltersSheet()` / `_clearFilters()` | Abre sheet de filtros / limpa filtros. |
| `_buildTab()` / `_buildChatBadge()` | Constroem aba com contador / badge de metadado. |
| `_formatRelativeTime()` | "agora / 5m / 2h / 3d / dd/mm". |
| `_fazerLogout()` | Encerra sessão e volta ao Login (remove histórico de navegação). |

### ChatScreen
| Função | O que faz |
|---|---|
| `_loadChatDetails()` / `_loadContactMeta()` | Carrega detalhes do chat e tags do contato. |
| `_loadMessages({loadMore})` | Carrega/pagina mensagens (cursor "before"). |
| `_loadTicketEvents()` | Carrega eventos do ticket (timeline de sistema). |
| `_startListeningToMessages()` | SSE: novas mensagens e status em tempo real. |
| `_sendMessage()` | Envia texto (com mensagem "otimista" antes da resposta). |
| `_sendMediaFile()` | Upload (`/api/upload`) + envio com `mediaKey`. |
| `_toggleRecording()` / `_startRecording()` / `_stopRecordingAndSend()` / `_cancelRecording()` | Gravação de áudio (AAC .m4a) com timer. |
| `_pickImage()` / `_pickVideo()` / `_pickDocument()` / `_pickAudioFile()` | Seletores de mídia. |
| `_assumeConversation()` | Assume o ticket (transfere para o atendente). Resolve o destino por token/sessão/org. |
| `_archiveTicketIfOpen()` | Arquiva ticket "open". |
| `_showSendTemplateSheet()` / `_showFollowUpSheet()` / `_showAttachmentOptions()` | Abrem os modais M2/M3/M4. |
| `_metaWindowLabel()` / `_isMetaWindowExpired()` | Calculam a janela Meta de 24h. |
| `_buildTimelineItems()` | Funde mensagens + eventos numa timeline ordenada. |
| `_updateMessageStatus()` / `_buildMessageStatusIcon()` | Status de entrega da mensagem. |

---

## 7. Estados globais e regras de negócio (para refletir no design)

- **Status do ticket** define quase toda a UI:
  - `pending` (IA) → aba "IA"; no chat, barra inferior bloqueada com "Assumir conversa";
    **sem** menu ⋮.
  - `open` (humano) → aba "Ativos"; chat com input liberado e menu ⋮ completo.
  - `closed` (arquivado) → contador "ARQUIVADOS".
  - com departamento e não fechado → aba "Departamento".
- **Janela Meta (24h)**: regra do WhatsApp Business — fora da janela, recomenda-se
  enviar **template**. O badge de contagem regressiva comunica isso visualmente.
- **Mensagens otimistas**: a mensagem aparece imediatamente como `pending` e depois
  muda para `sent/delivered/read` ou `failed`. O design deve prever esses 4 estados visuais.
- **Tempo real (SSE)**: lista e conversa se atualizam sozinhas — sem "pull to refresh"
  obrigatório (embora a lista recarregue ao voltar de um chat).
- **Multi-organização**: o usuário pode pertencer a várias orgs e trocar a qualquer momento.

---

## 8. Inventário de telas para entregáveis de design

Ao gerar mockups, produzir no mínimo estas variações:

1. **Splash** (loading).
2. **Login** — padrão, com erro, carregando.
3. **Seleção de Organização** — lista, vazio, carregando, erro.
4. **Lista de Conversas** — aba IA, aba Ativos, aba Departamento, com filtros ativos,
   estado vazio, carregando mais, diálogo de logout.
5. **Conversa** — recebida/enviada com vários tipos de mídia, ticket "pending"
   (assumir), ticket "open" (input completo), gravando áudio, badge Meta ativo vs expirado,
   evento de sistema na timeline, estado vazio.
6. **Sheet Filtros**, **Sheet Templates** (lista + formulário), **Sheet Follow-up**
   (existente + novo), **Sheet Anexos**.

---

## 9. Tom de voz / idioma

- Idioma da UI: **Português (mistura PT-PT/PT-BR)** — ex.: "Palavra-passe", "Escreve uma
  mensagem", "Tens a certeza". Ao redesenhar, **padronizar para um único português**
  (recomendado PT-BR, dado o domínio `.com.br`).
- Marca: a UI exibe **"Hubi"** — manter esse nome.
- Tom: direto, informal-profissional.
- Acentuação: o código tem várias strings sem acento (ex.: "Conexao", "Sessao") por
  limitação técnica — **no design, usar acentuação correta**.

---

### Resumo de 1 linha por tela
- **Login**: email + senha → entra (marca **Hubi**).
- **Organização**: escolhe a empresa.
- **Conversas**: inbox com abas (IA/Ativos/Departamento), filtros e tempo real.
- **Conversa**: chat com mídia, assumir/template/follow-up/arquivar, janela Meta 24h.

---

## 10. Anexo — Endpoints da API

Base URL: `https://rapidhub.com.br`. Todas as chamadas (exceto login) enviam o header
`Authorization: Bearer <session_token>`. `Content-Type: application/json` salvo no upload (multipart).

### Autenticação / Sessão
| Método | Endpoint | Uso |
|---|---|---|
| POST | `/api/auth/sign-in/email` | Login (body: `email`, `password`) → retorna `token` |
| POST | `/api/auth/sign-out` | Logout |
| GET | `/api/auth/organization/list` | Lista organizações do usuário |
| POST | `/api/auth/organization/set-active` | Ativa organização (body: `organizationId`) |
| GET | `/api/auth/get-organization?organizationId=` | Detalhes da org (resolve membro/usuário) |
| GET | `/api/auth/get-session` · `/api/auth/session` · `/api/auth/me` · `/api/me` · `/api/users/me` · `/api/member/me` · `/api/members/me` | Resolução de identidade (tentadas em ordem para descobrir o `userId` ao assumir conversa) |

### Conversas / Mensagens
| Método | Endpoint | Uso |
|---|---|---|
| GET | `/api/chats?limit=&cursor=&<filtros>` | Lista paginada de conversas (cursor) |
| GET | `/api/chats/{id}` | Detalhes de uma conversa |
| GET | `/api/chats/{id}/messages?limit=&before=` | Mensagens (paginação reversa por `before`) |
| POST | `/api/chats/{id}/messages` | Enviar mensagem (texto ou mídia via `mediaKey`) |
| POST | `/api/chats/{id}/send-template` | Enviar template aprovado |
| GET (SSE) | `/api/chats/stream` | Stream de atualizações de tickets (lista) |
| GET (SSE) | `/api/chats/{id}/stream` | Stream de mensagens/status da conversa |
| POST | `/api/upload` | Upload de arquivo (multipart `file`) → retorna `file.key` (mediaKey) |

**Filtros aceitos em `/api/chats`** (multivalor): `search`, `searchAllMessages`,
`status`/`ticketStatus` (`open`/`pending`/`closed`), `statusId`, `attendantId`/`responsibleId`,
`department`, `tag`, `connectionId`, `dateFrom`, `dateTo`.

### Tickets
| Método | Endpoint | Uso |
|---|---|---|
| PATCH | `/api/tickets/{id}` | Ações no ticket (ex.: `{"action":"archive"}`) |
| PATCH | `/api/tickets/{id}/transfer` | Transferir/assumir (body: `targetId`, `targetType`=`user`/`agent`/`department`) |
| GET | `/api/tickets/{id}/events` | Eventos do ticket (timeline de sistema) |

### Follow-up
| Método | Endpoint | Uso |
|---|---|---|
| GET | `/api/tickets/{id}/followup` | Follow-up atual do ticket |
| POST | `/api/tickets/{id}/followup` | Criar follow-up (mensagem + data/hora) |
| POST | `/api/tickets/{id}/followup/{fid}/pause` | Pausar |
| POST | `/api/tickets/{id}/followup/{fid}/resume` | Retomar |
| DELETE | `/api/tickets/{id}/followup/{fid}` | Cancelar |

### Contatos / Templates
| Método | Endpoint | Uso |
|---|---|---|
| GET | `/api/contacts` | Lista de contatos (usada para hidratar tags/departamento) |
| GET | `/api/templates/meta?connectionId=` | Templates Meta aprovados da conexão |

### Armazenamento local (FlutterSecureStorage)
| Chave | Conteúdo |
|---|---|
| `session_token` | Token JWT da sessão |
| `user_email` | Email do usuário logado |
| `current_user_id` | ID do usuário (cacheado ao resolver o destino de "assumir conversa") |
