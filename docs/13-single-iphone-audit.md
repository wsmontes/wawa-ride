# Single-iPhone Audit — 50+ coisas pra testar, corrigir e completar

Tudo que dá pra fazer com UM iPhone, sem precisar de segundo dispositivo.

Legenda: ✅ Feito | ⚠️ Parcial/Bug | ❌ Não existe

---

## 1. Mapas & Navegação

| # | Feature | Status | Notas |
|---|---------|--------|-------|
| 1 | Buscar endereço/lugar com autocomplete | ✅ | Proximidade funciona |
| 2 | Categorias rápidas (Posto, Restaurante...) | ✅ | 8 categorias |
| 3 | Histórico de buscas | ✅ | Últimas 10 |
| 4 | PlaceCard com info do lugar | ✅ | Nome, endereço, distância |
| 5 | PlaceCard com telefone e site | ✅ | Se MKMapItem tem |
| 6 | PlaceCard com foto do lugar | ❌ | MKMapItem não tem — precisaria Yelp API |
| 7 | Direções com múltiplas rotas | ✅ | Alternativas + seleção |
| 8 | Polyline visível ao selecionar rota | ✅ | Zoom automático |
| 9 | Step list antes do GO | ✅ | Primeiros 3, expansível |
| 10 | Distância nos resultados da busca | ⚠️ | Estimativa grosseira (~30% do diâmetro) |
| 11 | Navegação turn-by-turn | ✅ | MKRoute.Step |
| 12 | Instrução visível na tela | ✅ | NavigationHUD |
| 13 | Rerouting ao desviar | ✅ | > 50m |
| 14 | Indicador de chegada | ✅ | "Você chegou" < 50m |
| 15 | Resumo ao fim da navegação | ✅ | Distância, tempo, velocidade |
| 16 | Ver overview da rota durante nav | ❌ | Sem botão/gesto para zoom out |
| 17 | Step list durante navegação | ❌ | Só instrução atual |
| 18 | Pausar navegação | ❌ | Só parar (X) |
| 19 | Velocidade atual no HUD | ✅ | |
| 20 | Limite de velocidade | ❌ | MapKit não expõe |
| 21 | Mapa 3D | ✅ | isPitchEnabled |
| 22 | Trânsito | ✅ | showsTraffic |
| 23 | Tipos de mapa (Standard/Satellite/Hybrid) | ✅ | Botão flutuante |
| 24 | Modo noturno automático | ❌ | Sempre dark mode forçado |
| 25 | Cache offline de mapa | ⚠️ | MapKit faz automático, sem UI |
| 26 | Download explícito de área offline | ❌ | |

---

## 2. Criação e Edição de Rotas

| # | Feature | Status | Notas |
|---|---------|--------|-------|
| 27 | Criar rota no mapa (waypoints) | ✅ | Long press + busca |
| 28 | Desfazer último waypoint | ✅ | |
| 29 | Deletar waypoint específico | ❌ | Só undo último |
| 30 | Reordenar waypoints (drag) | ❌ | |
| 31 | Editar nome do waypoint | ❌ | |
| 32 | Adicionar parada (posto, descanso) | ⚠️ | isStop existe mas sem UI |
| 33 | Preview da rota com MKDirections | ✅ | Polyline azul tracejada |
| 34 | Alternativas de rota no criador | ✅ | Sheet de seleção |
| 35 | Salvar rota com nome | ✅ | |
| 36 | Rota de ida e volta | ❌ | |
| 37 | Inverter rota | ❌ | |
| 38 | Distância total da rota | ✅ | |
| 39 | Elevação da rota | ❌ | Modelo tem elevationGain, mas não calcula |
| 40 | Perfil de elevação (gráfico) | ❌ | |

---

## 3. Gravação de Track (ao vivo)

| # | Feature | Status | Notas |
|---|---------|--------|-------|
| 41 | Gravar track enquanto pilota | ⚠️ | RouteService.startRecording existe, sem UI acessível |
| 42 | Pausar/retomar gravação | ❌ | Só iniciar/parar |
| 43 | Ver stats ao vivo durante gravação | ❌ | Distância, tempo, velocidade atual |
| 44 | Salvar track como rota | ⚠️ | Salva via stopRecording, mas sem nome |

---

## 4. Import e Export

| # | Feature | Status | Notas |
|---|---------|--------|-------|
| 45 | Importar .GPX | ✅ | Files app + onOpenURL |
| 46 | Importar .KML (Google Maps) | ❌ | Google Maps exporta KML, não GPX |
| 47 | Importar .FIT / .TCX (Garmin/Wahoo) | ❌ | Formatos comuns de ciclismo |
| 48 | Abrir .GPX de outros apps (Rever, Calimoto) | ✅ | Funciona |
| 49 | Exportar .GPX | ✅ | Share sheet |
| 50 | Abrir rota no Apple Maps | ⚠️ | PlaceCard tem botão, mas exporta? |
| 51 | Abrir rota no Google Maps | ❌ | comgooglemaps:// URL scheme |
| 52 | Abrir rota no Waze | ❌ | waze:// URL scheme |
| 53 | Compartilhar rota como link | ❌ | |
| 54 | Compartilhar rota como imagem | ❌ | Screenshot do mapa com rota |
| 55 | Compartilhar coordenadas | ✅ | Copiar no PlaceCard |
| 56 | Receber coordenadas (geo URI) | ❌ | geo:lat,lng |

---

## 5. Biblioteca de Rotas

| # | Feature | Status | Notas |
|---|---------|--------|-------|
| 57 | Lista de rotas salvas | ✅ | RoutesLibraryView |
| 58 | Ver detalhes da rota | ✅ | RouteDetailView |
| 59 | Deletar rota | ❌ | .onDelete sem implementação |
| 60 | Renomear rota | ❌ | |
| 61 | Duplicar rota | ❌ | |
| 62 | Ordenar rotas (data, nome, distância) | ❌ | Só por data |
| 63 | Filtrar rotas (importada, gravada, etc) | ❌ | |

---

## 6. Perfil e Preferências

| # | Feature | Status | Notas |
|---|---------|--------|-------|
| 64 | Editar nome/apelido | ✅ | ProfileTabView |
| 65 | Editar moto | ✅ | |
| 66 | Mudar função padrão | ✅ | Líder/Rider/Varredor |
| 67 | Foto de perfil | ⚠️ | Botão existe, sem implementação de picker |
| 68 | Ativar/desativar voz (TTS) | ❌ | VoiceAssistant.isMuted existe, sem UI |
| 69 | Unidades (km/milhas) | ❌ | |
| 70 | Tipo de mapa padrão | ❌ | Sempre standard |
| 71 | Configurações de áudio | ❌ | Sem UI |
| 72 | Tema (claro/escuro) | ❌ | Forçado dark |
| 73 | Limpar histórico de buscas | ✅ | Botão "Limpar" |
| 74 | Limpar todas as rotas | ❌ | |
| 75 | Limpar histórico de passeios | ❌ | |
| 76 | Exportar todos os dados | ❌ | |
| 77 | Sobre / versão do app | ❌ | |

---

## 7. Histórico de Passeios

| # | Feature | Status | Notas |
|---|---------|--------|-------|
| 78 | Lista de passeios passados | ✅ | RidesListView |
| 79 | Estatísticas reais do passeio | ❌ | Dados hardcoded (3600s, nil) |
| 80 | Ver rota do passeio no mapa | ❌ | |
| 81 | Compartilhar resumo do passeio | ❌ | |
| 82 | Deletar passeio do histórico | ❌ | |

---

## 8. Áudio e Voz

| # | Feature | Status | Notas |
|---|---------|--------|-------|
| 83 | TTS durante navegação | ✅ | |
| 84 | Comandos de voz ("Ok moto") | ⚠️ | Código existe, nunca testado |
| 85 | Volume do TTS | ❌ | Usa volume do sistema |
| 86 | TTS audível com vento? | ❌ | Nunca testado em moto |
| 87 | TTS via Bluetooth (capacete) | ⚠️ | allowBluetooth configurado, não testado |
| 88 | Ducking de música | ✅ | .duckOthers configurado |

---

## 9. Permissões e Error States

| # | Feature | Status | Notas |
|---|---------|--------|-------|
| 89 | GPS negado → tela de erro | ❌ | Só não inicia tracking |
| 90 | Microfone negado → feedback | ❌ | Sem indicação |
| 91 | Bluetooth desligado → feedback | ⚠️ | JoinView mostra, mapa não |
| 92 | Sem internet → fallback | ⚠️ | MapKit cache, sem feedback visual |
| 93 | GPS sinal fraco → indicador | ❌ | |
| 94 | Modo avião → comportamento | ❌ | Não testado |
| 95 | Low Power Mode → otimização | ❌ | |
| 96 | Bateria < 10% → aviso | ❌ | |
| 97 | App em background → continuar nav | ⚠️ | Audio bg mode, não testado |
| 98 | App morto pelo iOS → restaurar estado | ❌ | Sem state restoration |
| 99 | Banco de dados corrompido → fallback | ⚠️ | In-memory fallback existe, não testado |

---

## 10. Integração com Outros Apps

| # | Feature | Status | Notas |
|---|---------|--------|-------|
| 100 | Receber .GPX de outros apps | ✅ | onOpenURL |
| 101 | "Abrir com..." → WAWA Ride | ✅ | Info.plist precisaria de CFBundleDocumentTypes |
| 102 | Share Extension (enviar local para WAWA) | ❌ | |
| 103 | Siri Shortcuts ("navegar para casa") | ❌ | |
| 104 | Widget (próximo passeio, atalho) | ❌ | |
| 105 | Dynamic Island (nav em andamento) | ❌ | |
| 106 | Apple Watch (distância, próxima curva) | ❌ | |
| 107 | CarPlay | ❌ | Não se aplica (moto) |

---

## 11. Acessibilidade

| # | Feature | Status | Notas |
|---|---------|--------|-------|
| 108 | VoiceOver nos pins | ❌ | accessibilityLabel |
| 109 | VoiceOver nos botões | ❌ | Botões sem labels |
| 110 | Dynamic Type | ❌ | Fontes fixas |
| 111 | Alto Contraste | ❌ | |
| 112 | Reduzir Movimento | ❌ | |

---

## 12. Performance

| # | Feature | Status | Notas |
|---|---------|--------|-------|
| 113 | Teste de bateria 4h | ❌ | |
| 114 | Memory leak em 4h de uso | ❌ | |
| 115 | GPS accuracy drift | ❌ | |
| 116 | DB size após 50 passeios | ❌ | |
| 117 | Cold launch time | ❌ | |

---

## Resumo

```
FEITO:      20  ████████░░░░░░░░░░░░  17%
PARCIAL:    15  ██████░░░░░░░░░░░░░░  13%
AUSENTE:    82  ██████████████████████ 70%
```

**Top 15 pra atacar AGORA (single iPhone, alto impacto):**

1. Gravação de track acessível (botão Gravar na UI)
2. Stats ao vivo durante gravação
3. Pausar/retomar gravação
4. Resumo real pós-passeio (não hardcoded)
5. Exportar rota para Google Maps e Waze
6. Importar KML (Google Maps)
7. Deletar rota
8. Ativar/desativar voz (TTS on/off)
9. GPS negado → tela de erro
10. Foto de perfil funcional
11. Abrir coordenadas (geo URI)
12. Ver overview da rota durante nav
13. Step list durante navegação
14. Editar nome do waypoint
15. Pausar navegação
