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

---

## Comunicação entre Riders

### O app tem mensagens ou voz?
**No MVP, não.** O app comunica por meio de dados, não palavras:
- **Presença no mapa** — "estou aqui" (automático, 1 Hz)
- **Trail do líder** — "segue por aqui" (automático)
- **Alertas visuais** — "fulano saiu da rota" (automático, vibração)
- **Waypoints** — líder marca ponto "parar aqui" (1 toque)

Motociclistas com capacete e luvas não conseguem digitar texto nem ler mensagens. O app comunica com dados visuais e hápticos.

### Terá walkie-talkie (voice PTT)?
**Sim, na fase 4.** Botão push-to-talk grande na tela. Pressiona, fala, solta.

| Aspecto | Detalhe |
|---------|---------|
| Canal | MultipeerConnectivity (Wi-Fi Direct) — não BLE (sem bandwidth para áudio) |
| Codec | Opus, 8 kHz mono, 8-12 kbps |
| Latência | <500ms |
| Alcance | ~100m (Wi-Fi Direct entre phones) |
| Internet necessária? | Não (P2P direto) |
| Background? | Não — app precisa estar em foreground |
| Grupo? | Sim — todos ouvem quem fala |

### Por que não voz no MVP?
Complexidade de audio pipeline (capture → Opus encode → transmit → decode → playback) é significativa. Validamos a malha de localização primeiro, depois adicionamos voz.

### Por que não BLE para voz?
BLE transfere ~Kbps. Opus a 8 kbps precisa de throughput constante que BLE não garante com fragmentação e relay. MultipeerKit (Wi-Fi Direct) oferece Mbps — suficiente para áudio sem esforço.

### Terá mensagens de texto?
**Não.** Impossível digitar com luva + capacete. Alternativa futura: "quick comms" — botões predefinidos (🛑 Parar, ⛽ Combustível, ☕ Pausa, ⚠️ Atenção, 👍 OK). Cada um é 1 byte via mesh.

### O que NÃO teremos?
- Chat de texto (impraticável com luva)
- Chamada VoIP contínua (bateria + vento no mic)
- Notificações push (sem servidor)
- Histórico de mensagens (não é um messenger)

---

## Cenários de Conectividade

### Líder se afasta além do alcance mesh, mas tem internet. Só 1 rider do grupo tem internet.
O rider com internet age como **bridge automático** entre Nostr e BLE mesh:

1. Líder publica posição no Nostr relay (tem 4G)
2. Rider com internet recebe via Nostr, mostra no mapa
3. Rider re-broadcast automaticamente via BLE mesh para o grupo
4. Riders sem internet veem o líder graças ao bridge

Isso acontece sem lógica especial — qualquer pacote recebido por qualquer canal é re-broadcast na mesh se TTL > 0. Dedup (messageID) garante processamento único.

### E se ninguém do grupo tiver internet?
Líder desaparece do mapa (cinza após 15s, some após 120s). Quando qualquer rider recuperar internet, o app baixa posições acumuladas no Nostr relay e preenche o gap.

### E se o líder voltar ao alcance mesh sem internet?
BLE reconecta. Automerge CRDT sincroniza as posições que faltavam. Trail preenche o gap automaticamente.

### Qualquer rider pode ser bridge?
**Sim.** Não é um papel atribuído. Qualquer phone que tenha internet E mesh ativo age como gateway automaticamente. Se vários riders têm internet, dedup previne duplicação.

---

## Grupos Grandes (>7 riders)

### Posso ter 20 riders num único grupo?
**Não diretamente.** BLE suporta ~6 conexões simultâneas por device. 20 riders num único mesh saturaria os links (20 × 1 Hz = 20 pacotes/segundo flooding).

### Como resolver para grupos grandes?
**Sub-grupos encadeados com sub-líderes.** Exemplo com 20 riders:

- Grupo A: Marcos (líder) + 6 riders + Pedro
- Grupo B: Pedro (líder) + 6 riders + Ana
- Grupo C: Ana (líder) + 5 riders

Pedro segue Marcos. Seu sub-grupo segue ele. Ana segue Pedro. É uma corrente.

### Um líder pode ser membro do grupo de outro líder?
**No MVP:** Não. Um phone = 1 grupo por vez.  
**Fase futura (Caravana Mode):** Sim. Sub-líderes participam de 2 grupos simultaneamente — recebem trail do líder-mestre e repassam para seu sub-grupo. Escala para 20+ riders.

### O que cada sub-grupo vê?
Cada rider vê apenas seu líder direto + peers do seu sub-grupo. Sub-líderes veem o líder acima + seus seguidores. Ninguém é sobrecarregado com 20 pins no mapa.

### Por que não simplesmente aumentar as conexões BLE?
Limitação de hardware (Apple). O chip BLE do iPhone não suporta mais de ~7 conexões estáveis. Além disso, flooding num grupo de 20 = 20 packets/segundo × TTL=5 hops = até 100 retransmissões/segundo — devastaria a bateria.

### Caravana Mode: Mesh Fluida (grupos grandes reais)
Para um motoclube com 20+ riders, sub-grupos fixos são artificiais. Na realidade, quem está do seu lado muda a cada minuto. A solução é **mesh oportunística**:

- Todos compartilham 1 PIN/groupID (uma única caravana)
- Cada phone conecta automaticamente com quem está no range BLE (~100m)
- Topologia muda organicamente conforme riders se movem
- Multi-hop garante que a informação percola pelo pelotão inteiro
- TTL adaptativo por densidade: muitos vizinhos → TTL baixo (evita flood); poucos vizinhos → TTL alto (tenta alcançar longe)

**O que cada rider vê:** Todos os riders alcançáveis por cadeia de hops (tipicamente 10-15 de 20 num pelotão de 2km). Riders muito distantes (>5 hops, sem internet) desaparecem até alguém se aproximar ou internet fazer bridge.

**Implicação técnica:** O código atual já suporta — BLE conecta com qualquer peer do mesmo serviceUUID. Não há sub-grupo no protocolo. Ajustes necessários: TTL adaptativo e teste de carga com 10+ devices.

### A caravana precisa de conexão ativa com o líder?
**Não.** O líder é uma referência, não um requisito de conectividade. A trail dele é um **dado** (coordenadas acumuladas), não uma conexão. Uma vez recebida, fica no mapa independente de o líder estar alcançável.

O pelotão segue o que já tem no mapa:
- Trail crescendo = líder ativo, tudo normal
- Trail parou = líder sem conectividade. Seguem até o último ponto, depois usam a rota combinada (GPX) ou esperam

### E se o líder compartilhou a rota antes de sair?
Aí a caravana **nunca se perde**, mesmo sem trail em tempo real. A rota (GPX ou Valhalla) está no phone de cada rider. A trail é apenas confirmação visual de que o líder está seguindo o plano.

### Isso replica o comportamento natural de motoclube?
Exatamente. Motoclubes já funcionam assim sem app: líder na frente, madrinha atrás, rota combinada antes. O app digitaliza:
- Trail = rastro visual do líder
- Rota compartilhada = "o combinado"
- Waypoints = "próxima parada"
- Mesh = saber que todo mundo está bem, mesmo sem ver

---

## Convites e Passeios Agendados

### Como convido riders para um passeio futuro (ex: domingo que vem)?
Crie o passeio no app → gera um **QR code** (ou link) que pode ser postado em qualquer lugar (Facebook, WhatsApp, Telegram). Qualquer pessoa que escaneia tem acesso ao passeio.

O QR contém:
```
{
  rideID: "uuid-do-passeio",
  secret: "32-bytes-shared-key",
  name: "Passeio Victoria Sunday",
  date: "2026-06-22T09:00:00-07:00",
  start: { lat: 48.4284, lon: -123.3656 },
  waypoints: [...],
  creatorPubKey: "ed25519-pub-key",
  signature: "assinatura-do-criador"
}
```

### Qualquer pessoa pode repassar o convite?
**Sim.** É o mesmo QR/link para todos. Daniel escaneia, decide convidar Raj → manda o mesmo QR. Raj escaneia → tem acesso ao passeio. Sem QR "cumulativo" ou cadeia de identidades.

### Por que não QR cumulativo (que acumula quem convidou quem)?
- **Privacidade:** QR cumulativo expõe identidades a cada hop. Se vaza num grupo aberto, todos sabem quem é quem.
- **Tamanho:** QR cresce a cada nível. No nível 5, fica ilegível.
- **Complexidade desnecessária:** Raj não precisa saber sobre você antes do dia. Ele só precisa do secret para entrar na mesh.

### Como sei quem vai antes do dia?
**RSVP via Nostr (opcional).** Quem escaneia o QR pode publicar "vou!" como evento Nostr com tag do rideID. O criador subscribe a essa tag e vê quem confirmou. Sem servidor, sem cadastro.

### A assinatura garante que o convite é legítimo?
**Sim.** A `creatorPubKey` + `signature` no QR provam que o convite veio do criador. Se alguém alterar data/local/rota, a assinatura invalida. Verificação é local (sem servidor).

### No dia do passeio, como funciona?
1. App verifica se tem rides agendados para hoje
2. Se sim, ativa mesh automaticamente com `groupID = rideID`
3. Qualquer device BLE próximo com mesmo groupID → conecta
4. Todos que escanearam o QR se veem no mapa imediatamente

### E se eu quiser revogar o convite?
Invalide o secret (o app do criador gera um novo). Quem tinha o secret antigo não consegue mais conectar na mesh (validação no handshake). Funciona porque o secret é verificado no momento da conexão, não no momento do scan.

---

## Alertas de Perigo (Hazard Beacons)

### Um rider pode reportar um perigo na pista para todos?
**Sim.** Com 1 toque no botão 🚨, o app registra o perigo (localização + hora + categoria) e propaga para:
- Riders do mesmo grupo (BLE mesh, imediato)
- **Qualquer rider WawaMesh** na região (via Nostr, sem limite de grupo)

### Como a propagação funciona sem limite de grupo?
Hazards são diferentes de location updates:
- **Sem TTL** — relay infinito no BLE (não decrementa, retransmite sempre)
- **Sem filtro de groupID** — todos recebem (é segurança pública)
- **Persiste no Nostr** com tag de geohash — riders que passam horas depois ainda veem
- **Expira automaticamente** (ex: 2h para óleo, 24h para buraco)

### Que tipos de perigo existem?
| Botão | Categoria | Expiração padrão |
|-------|-----------|------------------|
| 🛢️ | Óleo/líquido na pista | 2h |
| 🕳️ | Buraco/desnível | 24h |
| 🪨 | Detritos/objeto na pista | 4h |
| 🦌 | Animal na via | 1h |
| 🚔 | Fiscalização/radar | 2h |
| ⚠️ | Perigo genérico | 2h |

### Riders que passam depois são avisados?
**Sim.** Mesmo sem ter visto o rider que reportou:
1. App subscribe ao geohash da minha posição via Nostr
2. Recebe hazards ativos na região
3. Quando me aproximo (500m), vibração forte + pin vermelho no mapa + banner de alerta

### Posso confirmar ou descartar um alerta?
**Sim.** 1 toque: "✓ Resolvido" ou "🚨 Confirmo". Cada voto é publicado no Nostr. Mais confirmações = mais confiável. Mais "resolvido" = desaparece antes da expiração.

### É um Waze descentralizado?
Essencialmente sim — mas sem conta, sem servidor, sem tracking. Os alertas vivem na rede Nostr (relays públicos) e na mesh BLE local. Qualquer rider contribui e beneficia.

---

## Ride Beacons (Convites Abertos / Eventos Recorrentes)

### Posso criar um convite aberto que qualquer rider na região veja?
**Sim.** "Ride Beacons" são convites públicos geolocalizado. Funcionam como hazards invertidos: em vez de "cuidado aqui", é "venha aqui".

Exemplo: "Toda terça 18h — Posto Shell Centro — role livre com quem aparecer."

### Como funciona?
Mesmo mecanismo do hazard:
- Publicado no Nostr com geohash tag (região)
- Qualquer rider WawaMesh na área vê um pin dourado 📍 no mapa
- Suporta recorrência (iCal RRULE: toda terça, todo sábado, etc.)
- Não expira enquanto o criador não deletar

### No dia do evento, como o grupo se forma?
O beacon contém um `rideSecret`. Quem faz RSVP ("Vou!") recebe o secret. No dia:
1. Riders chegam no local
2. App ativa mesh automaticamente com o secret do beacon como groupID
3. Todos se veem no mapa
4. Alguém sai na frente → vira líder → trail cresce

### Qual a diferença de um passeio agendado (QR) vs Ride Beacon?
| | Passeio QR | Ride Beacon |
|--|---|---|
| Quem vê | Só quem recebeu o QR | Qualquer rider na região |
| Distribuição | Manual (share) | Automática (geohash) |
| Frequência | Evento único | Pode ser recorrente |
| Descoberta | Precisa receber convite | Aparece no mapa sozinho |
| Tipo | Grupo fechado | Semi-aberto |

### Como fica o mapa de um rider qualquer?
```
🔵 Eu
🟠 Meu grupo (passeio de hoje)
🟢 Riders de outros grupos (public visibility)
📍🟡 "Role de Terça" (beacon, convite aberto)
📍🟡 "Sáb Serra do Rio" (beacon, próximo evento)
⚠️🔴 "Óleo — Rua Augusta" (hazard)
```
Tudo descentralizado, tudo no mesmo protocolo WawaMesh + Nostr, tudo sem servidor.

---

## Perfil e Grafo Social (Rider Cards)

### Cada rider tem um perfil?
**Sim — o "Rider Card".** Troca automaticamente no handshake BLE quando dois riders se conectam. Contém:
- Nickname ("João Motoca")
- Avatar (emoji ou cor derivada da pubKey)
- Modelo da moto ("Tenere 700")
- Cidade
- Chave pública (identidade permanente)
- Assinatura (prova que é dele)

Tamanho: ~100-200 bytes. Cabe num pacote BLE sem fragmentar.

### Como a troca funciona?
Automática. Quando dois phones se descobrem no BLE:
1. Ambos enviam `.announce` com seu RiderCard
2. Ambos salvam o card do outro localmente (GRDB)
3. "Conhecer" alguém = ter estado na mesma mesh

Nenhuma ação manual necessária para trocar cards.

### Posso marcar alguém como amigo?
**Sim.** Long-press no pin → "⭐ Marcar como amigo". Salvo **localmente** — a pessoa não sabe. Efeito: próxima vez que aparecer, pin tem borda dourada.

### "Amigo de amigo" funciona?
**Sim, via confiança transitiva.** Se você optar por incluir uma lista de "friend badges" (hash dos amigos) no seu RiderCard, quando seu amigo encontra um amigo seu, o app avisa: "🤝 Amigo em comum: João".

O hash é de 8 bytes (SHA256 truncado) — suficiente para match local mas inútil para terceiros que não conhecem a pubKey original. Privacidade preservada.

### Níveis de confiança no mapa?
| Nível | Visual | Como se torna |
|-------|--------|---------------|
| Desconhecido | 🟠 (normal) | Default |
| Conhecido | 🟠 (card salvo) | Automático (handshake) |
| Amigo | ⭐ (borda dourada) | Manual (1 toque) |
| Amigo de amigo | 🤝 (badge) | Automático (hash match) |
| Bloqueado | Invisível | Manual |

### O que NÃO temos (e por quê)?
- Sem rating/estrelas público (incentivo tóxico)
- Sem seguidores (não é rede social)
- Sem DM fora do passeio (use WhatsApp)
- Friend badges são opt-in (privacidade)
- Ninguém edita o card de outra pessoa

---

## Motoclubes (Club Badge)

### Posso mostrar que sou membro de um motoclube?
**Sim.** O RiderCard inclui um `ClubBadge` — nome do clube + role + assinatura criptográfica do clube verificando que você é membro.

### Como o clube é criado?
1 rider cria o clube no app → gera par de chaves (clubPubKey/clubPrivKey). A chave privada fica com o presidente (ou diretoria). Publicação opcional no Nostr para que outros riders descubram clubes na região.

### Como membros são adicionados?
Presidente escaneia QR do rider → assina (riderPubKey + nome do clube + role) com a chave privada do clube → rider recebe o ClubBadge assinado para incluir no seu card.

### Como outros riders verificam que é real?
No handshake BLE, quem recebe o card verifica a assinatura do ClubBadge contra a clubPubKey. Se válida, é membro confirmado. **Impossível falsificar** sem a chave privada do presidente.

### Como aparece no mapa?
- Membros verificados de um clube: pin com badge/ícone do clube
- Quando ≥3 membros do mesmo clube estão juntos: label "BRAZOOCAS MC" aparece sobre o grupo
- Riders de fora veem: "aquele grupo ali é o Brazoocas"

### Hierarquia de roles?
| Role | Quem define |
|------|-------------|
| Presidente | Criador do clube |
| Membro | Presidente assina |
| Prospect | Presidente assina com role diferente |
| Convidado | Membro pode assinar (se habilitado) |

### No MVP vs Futuro?
- **MVP:** ClubBadge como string no card (sem verificação crypto — confiança social)
- **Fase 2+:** Ed25519 signature verification (impossível falsificar)

---

## Modelo Criptográfico e Chaves

### Cada rider tem chave pública e privada?
**Sim.** Par Ed25519 gerado 1x na primeira abertura do app. A chave privada nunca sai do Keychain do iOS. A pública é compartilhada em todo handshake BLE.

`PeerID = SHA256(riderPubKey)[0..8]` → 8 bytes usados nos pacotes mesh.

### Cada motoclube tem chave pública e privada?
**Sim.** Par Ed25519 gerado quando o presidente cria o clube. A privada fica com o presidente (Keychain). A pública é incluída em todos os ClubBadges e publicada no Nostr.

### Os QR codes usam isso para confirmar remetente?
**Sim.** Todo QR contém `creatorPubKey` + `signature(payload, privKey)`. Qualquer receptor verifica sem internet:
```
verify(payload, signature, creatorPubKey) → true/false
```
Se alguém alterar data/local/rota, a assinatura invalida.

### O app guarda todas as pubKeys que encontra?
**Sim.** Tabela GRDB `knownIdentity` (pubKey, peerID, nickname, firstSeen, lastSeen). Cresce a cada handshake. É o "contato" persistente — próxima vez que encontrar aquele rider, já sabe quem é.

### O que cada chave protege?
| Chave | Protege | Ataque prevenido |
|-------|---------|------------------|
| riderPrivKey | Minha identidade | Ninguém se faz passar por mim |
| clubPrivKey | Membership do clube | Ninguém finge ser membro |
| QR signature | Integridade do convite | Ninguém altera o passeio |
| rideSecret (simétrica) | Acesso à mesh | Só convidados entram |

### Onde ficam armazenadas?
| Chave | Armazenamento | Backup |
|-------|---------------|--------|
| riderPrivKey | iOS Keychain | iCloud Keychain (se habilitado) |
| clubPrivKey | iOS Keychain do presidente | Exportável via QR criptografado |
| pubKeys de outros | GRDB (SQLite) | Backup automático |
| rideSecret | GRDB | Efêmera (descartada após ride) |

### Quando cada camada de crypto entra?
| Fase | O que é ativo |
|------|---------------|
| MVP | PeerID random 8 bytes. Sem Ed25519. Cleartext. |
| Fase 2 | Ed25519 keypair. RiderCard assinado. ClubBadge verificável. |
| Fase 5 | Noise_XX (session keys BLE). OpenMLS (group encryption). NIP-44 (Nostr DMs). |

### Um passeio organizado pelo presidente do clube confirma tanto a pessoa quanto o clube?
**Sim. Dupla assinatura no QR:**
- `creatorSignature`: prova que o rider (presidente) criou o passeio
- `clubSignature`: prova que o clube (Brazoocas) autoriza

Qualquer receptor verifica ambos localmente. Um membro comum pode criar passeios pessoais (só rider signature), mas não pode assinar em nome do clube sem a `clubPrivKey`.

### Toda mensagem na mesh é assinada?
**Não.** Só o que é persistente ou propaga para fora do grupo:

| Assinado (Ed25519) | Não assinado |
|---|---|
| RiderCard (identidade) | Location updates (12B, 1 Hz) |
| QR codes (integridade) | Route share (só grupo) |
| ClubBadge (membership) | Waypoints (só grupo) |
| Hazard beacon (accountability) | Group control/PIN (efêmero) |
| Ride beacon (autenticidade) | |

**Por que locations não assinam?** Assinatura = +64 bytes por pacote. A 1 Hz × 7 riders, são 448 bytes/segundo desperdiçados. O rideSecret (controle de acesso ao grupo) já garante que só membros injetam posições.

**Regra:** Se pode ser verificado por alguém fora do grupo → assina. Se é efêmero dentro do grupo → rideSecret basta.
