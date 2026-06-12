# O que falta — Avaliação honesta

**Build:** `1c1e2ce`

O WAWA Ride tem uma base de mapas sólida (busca, direções, navegação, PlaceCard).
Mas o que faz ele ser um **rider app** — a razão de existir — ainda não foi validado.

---

## ✅ Construído e funcional

| Camada | Status |
|--------|--------|
| App de mapas (busca, direções, navegação, PlaceCard, rotas) | ✅ 80% |
| UI unificada (UnifiedMapView + overlays) | ✅ |
| Estrutura P2P (MultipeerConnectivity) | ✅ Código pronto |
| Voz/TTS (AVSpeechSynthesizer, comandos de voz) | ✅ Código pronto |
| Armazenamento local (SQLite/GRDB) | ✅ |
| Salas de comunicação | ✅ Código pronto |

---

## ❌ NÃO testado nem validado

### 🔴 O CORE DO APP — nunca rodou de verdade

| # | Item | Estado |
|---|------|--------|
| 1 | **Descoberta BLE entre 2 iPhones** | ❌ Nunca testado |
| 2 | **2+ riders no mesmo passeio, vendo pins no mapa** | ❌ Nunca testado |
| 3 | **Walkie-talkie entre 2 dispositivos** | ❌ Nunca testado |
| 4 | **Mensagem de áudio assíncrona (grava → mesh → toca)** | ❌ Nunca testado |
| 5 | **Alerta de perigo via mesh (um marca, todos veem/ouvem)** | ❌ Nunca testado |
| 6 | **Mesh offline (sem 4G, só BLE/WiFi Direct)** | ❌ Nunca testado |
| 7 | **Store-and-forward (A → B → C quando A e C não se alcançam)** | ❌ Nunca testado |
| 8 | **Reconexão automática após perda de sinal** | ❌ Nunca testado |

**Resumo: A premissa central do app — "abrir perto de riders, entrar no grupo, se ver no mapa, conversar" — nunca foi executada de ponta a ponta.**

### 🟡 Funcionalidades rider INCOMPLETAS

| # | Item | Estado |
|---|------|--------|
| 9 | **Opus codec placeholder** — envia PCM sem compressão (8x maior) | ⚠️ Funciona, mas consome 8x mais bateria/banda |
| 10 | **TTS não testado com vento/capacete** — as vozes são audíveis? | ⚠️ Nunca testado em condições reais |
| 11 | **Bateria em passeio real** — 4h de GPS + BLE + áudio? | ⚠️ Nunca medido |
| 12 | **Background GPS** — iOS mata o app depois de 30min? | ⚠️ Nunca testado em passeio longo |
| 13 | **RiderHUD não mostra dados do grupo** — riders online, posição do varredor, distância entre riders | ⚠️ Código existe, não integrado na UI |

### 🟢 Funcionalidades de passeio AUSENTES

| # | Item | Status |
|---|------|--------|
| 14 | **Líder/piloto parado** — notificação quando alguém para por mais de 2min | ✅ Implementado (build 1e2d2a7) |
| 15 | **Distância entre riders** — "Pedro está 500m atrás" no HUD | ✅ Implementado (build 1e2d2a7) |
| 16 | **Varredor confirma grupo** — botão "Todos juntos" / "Alguém ficou" | ✅ Implementado (build 6b7f94e) |
| 17 | **Rota do líder visível para followers** — polyline da rota que o líder está fazendo | ✅ Código existe (mesh route payloads) |
| 18 | **Resumo pós-passeio real** — distância, altimetria, velocidades (não hardcoded como estava) | ✅ Implementado (endRide calcula dados reais) |
| 19 | **Compartilhar rota pós-passeio** — exportar .GPX do passeio completo | ✅ GPX export + mesh share |

---

## O que atacar AGORA

A ordem certa é: **validar → corrigir → completar → polir.**

### Imediato (hoje) — VALIDAR o core

**Pegar 2 iPhones e testar:**

1. **Descoberta BLE** — iPhone A cria passeio. iPhone B abre o app. B vê o passeio? Em quanto tempo? A que distância?

2. **Mesh connection** — B aperta ENTRAR. A sessão MCSession conecta? Os dois se veem no mapa?

3. **Walkie-talkie** — A aperta FALAR. B ouve? Latência? Qualidade?

4. **Alerta de perigo** — A marca radar. B vê no mapa? Ouve o TTS?

**Sem isso, tudo que construímos é teórico.** O BLE pode não funcionar entre motos (metal, vibração, distância). O alcance pode ser 5m em vez de 50m. O áudio pode ser inaudível.

### Esta semana — CORRIGIR o que a validação revelar

Os bugs que aparecerem no teste real vão ditar as prioridades.

### Próxima semana — COMPLETAR o rider app

Depois de validado o core:
- Integrar libopus real (codec placeholder → Opus de verdade)
- HUD com dados do grupo (distância entre riders, status)
- Fluxo de varredor (confirma grupo completo)
- Resumo pós-passeio com dados reais

---

## Resumo

```
Construído:    ████████████████░░░░  ~80% do código escrito
Validado:      ░░░░░░░░░░░░░░░░░░░░  ~0% testado com 2+ dispositivos
Funcional:     ████████░░░░░░░░░░░░  ~40% realmente funcional
```

**O gap não é mais código. É validação.** Precisamos de 2 iPhones, 2 pessoas, e 1 hora de teste real.
