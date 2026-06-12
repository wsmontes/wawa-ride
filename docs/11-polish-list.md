# Lista de Polimento — Fricções e Becos sem Saída

**Build:** `11388ce` — mesh instrumentation + AAC codec + mini route snapshot

---

## ✅ Resolvidos

### ✅ 1. Sheet fecha com qualquer toque no mapa — RESOLVIDO
`onMapTap` agora só fecha sheets `.place`, NÃO sheets `.directions`. Linha 62-64 do UnifiedMapView.

### ✅ 2. Mapa não mostra a rota selecionada — RESOLVIDO
`pendingZoomToRoute` com `edgePadding` bottom 400px mostra a rota na área visível acima do sheet.

### ✅ 3. Sheet sem preview da rota — RESOLVIDO
MKMapSnapshotter adicionado dentro do DirectionsPreviewView. Mostra a rota selecionada dentro do card.

### ✅ 4. GO → transição sem respiro — RESOLVIDO
Transição: fecha sheet → zoom out → 0.6s delay → inicia navegação. Com indicador de chegada ("🎉 Você chegou!").

### ✅ 5. Fim da navegação sem resumo — RESOLVIDO
Card de resumo com distância, duração, velocidade média. Auto-dismiss em 4s.

---

## 🔴 Becos sem saída (bloqueiam o fluxo)

---

## 🟡 Fricções (quebram o ritmo)

### ✅ 6. Overlays competem por espaço — PARCIALMENTE RESOLVIDO
NavigationHUD no topo, RiderHUD embaixo. Search bar escondida durante riding. BLE banner só quando idle sem sheets.

### ✅ 7. Search bar inacessível durante navegação — RESOLVIDO
Botão lupa no canto esquerdo do NavigationHUD. Expande search bar temporariamente.

### ❌ 8. Navegação solo cria ride sem confirmação
Ainda cria "solo-XXXX" silenciosamente. Baixa prioridade — útil para gravação de rota.

### ✅ 9. Sem indicador de "Você chegou" — RESOLVIDO
Banner "🎉 Você chegou!" quando `remainingDistance < 50m`. Auto-dismiss em 3s.

### ✅ 10. RiderHUD mostra "WAWA Ride" fixo — RESOLVIDO
`statusText` agora mostra velocidade, rider count (ex: "72 km/h • 3/5 riders").

---

## 🟢 Micro-interações (polimento visual)

### ✅ 11. PlaceCard → Directions: sheet "pisca" na transição — RESOLVIDO
Com `.animation(.easeInOut(duration: 0.3))` na transição de place→directions.

### 12. Sem animação de pin drop ao fazer long press
⚠️ Pendente. `animatesWhenAdded = true` no MKMarkerAnnotationView cobre o caso básico.

### 13. Nenhum feedback quando a busca não encontra resultados
⚠️ Pendente. Adicionar toast "Nenhum resultado para 'X'".

### 14. Rider pins e search pins têm o mesmo estilo visual
⚠️ Pendente. Rider pins usam RiderAnnotationView customizado, mas search pins e preview pin ainda são laranja.

---

## Prioridade restante

```
HOJE (30min cada):
  13. Toast de busca sem resultados
  14. Diferenciar search pins de rider pins visualmente

OPCIONAL (menor impacto):
  8. Remover/mitigar "solo ride" sem confirmação
  12. Animação de pin drop melhorada
```
