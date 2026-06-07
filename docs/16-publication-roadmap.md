# WAWA Ride — Plano de Publicação (TestFlight → App Store)

**Status:** NÃO publicar na App Store ainda. TestFlight fechado primeiro.

---

## Diagnóstico

O WAWA Ride tem um produto muito bom escondido dentro de um app ambicioso demais. A versão atual tenta ser 9 coisas diferentes. A feature que diferencia (P2P offline em grupo) nunca foi validada.

**Versão publicável = app simples para passeio em grupo: criar passeio, entrar no grupo, ver riders no mapa, receber alertas, registrar rota.** Só isso já é forte.

---

## Corte de Escopo para V1

### Fica na V1 pública
- Mapa com pins dos riders
- Criar passeio (nome simples, rota opcional)
- Entrar em passeio (banner BLE, 1 toque)
- Riders no mapa com status (conectado/offline)
- Alertas rápidos (buraco, radar, polícia, acidente, perigo, ajuda)
- Gravação simples do passeio (distância, tempo, rota)
- Perfil mínimo (nome, papel, moto)
- Histórico simples
- Abrir rota no Apple Maps/Google Maps/Waze

### Experimental no TestFlight
- Walkie-talkie
- Mesh relay multi-salto
- Mensagens assíncronas
- TTS de alertas
- Background agressivo

### Sai da V1
- Salas estilo Discord
- Comandos de voz ("Ok moto")
- Navegação turn-by-turn própria
- Auto-pause/auto-resume
- Rerouting automático
- Elevation profile
- KML import
- Export para múltiplos apps
- Sala privada
- Promessa "funciona offline"

---

## Ajustes Técnicos Obrigatórios

1. **Logging persistente** — tela de diagnóstico (Bluetooth, GPS, peers, latência, exportar log)
2. **Feature flags** — desligar walkie-talkie, voice, salas, KML, turn-by-turn, mesh relay
3. **Modo pilotando vs parado** — UI diferente para cada estado
4. **Identidade do passeio** — código curto ou confirmação do líder
5. **Política de privacidade** — in-app + App Store
6. **Permissões no contexto** — GPS ao abrir mapa, mic ao falar, etc.

---

## Critérios para Sair do TestFlight

1. **2 iPhones, mesa:** descoberta <5s, conexão <3s, pin visível, alerta chega
2. **5 iPhones, mesa:** todos entram, líder claro, offline marcado, 30min estável
3. **Movimento controlado:** localização não pula, parado/offline diferenciado, background funciona
4. **Moto real, 3-5 motos:** 1h passeio, bateria medida, logs coletados
5. **Passeio 4h:** <25% bateria, sem crash, recuperação de background, salvamento ok

---

## Posicionamento

**NÃO dizer:** "Navegação completa como Apple Maps, walkie-talkie, mesh offline, Discord para motos."

**SIM dizer:** "Passeios de moto em grupo, mais simples: veja o grupo no mapa, compartilhe alertas e registre sua rota."

---

## Fases

1. **Build de campo** — cortar UI, logs, feature flags, diagnóstico, TestFlight interno
2. **Beta motoclube** — 5-10 testers, 3 passeios reais, métricas, feedback
3. **App Store** — privacy policy, screenshots honestos, descrição sem exagero, features instáveis desligadas
