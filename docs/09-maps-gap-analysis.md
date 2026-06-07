# WAWA Ride vs Google Maps / Apple Maps — Gap Analysis

## Metodologia

Análise comparativa do WAWA Ride (commit `35018cc`) contra os padrões de UX do **Google Maps iOS** e **Apple Maps iOS**, focando em: mapa, busca, direções, navegação, interações gestuais, e informação contextual.

---

## 1. Abertura do App

| Feature | Google Maps | Apple Maps | WAWA Ride |
|---------|-------------|------------|-----------|
| Tela inicial | Mapa fullscreen | Mapa fullscreen | TabView com 4 abas |
| Search bar default | Topo, colapsada, visível | Bottom sheet card, visível | Topo, visível, vazia |
| Sugestões ao abrir | "Explore nearby" + recentes | Favorites row + "Search Maps" | Nada — campo vazio |
| Current location | Botão flutuante à direita | Ícone no topo direito | ✅ MKUserTrackingButton |
| Map type toggle | Layers button (direita) | Button (topo direito) | ❌ Inexistente |
| Profile/account | Avatar topo direito | Avatar topo direito | Aba Perfil separada |

**Gaps críticos:**
- ❌ Sem sugestões ao abrir o app (recentes, favoritos, "perto de você")
- ❌ Sem toggle de tipo de mapa
- ❌ Search bar vazia — não mostra nada até o usuário digitar

---

## 2. Busca e Descoberta

### 2.1 Comportamento da Search Bar

| Feature | Google Maps | Apple Maps | WAWA Ride |
|---------|-------------|------------|-----------|
| Estado padrão | "Search here" | Card "Search Maps" | TextField vazio "Buscar lugar ou endereço" |
| Ao focar | Keyboard + recent searches + saved | Full search UI slides up | Só keyboard |
| Recent searches | Lista com ícones de histórico | Lista com ícones | ❌ Não existe |
| Autocomplete | Lista dropdown abaixo do campo | Lista abaixo do campo | ✅ MKLocalSearchCompleter |
| "Nearby" categories | Restaurants, Gas, Coffee, etc | Restaurants, Gas Stations, etc | ❌ Não existe |
| Favorites | Lista de salvos | Lista de favoritos | ❌ Não existe |

**Gaps críticos:**
- ❌ Sem recent searches — toda busca começa do zero
- ❌ Sem categorias "Perto de você" (posto, restaurante, etc)
- ❌ Sem favorites/saved places
- ⚠️ Autocomplete existe mas não mostra distância nem ícone de categoria

### 2.2 Resultado da Busca

| Feature | Ambos Maps | WAWA Ride |
|---------|-----------|-----------|
| Após selecionar | Place card desliza de baixo | Pin cai no mapa |
| Place card contém | Foto, nome, nota, endereço, telefone, horário, site | Nada — só o pin |
| Botão "Directions" | Sempre visível no place card | ❌ Não existe |
| Botão "Save" | Sempre visível | ❌ Não existe |
| Botão "Share" | Sempre visível | ❌ Não existe |
| Mapa ajusta zoom | Sim — centraliza e dá zoom no lugar | ❌ Não — fica no zoom atual |
| Vários resultados | Lista + mapa mostra todos com números | Apenas o último pin |

**Gaps críticos:**
- ❌ Sem place card — zero informação contextual sobre o lugar
- ❌ Sem botão "Directions" a partir do resultado
- ❌ Sem ajuste de zoom ao selecionar resultado
- ❌ Acumula pins sem limpar os anteriores

---

## 3. Direções e Roteamento

### 3.1 Fluxo de Direções

| Feature | Ambos Maps | WAWA Ride |
|---------|-----------|-----------|
| Origem | "Your Location" (default, editável) | ❌ Não existe campo origem |
| Destino | Search, tap on map, saved place | Pin ou busca (implícito) |
| Transport picker | Drive / Walk / Transit / Cycle / Ride | ❌ Só .automobile (hardcoded) |
| Route alternatives | 2-3 rotas com tempo e distância | ⚠️ RouteCreatorView tem, mas não no ExploreMap |
| Route preview | Linha azul + ETA + distância no card inferior | ❌ Só polyline, sem card |
| "Start" button | Botão "GO" ou "Start" gigante | ❌ Não existe |
| Step list | Lista de passos antes de iniciar | ❌ Não existe |

**Gaps críticos:**
- ❌ Sem campo "De" (origem) — sempre assume current location
- ❌ Sem transport picker (moto = .automobile, mas poderia ter opção)
- ❌ Sem card de preview com ETA e distância
- ❌ Sem botão "GO" para iniciar navegação
- ❌ Sem lista de passos antes de iniciar

### 3.2 RouteCreatorView (planejamento de rota)

| Feature | Status |
|---------|--------|
| Adicionar waypoints | ✅ Long press + busca |
| Preview da rota | ✅ Polylines com MKDirections |
| Alternativas | ✅ Sheet com opções |
| Distância/ETA total | ⚠️ Só por segmento |
| Salvar rota | ✅ |
| Reordenar waypoints | ❌ Drag não implementado |
| Remover waypoint específico | ❌ Só undo último |
| Cálculo de rota de volta | ❌ Não existe |

---

## 4. Navegação (Navigation Mode)

### 4.1 Tela de Navegação

| Feature | Google Maps | Apple Maps | WAWA Ride |
|---------|-------------|------------|-----------|
| Barra superior | ETA + distância + hora chegada | ETA + distância + hora (fundo verde) | Status text na bottom bar |
| Instrução atual | Faixa verde no topo com seta | Faixa no topo | ❌ Não visível (só TTS) |
| Próxima manobra | Preview da próxima curva | Preview abaixo da instrução | ❌ Não existe |
| Lane guidance | Setas de faixa | Setas de faixa | ❌ Não aplicável (moto) |
| Overview button | Botão para ver rota completa | Botão para ver overview | ❌ Não existe |
| Exit button | "X" ou "End" | "End" com confirmação | ✅ Botão X (sem confirmação) |
| Speed limit | Mostra limite de velocidade | Mostra limite | ❌ Não existe |
| Current speed | Mostra velocidade atual | Mostra velocidade | ✅ speed na status bar |

**Gaps críticos:**
- ❌ Instrução atual NÃO é visível na tela — só TTS
- ❌ Sem preview da próxima manobra
- ❌ Sem botão overview (ver rota completa durante navegação)
- ❌ Sem ETA/hora de chegada visível
- ❌ Barra de status da navegação no lugar errado (embaixo, não em cima como padrão)

### 4.2 Pós-Navegação

| Feature | Ambos Maps | WAWA Ride |
|---------|-----------|-----------|
| Summary screen | Distância, tempo, velocidade média, calorias | ❌ Não existe |
| Share trip | Botão share | ❌ Não existe |
| Save route | Add to saved | ⚠️ Salva no banco mas sem tela |
| Rate/review place | Stars | ❌ Não se aplica |

---

## 5. Interações com o Mapa

### 5.1 Gestos

| Gesto | Ambos Maps | WAWA Ride |
|-------|-----------|-----------|
| Tap no mapa | Seleciona lugar → mostra place card | ⚠️ Só callout básico no pin |
| Tap em lugar vazio | Deseleciona | ❌ Não faz nada |
| Double tap | Zoom in | ✅ Padrão MapKit |
| Two finger tap | Zoom out | ✅ Padrão MapKit |
| Two finger drag | Tilt/3D | ✅ isPitchEnabled |
| Long press | Drop pin → place card aparece | ✅ Drop pin (sem place card) |
| Pinch | Zoom | ✅ Padrão |
| Rotate | Rotaciona mapa | ✅ isRotateEnabled |

**Gaps:**
- ❌ Tap em lugar vazio não deseleciona
- ❌ Pin dropped não mostra place card

### 5.2 Elementos Visuais no Mapa

| Elemento | Status WAWA |
|----------|-------------|
| Compass | ✅ showsCompass |
| Scale | ✅ showsScale |
| Traffic | ✅ showsTraffic (sem toggle visível) |
| 3D buildings | ⚠️ isPitchEnabled mas sem toggle |
| User location pulse | ✅ Padrão MapKit |
| POI icons | ✅ Padrão MapKit |

---

## 6. Padrões de UI Inexistente

### 6.1 Bottom Sheet / Slide-up Panel

Ambos Google Maps e Apple Maps usam intensivamente um **bottom sheet** que desliza de baixo. Este é o padrão de interação MAIS IMPORTANTE que está ausente no WAWA Ride.

Usos do bottom sheet nos Maps:
```
┌──────────────────────────┐
│                          │
│        MAPA              │
│                          │
│  ┌────────────────────┐  │  ← Bottom sheet (deslizável)
│  │ Nome do lugar      │  │
│  │ ⭐ 4.5 (200)        │  │
│  │ 📍 Endereço         │  │
│  │ 🕐 Aberto até 22h   │  │
│  │ 📞 Telefone         │  │
│  │                     │  │
│  │ [  Directions  ]    │  │  ← Botão gigante
│  │ [ Save ] [ Share ]  │  │
│  └────────────────────┘  │
└──────────────────────────┘
```

O WAWA Ride **nunca usa bottom sheet** para nada. Isso é o maior gap de UX.

### 6.2 Pull-up Handle / Detents

O bottom sheet dos Maps tem "detents" (posições de parada):
- **Mini:** Só o nome do lugar + directions button
- **Meio:** Place details (horário, telefone, fotos)
- **Cheio:** Reviews, mais fotos, informações completas

WAWA Ride: ❌ Zero implementação de detents interativos.

### 6.3 Search Bar com Estados

```
APPLE MAPS SEARCH BAR:
  Estado 1 (fechado):  ┌──────────────────────────────┐
                       │  🔍  Search Maps             │
                       └──────────────────────────────┘
  
  Estado 2 (aberto):   ┌──────────────────────────────┐
                       │  🔍  [___________________]   │
                       │  ⏱️  Recentes                │
                       │  ⭐  Favoritos                │
                       │  🍽️  Restaurants            │
                       │  ⛽  Gas Stations            │
                       └──────────────────────────────┘

WAWA RIDE SEARCH BAR:
  Sempre:               ┌──────────────────────────────┐
                       │  🔍  Buscar lugar ou endereço │
                       └──────────────────────────────┘
                       (nada abaixo até digitar)
```

### 6.4 Floating Action Buttons

Google Maps tem:
- **Re-center button** (flutuante, direita)
- **Directions button** (flutuante, direita, abaixo do re-center)

Apple Maps tem:
- **Info button** (topo direito) → map type, report issue
- **Current location** (topo direito)

WAWA Ride tem:
- ✅ MKUserTrackingButton (nativo, pequeno, fácil de não ver)
- ❌ Sem directions FAB
- ❌ Sem map type toggle visível

---

## 7. Resumo — Tudo que está faltando

### 🔴 Bloqueia funcionalidade (MVP deve ter)

1. **Place card / Bottom sheet** — Ao buscar/tocar lugar, mostrar info + botão "Traçar rota"
2. **Botão "Directions"** — A partir de qualquer pin, iniciar fluxo de direções
3. **"De" / "Para" na busca** — Origem default = current location, destino = busca
4. **Preview de rota com ETA** — Antes de iniciar navegação, ver distância, tempo, alternativas
5. **Instrução visível na tela** — Durante navegação, a instrução atual DEVE ser visível (não só TTS)
6. **Search bar com estados** — Recentes, favoritos, categorias "perto de você"
7. **Zoom ao selecionar resultado** — Mapa ajusta para mostrar o lugar

### 🟡 Degrada experiência (MVP deveria ter)

8. **Map type toggle** — Botão visível para alternar Standard/Satellite/Hybrid
9. **Recenter button proeminente** — Fácil de achar e apertar com luva
10. **End navigation summary** — Tela pós-chegada com stats
11. **Swipe between search results** — Navegar entre múltiplos resultados
12. **Drag to reorder waypoints** — No RouteCreator
13. **Share ETA / route** — Compartilhar com outros riders
14. **Step list antes de iniciar** — Ver todos os passos da rota

### 🟢 Polimento (pós-MVP)

15. **Pin drop animation** — Animação de queda do pin
16. **Haptics on interactions** — Feedback tátil em ações do mapa
17. **3D buildings toggle** — Ativar/desativar prédios 3D
18. **Map style persistence** — Lembrar tipo de mapa preferido
19. **Accessibility labels** — VoiceOver nos pins e controles
20. **Dynamic Island integration** — Navegação no Dynamic Island

---

## 8. Plano de Implementação (ordem de prioridade)

### Sprint 1: Place Card + Directions Flow
1. Criar `PlaceCardView` — bottom sheet que aparece ao selecionar lugar
2. Adicionar botão "Traçar Rota" no place card
3. Criar `DirectionsPreviewView` — card inferior com ETA, distância, alternativas
4. Botão "GO" para iniciar navegação
5. Barra de instrução visível durante navegação

### Sprint 2: Search UX
6. Estados da search bar: vazia → com sugestões → com resultados
7. Histórico de buscas recentes (LocalStore)
8. Categorias "Perto de você" (Posto, Restaurante, etc.)
9. Zoom ao selecionar resultado

### Sprint 3: Polimento do Mapa
10. Map type toggle visível
11. Recenter button grande
12. Pin drop animation
13. Haptics
14. Step list antes de iniciar

### Sprint 4: Pós-Navegação
15. Summary screen
16. Share route/ETA
17. Drag to reorder waypoints
