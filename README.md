# Rocket Meter

Medidor de dano, cura e estatísticas de combate para World of Warcraft: Midnight (12.x).

## Por que existe

O Details! é o padrão do gênero e faz tudo — mas é visualmente datado e a configuração é
labiríntica. O Rocket Meter aposta no contrário: **bonito no primeiro segundo, configurável em
três cliques**, cobrindo o que 95% das pessoas realmente olham.

## Por que agora é possível

No Midnight a Blizzard removeu `COMBAT_LOG_EVENT_UNFILTERED` e introduziu os *Secret Values*.
Em troca, entregou a API oficial **`C_DamageMeter`**, que faz a coleta e a agregação do lado do
jogo. Ou seja: a parte difícil (parsear o combat log) deixou de existir para todo mundo, e o que
diferencia um medidor do outro passou a ser exatamente **apresentação e usabilidade** — o ponto
fraco do Details!.

## Arquitetura

| Arquivo | Responsabilidade |
|---|---|
| `Core.lua` | ciclo de vida, SavedVariables, eventos, fila de combate |
| `Data.lua` | **única** camada que fala com `C_DamageMeter`; trata secret values |
| `Window.lua` | desenho: janela, cabeçalho, linhas, barras |
| `Options.lua` | painel na Settings API |
| `Commands.lua` | `/rm` e subcomandos |

### A regra que orienta tudo

Durante o combate, os campos da sessão — inclusive `name` — são **secret values**: não podem ser
comparados, somados nem formatados. Podem apenas ser repassados a widgets, que o motor renderiza.
Fora de combate os mesmos campos voltam a ser legíveis.

Na prática:

```lua
bar:SetMinMaxValues(0, session.maxAmount)  -- aceita secret
bar:SetValue(source.totalAmount)           -- aceita secret
local texto = ns.Data.FormatAmount(source.totalAmount)
row.right:SetText(texto or source.totalAmount)  -- formatado fora de combate, cru dentro
```

Nada de ordenar a lista no Lua: a ordem vem pronta da API, porque comparar seria proibido.

## Estado

**0.1.0 — esqueleto funcional, ainda não testado no jogo.** Mostra o ranking da sessão atual com
barra por classe, alterna atributo (`/rm attr`), alterna atual/geral, zera sessões e tem painel de
opções com escala, travar janela e percentual.

## Roteiro

- [ ] Validar in-game os campos de `C_DamageMeter` e o comportamento em combate
- [ ] Drill-down: clicar num nome e ver as magias (`GetCombatSessionSourceFromType`)
- [ ] Histórico de segmentos (`GetAvailableCombatSessions` / `GetCombatSessionFromID`)
- [ ] Temas visuais prontos e escolha de fonte/textura
- [ ] Relatório para o chat (só fora de combate — os dados são secret durante)
