# WAWA Ride — Auditoria 200 Perguntas

Respostas baseadas em inspeção direta do código (branch `main`, commit `eaecba7`).

---

## A. Premissa Central do Produto (1–10)

**1. Problema principal vs WhatsApp + Google Maps + combinados?**
O app resolve coordenação de grupo em tempo real sem internet. WhatsApp não mostra posição ao vivo no mapa. Google Maps não tem walkie-talkie de grupo. Nenhum dos dois funciona sem 4G. O WAWA promete as 3 coisas simultaneamente. É real e diferenciado. Porém, **nunca foi validado com 2 iPhones**.

**2. Momento mágico?**
"5 motos no posto, líder cria passeio, todo mundo aperta ENTRAR sem digitar nada, 30 segundos depois estão no mapa se vendo e falando." Funciona no código. Não na realidade (não testado).

**3. App está tentando ser o quê primeiro?**
TUDO. O código tem 7 camadas de serviço, 13 views, 2 ViewModels. Navegação + grupo + walkie-talkie + rotas + social. Isso é o problema central.

**4. Indispensável para primeiro passeio real?**
Mapa com pins, criar/entrar por BLE, walkie-talkie. **3 features.**

**5. Funcionalidades que atrapalham o MVP?**
Salas estilo Discord, comandos de voz, export para 3 apps, elevation profile, KML parser. Tudo existe e adiciona complexidade.

**6. Se P2P falhar, ainda tem valor?**
Sim, como navegação standalone. Mas a UI é desenhada para modo grupo.

**7. Depende demais de "sem internet"?**
Sim. É o diferenciador. MapKit precisa de cache prévio. Sem cache = grade cinza. Não documentado.

**8. Planejado ou espontâneo?**
Código suporta ambos. Espontâneo é frágil (Form de 3 campos).

**9. Grupo saindo atrasado?**
BLE scanning: 2-5s para descoberta. Eternidade quando o grupo já está saindo.

**10. Útil para rider comum?**
UI complexa demais. Rider comum só quer: ver mapa, ver colegas, apertar FALAR.

---

## B. Uso Real em Motoclube (11–20)

**11. Líder precisa iniciar em 30s?**
Impossível. Fluxo atual: 4+ toques, formulário, 45-90 segundos.

**12. Toques para criar passeio?**
4 toques: Tab Passeios → + → nome → Criar.

**13. Toques para entrar?**
1 toque: banner ENTRAR. Se aparecer a tempo.

**14. Exige perfil?**
Onboarding pode ser pulado. `riderProfileId` fica vazio. App não quebra, mas perde identidade.

**15. Metade técnico, metade não?**
Mesma UI para todos. Sem modos de complexidade.

**16. Nomes duplicados?**
Sem tratamento. Dois "Pedro" = dois pins "Pedro" no mapa.

**17. Líder sabe quem entrou?**
TTS fala, mas líder precisa OLHAR para o HUD.

**18. Lista esperada de participantes?**
Não existe. Só quem apareceu no mesh.

**19. Ficou para trás vs fechou app?**
Ambos = `isConnected = false`. Sem diferenciação.

**20. Parado vs problema?**
`isMoving = speed > 5`. Sem lógica temporal.

---

## C. Segurança e Distração (21–30)

**21. Telas com atenção visual demais?**
RouteCreatorView, PlaceCard, DirectionsPreview, RoomListView. Todas exigem leitura e toques.

**22. Botão pequeno para luva?**
80-110pt. 2x mínimo Apple. Mas com luva de moto, ainda pequeno.

**23. PTT seguro em movimento?**
Botão fora da linha de visão. Piloto precisa olhar para baixo.

**24. Depende de leitura?**
Sim. Nomes, distâncias, status. TTS cobre navegação, não grupo.

**25. HUD compete?**
4 overlays simultâneos possíveis. Sem prioridade visual clara.

**26. Menu de perigo rápido?**
Grid em sheet. 2-3 segundos. Eternidade em emergência.

**27. Toque errado no alerta?**
Já enviou. Sem "desfazer".

**28. Incentiva mexer no celular?**
Sim. Search, PlaceCard, Directions — todos exigem tela.

**29. Modo "pilotando"?**
Não existe. UI igual parado ou a 120 km/h.

**30. Ações bloqueadas em movimento?**
Nenhuma. Todas disponíveis sempre.

---

## D. P2P, Mesh e Conectividade (31–40)

**31. Evidência de MC em motos?**
ZERO. Nunca testado.

**32. Testado com N dispositivos?**
ZERO. Compila, instala, nunca rodou com 2.

**33. Grupo além do alcance?**
Store-and-forward implementado, nunca testado.

**34. Mesh em cadeia?**
Suposição de arquitetura. Código pronto, zero evidência.

**35. Loops de mensagens?**
`MeshRelay.hasSeen()` + dedup por 5min. Funciona no código.

**36. Duplicadas com IDs diferentes?**
Dedup por ID, não semântico.

**37. TTL ideal?**
Chutes educados. Zero validação experimental.

**38. Subgrupos separam e reencontram?**
Sem reconciliação. Last-write-wins.

**39. Reconciliação após desconexão longa?**
Sobrescrita total. Sem merge por campo.

**40. Fonte da verdade?**
Líder. Se líder some, cada dispositivo tem sua verdade.

---

## E. Estado Compartilhado (41–50)

**41. Estado completo?**
`FullStatePayload`: ride, participants, rooms, activeRoute, activeAlerts.

**42. Rota imutável?**
Mutável, sem versionamento.

**43. Nova rota automática?**
Sim, mesh broadcast. Sem confirmação.

**44. Versões divergentes?**
Sem detecção de conflito.

**45. Versionamento?**
Nenhum.

**46. Líder perde conexão?**
Nada acontece. Líder some do mesh.

**47. Transferência de liderança?**
Não implementada.

**48. Varredor poderes?**
Só cor amarela.

**49. Entrar no meio?**
Sim, `FullStatePayload` na conexão.

**50. Voltar após 20min?**
Mensagens expiram na fila (1h críticas, 30min alta, 10min normal).

---

## F. Localização ao Vivo (51–60)

**51. Frequência de envio?**
Adaptativo: 1-10s. Bateria <20%: dobra.

**52. Muda com bateria/conectividade?**
Bateria sim, conectividade não.

**53. Precisão para "ficou para trás"?**
20m threshold, GPS ~5m. Razoável.

**54. GPS ruim em serra/túnel?**
Sem tratamento. Sem fallback.

**55. Rider "pulando"?**
Sem smoothing, Kalman, interpolação.

**56. Parado vs GPS congelado vs offline?**
Os dois primeiros não diferenciados.

**57. Heading?**
GPS course. Se inválido, mantém último.

**58. Rotação em baixa velocidade?**
GPS heading não confiável <5 km/h.

**59. Rastro recente?**
Não implementado.

**60. Distância líder-varredor?**
Não implementada.

---

## G. Áudio e Voz (61–70)

**61. Walkie-talkie em moto real?**
Nunca testado.

**62. Latência?**
Teórica: <200ms P2P, 1-2s relay. Nunca medida.

**63. Dois falam ao mesmo tempo?**
Mixer soma. Sem controle.

**64. Prioridade de fala?**
Não implementada.

**65. Caos em grupo grande?**
MC limita 8 peers. Relay degrada.

**66. AAC placeholder inviabiliza?**
8x maior que Opus. Pode quebrar em mesh BLE.

**67. Opus real?**
Não. Código tem `// TODO: Replace with actual Opus`.

**68. Intercom/Capacete?**
Detecta, configura `.allowBluetooth`. Não testado.

**69. TTS audível?**
Volume 1.0, rate 0.85x. Não testado.

**70. Ducking?**
Configurado. Pode não funcionar com intercom.

---

## H. Comandos de Voz (71–80)

**71. "Ok moto" offline com ruído?**
On-device, nunca testado com motor.

**72. pt-BR com capacete?**
Locale configurado. Microfone Bluetooth = qualidade baixa.

**73. Confunde conversa?**
Gatilho "Ok moto" tenta evitar. Nunca testado.

**74. Comando parcial?**
Fallback: "Não entendi."

**75. Confirmação para críticos?**
"Preciso de ajuda" dispara SOS sem confirmação.

**76. Frases naturais ou exatas?**
`.contains()`. Flexível, risco de falso positivo.

**77. Sotaques/ruído?**
SFSpeechRecognizer lida, mas moto é extremo.

**78. Voz melhor que botão?**
Em movimento, sim. Se confiável (não validado).

**79. Bateria ouvindo sempre?**
MVP usa push-to-listen. Modo contínuo não implementado.

**80. Fallback quando falha?**
TTS: "Não entendi."

---

## I. Navegação e Rotas (81–90)

**81. Competindo com Maps?**
Construído EM CIMA do MapKit. Não compete, usa.

**82. Partes perfeitas vs boas?**
Busca: boa. Navegação: boa. Rerouting: frágil. Instruções: texto bruto.

**83. Rerouting a 50m em serra?**
Vai recalcular demais. Threshold fixo.

**84. Auto-pause indevido?**
Sim, em semáforo de 45s.

**85. Auto-resume indevido?**
Movimento mínimo pode triggerar.

**86. GPX não bate com MapKit?**
Erro silencioso. Retry no preview.

**87. Rota com muitos pontos?**
NÃO simplifica. Simplifier removido na v2.

**88. MapKit waypoints nativos?**
Não. Múltiplas chamadas (N-1 por N pontos). Lento.

**89. Offline sem cache?**
Grade vazia. Sem botão "baixar".

**90. "Cache MapKit" na prática?**
Tiles visualizados, tempo limitado, não garantido.

---

## J. Biblioteca e Dados (91–100)

**91. Modelo de dados: planejada vs gravada?**
`Route.source`: `.drawn`, `.recorded`, `.imported`, `.shared`. `RouteSummary` separado para passeios.

**92. Track vira rota navegável?**
Sim, `stopRecording()` salva como `Route` com `simplifiedTrack`.

**93. Estatísticas planejadas vs reais?**
`Route.totalDistance` (planejado) ≠ `RideSummary.totalDistance` (real). Campos diferentes.

**94. Histórico: local ou também de outros?**
Só local (`LocalStore.saveRideSummary`).

**95. Apagar rota afeta passeios?**
Não. `RideSummary.routeId` é referência, não cascade delete.

**96. Migrações versionadas?**
Não. GRDB cria tabelas com `ifNotExists`. Sem versionamento de schema.

**97. GPX/KML problemático?**
Parser falha silenciosamente. Rota não importada.

**98. Limite prático?**
Sem limites explícitos. Offline queue limpa >1000 mensagens.

**99. Limpeza automática?**
Offline queue expira por TTL. Mensagens dedup: 5min. Resto: cresce indefinidamente.

**100. Proteção contra perda?**
`stopRecording()` salva ao parar. Se app mata durante gravação, track não salvo.

---

## K. Background, Bateria e iOS (101–110)

**101. Background após 30/60/120min?**
Nunca testado. Modos: location, bluetooth-central, bluetooth-peripheral, audio.

**102. Permissões habilitadas?**
Info.plist: 4 background modes. 6 permissões de uso.

**103. iOS permite MC em background?**
Sim, com BLE bg modes. Mas iOS pode throttlar.

**104. Teste tela apagada?**
Nunca.

**105. Consumo por hora?**
Nunca medido. GPS+mapa+BLE+P2P+áudio = estimativa 8-15%/h.

**106. Consumo por role?**
Líder: advertising + GPS + áudio. Rider: browsing + GPS. Varredor: igual rider.

**107. Modo economia?**
Não implementado.

**108. Degrada com bateria baixa?**
GPS dobra intervalo. Áudio/mesh não degradam.

**109. Superaquecimento?**
Nunca testado com sol + GPS + mapa.

**110. iPhones antigos?**
Target iOS 17. Testado só no iPhone do desenvolvedor.

---

## L. UX de Entrada, Permissões (111–120)

**111. Primeiro uso sem internet?**
Onboarding sheet. Mapa funciona se cache. BLE não acha nada.

**112. Onboarding suficiente?**
2 campos + PULAR. 10s. OK para MVP.

**113. Permissões no momento certo?**
Location no launch. Mic/P2P no uso. OK.

**114. Entende o porquê?**
Strings explicativas claras.

**115. GPS negado, app útil?**
Sim. Mapa, busca, planejamento funcionam. Grupo não.

**116. Bluetooth off?**
JoinView mostra. UnifiedMapView não.

**117. Mic negado, restante funciona?**
Sim. PTT bloqueado, TTS/mapa ok.

**118. Erro recuperável vs fatal?**
Permissões = recuperável. DB corrupto = fallback in-memory.

**119. Mensagens para motociclista?**
Algumas sim ("GPS desativado"). Outras `print()`.

**120. JoinView: sem passeio vs permissão?**
Diferencia Bluetooth off vs sem passeios vs permissão negada.

---

## M. Arquitetura de Código (121–130)

**121. UnifiedMapView é God View?**
Sim. 1020+ linhas, 13 `@State`, 2 ViewModels, 5 overlays, 3 sheets, mesh handling, navigation session, recording, PTT. Responsabilidades demais.

**122. O que deveria estar no ViewModel?**
`handleMeshPayload` (150 linhas de switch). `setupRideSession` (50 linhas). `endRide` (30 linhas). Tudo isso está na View.

**123. AppState centraliza demais?**
Sim. Ride state + participants + rooms + navigation + reset. 90 linhas, mas conceitualmente sobrecarregado.

**124. MeshService sabe demais?**
Sim. Cuida de advertising, browsing, relay, dedup, voice streams, payload routing. 330 linhas.

**125. TransportManager vs MeshService?**
Sobreposição: TransportManager decide estratégia, mas MeshService também decide (TTL, prioridade). Separação não é clara.

**126. NavigationEngine depende demais de MapKit?**
Sim. `MKRoute`, `MKRoute.Step`, `MKPolyline` diretamente. Sem abstração.

**127. Protocols para testes?**
Zero. Nenhum serviço tem protocolo. Tudo é `shared` singleton.

**128. Teste unitário GPX/KML?**
Zero.

**129. Teste dedup/TTL/roteamento?**
Zero.

**130. Teste migração SQLite?**
Zero.

---

## N. Modelo de Produto e Escopo (131–140)

**131. Grande demais antes de provar P2P?**
Sim. ~40 arquivos, 7000 linhas. Premissa central (P2P) 0% validada.

**132. Menor versão que provaria valor?**
2 iPhones. Criar passeio → entrar → ver pin no mapa → walkie-talkie. 4 features.

**133. Precisa de salas Discord?**
Não. Walkie-talkie do grupo resolve 90% dos casos.

**134. Precisa de comandos de voz?**
Não. Botões grandes resolvem MVP.

**135. Precisa competir com navegação completa?**
Não. Integração com Apple Maps/Google Maps seria suficiente para MVP.

**136. Funcionalidade que reduziria risco se removida?**
Salas, comandos de voz, export para 3 apps, elevation profile, KML.

**137. Parece essencial mas ninguém usa?**
Comandos de voz. Salas privadas. Elevation profile.

**138. Para motoclubes brasileiros ou genérico?**
Código é genérico. pt-BR está no TTS e comandos, mas não na UX ou features.

**139. 5, 20 ou 100 motos?**
MC limita 8 peers conectados. Grupos de 5-8 são o alvo realista.

**140. Tamanho inicial realista?**
4-6 motos. MC funciona bem nessa faixa.

---

## O. Concorrência e Diferenciação (141–150)

**141. Diferencial depende de feature não validada?**
Sim. P2P mesh offline é o diferencial. 0% validado.

**142. Funcionalidades vs experiências?**
Funcionalidades. Experiência real = zero.

**143. Usuário pagaria?**
MVP deve ser gratuito. Monetização futura (premium, grupos grandes, offline maps).

**144. Sustentabilidade?**
Sem servidor = custo operacional zero. Time de desenvolvimento = custo real.

**145. Zero servidor: vantagem ou redução de custo?**
Os dois. Mas o usuário não escolhe app porque "não tem servidor".

**146. Servidor opcional melhoraria?**
Sim. Relay server para grupos grandes. Sincronização confiável. Backup de rotas. Analytics.

**147. iOS-only no Brasil?**
Android é ~85% do mercado brasileiro. iOS-only limita adoção severamente.

**148. Motoclubes com maioria iPhone?**
Não. Maioria Android no Brasil.

**149. Android: requisito ou expansão?**
Requisito para adoção em massa no Brasil. MultipeerConnectivity → Google Nearby Connections.

**150. Crescer sem quebrar simplicidade?**
Desafio central. Quanto mais features, mais complexidade.

---

## P. Testes Reais (151–160)

**151. Primeiro teste obrigatório?**
2 iPhones, mesma sala. Criar passeio → descobrir → conectar.

**152. Medir com 2 iPhones?**
Tempo de descoberta BLE. Tempo de conexão. Latência de mensagem. Qualidade de áudio.

**153. Medir com 5 iPhones?**
Store-and-forward. Relay. Grupos com saltos. Áudio em cadeia.

**154. Medir com motos em movimento?**
Alcance BLE real. Estabilidade da conexão. GPS accuracy comparado.

**155. Critério "P2P funciona"?**
2+ dispositivos: descoberta < 5s, conexão < 3s, latência < 200ms, sem perda de mensagens.

**156. Critério "áudio funciona"?**
Latência < 500ms. Áudio inteligível. Sem artefatos.

**157. Critério "bateria aceitável"?**
< 25% em 4h de passeio.

**158. Critério "background confiável"?**
GPS + BLE mantidos por > 30min em background.

**159. Logging suficiente?**
Apenas `print()`. Sem logs persistentes.

**160. Recuperar logs pós-teste?**
Sem mecanismo. Precisaria conectar ao Xcode.

---

## Q. Casos Extremos (161–170)

**161. Líder e varredor fora de alcance?**
Sem conexão direta. Dependem de relay (se existir). Senão, offline total.

**162. Grupo se divide em dois caminhos?**
Duas ilhas independentes. Sem reconciliação automática.

**163. Rider entra no passeio errado?**
Vê múltiplos na lista. Pode escolher errado. Sem confirmação.

**164. Dois passeios mesmo nome?**
Identificados por `rideId` (UUID). Nomes duplicados no banner.

**165. Rider mal-intencionado?**
MC encryption = `.required`. Mas identidade (`displayName`) não é verificada. Pode forjar.

**166. Spam de alertas?**
Sem rate limiting. Qualquer rider pode mandar alertas ilimitados.

**167. Mudar nome para se passar por líder?**
Possível. `MCPeerID.displayName` = `UIDevice.current.name`. Pode ser mudado.

**168. Payload antigo pós-passeio?**
Dedup por ID verifica. Mas se expirou do set (5min), pode ser processado.

**169. Relógio errado?**
Timestamps inconsistentes. Last-write-wins usa timestamp local.

**170. Banco corrompido?**
`LocalStore` tenta in-memory fallback. Não recupera dados perdidos.

---

## R. Privacidade e Confiança (171–180)

**171. Identidade sem login?**
`RiderProfile.id` (UUID). `MCPeerID.displayName` (`UIDevice.current.name`). Não verificável.

**172. Passeio visível para qualquer um?**
BLE advertising é público. Qualquer app com serviceType "wawa-ride" vê.

**173. Aberto ou convite?**
Aberto. Auto-accept no MeshAdvertiser.

**174. Localização visível para quem?**
Todos no mesmo `rideId`. Sem controle de acesso granular.

**175. Pós-passeio, localização visível?**
Não. Passeio termina → mesh para → sem transmissão.

**176. Histórico indefinidamente?**
Sim. `RideSummary` e `Route` ficam até deletados manualmente.

**177. Usuário sabe onde dados estão?**
Não explicitamente. Só local, mas não há indicador na UI.

**178. Apagar histórico?**
Delete de rota implementado. Delete de passeio não.

**179. Criptografia ponta-a-ponta?**
MC `encryptionPreference = .required`. Criptografia de transporte.

**180. Eventos com muitos motociclistas?**
Múltiplos passeios no mesmo local. Lista mostra todos. Pode ser confuso.

---

## S. App Store e Produção (181–190)

**181. Permissões que geram rejeição?**
Background location + always. Precisa de justificativa forte.

**182. "Como Apple Maps" perigoso?**
Sim. Cria expectativa de feature parity impossível.

**183. APIs usadas corretamente?**
Background location: `activityType = .otherNavigation`. Audio: ducking. BLE: bg modes.

**184. Descrição MC para revisão?**
Não preparada.

**185. Justificativa localização contínua?**
"WAWA Ride mostra sua localização no mapa do passeio, mesmo com app em segundo plano." Claro.

**186. Política de privacidade?**
Não existe.

**187. Explicar dados locais/P2P?**
Não implementado na UI.

**188. Tela de diagnóstico?**
Não existe.

**189. Crash reporting sem servidor?**
Não implementado. `print()` não persiste.

**190. Beta fechado?**
TestFlight possível. Precisa de App Store Connect setup.

---

## T. Perguntas Finais (191–200)

**191. Remover turn-by-turn, app fica mais forte?**
Sim. Navegação é complexa de manter. Delegar para Apple/Google Maps manteria foco no grupo.

**192. Remover walkie-talkie live, ficar com async+alerts+localização?**
Sim. MVP muito mais confiável. Walkie-talkie é o recurso mais frágil tecnicamente.

**193. App só com internet no começo valeria?**
Sim. Valida a dinâmica de grupo. Mesh offline é otimização, não MVP.

**194. Mesh offline até 4-5 motos?**
Sim. Resolve 90% dos passeios reais. Não precisa de 20.

**195. 40% bateria em 2h?**
Quebra confiança. Usuário não usa app que drena bateria.

**196. Feature com maior chance de falhar no momento importante?**
Walkie-talkie. Latência, ruído, perda de pacotes — tudo piora em movimento.

**197. "Tecnicamente pronta" mas não produto?**
P2P mesh inteiro. 0% validado. Código existe, premissa não.

**198. Mais caro de manter?**
Navegação turn-by-turn. Atualizações de MapKit, edge cases de roteamento, expectativa de feature parity.

**199. Decisão que limita em 6 meses?**
Arquitetura sem protocols. Testar qualquer coisa requer iPhone real. Sem injeção de dependência.

**200. Pergunta mais desconfortável?**
"Se você tivesse que lançar esse app em 2 semanas para um passeio real com 5 motos, o que você cortaria AGORA e o que manteria?" 

Resposta: Manteria só mapa + localização P2P + alertas de perigo. Cortaria navegação turn-by-turn, salas Discord, comandos de voz, export para 3 apps, gravação de track, elevation profile, KML, geo URI. Reduziria de 40 arquivos para ~15. Foco total em "se ver no mapa e marcar perigo". Walkie-talkie seria bônus se funcionasse.
