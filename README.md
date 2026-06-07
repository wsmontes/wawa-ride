# WAWA Ride

Aplicativo iOS de navegação em grupo para motociclistas.  
Mapa ao vivo, comunicação por voz, e descoberta por aproximação — sem digitar nada durante o passeio.

## Status

**Fase:** Documentação do MVP  
**Plataforma:** iOS 17+

## Documentação

| Documento | Conteúdo |
|-----------|----------|
| [MVP.md](MVP.md) | Definição do MVP, funcionalidades, fluxo do passeio |
| [docs/01-architecture.md](docs/01-architecture.md) | Arquitetura do sistema, stack, estrutura de diretórios |
| [docs/02-data-models.md](docs/02-data-models.md) | Modelos de dados (Firestore, SQLite, mesh payloads) |
| [docs/03-ui-spec.md](docs/03-ui-spec.md) | Especificação das 4 telas + sistema de design |
| [docs/04-mesh-protocol.md](docs/04-mesh-protocol.md) | Protocolo P2P (MultipeerConnectivity) |
| [docs/05-audio-system.md](docs/05-audio-system.md) | TTS, comandos de voz, walkie-talkie |
| [docs/06-connectivity-strategy.md](docs/06-connectivity-strategy.md) | Estratégia offline, fila, resolução de conflitos |

## Stack

- **UI:** SwiftUI + UIKit (MKMapView)
- **Mapa:** MapKit
- **GPS:** CoreLocation
- **Mesh P2P:** MultipeerConnectivity
- **Cloud:** Firebase Firestore
- **Voz:** AVSpeechSynthesizer (TTS), SFSpeechRecognizer (comandos), GoogleWebRTC (walkie-talkie)
- **Offline:** SQLite (GRDB.swift)

## Princípios do MVP

1. **Zero digitação durante o passeio.** Voz e toques grandes.
2. **Aproximação resolve tudo.** Sem código, QR code, convite.
3. **Mapa é o centro.** Toda a experiência gira em torno do mapa.
4. **Áudio é a interface primária.** O app fala, o piloto ouve.

## Próximos passos

- [ ] Validar UX das 4 telas com riders reais
- [ ] Testar alcance BLE/MultipeerConnectivity entre 2 iPhones
- [ ] Prototipar fluxo de descoberta por aproximação
- [ ] Iniciar implementação dos modelos e serviços core
