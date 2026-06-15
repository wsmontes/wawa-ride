# Wawa Ride — FAQ Técnico e de Produto

Documento de referência para manter o app dentro da especificação.  
Cada resposta aqui é uma decisão de design que guia a implementação.

---

## Arquitetura Geral

### O que é o WawaMesh?
É o protocolo de transporte do Wawa Ride. Derivado do BitChat (Unlicense, 26k stars), funciona como um "TCP/IP" para a malha BLE. Ele define como pacotes viajam entre phones (header, TTL, relay, dedup, fragmentação) mas não se importa com o conteúdo do payload.

### Qual a relação com o BitChat?
Usamos o mesmo protocolo de envelope (wire format de 16 bytes + flags), mesmas regras de flood/dedup/TTL, mesma arquitetura dual Central+Peripheral. Mas em vez de chat, encapsulamos dados de localização (12 bytes), rotas e waypoints.

### O app precisa de servidor?
**Não para funcionar.** BLE mesh e MultipeerKit são 100% device-to-device. Para fallback via internet (Nostr), usamos relays públicos gratuitos. O único servidor próprio é o Valhalla (cálculo de rotas, fase 3) — e mesmo esse é evitável se riders importarem rotas GPX.

| Canal | Servidor? | Custo |
|-------|-----------|-------|
| BLE mesh | Não | $0 |
| MultipeerKit | Não | $0 |
| Nostr (MVP) | Relays públicos | $0 |
| Nostr (produção) | Opcional, 1 VPS | ~$5/mês |
| Valhalla (fase 3) | Docker container | ~$10-20/mês |

---

## Hardware e Transporte

### Que hardware o app usa?
Apenas o iPhone. Não precisa de nenhum acessório. Os 3 canais de comunicação usam chips que já existem no device:
- **Bluetooth Low Energy** (chip BLE) → malha mesh
- **Wi-Fi Direct** (chip WiFi) → MultipeerConnectivity
- **4G/5G** (chip celular) → Nostr fallback

### Qual a diferença entre BLE e MultipeerKit?
| | BLE Mesh | MultipeerKit |
|--|----------|-------------|
| Velocidade | Kbps (lento) | Mbps (rápido) |
| Multi-hop | Sim (TTL=5, ~500m) | Não (1 hop, ~100m) |
| Background | Parcial (precisa 1 em foreground) | Não funciona |
| Payload | CompactLocation 12 bytes | LocationPayload JSON ~80 bytes |
| Papel | Resiliente, off-grid | Primário enquanto app aberto |

### E se todos colocarem o app em background?
A malha BLE para. iOS não permite BLE background-to-background entre dois phones simultaneamente em background. **Pelo menos um rider precisa manter o app em foreground** (tela ligada no suporte do guidão). Isso é esperado e desejável para um app de navegação.

### Qual o alcance?
- **Direto:** ~30-100m entre 2 iPhones (BLE, ao ar livre)
- **Multi-hop:** Até ~500m teórico (5 hops × 100m cada)
- **Com internet:** Global (via Nostr relay)

---

## Pareamento e Grupo

### Como funciona o pareamento?
1. Líder abre app → toca "Criar" → PIN de 4 dígitos aparece na tela
2. Seguidores abrem app → tocam "Entrar" → digitam o PIN
3. Conexão BLE se estabelece automaticamente
4. Quando todos conectaram, líder toca "Partiu!"

### Precisa de internet para parear?
**Não.** Pareamento é 100% via BLE. Funciona no meio do mato.

### Precisa estar perto?
Sim, no momento do pareamento (~30m, alcance BLE). Depois de pareados, podem se afastar até ~500m (multi-hop via outros riders).

### Precisa parear de novo a cada passeio?
Sim. Um novo PIN é gerado cada vez. São apenas 2 toques (Criar → Partiu) ou 6 toques (Entrar → 4 dígitos). Decisão de segurança: não manter sessões antigas abertas.

### Quem é o líder?
Quem toca "Criar". Não tem superpoderes no MVP — a única diferença é que ele gera o PIN. Futuramente: líder compartilha rota, marca waypoints, e sua trail aparece como referência para o grupo.

### Tamanho máximo do grupo?
5-7 riders de forma confortável. O BLE permite até 6 conexões simultâneas por device. Com multi-hop, riders que não estão diretamente conectados ainda se comunicam via intermediários.

---

## Durante o Passeio

### O líder anda mais rápido — o time vê o caminho dele?
**Sim.** Uma linha azul (trail) cresce em tempo real no mapa de todos os seguidores, mostrando exatamente por onde o líder passou. O seguidor só precisa seguir a linha.

### Como a trail funciona tecnicamente?
1. GPS do líder emite coordenadas a 0.5-1 Hz
2. Cada ponto é enviado via mesh (CompactLocation, 12 bytes)
3. Phones dos seguidores acumulam os pontos: `[coord1, coord2, ...]`
4. Mapa desenha polyline conectando os pontos
5. Periodicamente, map matching (Valhalla Meili) limpa a trail ruidosa

### O rider precisa interagir durante o passeio?
**Não.** Zero toques necessários. O mapa mostra tudo automaticamente:
- Minha posição (azul, centro)
- Outros riders (laranja, pulsando)
- Trail do líder (linha azul)
- Velocidade atual (HUD)

### O que acontece se alguém sai do alcance BLE?
| Situação | Resultado |
|----------|-----------|
| Rider a 200m | BLE direto funciona normalmente |
| Rider a 500m | BLE via multi-hop (relay intermediários) |
| Rider a 2km+ sem internet | Trail para. Pin fica cinza (stale após 15s). Remove após 120s. |
| Rider a 2km+ com 4G | Nostr ativa. Trail continua via internet. |
| Rider volta ao alcance | BLE reconecta. Automerge CRDT preenche o gap. |

### O que acontece se alguém sai da rota?
Se o líder compartilhou uma rota (GPX ou Valhalla), o app verifica se cada rider está dentro de 100m da polyline (via Turf-Swift). Se sair:
- Pin do rider fica vermelho no mapa de todos
- Vibração forte (haptic) em todos os phones
- Nenhuma ação necessária — é informativo

### Como encerrar o passeio?
Long-press no handle (quase invisível) na base da tela → confirmação "Encerrar?" → toca "Encerrar". Proteção contra toque acidental com luva.

---

## Mapa e Offline

### O mapa funciona sem internet?
**Sim.** Usamos PMTiles — um arquivo contendo todo o mapa vetorial da região pré-carregado no app. Renderizado via MapLibre Native. Sem internet = sem problema.

### Qual o tamanho do mapa offline?
| Região | Tamanho |
|--------|---------|
| Cidade (SP metro) | ~50-150 MB |
| Estado de SP | ~200-500 MB |
| Corredor de rota específica | ~5-20 MB |

### Preciso baixar o mapa antes?
No MVP, o mapa da região de teste vem embutido no app. Futuramente, o rider escolhe regiões para download (como apps de mapas offline).

---

## Navegação (Fase 3)

### Tem navegação turn-by-turn?
Não no MVP. O MVP é "siga a trail do líder". Na fase 3, com Valhalla + Ferrostar, teremos:
- Cálculo de rota (perfil motocicleta: prefere estradas secundárias e trilhas)
- Instruções de curva em português
- Voz (text-to-speech)
- Recálculo se sair da rota

### Posso importar uma rota de outro app?
Sim — via arquivo GPX. Qualquer app (Calimoto, Kurviger, Scenic, Google Maps) pode exportar GPX. O rider importa via share sheet → rota aparece como polyline no mapa de todo o grupo.

---

## Bateria e Performance

### Quanto consome de bateria?
GPS a 1 Hz + BLE ativo ≈ 3-5% por hora em iPhones recentes (14+). Um passeio de 3h consome ~10-15% de bateria. Recomendação: usar carregador USB no suporte.

### Por que a tela fica sempre ligada?
Porque BLE mesh precisa de pelo menos 1 peer em foreground. E porque motociclistas precisam ver o mapa sem tocar na tela. O app desativa o sleep automático (`isIdleTimerDisabled = true`).

### O app drena a bateria quando não estou em passeio?
**Não.** BLE e GPS só ligam quando o rider toca "Criar" ou "Entrar". Em idle, o app é um mapa estático — consome praticamente nada.

---

## Segurança e Privacidade

### Os dados são encriptados?
**Não no MVP.** Packets de localização são cleartext. Justificativa: validar a malha primeiro, sem a complexidade de handshakes criptográficos.

Na fase 5, adicionamos:
- NIP-44 (ECDH + ChaCha20) para mensagens 1:1 via Nostr
- OpenMLS (RFC 9420) para criptografia de grupo com forward secrecy
- Noise_XX handshake no BLE mesh

### Alguém pode interceptar minha localização?
No MVP, sim — qualquer device com BLE scanner próximo pode ver os pacotes. Na prática, isso exige estar a <100m com um device específico escaneando. O risco é baixo para passeios recreativos. Para uso crítico, aguardar fase 5 (encryption).

### O app coleta dados?
**Não.** Zero analytics, zero telemetria, zero servidor nosso no MVP. Localização só existe entre os phones do grupo enquanto o passeio está ativo.

---

## Futuro

### Voice (walkie-talkie)?
Fase 4. Via MultipeerConnectivity (Wi-Fi Direct), com codec Opus a 8-12 kbps. BLE é muito lento para áudio. Será um botão PTT (push-to-talk) grande na tela.

### CarPlay?
Fase 4. Ferrostar já tem módulo `FerrostarCarPlayUI`. Ideal para motos com suporte CarPlay wireless (display simplificado, botões grandes).

### Android?
Não está no roadmap atual. O protocolo WawaMesh é transport-agnostic — poderia ser portado para Android (Kotlin + BLE) usando os mesmos packet types. BitChat já tem versão Android.

### Mais de 7 riders?
O limite é de hardware (6 conexões BLE simultâneas). Com multi-hop, grupos de 10+ são possíveis mas não testados. Na fase 5, testamos com 10 devices e ajustamos TTL/dedup conforme necessário.

---

## Dados e Privacidade

### Cada rider guarda seus próprios dados?
**Sim.** Cada phone armazena localmente (GRDB/SQLite):
- PeerID (8 bytes, identidade persistente)
- Histórico de rides (data, duração, distância)
- Fila offline (pacotes pendentes)
- Waypoints salvos
- Mapa offline (PMTiles)
- Documento Automerge (estado CRDT para sync)

### Quais dados são compartilhados com o grupo?
Apenas o mínimo para o grupo funcionar:

| Dado | Pacote | Tamanho | Frequência |
|------|--------|---------|-----------|
| Posição (lat, lon, heading, speed) | `.locationUpdate` | 12 bytes | 0.5-1 Hz |
| Apelido | `.announce` | ~20 bytes | 1x ao conectar |
| PIN de entrada | `.groupControl` | ~9 bytes | 1x ao parear |
| Rota planejada (líder) | `.routeShare` | ~500B-2KB | 1x ao iniciar |
| Waypoint compartilhado | `.waypointSync` | ~30 bytes | Sob demanda |

### O que NÃO é compartilhado?
- Histórico de rides anteriores (privacidade)
- Velocidade máxima (desnecessário)
- Nível de bateria (fase futura, talvez)
- Identidade real (só apelido, sem email/telefone)
- GPS quando app está idle (só transmite durante ride ativa)

### Princípio de design
**Compartilhar o mínimo para o grupo funcionar.** Localização em tempo real é o core. Todo o resto é local ou eventual.
