# WAWA Ride

App iOS de navegação em grupo para motociclistas.  
Mapa ao vivo, comunicação por voz, e descoberta por aproximação — sem digitar nada durante o passeio.

**Zero servidor. Zero login. 100% P2P.**

## Status

**Fase:** Documentação do MVP (v2)  
**Plataforma:** iOS 17+

## Documentação

| Documento | Conteúdo |
|-----------|----------|
| [MVP.md](MVP.md) | Definição do MVP, funcionalidades, stack |
| [docs/01-architecture.md](docs/01-architecture.md) | Arquitetura zero-servidor, estrutura, fluxo de dados |
| [docs/02-data-models.md](docs/02-data-models.md) | Modelos (SQLite, mesh payloads, salas, rotas) |
| [docs/03-ui-spec.md](docs/03-ui-spec.md) | 5 telas + sistema de design + regras de toque |
| [docs/04-mesh-protocol.md](docs/04-mesh-protocol.md) | Protocolo P2P completo (MultipeerConnectivity) |
| [docs/05-audio-system.md](docs/05-audio-system.md) | TTS, comandos de voz, walkie-talkie (Opus + MC Stream), áudio assíncrono |
| [docs/06-connectivity-strategy.md](docs/06-connectivity-strategy.md) | Estratégia offline, fila, adaptive GPS |
| [docs/07-rooms-channels.md](docs/07-rooms-channels.md) | Sistema de salas tipo Discord |

## Stack

- **UI:** SwiftUI + UIKit (MKMapView)
- **Mapa:** MapKit nativo
- **GPS:** CoreLocation
- **Transporte:** MultipeerConnectivity (BLE + WiFi Direct + WiFi Infra)
- **Voz ao vivo:** MCSession stream + Opus codec
- **Voz assíncrona:** MeshPayload + Opus codec
- **TTS:** AVSpeechSynthesizer
- **Comandos:** SFSpeechRecognizer
- **Armazenamento:** SQLite (GRDB.swift)
- **Dependências:** GRDB.swift + libopus

## Princípios

1. **Zero servidor** — App funciona completamente offline, P2P. Internet acelera, não é requisito.
2. **Zero digitação** — Voz e toques grandes. O piloto não digita durante o passeio.
3. **Aproximação** — Abriu o app perto de outros riders, entrou no grupo. Sem código, sem link.
4. **Áudio primeiro** — O app fala com o piloto. O piloto fala com o app e com o grupo.
5. **Salas** — Qualquer rider cria canais de voz/mensagem, público ou privado.
