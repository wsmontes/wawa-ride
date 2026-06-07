# WAWA Ride — Definição do MVP (v2)

**Versão:** 0.2
**Plataforma:** iOS 17+
**Princípio:** Zero servidor. Tudo P2P. Internet é acelerador, não requisito.

---

## Funcionalidades do MVP

### 1. Perfil do Piloto
- Nome/apelido, foto, moto (opcional)
- Role: líder, rider, ou varredor
- Setup único, local, sem login

### 2. Descoberta por Aproximação
- Líder cria passeio → anuncia via BLE (MultipeerConnectivity)
- Riders abrem o app → veem o passeio → entram com 1 toque
- Sem código, QR code, link, ou internet
- Alcance BLE: ~50m. Se rider chegar depois, detecta e entra

### 3. Mapa ao Vivo
- Pins de todos os riders com direção (heading), velocidade, status
- Rota do líder como polyline (gravada ao vivo ou planejada)
- Alertas de perigo no mapa (radar, buraco, polícia, etc.)
- Indicador de desvio da rota (🟢 na rota, 🟡 desviando, 🔴 fora)
- MapKit nativo, cache offline opcional

### 4. Criação e Navegação de Rotas
- **Gravar ao vivo:** líder grava rastro → polyline em tempo real
- **Desenhar:** waypoints no mapa antes do passeio
- **Importar:** .GPX de outros apps
- **Navegação:** TTS alerta curvas baseado na geometria da rota
- **Compartilhar:** exportar .GPX, enviar via mesh, AirDrop

### 5. Salas de Comunicação (tipo Discord)
- **Geral:** automática, todos dentro, walkie-talkie do grupo
- **Alertas:** automática, notificações do sistema
- **Privadas:** qualquer rider cria sala com membros selecionados
- **Direct:** conversa privada entre 2 riders
- Cada sala tem voz ao vivo e/ou mensagens de áudio

### 6. Voz ao Vivo (Walkie-Talkie)
- Push-to-talk: botão grande na tela ou comando de voz
- Codec Opus 32kbps, latência < 200ms P2P direto
- Transporte: MCSession stream (P2P) + relay mesh
- Funciona em salas privadas (só membros ouvem)
- Zero dependência de servidor (sem WebRTC/TURN)

### 7. Mensagens de Áudio Assíncronas
- Grava → comprime Opus → envia via mesh → notifica → toca
- Store-and-forward completo: funciona offline
- Confirmação de entrega e leitura
- Transcrição on-device (futuro)

### 8. Alertas de Perigo
- Menu radial com ícones grandes (radar, buraco, polícia, óleo, animal, acidente)
- Toque ou comando de voz ("Ok moto, marcar radar")
- Propagação crítica via mesh (TTL alto)
- Expiração automática, confirmação/limpeza por outros riders

### 9. Comandos de Voz
- "Ok moto" como gatilho
- Marcar perigos, status do grupo, falar/ouvir, enviar mensagem
- SFSpeechRecognizer on-device (funciona offline)

---

## O que NÃO vai no MVP

- ❌ Servidor, Firebase, API REST — app é 100% P2P
- ❌ Login, autenticação, contas — perfil local
- ❌ Chat por texto — só voz
- ❌ WebRTC / TURN / STUN — substituído por MCSession stream + Opus
- ❌ Android — iOS primeiro
- ❌ Integração com intercom (Cardo/Sena) — só detecção e coexistência
- ❌ Rota planejada com turn-by-turn real — só alertas de curva por geometria

---

## Stack

| Camada | Tecnologia |
|--------|-----------|
| UI | SwiftUI + UIKit (MKMapView) |
| Mapa | MapKit nativo |
| GPS | CoreLocation |
| Transporte | MultipeerConnectivity (BLE + WiFi Direct + WiFi Infra) |
| Voz ao vivo | MCSession stream + Opus codec |
| Voz assíncrona | MeshPayload + Opus codec |
| TTS | AVSpeechSynthesizer |
| Comandos de voz | SFSpeechRecognizer |
| Armazenamento | SQLite (GRDB.swift) |
| Dependências | GRDB.swift + libopus |

---

## Métricas de sucesso

- [ ] Grupo de 4+ riders conecta por proximidade, sem digitar nada
- [ ] Posições visíveis com latência < 3s (mesh) ou < 1s (WiFi Direct)
- [ ] Walkie-talkie com latência < 200ms (P2P direto)
- [ ] Mensagem de áudio entregue offline (armazena e retransmite)
- [ ] Alerta de perigo chega em < 2s (P2P) ou < 5s (relay 3 saltos)
- [ ] App funciona 100% sem internet
- [ ] Bateria: 4h de passeio < 40% de consumo
- [ ] Zero crashes em passeio de 4h com 10 riders
