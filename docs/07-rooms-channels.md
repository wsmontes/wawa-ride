# WAWA Ride — Salas e Canais (Sistema de Comunicação)

## 1. Conceito

O sistema de salas do WAWA Ride é inspirado no Discord: um passeio tem salas de comunicação independentes. A sala "Geral" existe automaticamente. Qualquer rider pode criar salas adicionais para conversas privadas ou em grupo.

```
PASSEIO "Serra do Rio do Rastro"
│
├── 🏠 Geral               ← Automática, todos dentro, walkie-talkie do grupo
├── 📍 Alertas             ← Automática, notificações do sistema (perigo, SOS)
├── 🔒 Líder+Varredor      ← Criada pelo líder, coordenação de ritmo
├── 💬 Pedro+Ana           ← Criada pelo Pedro, papo privado
└── 🎙️ Música+Prosa        ← Criada pela Ana, sala de áudio aberta
```

## 2. Tipos de sala

| Tipo | Ícone | Criação | Membros | Áudio ao vivo | Áudio assíncrono | Fechável |
|------|-------|---------|---------|---------------|------------------|----------|
| `general` | 🏠 | Automática com o passeio | Todos os riders | ✅ (grupo todo) | ✅ | ❌ |
| `alerts` | 📍 | Automática com o passeio | Todos os riders | ❌ | ✅ (sistema) | ❌ |
| `voice` | 🎙️ | Qualquer rider | Selecionados na criação | ✅ (só membros) | ✅ | ✅ |
| `messaging` | 💬 | Qualquer rider | Selecionados na criação | ❌ | ✅ | ✅ |
| `direct` | 👤 | Automática (ao iniciar conversa) | 2 riders | ✅ | ✅ | ✅ |

## 3. Regras de negócio

```
SALA GERAL:
  - Criada automaticamente quando o líder cria o passeio
  - Todos os riders que entram no passeio entram automaticamente
  - Ninguém pode sair da Geral (é a sala âncora)
  - Ninguém pode fechar a Geral
  - Walkie-talkie padrão: PTT na tela principal fala na Geral

SALA DE ALERTAS:
  - Criada automaticamente
  - Só o sistema "fala" (alertas de perigo, SOS, status)
  - Riders não podem enviar mensagens nela
  - Serve como log de eventos do passeio

SALA PRIVADA (voice/messaging):
  - Qualquer rider pode criar
  - Criador escolhe nome + membros iniciais
  - Membros podem adicionar outros riders (desde que no passeio)
  - Membros podem sair (exceto criador? Configurável)
  - Criador pode remover membros
  - Criador pode fechar a sala
  - Sala fechada → membros recebem notificação → sala desaparece

SALA DIRECT:
  - Criada automaticamente quando um rider inicia conversa privada com outro
  - Exatamente 2 membros
  - Não tem nome customizado (usa nome do outro rider)
  - Se um rider sai, a sala é fechada
  - Suporta voz ao vivo + áudio assíncrono
```

## 4. Fluxo de criação de sala

```
RIDER CRIA SALA:
  1. Na tela do mapa, toca no ícone 🏠 (salas) → abre lista de salas
  2. Toca "+" → modal de criação
  3. Escolhe:
     - Tipo: 🎙️ Voz ao vivo / 💬 Só mensagens
     - Nome: "Líder+Varredor"
     - Membros: checklist com nomes dos riders (Geral já tem todos)
     - Privacidade: 🔒 Privada (só membros veem) / 🔓 Pública (todos veem)
  4. Toca "Criar"
  5. App cria Room localmente → envia mesh payload roomCreated
  6. Membros recebem → sala aparece com badge "Nova"
  7. TTS (membros): "Sala Líder+Varredor criada por Pedro"

OUTRO RIDER VÊ SALA PÚBLICA:
  1. Abre lista de salas → vê sala pública listada
  2. Toca na sala → "Entrar"
  3. App envia roomJoin → membros recebem
  4. TTS (sala): "Ana entrou na sala"

SALA FECHADA:
  1. Criador toca "Fechar sala" (com confirmação)
  2. App envia roomClosed → sala desaparece pra todos
  3. Mensagens da sala são removidas do cache local
```

## 5. Fluxo de comunicação em cada sala

### 5.1 Sala "Geral" — Walkie-talkie

```
FALAR NA GERAL:
  1. Rider segura botão 🎤 FALAR (na tela do mapa)
  2. Áudio: PCM 16kHz → Opus encode 32kbps, chunks de 20ms
  3. Transporte: MCSession stream → todos os peers conectados
  4. Peers NÃO diretamente conectados: chunks viram MeshPayload
     → relay via store-and-forward (TTL 3, prioridade critical)
  5. Receptor: Opus decode → alto-falante (ou headset Bluetooth)
  6. Se intercom Cardo/Sena detectado: NÃO toca áudio do app
     (intercom já está fazendo esse papel)

QUEM OUVE:
  - Todos os riders no passeio (não é por sala, é broadcast do passeio)
  - A "Geral" na verdade é o próprio canal de voz broadcast
  - Salas de voz privadas são canais separados
```

### 5.2 Sala de voz privada — Walkie-talkie privado

```
FALAR NA SALA PRIVADA:
  1. Rider abre a sala → botão 🎤 FALAR (específico da sala)
  2. Áudio: Opus encode
  3. Transporte: MCSession stream direto pros membros da sala
     (MultipeerConnectivity permite múltiplos streams com nomes diferentes)
  4. Membros fora de alcance: relay via mesh
  5. NÃO-membros: NÃO recebem

MÚLTIPLAS SALAS DE VOZ SIMULTÂNEAS:
  - Um rider pode estar "ouvindo" várias salas ao mesmo tempo
  - Mas só "fala" em uma por vez (a sala ativa)
  - Áudio das salas é mixado (ducking: sala ativa mais alta)
  - UI: indicador visual de qual sala está ativa
```

### 5.3 Sala de mensagens — Áudio assíncrono

```
ENVIAR MENSAGEM DE VOZ:
  1. Rider abre a sala → toca 🎙️ Gravar
  2. App grava: PCM 16kHz → buffer em memória
  3. Rider solta ou atinge 60s → gravação para
  4. App comprime: PCM → Opus (32kbps)
  5. Cria VoiceMessage → salva localmente no SQLite
  6. Envia via mesh: priority high, TTL 10
  7. Se offline: OfflineQueue → transmite quando possível
  8. UI: indicador de entrega (✓ enviado, ✓✓ entregue)

RECEBER MENSAGEM DE VOZ:
  1. App recebe voiceMessage payload
  2. Salva localmente no SQLite
  3. Se o rider NÃO está na sala de destino:
     - Cria a sala automaticamente (direct) ou ignora (se sala não existe mais)
  4. UI: badge na sala "🔵 1"
  5. Se sala é a que está aberta: mensagem aparece na timeline
  6. TTS: "Nova mensagem de Pedro na sala Líder+Varredor"

PLAYBACK:
  1. Rider abre a sala → vê timeline de mensagens
  2. Toca na mensagem → Opus decode → toca
  3. Marca como tocada → voiceMessageAck enviado ao remetente
  4. UI: mensagem tocada fica com indicador visual diferente
```

## 6. UI das Salas

### 6.1 Lista de Salas (acessível pelo mapa)

```
┌──────────────────────────────────────┐
│  ← Voltar ao mapa                    │
│                                      │
│  🏍️ Serra do Rio do Rastro          │
│  Salas                               │
│                                      │
│  ┌────────────────────────────────┐  │
│  │ 🏠 Geral                      │  │
│  │    4 membros                  │  │
│  │    🟢 Pedro está falando      │  │
│  └────────────────────────────────┘  │
│                                      │
│  ┌────────────────────────────────┐  │
│  │ 📍 Alertas                    │  │
│  │    3 alertas hoje             │  │
│  │    ⚠️ Radar em 500m           │  │
│  └────────────────────────────────┘  │
│                                      │
│  ┌────────────────────────────────┐  │
│  │ 🔒 Líder+Varredor     🔵 1    │  │  ← Badge = 1 mensagem não lida
│  │    2 membros                  │  │
│  │    Última: "Vamos parar no..." │  │
│  └────────────────────────────────┘  │
│                                      │
│  ┌────────────────────────────────┐  │
│  │ 💬 Pedro+Ana                  │  │
│  │    2 membros                  │  │
│  │    Última: há 15 min          │  │
│  └────────────────────────────────┘  │
│                                      │
│  ┌────────────────────────────────┐  │
│  │ ➕  Nova Sala                  │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

### 6.2 Dentro de uma Sala (timeline de áudio)

```
┌──────────────────────────────────────┐
│  ← Salas    Líder+Varredor    ⚙️     │
│                                      │
│  ┌────────────────────────────────┐  │
│  │ Membros: Wagner, João         │  │
│  │ Criada por: Wagner            │  │
│  └────────────────────────────────┘  │
│                                      │
│  ─── Hoje, 10:30 ───                │
│                                      │
│  ┌────────────────────────────┐     │
│  │ 🟢 Wagner              10:30│     │
│  │ ┌──────────────────────┐   │     │
│  │ │ ▶️ 0:12              │   │     │  ← Mensagem de áudio (toque pra ouvir)
│  │ └──────────────────────┘   │     │
│  │ "Vamos parar no posto..."  │     │  ← Transcrição on-device (futuro)
│  └────────────────────────────┘     │
│                                      │
│  ┌────────────────────────────┐     │
│  │ 🔵 João               10:32│     │
│  │ ┌──────────────────────┐   │     │
│  │ │ ▶️ 0:08              │   │     │
│  │ └──────────────────────┘   │     │
│  │ "Ok, chegando aí"          │     │
│  └────────────────────────────┘     │
│                                      │
│  ─── Hoje, 11:15 ───                │
│                                      │
│  ┌────────────────────────────┐     │
│  │ 🟢 Wagner              11:15│     │
│  │ ┌──────────────────────┐   │     │
│  │ │ ▶️ 0:05              │   │     │
│  │ └──────────────────────┘   │     │
│  │ "Pronto?"                   │     │
│  └────────────────────────────┘     │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  🎤 Gravar mensagem           │  │  ← Botão gravar
│  └────────────────────────────────┘  │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  🎙️ Falar ao vivo (PTT)       │  │  ← Se for sala de voz
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

## 7. Sincronização de salas via mesh

```
QUANDO UM RIDER ENTRA NO PASSEIO:
  1. Líder envia estado completo (ou rider mais próximo)
  2. Estado inclui: lista de salas ativas + membros de cada uma
  3. Rider é automaticamente adicionado à "Geral"
  4. Rider vê salas públicas na lista
  5. Salas privadas onde rider NÃO é membro: invisíveis

QUANDO UMA SALA É CRIADA:
  1. Criador adiciona localmente → mesh broadcast roomCreated
  2. Destinatários (membros): adicionam localmente
  3. Não-destinatários (sala privada): ignoram

QUANDO UM RIDER PERDE CONEXÃO (offline):
  - Permanece como membro das salas
  - Mensagens enviadas pra ele ficam em buffer (OfflineQueue)
  - Ao reconectar: recebe estado atualizado das salas + mensagens pendentes

QUANDO UM RIDER SAI DO PASSEIO:
  - Removido de todas as salas
  - Salas direct onde ele era um dos 2 membros: fechadas
  - Salas onde ele era o único membro restante: fechadas
```

## 8. Persistência

```
SALAS: SQLite, tabela 'rooms'
  - Persistem durante o passeio
  - Ao encerrar o passeio: salas são removidas
  - Exceção: mensagens de voz podem ser salvas (opção "Salvar mensagens")

MENSAGENS DE VOZ: SQLite, tabela 'voice_messages'
  - Persistem durante o passeio
  - Ao encerrar: removidas (default) ou mantidas (se configurado)
  - Limite de armazenamento: 200MB para mensagens
  - Política de evicção: mensagens mais antigas e já ouvidas são removidas primeiro
```
