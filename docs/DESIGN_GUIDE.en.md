# Hubi Mobile — Design Guide for AI

> Reference document for a design AI (or a designer) to recreate / redesign the
> **Hubi Mobile** app. It describes **all screens, routes, navigation flows,
> components, states and functions** present in the current codebase
> (Flutter / Material, dark theme).
>
> Goal: give enough context to generate screens (Figma, mockups, prototypes)
> faithful to the real behavior **without reading the source code**.
>
> 🇧🇷 A Portuguese version of this document lives in [`DESIGN_GUIDE.md`](./DESIGN_GUIDE.md).

---

## 1. Product overview

Hubi Mobile is a **WhatsApp omnichannel support app** (a "ticket inbox" style).
The human agent:

1. Logs in.
2. Picks the organization (company) they'll work in.
3. Sees the list of conversations/tickets, split by state (AI, Active, Department, Archived).
4. Opens a conversation, reads the history, takes over the support (when it's with the AI),
   exchanges messages (text, audio, image, video, documents), sends templates,
   schedules follow-ups, and archives the ticket.

Backend: REST API + real-time streaming (SSE) at `https://rapidhub.com.br`.

UI platform: **Flutter / Material**, **fixed dark theme** (no light mode).

> **Brand name shown in the UI: "Hubi"** — keep this name across every screen.
> (The project's technical package/icon is named "RapidHub", but that is only the
> build identifier — the user-facing brand is **Hubi**.)

---

## 2. Visual identity / Design tokens

The app does NOT use a central theme file — colors are applied inline. Below is the
consolidated palette extracted from the whole codebase. **Use these tokens as the
official design system.**

### 2.1 Background colors (surfaces)

| Token | Hex | Usage |
|---|---|---|
| `bg/base` | `#0D1117` | Main background of every screen (scaffold); text input background |
| `surface/1` | `#161B22` | AppBar, cards, section bars, login surfaces |
| `surface/2` | `#1E2733` | Incoming message bubble, chips, inactive tab buttons, follow-up cards, popup menu |
| `surface/3` | `#11161E` / `#111B26` | Badge bar at the top of the chat; inner badge background |
| `surface/sheet` | `#0F1722` / `#161B22` | Bottom sheets background (filters / templates / follow-up) |

### 2.2 Brand / action colors

| Token | Hex / Material | Usage |
|---|---|---|
| `primary` | `Colors.blue` (`#2196F3`) | Primary buttons, active tabs, avatars, sent message bubble (`Colors.blue[700]`) |
| `primary/accent` | `Colors.blueAccent` | Active tab borders, filter-count badge |
| `danger` | `Colors.redAccent` | Errors, logout, cancel, recording, send failure |
| `success` | `Colors.green` / `Colors.greenAccent` | Success, unread counter, "Resume" |
| `warning` | `Colors.orange` / `#F59E0B` | Warnings, active Meta window, "Pause" |

### 2.3 Text colors

| Token | Value | Usage |
|---|---|---|
| Primary text | `Colors.white` | Titles, contact name, own message |
| Secondary text | `Colors.white70` | Message body, labels |
| Tertiary text | `Colors.white54` / `white38` | Timestamps, hints, placeholders |
| Disabled/grey | `Colors.grey` | Subtitles, empty states |

### 2.4 Badge accent colors (status / metadata)

| Meaning | Border / Icon | Text |
|---|---|---|
| Connection (phone) | `Colors.tealAccent` | `tealAccent` |
| Agent (person) | `#3B82F6` | `#93C5FD` |
| Department | `#FDE68A` | — |
| Contact tag | `#A78BFA` | `#D8B4FE` |
| Active Meta window | `#F59E0B` | `#FCD34D` |
| Expired Meta window | `#EF4444` | `#FCA5A5` |

### 2.5 Shape / Radius / Spacing

- **Border radius**: text fields `12`; message bubbles `12` ("tail" corner = `0`);
  chips/badges/pills `999` (fully rounded); buttons `10`–`12`; sheets top `16`–`20`.
- **Avatars**: `CircleAvatar`, background `Colors.blue[800]`, with initial or `person` icon.
- **Bottom sheets**: rounded top, with a "grabber" (40×4 bar, `Colors.white24`, radius 2).
- **Typography**: system default font. Sizes: AppBar title ~20, logo title 28,
  body 13–14, badges/labels 11–12, timestamps/hints 10–11.

### 2.6 Logo / Brand

- Logo: `assets/icon/logo.png` (100×100 on the login screen).
- **UI brand name: "Hubi"** (MaterialApp title and login screen). This is the
  user-facing name and **must be kept** on every screen (splash, login, headers).

---

## 3. Route & navigation map

Navigation is **imperative** (`Navigator.push` / `pushReplacement` /
`pushAndRemoveUntil`) — **there are no named routes**. Screens are pushed directly
via their constructors.

```
main()
 └─ HubiApp (MaterialApp, dark theme)
     └─ [Splash/Gate] FutureBuilder: checks token in secure storage
         ├─ valid token ──▶ OrgSelectionScreen
         └─ no token     ──▶ LoginScreen

Full flow:
LoginScreen ──(login OK)──▶ OrgSelectionScreen ──(pick org)──▶ ChatListScreen ──(tap chat)──▶ ChatScreen
     ▲                              │  ▲                                │  ▲                            │
     │                              │  └────(switch organization)───────┘  │                            │
     └──(logout / 401)──────────────┴──────────────────────────────────────┘                            │
                                                                                                         │
ChatScreen opens (modal bottom sheets): Send Template · Schedule Follow-up · Attachment options          ┘
```

| # | Screen / Component | Type | How it's reached |
|---|---|---|---|
| 0 | **Splash/Gate** | Screen (loading) | Initial. Spinner while checking the token. |
| 1 | **LoginScreen** | Screen | No session, or after logout |
| 2 | **OrgSelectionScreen** | Screen | After login with active session, or via "Switch Organization" |
| 3 | **ChatListScreen** | Screen | After selecting an organization |
| 4 | **ChatScreen** | Screen | On tapping a conversation in the list |
| M1 | **Filter Conversations** | Bottom sheet | Filter icon in the ChatListScreen AppBar |
| M2 | **Send Template** | Bottom sheet | ⋮ menu in ChatScreen (only "open" tickets) |
| M3 | **Schedule Follow-up** | Bottom sheet | ⋮ menu in ChatScreen (only "open" tickets) |
| M4 | **Attachment options** | Bottom sheet | 📎 clip in the ChatScreen input bar |

---

## 4. Screens (detailed spec)

### 4.0 Splash / Auth gate

- **Layout**: empty screen, `Scaffold` background `#0D1117`, centered blue `CircularProgressIndicator`.
- **Function**: reads `session_token` from secure storage; decides which screen to open.
- **States**: loading (spinner) → redirects.

---

### 4.1 LoginScreen — *"Sign in"*

**Function:** authenticate the agent via email + password
(`POST /api/auth/sign-in/email`). On success, stores `session_token` and `user_email`
and goes to organization selection.

**Layout (vertical, centered, scrollable):**
1. Logo (100×100).
2. Title **"Hubi"** (official UI brand), 28px, bold, white.
3. **Email** field — input with `email` icon, background `#161B22`, radius 12, grey label.
4. **Password** field — obscured input with `lock` icon.
5. Error message (red) when present.
6. **"Sign in"** button — full width, height 50, blue, radius 12. Turns into a spinner while signing in.

**States:**
- Empty (unfilled fields) → error "fill in email and password".
- Loading → button with spinner, disabled.
- Invalid credentials → "wrong email or password".
- No connection → "connection error, check your internet".

> Current microcopy is Portuguese (PT-PT): "Email", "Palavra-passe", "Entrar".

---

### 4.2 OrgSelectionScreen — *"Choose Organization"*

**Function:** list the user's organizations (`GET /api/auth/organization/list`) and
activate the chosen one (`POST /api/auth/organization/set-active`), then go to the chat list.

**Layout:**
- **AppBar**: title "Choose Organization", background `#161B22`.
- **Body**: list of **cards** (`#161B22`, radius 12, bottom margin 12), each one:
  - `leading`: blue circular avatar with the name's initial.
  - `title`: organization name (bold, white, 16).
  - `subtitle`: slug (grey, 13).
  - `trailing`: `arrow_forward_ios` chevron (grey).

**States:**
- Loading → centered blue spinner.
- Error → red text ("error loading organizations" / "connection error").
- Empty list → "no organization found" (grey).
- `401` → wipes storage and returns to Login.

---

### 4.3 ChatListScreen — *"My Conversations"*

**Function:** main inbox. Paginated list of conversations/tickets with filters,
state tabs, counters, real-time updates (SSE) and metadata badges.

**AppBar:**
- Title: **"My Conversations"**.
- Actions (right):
  - **Filter** (`filter_alt_outlined`) — opens the filters sheet. Shows a numeric
    (blue) badge with the count of active filters.
  - **Switch Organization** (`swap_horiz`, blue) — returns to OrgSelectionScreen.
  - **Sign out** (`logout`, red) — opens a logout confirmation dialog.

**Tabs (horizontal chips with counter):**
Each tab is a pill (radius 10) with label + count badge. Active = blue; inactive = `#1E2733`.
- **AI** — tickets with `pending` status (handled by the AI).
- **Active** — tickets with `open` status (taken by a human). *(default tab on open)*
- **Department** — tickets with an assigned department, not closed.

**"ARCHIVED" bar:** strip below the tabs (`inventory_2_outlined` icon + "ARCHIVED"
label + counter). Informational/counter only (`closed` status).

**"Active filters" strip:** shows only when there are filters. Displays the applied
filter chips + a "Clear" button.

**List item (ListTile, 3 lines):**
- `leading`: contact avatar (photo via URL, or `person` icon).
- `title`: contact name (bold if there are unread messages).
- `subtitle`:
  - Last message (1 line, ellipsized).
  - **Badges** row (Wrap): Connection (teal, phone icon), Agent (blue, person icon),
    Department (yellow, building icon), up to 2 Tags (purple, tag icon).
- `trailing`:
  - Relative time ("now", "5m", "2h", "3d", "05/12") — green if there are unread.
  - Green circular badge with the unread count (when > 0).

**Pagination / scroll:** loads more when reaching near the end ("infinite scroll").
"Loading more conversations..." indicator at the bottom.

**States:**
- Loading → blue spinner.
- Error → centered red text.
- Empty (per tab):
  - AI: "no conversation handled by AI".
  - Active: "no active conversation found".
  - Department: "no department found".

**Logout dialog:** AlertDialog (`#161B22`), title "End Session", text "are you sure
you want to sign out?", buttons "Cancel" (blue) / "Sign out" (red).

**Real-time:** SSE `GET /api/chats/stream` — `ticket_update` events insert/update the
conversation at the top of the list.

---

### 4.4 ChatScreen — Conversation

**Function:** display and operate a specific conversation: history (messages + ticket
events in a single timeline), message/media sending, audio recording, and ticket
actions (take over, template, follow-up, archive).

**AppBar:**
- Title: contact name (or "Chat").
- Back button (white arrow).
- **⋮** menu (appears only when the ticket is **"open"**), with options:
  - **Send Template** (`send_outlined`) → sheet M2.
  - **Schedule Follow-up** (`schedule_outlined`) → sheet M3.
  - **Archive ticket** (`archive_outlined`) → archives (`PATCH /api/tickets/{id}` action=archive).

**Badge bar (top, horizontal scroll, background `#11161E`):**
- Connection (teal, phone icon) — when identified.
- Agent (blue, person icon) — or "No agent".
- Up to 2 contact Tags (purple).
- **Meta window** (clock icon): 24h countdown since the last inbound message.
  "Meta: 5h 12m" (orange) or "Meta: expired" (red). WhatsApp rule: 24h window for
  free-form messages.

**Body — Timeline (messages + events):**
- **Message bubble**: aligned right if own (`Colors.blue[700]`), left if incoming
  (`#1E2733`). Rounded corners (12) with a "tail" at the bottom corner on the sender's side.
  - Content by type:
    - **Text**: plain text; detected URLs become clickable links.
    - **Image**: thumbnail/preview.
    - **Video**: embedded player (`_VideoPlayerBubble`).
    - **Audio**: player with play/pause + progress (`_AudioPlayerBubble`).
    - **Document**: placeholder/action to open.
    - **Unavailable media**: error placeholder (`_MediaErrorPlaceholder`).
  - Bubble footer: time (HH:mm) + **status icon** (own messages):
    - `pending` → clock (`access_time`, grey).
    - `sent`/`delivered`/`read` → ticks.
    - `failed` → `error_outline` (red).
- **Ticket event** (`_buildTimelineEvent`): centered system item (e.g., transfer,
  status change), with full date/time.
- Loads more messages when scrolling to the top (reverse pagination), with a spinner.

**Body states:**
- Loading → blue spinner.
- Empty → "no messages or events" (grey).

**Bottom bar (3 mutually exclusive modes):**

1. **"pending" ticket (handled by AI):** a card with the text *"Conversation handled
   by AI."* + full-width blue **"Take over conversation"** button (turns into a spinner
   while taking over). Typing is not allowed.

2. **Recording audio:** trash button (cancel, red) + pulsing red dot +
   "Recording... MM:SS" + **stop** button (red circle) that sends the audio.

3. **Normal:** 📎 clip (attachments) + text field ("Type a message...", background
   `#0D1117`, radius 24) + **mic** button (blue) + **send** button (paper plane, blue).

**Real-time:** SSE `GET /api/chats/{id}/stream` — new messages and status changes arrive live.

---

## 5. Modals / Bottom Sheets

### M1 — Filter Conversations
Scrollable bottom sheet (`#0F1722`). Header "Filter Conversations" + "Clear" button.
Fields:
- **Search** (text) — name, message, agent...
- **"Search across all messages"** switch.
- Multi-select sections (chips/checkbox), options derived from the current conversations:
  - **Status** (flag icon) — AI / Active / Archived.
  - **Responsible** (agent).
  - **Department**.
  - **Tags**.
  - **Connection**.
- **Date range**: "From" / "To" (date pickers).
- Each section has an `emptyLabel` when there are no options (e.g., "no status found in conversations").
- Apply button at the bottom (returns the filters and reloads the list).

### M2 — Send Template
Scrollable bottom sheet (`#161B22`, `DraggableScrollableSheet`). Two steps:
1. **Template list** of the connection's approved templates (`GET /api/templates/meta`
   by `connectionId`, with in-memory cache per connection). Each item shows name/language/category.
2. **Form** for the selected template:
   - **PREVIEW**: renders the template's HEADER/BODY/FOOTER.
   - **Parameters**: one field per `{{name}}` variable (labeled with the component type).
   - **"Send Template"** button (blue). Errors shown in a red box.
   - Success → closes and shows a snackbar "template sent successfully".

### M3 — Schedule Follow-up
Bottom sheet (`DraggableScrollableSheet`, 65% initial). Header with clock icon + "Follow-up".
- **Existing follow-up card** (if any):
  - Colored status badge + label (`pending`/`paused`/etc.) + scheduled date.
  - Follow-up message.
  - Actions by status: **Pause** (orange), **Resume** (green), **Cancel** (red).
- **New follow-up** (form):
  - **Message** field (multiline, "Follow-up message...").
  - **Select date** (`calendar_today`) and **Select time** (`access_time`) buttons.
  - **"Schedule Follow-up"** button (blue).
- Errors in a red box.

### M4 — Attachment options
Bottom sheet (`#1E2733`) with a grabber and a list of options (colored icon + label):
- **Gallery (Photo)** — green, `photo`.
- **Camera (Photo)** — blue, `camera_alt`.
- **Gallery (Video)** — orange, `videocam`.
- **Camera (Video)** — red, `video_camera_back`.
- **Audio file** — purple, `audio_file`.
- **Document** — teal, `insert_drive_file`.

---

## 6. Function catalog (behavior per screen)

> Functional map so the AI understands **what each action does** when designing flows/prototypes.

### LoginScreen
| Function | What it does |
|---|---|
| `_fazerLogin()` | Validates fields, calls `sign-in/email`, stores token, navigates to OrgSelection. Handles errors. |

### OrgSelectionScreen
| Function | What it does |
|---|---|
| `_loadOrganizations()` | Loads the organization list. 401 → logout. |
| `_selectOrg(id)` | Sets the active org and navigates to ChatList. |
| `_logoutAndGoToLogin()` | Wipes storage and returns to Login. |

### ChatListScreen
| Function | What it does |
|---|---|
| `_carregarChats({loadMore})` | Loads/paginates conversations (cursor), extracts tab counters. |
| `_startListeningToChatListUpdates()` | SSE: real-time ticket updates (reconnects on error). |
| `_upsertChat()` | Inserts/updates a conversation at the top of the list. |
| `_hydrateChatsContactMeta()` | Fetches missing details/contacts (department, tags, connection). |
| `_visibleChats()` | Filters by active tab + user filters. |
| `_openFiltersSheet()` / `_clearFilters()` | Opens the filters sheet / clears filters. |
| `_buildTab()` / `_buildChatBadge()` | Build a tab with counter / a metadata badge. |
| `_formatRelativeTime()` | "now / 5m / 2h / 3d / dd/mm". |
| `_fazerLogout()` | Ends the session and returns to Login (clears navigation history). |

### ChatScreen
| Function | What it does |
|---|---|
| `_loadChatDetails()` / `_loadContactMeta()` | Loads chat details and contact tags. |
| `_loadMessages({loadMore})` | Loads/paginates messages (cursor "before"). |
| `_loadTicketEvents()` | Loads ticket events (system timeline). |
| `_startListeningToMessages()` | SSE: real-time new messages and status. |
| `_sendMessage()` | Sends text (with an "optimistic" message before the response). |
| `_sendMediaFile()` | Upload (`/api/upload`) + send with `mediaKey`. |
| `_toggleRecording()` / `_startRecording()` / `_stopRecordingAndSend()` / `_cancelRecording()` | Audio recording (AAC .m4a) with a timer. |
| `_pickImage()` / `_pickVideo()` / `_pickDocument()` / `_pickAudioFile()` | Media pickers. |
| `_assumeConversation()` | Takes over the ticket (transfers to the agent). Resolves the target via token/session/org. |
| `_archiveTicketIfOpen()` | Archives an "open" ticket. |
| `_showSendTemplateSheet()` / `_showFollowUpSheet()` / `_showAttachmentOptions()` | Open modals M2/M3/M4. |
| `_metaWindowLabel()` / `_isMetaWindowExpired()` | Compute the 24h Meta window. |
| `_buildTimelineItems()` | Merges messages + events into an ordered timeline. |
| `_updateMessageStatus()` / `_buildMessageStatusIcon()` | Message delivery status. |

---

## 7. Global states and business rules (to reflect in the design)

- **Ticket status** drives almost all of the UI:
  - `pending` (AI) → "AI" tab; in chat, the bottom bar is blocked with "Take over conversation";
    **no** ⋮ menu.
  - `open` (human) → "Active" tab; chat with input enabled and full ⋮ menu.
  - `closed` (archived) → "ARCHIVED" counter.
  - with a department and not closed → "Department" tab.
- **Meta window (24h)**: WhatsApp Business rule — outside the window, sending a
  **template** is recommended. The countdown badge communicates this visually.
- **Optimistic messages**: the message appears immediately as `pending` and then changes
  to `sent/delivered/read` or `failed`. The design must account for these 4 visual states.
- **Real-time (SSE)**: list and conversation update on their own — no mandatory
  "pull to refresh" (although the list reloads when returning from a chat).
- **Multi-organization**: the user may belong to several orgs and switch at any time.

---

## 8. Screen inventory for design deliverables

When generating mockups, produce at least these variations:

1. **Splash** (loading).
2. **Login** — default, with error, loading.
3. **Organization Selection** — list, empty, loading, error.
4. **Conversation List** — AI tab, Active tab, Department tab, with active filters,
   empty state, loading more, logout dialog.
5. **Conversation** — incoming/outgoing with various media types, "pending" ticket
   (take over), "open" ticket (full input), recording audio, active vs expired Meta badge,
   system event in the timeline, empty state.
6. **Filters sheet**, **Templates sheet** (list + form), **Follow-up sheet**
   (existing + new), **Attachments sheet**.

---

## 9. Tone of voice / language

- UI language: **Portuguese (mixed PT-PT/PT-BR)** — e.g., "Palavra-passe", "Escreve uma
  mensagem", "Tens a certeza". When redesigning, **standardize to a single Portuguese**
  (PT-BR recommended, given the `.com.br` domain).
- Brand: the UI shows **"Hubi"** — keep this name.
- Tone: direct, informal-professional.
- Accents: the code has several unaccented strings (e.g., "Conexao", "Sessao") due to
  a technical limitation — **in the design, use correct accentuation**.

---

## 10. Appendix — API endpoints

Base URL: `https://rapidhub.com.br`. Every call (except login) sends the header
`Authorization: Bearer <session_token>`. `Content-Type: application/json` except on upload (multipart).

### Authentication / Session
| Method | Endpoint | Usage |
|---|---|---|
| POST | `/api/auth/sign-in/email` | Login (body: `email`, `password`) → returns `token` |
| POST | `/api/auth/sign-out` | Logout |
| GET | `/api/auth/organization/list` | List the user's organizations |
| POST | `/api/auth/organization/set-active` | Activate an organization (body: `organizationId`) |
| GET | `/api/auth/get-organization?organizationId=` | Org details (resolves member/user) |
| GET | `/api/auth/get-session` · `/api/auth/session` · `/api/auth/me` · `/api/me` · `/api/users/me` · `/api/member/me` · `/api/members/me` | Identity resolution (tried in order to discover the `userId` when taking over a conversation) |

### Conversations / Messages
| Method | Endpoint | Usage |
|---|---|---|
| GET | `/api/chats?limit=&cursor=&<filters>` | Paginated conversation list (cursor) |
| GET | `/api/chats/{id}` | Conversation details |
| GET | `/api/chats/{id}/messages?limit=&before=` | Messages (reverse pagination via `before`) |
| POST | `/api/chats/{id}/messages` | Send message (text or media via `mediaKey`) |
| POST | `/api/chats/{id}/send-template` | Send approved template |
| GET (SSE) | `/api/chats/stream` | Ticket updates stream (list) |
| GET (SSE) | `/api/chats/{id}/stream` | Conversation messages/status stream |
| POST | `/api/upload` | File upload (multipart `file`) → returns `file.key` (mediaKey) |

**Filters accepted by `/api/chats`** (multi-value): `search`, `searchAllMessages`,
`status`/`ticketStatus` (`open`/`pending`/`closed`), `statusId`, `attendantId`/`responsibleId`,
`department`, `tag`, `connectionId`, `dateFrom`, `dateTo`.

### Tickets
| Method | Endpoint | Usage |
|---|---|---|
| PATCH | `/api/tickets/{id}` | Ticket actions (e.g., `{"action":"archive"}`) |
| PATCH | `/api/tickets/{id}/transfer` | Transfer/take over (body: `targetId`, `targetType`=`user`/`agent`/`department`) |
| GET | `/api/tickets/{id}/events` | Ticket events (system timeline) |

### Follow-up
| Method | Endpoint | Usage |
|---|---|---|
| GET | `/api/tickets/{id}/followup` | Current ticket follow-up |
| POST | `/api/tickets/{id}/followup` | Create follow-up (message + date/time) |
| POST | `/api/tickets/{id}/followup/{fid}/pause` | Pause |
| POST | `/api/tickets/{id}/followup/{fid}/resume` | Resume |
| DELETE | `/api/tickets/{id}/followup/{fid}` | Cancel |

### Contacts / Templates
| Method | Endpoint | Usage |
|---|---|---|
| GET | `/api/contacts` | Contact list (used to hydrate tags/department) |
| GET | `/api/templates/meta?connectionId=` | Connection's approved Meta templates |

### Local storage (FlutterSecureStorage)
| Key | Content |
|---|---|
| `session_token` | Session JWT |
| `user_email` | Logged-in user's email |
| `current_user_id` | User ID (cached when resolving the "take over conversation" target) |

---

### One-line summary per screen
- **Login**: email + password → sign in (**Hubi** brand).
- **Organization**: pick the company.
- **Conversations**: inbox with tabs (AI/Active/Department), filters and real-time.
- **Conversation**: chat with media, take over/template/follow-up/archive, 24h Meta window.
