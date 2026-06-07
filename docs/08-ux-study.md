# WAWA Ride — Estudo de Jornada do Usuário (UX)

**Versão:** 0.3  
**Problema:** A jornada atual está fragmentada, assume cenários irreais, e não cobre os casos de uso reais de um motociclista.

---

## 1. Jornada atual (o que o código faz hoje)

```
APP ABRE
  │
  ├─ Tem perfil?
  │   └─ NÃO → Tela de Perfil (preenche nome, moto, role)
  │              └─ Salva → volta pra ContentView → hasProfile = true
  │
  └─ Tem perfil?
      ├─ NÃO está em passeio → JoinRideView
      │     │
      │     ├─ BLE scanning começa automaticamente
      │     ├─ Spinner: "Procurando passeios próximos..."
      │     │   (fica aqui pra sempre se não tiver ninguém)
      │     │
      │     ├─ Se achar passeio → mostra card com "ENTRAR"
      │     │
      │     └─ Botão "CRIAR PASSEIO" (escondido no fim da tela)
      │           └─ Alert: "Nome do passeio" → cria → vai pro mapa
      │
      └─ Está em passeio → RideActiveView (mapa ao vivo)
```

## 2. Problemas identificados

### 🔴 CRÍTICO — App não funciona sozinho

**Problema:** O app assume que o usuário está SEMPRE perto de outros riders com o app aberto. Mas o uso real é:

| Momento | O que o piloto quer fazer | O app atual permite? |
|-----------------------------------|----------------------|
| Em casa, antes do passeio | Planejar rota, ver mapa, carregar .GPX | ❌ Só mostra spinner de busca |
| No posto, esperando o grupo | Criar passeio, ver quem chega | ⚠️ Funciona se for líder |
| Durante o passeio | Ver mapa, seguir líder, falar | ✅ |
| Depois do passeio | Ver resumo, compartilhar rota | ❌ Não tem tela |
| Sozinho, explorando | Ver mapa, testar navegação | ❌ Precisa "criar passeio" fake |

**Raiz do problema:** O app não tem uma Home screen. Ele força o usuário a estar "em um passeio" pra acessar o mapa.

### 🔴 CRÍTICO — Hierarquia invertida na JoinRideView

```
┌──────────────────────────────────────┐
│          WAWA Ride                   │
│                                      │
│       ⚪ Carregando...               │  ← OCUPA O CENTRO DA TELA
│   Procurando passeios próximos...    │
│                                      │
│              ── OU ──                │
│                                      │
│     [      CRIAR PASSEIO      ]      │  ← ESCONDIDO NO FINAL
└──────────────────────────────────────┘
```

O BLE scanning (passivo, depende de terceiros) ocupa o centro visual.  
A ação principal do líder (CRIAR PASSEIO) está escondida abaixo do fold.

**Deveria ser exatamente o contrário:**
- Ações primárias no centro: "Criar Passeio", "Ver Mapa"
- BLE scanning secundário: um indicador pequeno "3 passeios próximos encontrados"

### 🟡 MÉDIO — Criar passeio é um alert simples

Um `alert` com campo de texto. Isso é insuficiente. O líder quer:
- Nome do passeio
- **Selecionar rota** (carregar uma salva, ou criar nova)
- **Ver opções** (modo livre ou com rota planejada)
- **Saber que vai funcionar** (confirmar que o BLE vai anunciar)

### 🟡 MÉDIO — Sem acesso ao mapa fora de passeio

O mapa (MapKit com busca, navegação, etc.) é o core do app. Mas ele só existe dentro de `RideActiveView`, que só aparece quando `appState.currentRideId != nil`. 

Um piloto sozinho não consegue:
- Abrir o mapa pra explorar
- Planejar rota visualmente
- Testar navegação
- Buscar endereços

### 🟡 MÉDIO — Navegação entre telas é frágil

```swift
// ContentView — decide qual tela mostrar com if/else
if !hasProfile {
    ProfileSetupView()
} else if appState.currentRideId == nil {
    JoinRideView()
} else {
    RideActiveView()
}
```

Isso funciona pra 3 estados, mas não escala. Se adicionarmos Home, Histórico, Rotas Salvas, essa estrutura quebra. Precisamos de um sistema de navegação real (TabView ou NavigationStack com paths).

### 🟢 BAIXO — ProfileSetupView tem NavigationStack desnecessário

A tela de perfil usa `NavigationStack` e `.dismiss`, mas NÃO é apresentada como modal — é uma tela condicional dentro da ContentView. O dismiss não vai funcionar, e o NavigationStack é desperdiçado.

### 🟢 BAIXO — Falta feedback após ações

- Depois de criar perfil: sem confirmação, sem transição animada
- Depois de criar passeio: vai direto pro mapa, sem onboarding
- Depois de entrar no passeio: sem confirmação visual ou TTS

---

## 3. Jornada proposta (como deveria ser)

```
APP ABRE
  │
  ├─ Primeiro uso?
  │   └─ SIM → Onboarding (1 tela: nome + "Sou líder/rider")
  │              └─ Salva → vai pra Home
  │
  └─ Home (sempre acessível)
      │
      ├─ 📍 Ver Mapa (modo livre)
      │     └─ Mapa com busca, zoom, sem passeio ativo
      │     └─ "Criar Passeio" — botão flutuante no mapa
      │     └─ "Entrar em Passeio" — se detectar BLE
      │
      ├─ 🏍️ Meus Passeios
      │     └─ Criar novo (tela dedicada: nome + rota + config)
      │     └─ Próximos (planejados)
      │     └─ Histórico (finalizados)
      │
      ├─ 🗺️ Minhas Rotas
      │     └─ Rotas salvas (lista)
      │     └─ Importar .GPX
      │     └─ Criar nova rota no mapa
      │
      └─ ⚙️ Perfil (acessível via ícone)

DURANTE UM PASSEIO ATIVO:
  └─ TabView é substituída por tela cheia (mapa ao vivo)
  └─ Ao encerrar passeio → volta pra Home
```

### Fluxo: Criar Passeio (nova versão)

```
Home → "Criar Passeio" → Tela dedicada:
  ┌──────────────────────────────────────┐
  │  Cancelar        Criar Passeio       │
  │                                      │
  │  Nome do passeio:                    │
  │  ┌──────────────────────────────┐   │
  │  │ Serra do Rio do Rastro       │   │
  │  └──────────────────────────────┘   │
  │                                      │
  │  Rota:                              │
  │  ○ Sem rota (modo livre)            │
  │  ○ Usar rota salva          ▸      │
  │  ○ Criar rota no mapa       ▸      │
  │                                      │
  │  ⓘ Seu iPhone vai anunciar o        │
  │    passeio via Bluetooth para       │
  │    riders próximos (até 50m).       │
  │                                      │
  │  ┌──────────────────────────────┐   │
  │  │     CRIAR PASSEIO            │   │
  │  └──────────────────────────────┘   │
  └──────────────────────────────────────┘
```

### Fluxo: Entrar em Passeio

```
Modo A — Abordagem atual (melhorada):
  - Home tem um indicador: "🟢 2 passeios próximos"
  - Toque → lista de passeios → "Entrar"
  - NÃO ocupa o centro da tela, NÃO bloqueia o app

Modo B — Atalho no mapa:
  - No mapa (modo livre), se detectar BLE:
    - Banner no topo: "🏍️ Passeio do Wagner por perto — Entrar"
    - Toque → entra direto
```

---

## 4. Nova arquitetura de navegação

```swift
// Substituir o if/else da ContentView por TabView + overlay

struct ContentView: View {
    @StateObject private var appState = AppState.shared

    var body: some View {
        ZStack {
            if appState.currentRideId != nil {
                // Passeio ativo — tela cheia
                RideActiveView()
            } else {
                // Modo normal — TabView
                TabView {
                    ExploreMapView()        // Mapa livre
                        .tabItem { Label("Mapa", systemImage: "map") }

                    RoutesListView()        // Rotas salvas
                        .tabItem { Label("Rotas", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }

                    RidesListView()         // Passeios (criar/histórico)
                        .tabItem { Label("Passeios", systemImage: "motorcycle") }

                    ProfileView()           // Perfil
                        .tabItem { Label("Perfil", systemImage: "person.circle") }
                }
            }
        }
    }
}
```

## 5. Telas que faltam

| Tela | Função | Prioridade |
|------|--------|-----------|
| **Home / ExploreMapView** | Mapa livre, buscar endereços, planejar rota, ver trânsito | 🔴 Crítica |
| **CreateRideView** | Tela dedicada pra criar passeio (nome + rota + opções) | 🔴 Crítica |
| **RoutesListView** | Lista de rotas salvas, importar .GPX | 🟡 Média |
| **RidesListView** | Histórico de passeios, resumos, compartilhar | 🟡 Média |
| **OnboardingView** | Primeiro uso simplificado (só nome + role) | 🟢 Baixa |

## 6. Recomendação

1. **Primeiro:** Criar `ExploreMapView` — um mapa standalone com busca que funciona SEM passeio ativo
2. **Depois:** Criar `CreateRideView` — tela dedicada pra criar passeio
3. **Depois:** Refatorar `ContentView` pra usar TabView + overlay (passeio ativo)
4. **Por último:** Adicionar `RoutesListView` e `RidesListView`
