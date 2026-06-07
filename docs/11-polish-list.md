# Lista de Polimento — Fricções e Becos sem Saída

**Build:** `05c1be3` — UnifiedMapView

---

## 🔴 Becos sem saída (bloqueiam o fluxo)

### 1. Sheet fecha com qualquer toque no mapa

**Problema:** `onMapTap` faz `sheetState = nil` para QUALQUER toque no mapa que não seja num pin. Isso inclui:
- Tentar dar pan no mapa atrás do sheet → sheet fecha
- Tentar dar zoom no mapa → sheet fecha se o gesto começar no mapa
- Tocar sem querer → sheet fecha e perde o lugar

**O usuário fica preso:** Abre o PlaceCard, tenta ver o mapa atrás, toca no mapa → puff, some tudo. Tem que buscar de novo.

**Solução:** `onMapTap` só deve fechar sheets `.place`, NÃO sheets `.directions`. E só se o toque não for um gesto de pan/zoom. Ou melhor: usar o comportamento nativo do sheet (drag down pra fechar) e remover o `onMapTap` completamente.

### 2. Mapa não mostra a rota selecionada (coberta pelo sheet)

**Problema:** Quando o usuário seleciona uma rota alternativa no DirectionsPreview, a polyline atualiza no mapa, mas o sheet cobre metade da tela. O usuário NÃO VÊ a rota que selecionou. Precisa fechar o sheet pra ver.

**Solução:** Quando o sheet de direções está aberto, o mapa deve fazer zoom out e se ajustar para mostrar a rota INTEIRA na metade superior (visível) da tela. Usar `MKMapView.setVisibleMapRect(edgePadding:)` com padding no bottom igual à altura do sheet.

### 3. Sheet de direções cobre a polyline, mas não tem preview no próprio sheet

**Problema:** Os apps de mapas mostram um mini-mapa da rota DENTRO do próprio card de direções. O WAWA não tem isso — depende do mapa atrás, que está coberto.

**Solução:** Adicionar um `MKMapSnapshotter` ou um mini `MKMapView` estático dentro do DirectionsPreviewView mostrando a rota selecionada. Não precisa ser interativo — só um preview visual.

### 4. GO → sheet fecha → navegação começa sem transição

**Problema:** Linha 149-150: `sheetState = nil; rideVM.startNavigation(with: route)`. O sheet desaparece instantaneamente e a navegação começa. O usuário não vê a rota completa antes de começar. Não tem aquele momento "visualize the route, then GO".

**Solução:** Ao tocar GO: 1) Fecha o sheet, 2) Dá zoom out pra mostrar a rota inteira no mapa, 3) Espera 0.5s com a rota visível, 4) Depois inicia navegação e zoom in na posição atual. Esse "respiro" de 0.5s faz toda diferença.

### 5. Fim da navegação não tem tela de resumo

**Problema:** Quando o usuário aperta X no NavigationHUD, a navegação simplesmente para. Nada acontece. Não mostra distância percorrida, tempo, velocidade média. O usuário fica sem closure.

**Solução:** Ao parar navegação, mostrar um card de resumo breve: "12 km • 18 min • 68 km/h média" com botão "OK".

---

## 🟡 Fricções (quebram o ritmo)

### 6. Overlays competem por espaço

**Problema:** NavigationHUD (topo) + RiderHUD (baixo) + Map controls (direita) + BLE banner (topo-meio). Em alguns estados, 4 overlays diferentes ocupam a tela.

**Solução:** Regras de prioridade:
- Navegação ativa → NavigationHUD no topo, RiderHUD compacto embaixo (só botão PTT + End)
- Sem navegação → RiderHUD full embaixo
- BLE banner só aparece se NÃO tem sheet aberto e NÃO está navegando

### 7. Search bar e NavigationHUD no mesmo lugar

**Problema:** Quando `isInRide && rideVM.isNavigating`, a search bar esconde (linha 48). Mas e se o usuário quer buscar um posto durante a navegação? Não consegue.

**Solução:** Search bar deve ser acessível via um botão pequeno (ícone de lupa) no canto superior esquerdo durante navegação. Toque → expande search bar temporariamente.

### 8. Navegação solo cria ride automaticamente sem confirmação

**Problema:** `startSoloRide()` é chamado silenciosamente. Cria `AppState.currentRideId = "solo-XXXX"`. O usuário nem sabe que entrou em "modo ride".

**Solução:** Ou remove o conceito de "solo ride" completamente (navegação não precisa de ride), ou mostra um toast rápido: "Navegação iniciada" com opção de desfazer.

### 9. Sem indicador de "Você chegou"

**Problema:** Quando `remainingDistance < 50m`, nada acontece. A navegação continua como se nada tivesse mudado.

**Solução:** Quando `remainingDistance < 50m`:
- NavigationHUD muda para verde com "🎉 Você chegou!"
- Para de dar instruções
- Depois de 3 segundos, mostra card de resumo

### 10. RiderHUD mostra "WAWA Ride" fixo em vez de info útil

**Problema:** `statusText` retorna "WAWA Ride" hardcoded. Não mostra velocidade, distância, riders online — nada.

**Solução:** `statusText` deve mostrar info relevante: "72 km/h • 3 riders • 5.2 km restantes"

---

## 🟢 Micro-interações (polimento visual)

### 11. PlaceCard → Directions: sheet "pisca" na transição

**Problema:** A transição `sheetState = .place → .directions` usa `withAnimation`, mas o sheet host recria o conteúdo. Dependendo do timing, pode dar flicker.

**Solução:** Verificar se `.animation(.snappy, value: sheetState)` no sheet host resolve. Ou usar `.transition(.opacity)` no conteúdo do sheet.

### 12. Sem animação de pin drop ao fazer long press

**Problema:** `animatesWhenAdded = true` só funciona quando o annotation é adicionado. Se o pin já existe e é reposicionado, não anima.

**Solução:** Ao dropar pin, brevemente remover e readicionar o annotation, ou usar `UIView.animate` com scale transform.

### 13. Nenhum feedback quando a busca não encontra resultados

**Problema:** Se `MKLocalSearch` retorna vazio, nada acontece. O usuário digita, aperta buscar, e... silêncio.

**Solução:** Mostrar toast ou alert sutil: "Nenhum resultado para 'X'".

### 14. Rider pins e search pins têm o mesmo estilo visual

**Problema:** Ambos usam MKMarkerAnnotationView laranja. O usuário não sabe diferenciar "pin de busca" de "rider".

**Solução:** Rider pins = custom RiderAnnotationView (já existe, cor por role). Search pins = MKMarkerAnnotationView vermelho. Preview pin = azul.

---

## Prioridade de ataque

```
HOJE (1-2h cada):
  1. Remover onMapTap dismiss do sheet de direções (só fecha place)
  2. Zoom out ao selecionar rota (mostrar rota na área visível)
  4. Transição GO → zoom out → navegação (0.5s respiro)

AMANHÃ (30min-1h cada):
  3. Mini snapshot da rota no DirectionsPreview
  5. Card de resumo ao fim da navegação
  6. Regras de prioridade de overlays
  9. Indicador de chegada

DEPOIS:
  7. Lupa de busca durante navegação
  8. Remover "solo ride" — navegação não precisa de ride
  10. RiderHUD com info real
  11-14. Micro-interações e polimento visual
