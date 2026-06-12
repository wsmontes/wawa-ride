# WAWA Ride — TestFlight Build & Validation Checklist

**Versão:** 0.1.0 (build `b800cd1`)
**Objetivo:** Compilar, instalar em 2+ iPhones, validar o core P2P, enviar ao TestFlight.

---

## Pré-requisitos

- [ ] Mac com Xcode 16+ instalado
- [ ] 2 iPhones (mínimo) com iOS 17+
- [ ] Apple Developer Account (paga) — Team ID configurado no projeto
- [ ] iPhones com Bluetooth ligado, WiFi ligado (não precisa de internet)
- [ ] Ambos iPhones com o app instalado (via Xcode ou TestFlight)

---

## Fase 1 — Build & Deploy

### 1.1 Abrir o projeto

```bash
cd /path/to/wawa-ride
open WAWARide.xcodeproj
# OU: xcodegen generate && open WAWARide.xcodeproj
```

### 1.2 Verificar configuração

- [ ] Team: `BU5227WFYX` (ou seu Team ID) em Signing & Capabilities
- [ ] Bundle ID: `com.wawa.ride`
- [ ] Deployment Target: iOS 17.0
- [ ] Background Modes: location, bluetooth-central, bluetooth-peripheral, audio
- [ ] Info.plist: `NSLocationAlwaysUsageDescription`, `NSMicrophoneUsageDescription`, `NSBluetoothAlwaysUsageDescription`

### 1.3 Compilar

```bash
# Opção A: Xcode GUI
# Product → Build (⌘B)

# Opção B: Linha de comando
xcodebuild -project WAWARide.xcodeproj \
  -scheme WAWARide \
  -destination 'platform=iOS,name=iPhone 16 Pro' \
  build
```

- [ ] Build succeeds with 0 errors
- [ ] Warnings aceitáveis (principalmente de API availability)

### 1.4 Instalar nos dispositivos

- [ ] Conectar iPhone A via USB
- [ ] Selecionar iPhone A como destination → Run (⌘R)
- [ ] Confiar no certificado de desenvolvedor no iPhone (Settings → General → VPN & Device Management)
- [ ] Repetir para iPhone B

---

## Fase 2 — Smoke Test (1 iPhone)

Antes de testar P2P, validar que o app funciona standalone.

### 2.1 Primeira abertura

- [ ] App abre sem crash
- [ ] Onboarding aparece ("Bem-vindo ao WAWA Ride")
- [ ] Preencher nome → "COMEÇAR"
- [ ] App mostra mapa com localização atual

### 2.2 Mapa e busca

- [ ] Search bar funcional — digitar "Posto" mostra resultados
- [ ] Categorias rápidas aparecem (Posto, Restaurante, Café...)
- [ ] Selecionar resultado → PlaceCard abre
- [ ] PlaceCard mostra nome, endereço, botão Rotas
- [ ] Tocar Rotas → DirectionsPreview abre com opções de rota
- [ ] Mini snapshot da rota aparece no sheet (MKMapSnapshotter)
- [ ] Selecionar rota → polyline azul tracejada no mapa
- [ ] Tocar IR → fecha sheet, mostra rota, inicia navegação
- [ ] NavigationHUD aparece com instruções
- [ ] Tocar X → mostra resumo de navegação

### 2.3 Perfil

- [ ] Tab Perfil → mostra nome, foto, função
- [ ] PhotosPicker funcional (selecionar foto)
- [ ] TTS toggle funcional (botão speaker no mapa)
- [ ] DiagnosticView acessível → mostra conectividade, permissões, feature flags
- [ ] Privacy Policy acessível
- [ ] About screen acessível

### 2.4 Rotas

- [ ] Tab Rotas → lista vazia ou com rotas
- [ ] Criar rota no mapa (long press → PlaceCard → adicionar waypoint)
- [ ] Salvar rota com nome
- [ ] Swipe para deletar, swipe para renomear
- [ ] Abrir detalhes da rota → elevação, waypoints, exportar
- [ ] Abrir no Apple Maps / Google Maps / Waze (se instalados)

### 2.5 Gravação de track

- [ ] Botão record (●) no mapa → inicia gravação
- [ ] Barra de gravação aparece com stats ao vivo
- [ ] Pausar/retomar funcional
- [ ] Parar → alerta para nomear e salvar

### 2.6 DiagnosticView

- [ ] Abrir Perfil → Diagnóstico
- [ ] Conectividade: Bluetooth, Internet, GPS mostram valores reais
- [ ] Permissões: Localização, Microfone, Bluetooth OK
- [ ] Log visível (pode estar vazio inicialmente)
- [ ] Feature flags: Walkie-Talkie = OFF, Comandos de Voz = OFF (padrão)
- [ ] Ligar Walkie-Talkie feature flag para teste

---

## Fase 3 — Core P2P Validation (2 iPhones) 🔴 CRÍTICO

**Este é o teste que NUNCA foi feito.** Sem isso passar, o app não tem razão de existir.

### Configuração

- [ ] iPhone A e B: force kill do app, reabrir
- [ ] Ambos: verificar que Bluetooth está ligado
- [ ] Ambos: verificar que WiFi está ligado (não precisa de internet, só o rádio)
- [ ] Ambos: Feature flag Walkie-Talkie = ON (no DiagnosticView)
- [ ] Posicionar iPhones a ~1m de distância (mesa)

### 3.1 Descoberta BLE

**No iPhone A (Líder):**
- [ ] Tab Passeios → "+" → Criar Passeio
- [ ] Nome: "Teste Passeio"
- [ ] Tocar Criar
- [ ] Mapa entra em modo ride (fullscreen)
- [ ] RiderHUD aparece embaixo
- [ ] **CÓDIGO de 4 caracteres visível no HUD** (ex: "K7XP")

**No iPhone B (Rider):**
- [ ] Manter na tela de mapa (tab Mapa)
- [ ] **Banner BLE aparece no topo:** "Teste Passeio · K7XP" com botão ENTRAR
- [ ] ⏱️ Medir tempo até banner aparecer: _______ segundos (alvo: < 10s)
- [ ] Tocar ENTRAR

**Resultados esperados:**
- [ ] Banner aparece em < 10 segundos
- [ ] Banner mostra nome do passeio + código de 4 caracteres
- [ ] Código confere com o que o Líder vê no HUD

### 3.2 Conexão Mesh

**Após o Rider tocar ENTRAR:**
- [ ] iPhone B: banner "Rider entrou no grupo" aparece brevemente
- [ ] iPhone A: banner "[nome] entrou no grupo" aparece brevemente
- [ ] Ambos: RiderHUD mostra "X/Y riders" (ex: "2/2 riders")
- [ ] ⏱️ Medir tempo até conexão: _______ segundos (alvo: < 5s)

**Verificar no DiagnosticView (iPhone A):**
- [ ] Peer count = 1
- [ ] Último peer conectado = nome do iPhone B
- [ ] Messages processed > 0

### 3.3 Localização Compartilhada

- [ ] iPhone A: mapa mostra pin do iPhone B (posição do rider)
- [ ] iPhone B: mapa mostra pin do iPhone A (posição do líder)
- [ ] Pins têm cores diferentes baseadas no role (líder = cor específica)
- [ ] ⏱️ Latência de atualização: _______ segundos (alvo: < 3s)

**Teste de movimento:**
- [ ] Mover iPhone B fisicamente ~5 metros
- [ ] iPhone A: pin do iPhone B se move no mapa
- [ ] Velocidade aparece no HUD (se detectada)

### 3.4 Walkie-Talkie (PTT)

**No iPhone A:**
- [ ] Pressionar e segurar botão "FALAR" (centro do RiderHUD)
- [ ] Botão expande, glow verde na borda da tela
- [ ] Falar algo: "Teste 1, 2, 3"
- [ ] Soltar botão → glow desaparece
- [ ] Haptic feedback ao pressionar e soltar

**No iPhone B:**
- [ ] ⏱️ Latência de áudio: _______ ms (alvo: < 200ms direto)
- [ ] Qualidade de áudio: _____________ (alvo: compreensível)
- [ ] Áudio chega SEM duplicação (apenas 1 stream, não 2)

**Repetir o teste ao contrário (B → A):**
- [ ] B fala, A ouve
- [ ] Latência e qualidade similares

**Teste de microfone negado:**
- [ ] iPhone A: Settings → Privacy → Microphone → WAWA Ride → OFF
- [ ] Tentar PTT → alerta "Microfone necessário" aparece
- [ ] Botão "Abrir Ajustes" funciona
- [ ] Reativar microfone para próximos testes

### 3.5 Alertas de Perigo

**No iPhone A:**
- [ ] Tocar botão "Perigo" (esquerda do RiderHUD)
- [ ] HazardMenuView abre com opções (Radar, Buraco, Polícia, etc.)
- [ ] Selecionar "Radar"
- [ ] **Toast "Radar marcado — DESFAZER" aparece por 3 segundos**
- [ ] NÃO tocar desfazer → hazard é enviado após 3s

**No iPhone B:**
- [ ] Alerta de radar aparece no mapa (pin de perigo)
- [ ] TTS anuncia: "Radar" (se feature flag TTS ativa)
- [ ] ⏱️ Latência do alerta: _______ segundos (alvo: < 2s direto)

**Teste de UNDO:**
- [ ] iPhone A: abrir menu perigo, selecionar "Polícia"
- [ ] Toast aparece → tocar DESFAZER antes de 3s
- [ ] iPhone B: NÃO recebe alerta de polícia
- [ ] UNDO funciona corretamente

### 3.6 Desconexão e Reconexão

- [ ] iPhone B: bloquear tela (power button)
- [ ] iPhone A: rider B aparece como offline (pin cinza?)
- [ ] iPhone B: desbloquear, voltar ao app
- [ ] Reconexão acontece automaticamente
- [ ] ⏱️ Tempo de reconexão: _______ segundos

---

## Fase 4 — Robustez e Edge Cases

### 4.1 Distância BLE

- [ ] Aumentar distância entre iPhones gradualmente
- [ ] Conexão mantém até _______ metros (alvo: 30-50m em espaço aberto)
- [ ] Ao perder conexão, re-conecta ao aproximar
- [ ] Registrar distância máxima no log

### 4.2 Múltiplas Conexões (se tiver 3+ iPhones)

- [ ] iPhone C também conecta ao grupo
- [ ] Todos os 3 se veem no mapa
- [ ] PTT de A → ouvido por B e C
- [ ] Alerta de A → aparece em B e C
- [ ] Store-and-forward: A → B → C (B faz relay para C)

### 4.3 Background

- [ ] Iniciar passeio, bloquear tela
- [ ] GPS continua atualizando (verificar no outro iPhone)
- [ ] Após 5 minutos bloqueado, ainda aparece no mapa
- [ ] Após 15 minutos, ainda aparece
- [ ] Nota: iOS pode matar o app após ~30min em background

### 4.4 Bateria (teste de 1 hora)

- [ ] iPhone 100% bateria
- [ ] Iniciar passeio com GPS + BLE ativos
- [ ] Walkie-talkie: 10 transmissões de 5 segundos cada
- [ ] Após 1 hora: bateria em _______% (alvo: > 80%)
- [ ] Log registra eventos sem gaps

---

## Fase 5 — TestFlight Upload

### 5.1 Preparar Archive

- [ ] Product → Archive
- [ ] Archive succeeds sem erros
- [ ] Organizer → Validate App
- [ ] Validation succeeds (sem warnings críticos)

### 5.2 Configurar TestFlight no App Store Connect

- [ ] appstoreconnect.apple.com → Apps → WAWA Ride
- [ ] App Information preenchida
- [ ] Privacy Policy URL configurada
- [ ] Screenshots para 6.7" (iPhone 15 Pro Max) e 6.1" (iPhone 15 Pro) — mínimo 3 telas
- [ ] Build aparece em TestFlight → "Ready to Submit"
- [ ] Adicionar testers internos (email Apple ID)
- [ ] Enviar para revisão (TestFlight internal — sem revisão da Apple)

### 5.3 Configuração de Feature Flags para TestFlight

**No build de TestFlight, configurar:**
```
ff_walkie_talkie:        false  (experimental)
ff_voice_commands:       false  (experimental)
ff_async_voice_messages: false  (experimental)
ff_rooms:                false  (experimental)
ff_mesh_relay:           false  (experimental)
ff_turn_by_turn_nav:     false  (cortado)
ff_auto_pause:           false  (cortado)
ff_rerouting:            false  (cortado)
ff_elevation_profile:    false  (cortado)
ff_kml_import:           false  (cortado)
ff_export_multi_apps:    false  (cortado)
ff_private_rooms:        false  (cortado)
ff_geo_uri:              false  (cortado)
ff_show_diagnostics:     true   (útil para feedback)
```

**Para testers internos que vão testar walkie-talkie:**
- Pedir para ativar `ff_walkie_talkie` no DiagnosticView

---

## Fase 6 — Logs e Debug

### Coletando logs após o teste

- [ ] Após sessão de teste, abrir DiagnosticView
- [ ] Log contém entradas com prefixo `[mesh]`, `[gps]`, `[audio]`, `[ride]`
- [ ] Tocar "Exportar log" → Share Sheet → enviar por email/AirDrop
- [ ] Verificar entradas relevantes:
  - `Auto-presence started`
  - `FOUND peer: <nome>`
  - `AUTO-INVITING <nome>`
  - `Peer CONNECTED: <nome>`
  - `RECV locationUpdate from <nome>`
  - `RECV voiceLive from <nome>`
  - `SEND locationUpdate to N peers`

### Sinais de problemas

| Sintoma | Possível causa | Log a verificar |
|---------|---------------|-----------------|
| Banner BLE não aparece | Bluetooth desligado, MCNearbyService não iniciou | `Auto-presence started` ausente |
| Banner aparece mas ENTRAR falha | MCSession invitation recusada | `Peer CONNECTED` ausente, `Peer connecting` sem follow-up |
| Conecta mas não vê pins | LocationService não autorizado, mesh payload falhou | `RECV locationUpdate` ausente |
| Walkie-talkie sem áudio | Microfone negado, codec AAC falhou, stream fechou | `Codec:` erros, `Voice stream error` |
| Áudio com eco/duplicado | Stream + mesh ambos ativos (bug fixado em `b800cd1`) | `RECV voiceLive` duplicado |
| Alerta de perigo não chega | TTL expirou, mesh relay falhou | `SEND hazardAlert` no remetente, `RECV hazardAlert` ausente no destinatário |

---

## Resumo de Resultados

| Teste | Alvo | Resultado |
|-------|------|-----------|
| Descoberta BLE | < 10s | |
| Conexão Mesh | < 5s | |
| Latência localização | < 3s | |
| Latência walkie-talkie | < 200ms | |
| Qualidade áudio | Compreensível | |
| Latência alerta | < 2s | |
| Distância BLE máx | 30-50m | |
| Bateria 1h | > 80% | |
| Reconexão automática | Sim | |
| Build archive | Sucesso | |
| App Store Connect upload | Sucesso | |

---

## Próximo passo após validação

Se todos os testes acima passarem:
1. Corrigir bugs encontrados
2. Subir build para TestFlight
3. Convidar 5-10 motociclistas para beta fechado
4. 3 passeios reais com coleta de logs
5. Iterar baseado no feedback real
6. App Store submission (com screenshots honestos, descrição sem exagero)

**O app está pronto para ser testado. O código está sólido. Falta só ligar os iPhones.**
