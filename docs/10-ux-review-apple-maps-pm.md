# UX Review — Ex-Apple Maps PM + UX Team

**Produto:** WAWA Ride  
**Build:** `1c68d10`  
**Revisores:** Ex-Apple Maps Product Manager, UX Lead, iOS Interaction Designer  
**Data:** 2026-06-07

---

## Sumário Executivo

O WAWA Ride está no caminho certo. A estrutura base (TabView, mapa standalone, PlaceCard, Directions, busca com autocomplete) existe. Mas a execução está entre 30-40% do que precisa para ser um app de mapas "fully functional". O gap principal não é técnico — é de **informação visual, hierarquia de ações, e micro-interações**.

Vamos ser diretos. Aqui está o que precisa mudar.

---

## 1. Tela do Mapa (ExploreMapView)

### 1.1 O que está bom
- Mapa ocupa a tela toda ✅
- Search bar no topo ✅
- Autocomplete funcional ✅
- Pin no mapa ao buscar ✅

### 1.2 O que está errado

**A. O mapa não tem informação suficiente**

Quando você abre Google Maps ou Apple Maps, o mapa está VIVO. Mostra:
- Nomes de ruas legíveis
- Ícones de POI (restaurantes, postos, hotéis) visíveis
- Trânsito (se ativado)
- Seu ponto azul pulsando

O WAWA Ride mostra... um mapa escuro vazio. `mutedStandard` é bom para navegação noturna, mas ruim para descoberta.

**Recomendação:** 
- Default para `.standard` durante o dia
- Mostrar POIs nativos (`mapView.showsPointsOfInterest = true` — está desabilitado no `mutedStandard`)
- Toggle de tipo de mapa VISÍVEL no mapa (não escondido no código)

**B. Os botões flutuantes estão no lugar errado**

```
ATUAL:                           GOOGLE MAPS / APPLE MAPS:
┌──────────────────────┐         ┌──────────────────────┐
│                      │         │            ┌──┐      │
│                      │         │            │📍│      │ ← Recenter
│                      │         │            └──┘      │
│                      │         │            ┌──┐      │
│                      │         │            │🧭│      │ ← Directions
│                      │         │            └──┘      │
│  [Criar Passeio]     │         │                      │
└──────────────────────┘         └──────────────────────┘
```

Os botões no WAWA estão na BORDA INFERIOR, horizontalmente. Isso funciona para os apps de navegação, mas:
- Google Maps tem botões flutuantes na borda DIREITA (vertical)
- Apple Maps tem o tracking button no canto superior direito

**Recomendação:** Colocar os botões de ação rápida na borda DIREITA, flutuantes, empilhados verticalmente. Exatamente como Google Maps. O tracking button já está lá (nativo do MapKit). Adicionar:
- Botão "Directions" (se tiver pin selecionado)
- Botão "Recenter" (maior, mais fácil com luva)
- Botão de tipo de mapa (layers)

**C. A barra de busca não está integrada com o mapa**

Em ambos Maps, a barra de busca "desliza" pra cima e vira uma tela de busca completa quando você toca nela. O mapa fica em segundo plano com um overlay translúcido.

No WAWA, a barra expande inline e os resultados aparecem num dropdown flutuante. Isso funciona, mas não é o padrão da plataforma.

**Recomendação:** Quando a search bar é focada, aplicar um overlay escuro semi-transparente sobre o mapa e mostrar os resultados numa lista que ocupa a metade inferior da tela (estilo Apple Maps). O mapa deve "afundar" visualmente.

---

## 2. Search & Discovery

### 2.1 O que está bom
- Autocomplete em tempo real ✅
- Categorias rápidas quando vazio ✅
- Ícones por categoria ✅
- Filtro por proximidade (região do mapa) ✅

### 2.2 O que está errado

**A. Os resultados do autocomplete não mostram distância**

Google Maps mostra "3.2 km" ao lado de cada resultado. WAWA mostra só título + subtítulo + ícone.

**Recomendação:** Adicionar distância aproximada em cada resultado, calculada a partir da coordenada central da região visível do mapa. Não precisa ser precisa — é uma estimativa visual. Ex: "2.4 km", "8.1 km".

**B. Não tem pesquisa por voz (ditado)**

Apple Maps e Google Maps têm um ícone de microfone na barra de busca.

**Recomendação:** Adicionar botão de microfone na search bar que ativa o ditado nativo (`SFSpeechRecognizer` já está integrado no app via VoiceCommandListener). Toque → fala "Posto Ipiranga" → busca.

**C. As categorias rápidas são estáticas**

Apple Maps mostra categorias dinâmicas baseadas no que está popular/próximo. "Posto" pode não ser relevante se não tem nenhum por perto.

**Recomendação:** Ok para MVP. Baixa prioridade. Fica para depois.

**D. Histórico de buscas não persiste**

Toda vez que o usuário abre o app, o histórico está vazio. Ele precisa digitar "Posto Ipiranga" de novo.

**Recomendação:** Salvar as últimas 10 buscas em UserDefaults e mostrá-las como sugestão ao focar a search bar (antes de digitar qualquer coisa). Isso é trivial de implementar.

---

## 3. Place Card (Bottom Sheet)

### 3.1 O que está bom
- Aparece ao selecionar resultado ✅
- Drag handle ✅
- Botão "Traçar Rota" com destaque ✅
- Copiar coordenadas ✅
- Abrir no Apple Maps ✅

### 3.2 O que está errado

**A. O card é genérico — não mostra informações do lugar**

Google Maps place card mostra:
- Galeria de fotos do lugar
- Nota (⭐ 4.5)
- Horário de funcionamento (🕐 Aberto até 22h)
- Telefone
- Website
- Botão "Ligar", "Site", "Salvar", "Compartilhar"

WAWA place card mostra:
- Nome
- Endereço
- Distância
- Traçar Rota
- Copiar / Abrir no Maps

O WAWA NÃO USA os dados que o `MKMapItem` já retorna:
- `phoneNumber` → nem mostramos (PlaceCardItem tem o campo mas não é exibido!)
- `url` → nem mostramos
- `placemark` não tem horários, mas poderíamos mostrar categorias

**Recomendação:** Adicionar ao PlaceCard:
- Telefone (se disponível) com botão "Ligar"
- Website (se disponível) com botão "Abrir"
- Placemark details: cidade, estado, CEP (o MKPlacemark tem tudo isso)

**B. A transição de abertura é abrupta**

O card simplesmente "aparece" (`.sheet`). Apple Maps faz o card DESLIZAR de baixo com animação fluida, e o mapa simultaneamente faz um leve ajuste de enquadramento.

**Recomendação:** Usar `.matchedGeometryEffect` ou animação customizada para o card. Ou no mínimo, garantir que o mapa faça zoom no lugar quando o card abre (atualmente o zoom só acontece na busca, não no long press).

**C. O card não tem interação com o mapa**

Quando você arrasta o card no Apple Maps, o mapa se ajusta dinamicamente:
- Meio aberto → mapa mostra o lugar + seu entorno
- Totalmente aberto → mapa fica menor, mostra mais detalhes

No WAWA, o card é um sheet fixo que não interage com o mapa.

**Recomendação:** Para MVP, usar `.presentationDetents([.medium, .large])` com `.interactive` (que já é o default) e vincular o detent ao estado. Adicionar um callback `onDetentChange` que ajusta o mapa.

---

## 4. Directions Flow (Preview de Rota)

### 4.1 O que está bom
- Múltiplas rotas com seleção ✅
- ETA e distância por rota ✅
- Botão GO verde ✅
- Loading state ✅
- Error state com retry ✅

### 4.2 O que está errado

**A. O preview é só texto — não mostra a rota NO MAPA**

Este é o gap MAIS CRÍTICO do fluxo de direções. Quando você seleciona uma rota alternativa no Apple Maps, o MAPA imediatamente mostra a polyline daquela rota. Você VÊ a diferença entre as rotas no mapa.

No WAWA, você seleciona uma rota na lista, mas o mapa atrás do sheet está PARADO, mostrando a rota anterior (ou nada). A polyline não atualiza quando você seleciona uma alternativa.

**Recomendação:** O `DirectionsPreviewView` precisa se comunicar com o mapa atrás dele. Quando o usuário seleciona uma rota diferente, o mapa deve atualizar a polyline. Isso requer que o `DirectionsPreviewView` receba um binding ou callback para o mapa, ou que o `ExploreMapView` observe as mudanças do view model.

**B. A lista de passos (step list) não existe**

Antes de apertar GO no Apple Maps, você pode deslizar o card pra cima e ver TODOS os passos da rota: "1. Siga pela BR-101 por 5km", "2. Vire à direita na Rua X", etc.

No WAWA, não tem step list. Você só vê distância e ETA.

**Recomendação:** Adicionar uma seção "Passos" abaixo das rotas no DirectionsPreview, mostrando um resumo dos primeiros 3-4 passos com "Ver todos os N passos" para expandir.

**C. O fluxo de transição é quebrado**

1. Abre PlaceCard → sheet 1
2. Toca "Traçar Rota" → sheet 1 fecha → delay → sheet 2 abre

Isso cria um flash do mapa entre os sheets. Apple Maps faz uma transição contínua: o PlaceCard se transforma no DirectionsPreview.

**Recomendação:** Usar uma única sheet com navegação interna (NavigationStack dentro do sheet) em vez de fechar e abrir outra. Ou usar `.sheet(item:)` com transição customizada.

---

## 5. RideActiveView (Mapa Durante o Passeio)

### 5.1 O que está bom
- Mapa fullscreen ✅
- Botões grandes (Perigo, FALAR, Rota) ✅
- Status bar com velocidade ✅
- Banner de navegação verde ✅

### 5.2 O que está errado

**A. O top bar e o bottom bar competem por atenção**

```
┌──────────────────────────┐
│ Serra do Rio   🟢4  ✉️ ✕ │  ← Top bar
│ 3 de 4 online            │
│ ┌──────────────────────┐ │
│ │ ↗️ Vire à direita... │ │  ← Nav banner (quando navegando)
│ │    200m              │ │
│ └──────────────────────┘ │
│                          │
│         MAPA             │
│                          │
│  72 km/h • 5.2 km • 8min │  ← Bottom status
│  ┌─────┐ ┌──────┐ ┌────┐│
│  │Perigo│ │FALAR │ │Rota││  ← Bottom buttons
│  └─────┘ └──────┘ └────┘│
└──────────────────────────┘
```

Temos TRÊS barras de informação (topo, meio, baixo) mais botões. É ruído visual demais para um piloto em movimento.

**Recomendação:** Consolidar. Quando estiver navegando, o banner verde DEVE ser a barra principal. A barra de status inferior pode mostrar só velocidade + distância restante. O top bar pode ser mais compacto (só nome do passeio + contagem de riders).

**B. O botão FALAR não tem indicador claro de estado**

Quando o piloto aperta FALAR, o botão muda de cor e tamanho. Mas com luva, vibração na moto, e sol na tela, isso é muito sutil.

**Recomendação:** Adicionar um indicador de áudio MAIS VISÍVEL:
- O botão FALAR deve pulsar quando ativo
- A borda da tela deve ter um glow verde/vermelho sutil quando o canal está aberto
- O texto "FALANDO" deve ser maior e em negrito
- Considerar um indicador estilo "walkie-talkie" com ondas de áudio animadas

**C. Os botões inferiores não são acessíveis em movimento**

Três botões lado a lado (70pt cada) é difícil de acertar com precisão quando a moto está vibrando. A taxa de erro de toque em movimento a 80 km/h é alta.

**Recomendação:** 
- Aumentar os botões para 90pt mínimo
- Espaçamento de 24pt entre eles
- Área de toque maior que o visual (padding invisível)
- O botão central (FALAR — o mais usado) deve ser 30% maior que os laterais
- Considerar gestos em vez de toques: swipe up = falar, swipe left = perigo (modo "moto" com gestos simplificados)

---

## 6. Navegação

### 6.1 O que está bom
- Banner verde com instrução ✅
- TTS funcional ✅
- Rerouting ao desviar ✅

### 6.2 O que está errado

**A. A instrução usa texto bruto do MKRoute.Step**

`MKRoute.Step.instructions` retorna coisas como: "Turn right onto Avenida Paulista". Em inglês. No iOS pt-BR.

O MapKit LOCALIZA as instruções se o device estiver em pt-BR, mas o texto pode ser verboso ou confuso em alta velocidade.

**Recomendação:** Processar o texto do step para ser mais conciso:
- "Siga pela BR-101 por 5 km" → "BR-101, 5 km"
- "Vire à direita na Rua XV de Novembro" → "Direita na XV de Novembro"
- Manter o texto original como fallback se a concisão não for possível

**B. Não mostra overview da rota durante navegação**

Apple Maps tem um botão "Overview" que mostra a rota inteira. Google Maps tem uma barra no topo que, ao tocar, mostra o overview.

WAWA não tem como ver a rota completa durante a navegação. O piloto pode querer saber "quanto falta até o destino" ou "qual é a próxima cidade".

**Recomendação:** Adicionar um gesto de pinça (zoom out) durante navegação que automaticamente mostra a rota completa. Ou um botão pequeno no canto do mapa.

**C. Não tem indicação de "chegada"**

Quando você chega no Apple Maps, tem uma animação, um card de "Você chegou", e opções. No WAWA, você simplesmente... chega. Nada acontece visualmente.

**Recomendação:** Quando `remainingDistance < 50m` e `currentStepIndex == lastStep`:
- Banner verde muda para "🎉 Você chegou!"
- Card de resumo aparece (distância, tempo, velocidade média)
- Opção de "Compartilhar" ou "Salvar rota"

---

## 7. Gestos e Micro-Interações

### 7.1 O que falta completamente

| Interação | Google/Apple Maps | WAWA Ride |
|-----------|-------------------|-----------|
| Tap duplo + arrastar (zoom) | ✅ | ✅ (MapKit nativo) |
| Dois dedos + arrastar (tilt/3D) | ✅ | ✅ |
| Pinça (zoom) | ✅ | ✅ |
| Tap em lugar vazio | Deseleciona | ⚠️ Só se tiver sheet aberto |
| Swipe no card | Muda detent | ✅ (nativo sheet) |
| Tap + hold + drag (medir distância) | ✅ Google Maps | ❌ |
| Haptic em interação | ✅ sutil | ❌ |
| Animação de pin drop | ✅ | ⚠️ `animatesWhenAdded = true` mas sem curva |
| spring animation no card | ✅ | ✅ (nativo sheet) |

**Prioridade para o MVP:**
1. Tap no mapa vazio → deselecionar e fechar qualquer sheet
2. Haptics em ações de toque nos botões
3. Animação de pin drop melhorada

---

## 8. Arquitetura de Informação (TabView)

### 8.1 O que está bom
- 4 abas: Mapa, Rotas, Passeios, Perfil ✅
- Mapa como aba principal ✅

### 8.2 O que está errado

**A. As abas "Rotas" e "Passeios" são vazias no primeiro uso**

Clássico problema de empty state. As telas mostram "Nenhuma rota salva" e "Nenhum passeio ainda" — o que é correto, mas não ajuda o usuário.

**Recomendação:** Transformar os empty states em CTAs (calls-to-action):
- "Nenhuma rota salva" → mostrar cards de exemplo "Como criar sua primeira rota"
- "Nenhum passeio ainda" → botão gigante "Criar Primeiro Passeio"

**B. A aba Perfil é subutilizada**

Tem só nome + moto + função. Poderia ter:
- Estatísticas: "3 passeios, 450 km percorridos"
- Conquistas: "5 alertas de perigo reportados"
- Configurações: "Voz: Ligada", "Unidade: km", etc.

Mas isso é pós-MVP.

---

## 9. Lista Priorizada de Ações

### 🚨 Bloqueadores — precisam ser resolvidos ANTES do MVP

1. **Rota no mapa durante seleção de alternativa** — A polyline precisa atualizar no mapa quando o usuário seleciona uma rota diferente no DirectionsPreview. Sem isso, o fluxo de direções é quebrado.

2. **Transição PlaceCard → Directions sem flicker** — Uma única sheet com navegação interna, em vez de fechar e abrir outra.

3. **PlaceCard com informações do lugar** — Adicionar telefone, website, endereço completo. Os dados já estão no `MKMapItem`, só não estão sendo exibidos.

### ⚡ Alta prioridade — próximos 3 dias

4. **Resultados de busca com distância** — Mostrar "X km" em cada resultado do autocomplete.

5. **Histórico de buscas** — Últimas 10 buscas salvas em UserDefaults, mostradas na search bar vazia.

6. **Step list no DirectionsPreview** — Mostrar resumo dos primeiros passos antes do GO.

7. **Indicador de áudio mais visível** — Glow na borda da tela quando PTT ativo.

8. **Botão de tipo de mapa visível** — Floating action button para alternar Standard/Satellite/Hybrid.

### 📋 Média prioridade — próxima semana

9. **Consolidar barras de status no RideActiveView** — Reduzir de 3 para 2 barras.

10. **Animação de chegada** — "Você chegou!" quando remaining < 50m.

11. **Texto de instrução mais conciso** — Processar `MKRoute.Step.instructions` para comandos mais diretos.

12. **Botões maiores no RideActiveView** — 90pt mínimo, especialmente o FALAR.

13. **Haptics em interações** — `UIImpactFeedbackGenerator` nos botões do mapa.

14. **Empty states como CTAs** — Transformar "Nenhuma rota" em "Criar primeira rota".

### 🎨 Polimento — depois

15. Fotos e ratings no PlaceCard (requer Yelp API ou similar)
16. Categorias dinâmicas na busca
17. Medir distância com gesto
18. Conquistas e stats no Perfil
