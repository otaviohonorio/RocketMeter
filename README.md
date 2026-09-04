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

## A decisão de design: uma janela, várias colunas

O Details! resolve "quero ver dano e cura ao mesmo tempo" mandando você abrir uma segunda janela.
Depois uma terceira para interrupts. O Rocket Meter faz o contrário: **uma janela só**, em que
cada métrica é uma **coluna** que você liga ou desliga.

```
┌ Rocket Meter — Combate atual — 02:14 ─────────────────┐
│                        DPS    HPS  Interr Evitáv Mortes│
│ ███████████ Thalyra   1,2M    —      3     820k    0   │
│ ████████    Brumm     980k   12k     1     1,4M    1   │
│ ██████      Sarien    740k  1,1M     2     210k    0   │
└────────────────────────────────────────────────────────┘
```

Clique no cabeçalho de uma coluna para ordenar por ela. Conjuntos prontos para **Mítico+**
(DPS, HPS, Interrupções, Dano evitável, Mortes) e **Raide** (DPS, HPS, Absorções, Dano evitável,
Mortes) — um clique troca tudo.

A moldura é a nativa do jogo (`DefaultPanelTemplate`), então combina com a UI padrão sem skin
própria e sem configuração.

### Como isso é possível em tempo real

Cada métrica é uma consulta separada em `C_DamageMeter`, e cruzar as consultas exigiria casar o
mesmo jogador entre elas — mas em combate até o GUID é secret, e valor secret não pode ser chave
de tabela. A saída: **o cruzamento é feito pela própria API**. A consulta da métrica de ordenação
devolve a lista já ordenada; para cada jogador dela, o GUID (mesmo opaco) é devolvido à API para
buscar o valor nas outras métricas:

```lua
local session = C_DamageMeter.GetCombatSessionFromType(sessionType, sortAttr)
for _, source in ipairs(session.combatSources) do
    local outra = C_DamageMeter.GetCombatSessionSourceFromType(
        sessionType, outroAtributo, source.sourceGUID, source.sourceCreatureID)
    -- outra.totalAmount é o valor daquele jogador naquela métrica
end
```

É o mesmo caminho que o Details! usa internamente no `parser_nocleu1.lua`.

## Estado

**0.2.0 — janela com colunas configuráveis, ainda não testada no jogo.**

## Roteiro

- [ ] Validar in-game os campos de `C_DamageMeter` e o comportamento em combate
- [ ] Medir o custo do cruzamento em raide de 20 (linhas × colunas consultas por refresh)
- [ ] Drill-down: clicar num nome e ver as magias daquela métrica
- [ ] Histórico de segmentos (`GetAvailableCombatSessions` / `GetCombatSessionFromID`)
- [ ] Colunas específicas de M+: dano em adds prioritários, uso de defensivos, dispels perdidos
- [ ] Relatório para o chat (só fora de combate — os dados são secret durante)
