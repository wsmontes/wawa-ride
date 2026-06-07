# WAWA Ride — Definição do MVP

**Versão:** 0.1
**Plataforma:** iOS (exclusivo no MVP)
**Meta:** Aplicativo funcional para um grupo real de motociclistas fazer um passeio com mapa ao vivo e comunicação por voz, sem precisar digitar nada na hora do rolê.

---

## Princípios do MVP

1. **Zero digitação durante o passeio.** O piloto só interage com o app por voz ou toques grandes. A única digitação permitida é no perfil (setup único, em casa).
2. **Aproximação resolve tudo.** Não tem código, link, QR code, convite. Abriu o app perto de outros riders, entrou no grupo.
3. **Mapa é o centro.** Toda a experiência gira em torno do mapa — é o que o piloto vê quando olha (e ele deve olhar o mínimo possível).
4. **Áudio é a interface primária.** O app fala com o piloto. O piloto fala com o app. Voz entre riders é essencial.

---

## Funcionalidades do MVP

### MÓDULO 1 — Perfil do Piloto (setup único, pré-passeio)

- Nome ou apelido
- Foto (opcional)
- Moto (modelo, opcional)
- Um toggle: "Sou líder" / "Sou rider"
- Só isso. Feito em 2 minutos, nunca mais mexe.

### MÓDULO 2 — Entrada por Aproximação (o core diferentão)

```
Fluxo real:
  1. Líder abre o app, aperta "Criar Passeio"
  2. App começa a anunciar o passeio via BLE (MultipeerConnectivity)
  3. Riders chegam no ponto de encontro, abrem o app
  4. App detecta o passeio anunciado — mostra nome do líder e quantos já entraram
  5. Rider aperta "Entrar" (botão enorme, 80% da tela)
  6. Pronto. Tá no mapa junto com todo mundo.

  Sem 4G? Funciona igual. A malha P2P segura.
  Chegou depois que o grupo saiu? O líder continua anunciando em movimento.
    Se o rider alcançar o grupo (BLE range ~50m), entra automaticamente.
  Mais de um passeio por perto? Mostra lista, rider escolhe.
```

- **Tecnologia:** MultipeerConnectivity (Apple) — BLE discovery + WiFi Direct automático
- **Sem servidor.** A descoberta é 100% P2P. Não depende de internet.
- **Persistência:** Uma vez "dentro" do passeio, o rider permanece mesmo se perder sinal. O mesh tenta reconectar. Se sair do alcance total, o app guarda o último estado conhecido.

### MÓDULO 3 — Mapa ao Vivo (o que todo mundo vê)

```
O mapa mostra:
  ┌──────────────────────────────────────────┐
  │  🟢 Líder (Wagner)    72 km/h  →         │
  │  🔵 Pedro             68 km/h  →         │
  │  🔵 Ana               65 km/h  →         │
  │  🟡 Varredor (João)   60 km/h  →         │
  │                                          │
  │  ──── Rota do líder (polyline roxa)      │
  │  📍 Paradas planejadas (ícones)           │
  │  ⚠️ Alertas no mapa (radar, buraco)       │
  └──────────────────────────────────────────┘
```

**Pins no mapa:**
- Cada rider é um pin que mostra direção (seta rotacionada conforme heading), velocidade e cor da função
- Líder = estrela/laranja, Rider = azul, Varredor = amarelo
- Tamanho do pin indica se está parado (maior, pulsando) ou em movimento

**Rota do líder:**
- Modo "improviso" primeiro (MVP): líder grava o rastro ao vivo
- A rota aparece como polyline no mapa de todos
- Riders veem se estão na rota ou desviando (indicador visual simples)

**Updates:**
- Posição a cada ~3 segundos (reta) ou ~1 segundo (curva/detecção de inclinação)
- Firebase quando tem 4G, mesh P2P quando não tem

**Mapa offline:**
- Cache do mapa da região do passeio (baixado antes de sair, opcional)
- Sem cache = mapa cinza onde não tem 4G. Com cache = funciona normal.

### MÓDULO 4 — Comunicação por Voz

**4A — App falando com o piloto (TTS — MVP essencial)**

Alertas de voz em português, disparados automaticamente:

| Situação | O que o app fala | Prioridade |
|----------|-----------------|------------|
| Rider entrou no grupo | "Pedro entrou no passeio" | normal |
| Rider ficou pra trás (+500m) | "Pedro está 500 metros atrás" | normal |
| Desviou da rota (+30m) | "Você saiu da rota" | alta |
| Alerta de perigo marcado | "Radar em 300 metros" | crítica |
| Próxima parada se aproxima | "Posto em 2 quilômetros" | normal |
| Líder parou | "O líder parou" | alta |
| Rider pediu ajuda | "Pedro precisa de ajuda" | crítica (repete 3x) |

**4B — Walkie-talkie entre riders (MVP essencial)**

- Push-to-talk: botão na tela (grande, ~60% da tela, fácil com luva) ou comando de voz
- Áudio transmitido via WebRTC (4G) ou direto via MultipeerConnectivity (sem 4G)
- Sempre grupo inteiro. Não tem canal privado no MVP.
- Funciona como um intercom simplificado

**4C — Comandos de voz (MVP desejável, não bloqueante)**

- "Ok moto" como gatilho
- "Ok moto, marcar radar" → registra alerta de perigo na localização atual
- "Ok moto, marcar buraco" → idem
- "Ok moto, status do grupo" → app fala quem está presente
- "Ok moto, falar com o grupo" → abre canal de voz (alternativa ao PTT)
- Funciona offline (SFSpeechRecognizer on-device)

### MÓDULO 5 — Alertas de Perigo (MVP essencial)

- Qualquer rider marca um perigo: toque grande na tela → botão "Radar", "Buraco", "Polícia", "Óleo", "Animal"
- O alerta aparece NO MAPA como ícone + o app FALA pra todos
- Alertas expiram automaticamente (radar/buraco: 30min, animal: 15min, óleo: 1h)
- Confirmar/Desmentir: rider seguinte pode "confirmar" (ainda tem) ou "limpar" (já passou)

---

## O que NÃO vai no MVP

| Feature | Por que ficou pra depois |
|---------|------------------------|
| Rota planejada (desenhar antes) | MVP é só rastro ao vivo. Desenhar rota no mapa é complexo. |
| Chat por texto | Ninguém digita na moto. Voz resolve. |
| Compartilhar .GPX | Pós-MVP, fácil de adicionar. |
| Estatísticas pós-passeio | Pós-MVP, simples mas não essencial. |
| Modo "alcançar o grupo" | Precisa de navegação turn-by-turn, complexo. |
| Integração com Cardo/Sena | Só quando tiver intercom real pra testar. |
| Android | MVP é iOS. Android vem no próximo ciclo. |
| Servidor TURN próprio | MVP usa servidor TURN público do Google. |
| Autenticação (login/senha) | MVP não tem conta. O perfil é local. Futuro: Sign in with Apple. |

---

## Fluxo completo do MVP — passeio típico

```
PRÉ-PASSEIO (em casa, 2 minutos):
  1. Líder e riders instalam o app
  2. Cada um preenche nome, foto (opcional), moto (opcional)
  3. Líder vai em "Sou líder", outros em "Sou rider"
  4. Líder baixa mapa offline da região (opcional, 1 toque)

PONTO DE ENCONTRO (Posto, 5 minutos antes de sair):
  5. Líder abre app, aperta "Criar Passeio"
  6. Riders abrem o app — veem "Wagner criou um passeio. Entrar?"
  7. Cada rider aperta "Entrar" (botão gigante)
  8. Todos aparecem no mapa uns dos outros

DURANTE O PASSEIO:
  9. Líder começa a pilotar → rastro vira rota visível pra todos
  10. App fala: "Pedro está 300 metros atrás" (se alguém atrasa)
  11. Rider vê buraco → aperta botão de alerta → todos ouvem "Buraco na pista"
  12. "Ok moto, marcar radar" → app registra e avisa todos
  13. Líder aperta PTT: "Galera, próximo posto em 30km, vamos parar"
  14. App fala quando a parada se aproxima

PÓS-PASSEIO:
  15. Líder aperta "Encerrar Passeio"
  16. App mostra resumo simples: distância, tempo, riders
  17. Fim. Dados do passeio ficam salvos localmente.
```

---

## Stack técnica do MVP

| Camada | Tecnologia | Por que |
|--------|-----------|---------|
| UI | SwiftUI + UIKit híbrido | SwiftUI pras telas simples, UIKit pro mapa (MKMapView) |
| Mapa | MapKit (nativo) | Gratuito, sem limite, cache offline nativo |
| GPS | CoreLocation | Melhor stack de localização do mercado |
| Mesh P2P | MultipeerConnectivity | Apple nativo, BLE + WiFi Direct, criptografado |
| Cloud sync | Firebase Firestore | Setup rápido, snapshots em tempo real, offline mode |
| TTS | AVSpeechSynthesizer | Nativo, português, sem dependência |
| Voz P2P | MultipeerConnectivity stream | Voz sem servidor quando sem 4G |
| Voz 4G | WebRTC (GoogleWebRTC) | Padrão da indústria, codec Opus |
| Voz commands | SFSpeechRecognizer | On-device, funciona offline |
| Auth | Nenhuma (perfil local) | Sem fricção no MVP |

---

## Métricas de sucesso do MVP

- [ ] Um grupo de 4+ riders consegue se conectar no ponto de encontro sem ninguém digitar nada
- [ ] Todos veem a posição dos outros no mapa com latência < 3s (com 4G)
- [ ] Alerta de perigo marcado por um rider chega em áudio pros outros em < 2s
- [ ] Walkie-talkie funciona com latência < 500ms (4G) e < 200ms (P2P direto)
- [ ] App continua funcionando (posições + alertas + voz) sem 4G via mesh P2P
- [ ] Bateria: 4h de passeio contínuo consome < 40% da bateria
- [ ] Zero crashes durante um passeio de 4h com 10 riders

---

## Próximos passos (antes de codar)

1. Definir UX detalhada das ~4 telas do MVP (perfil, criar/entrar, mapa, encerrar)
2. Prototipar o fluxo de descoberta por BLE — testar com 2 iPhones reais
3. Definir modelo de dados Firestore + payload do mesh P2P
4. Testar alcance real do MultipeerConnectivity entre duas motos em movimento
