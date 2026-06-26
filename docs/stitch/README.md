# RapidHub — Layouts Stitch (Google)

Designs modernos gerados via **Stitch (Google)** para o app mobile RapidHub.
Servem como **referência visual** para a implementação em Flutter (não são código Flutter).

- **Projeto Stitch:** `RapidHub Mobile — Inbox Moderno` (`projects/3092948567541842826`)
- **Design System:** `RapidHub Dark` (`assets/6314271635546384917`)

## Sistema de Design

| Token | Valor |
|-------|-------|
| Fundo principal | `#0D1117` |
| Superfícies / cards | `#161B22` |
| Bordas sutis | `#21262D` / `#30363D` |
| Acento primário (azul) | `#2F81F7` |
| IA / destaque secundário (roxo) | `#A371F7` |
| Sucesso / online (verde) | `#2ECC71` |
| Texto principal | `#E6EDF3` |
| Texto secundário | `#8B949E` |
| Fonte títulos | Plus Jakarta Sans |
| Fonte corpo | Inter |
| Cantos | 8–12px (cards), 16px+ (sheets) |

## Telas

| # | Tela | Preview | HTML | Tela Flutter correspondente |
|---|------|---------|------|------------------------------|
| 1 | Inbox / Lista de conversas | `01_inbox.png` | `01_inbox.html` | `lib/chat_list_screen.dart` |
| 2 | Conversa aberta (chat) | `02_chat.png` | `02_chat.html` | `lib/chat_screen.dart` |
| 3 | Login | `03_login.png` | `03_login.html` | `lib/login_screen.dart` |
| 4 | Seleção de organização | `04_org_selection.png` | `04_org_selection.html` | `lib/org_selection_screen.dart` |

### 1. Inbox
Top bar com logo + avatar e chip de organização ativa, busca em pílula com badge de filtros,
tabs segmentadas (IA roxo / Ativos azul / Grupos), cards de conversa com avatar+status online,
badges de não lidas, etiquetas de departamento, indicadores de áudio e visto, FAB azul e bottom nav.

### 2. Chat
Top bar de contato (online), banner de status da IA com toggle, bolhas recebidas/enviadas,
mídia (áudio com waveform, documento PDF), indicador de digitando, chips de sugestão da IA
e barra de input com anexo/emoji/microfone.

### 3. Login
Glow radial azul-roxo, logo, card de formulário (email, senha com olho, lembrar-me,
esqueceu a senha), botão Entrar, login social (Google/Microsoft) e rodapé de conexão segura.

### 4. Seleção de organização
Perfil do usuário + logout, busca, cards de workspace com logo, métricas (conexões/agentes),
stack de avatares, estado selecionado, badges (Ativo/Admin), card pontilhado "Criar nova" e
botão Continuar fixo.

## Observações de implementação (Flutter)

- O Stitch gera HTML/Tailwind. Para o Flutter, traduzir para widgets Material 3 com `ThemeData.dark()`.
- As cores acima já estão parcialmente no app (`main.dart`, `login_screen.dart`).
  Sugestão: centralizar num `AppColors`/`AppTheme`.
- Componentes reutilizáveis sugeridos: `ConversationTile`, `SegmentedTabs`, `ChatBubble`,
  `AiSuggestionChip`, `OrgCard`.
- Fontes Plus Jakarta Sans + Inter: adicionar via `google_fonts` ou declarar em `pubspec.yaml`.
</content>
