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
| `Scoreboard.lua` | placar de fim de Mítico+ e de encontro de raide |
| `Options.lua` | painel na Settings API |
| `Commands.lua` | `/rm` e subcomandos |
| `Picker.lua` | painel de colunas — a tela de configuração de verdade |
| `Minimap.lua` | botão de minimapa próprio, sem biblioteca externa |
| `Profile.lua` | onde a configuração mora: conta ou personagem |
| `Locales/` | `enUS.lua` (chaves = inglês) e `ptBR.lua` |

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
┌ Rocket Meter — Combate atual — 02:14 ─────────────────────────────┐
│                   Dano    DPS    Cura    CPS  Interr Evitáv Mortes│
│ ███████ Thalyra   1,2M  9,1k/s     —      —      3    820k    0   │
│ █████   Brumm     980k  7,4k/s   12k    91/s     1    1,4M    1   │
└───────────────────────────────────────────────────────────────────┘
```

Total e valor por segundo são **colunas separadas** — dano total, dano por segundo, cura total,
cura por segundo. Quem só quer o ritmo liga DPS e CPS; quem quer a contribuição da corrida
inteira liga os totais; quem quer os dois, liga os quatro.

Clique no cabeçalho de uma coluna para ordenar por ela. Conjuntos prontos para **Mítico+**
(dano, DPS, cura, CPS, interrupções, dano evitável, mortes) e **Raide** (o mesmo, com absorções
no lugar das interrupções) — um clique troca tudo.

### Configurar: o painel de colunas

A engrenagem na barra de título abre o **painel de colunas**, colado na janela: as onze métricas
numa lista só, com caixa para ligar, setas para reordenar e a posição atual (1º, 2º…) ao lado.
Cada clique se reflete na janela atrás, na hora — sem "aplicar", sem submenu, sem procurar.

Em cima, os três conjuntos prontos como botões. Embaixo, um atalho para as opções do jogo, onde
ficam escala, travar, linhas, perfil e o botão de minimapa.

O painel da Settings API continua existindo porque é onde o jogador espera achar as opções
globais — mas não é preciso passar por ele para fazer o que se faz todo dia, que é mexer nas
colunas.

### Botão de minimapa

Escrito à mão (~60 linhas) em vez de embutir LibDBIcon: guarda a posição como **ângulo**, então
fica no lugar em qualquer tamanho de minimapa, e arrasta ao redor da borda.

- **Clique**: mostra ou esconde o medidor
- **Shift+clique**: placar da última corrida
- **Clique direito**: opções

Pode ser escondido nas opções — quem usa o compartimento de addons não precisa dos dois.

### Ordenação

Clique no cabeçalho para ordenar por aquela coluna; clique de novo para **inverter a direção**
(a seta ▼/▲ mostra qual está valendo). A inversão é feita percorrendo a lista da API de trás para
frente — inverter não exige comparar nada, então funciona mesmo com os valores secret do combate.

**Shift+clique** move a coluna uma casa para a esquerda, **Ctrl+clique** para a direita. Pelo
chat: `/rm move 3 left`.

### Perfil por personagem

Por padrão a configuração é da conta inteira. A opção *"Configuração só deste personagem"*
passa a guardar tudo em `SavedVariablesPerCharacter` — e ao ligar pela primeira vez o personagem
**herda** o que estava valendo, em vez de recomeçar do zero. Desligar volta para a configuração
da conta, sem perder a do personagem.

`ns.db` é um proxy que aponta para o armazenamento ativo. Isso não é firula: a Settings API
guarda a referência da tabela no momento do registro, então trocar `ns.db` por outra tabela
faria o painel de opções continuar escrevendo na antiga.

Comandos: `/rm profile char`, `/rm profile account`, `/rm profile reset`.

### Idiomas

Português e inglês. As chaves de tradução **são** o texto em inglês, então um idioma sem arquivo
cai no inglês em vez de mostrar chave crua. `Locales/ptBR.lua` só carrega quando
`GetLocale() == "ptBR"`. Nomes de métrica que o próprio cliente já traduz continuam vindo dele.

### Aparência: o medidor nativo, com colunas

O visual copia o medidor embutido do Midnight: cabeçalho com o atlas
**`ui-damagemeters-header-bar`** (a mesma arte que a Blizzard usa), corpo escuro sem moldura
pesada, linhas chapadas de 16px coloridas por classe. Nada de skin para configurar.

E a janela **encolhe para o número de jogadores que existem**: solo é uma linha, grupo de cinco
são cinco. Caixa vazia esperando gente é justamente o que deixava a janela com cara de painel
solto — o medidor da Blizzard não faz isso, e agora o Rocket Meter também não.

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

### Comportamento da janela

- **Volta como você deixou**: a visibilidade é salva, então a janela reaparece sozinha na posição
  de sempre — sem precisar clicar no minimapa a cada login.
- **ESC não fecha.** Fecha só no X. (A janela fica fora de `UISpecialFrames` justamente por isso.)
- **Só em combate**, opcional: aparece quando a luta começa e some alguns segundos depois.
- **Atual / Geral** alternam clicando no próprio título. O combate atual zera a cada luta nova;
  o geral acumula sempre — os dois vêm prontos do motor do jogo (`sessionType` 0 e 1), não somos
  nós que zeramos nada.

## Placar de fim de corrida

No fim de um Mítico+ (`CHALLENGE_MODE_COMPLETED`) ou de um encontro de raide vencido
(`ENCOUNTER_END`), abre sozinho um painel com o grupo inteiro e **todas** as métricas de uma vez
— dano, cura, interrupções, dissipações, dano recebido, dano evitável e mortes. É o equivalente
ao scoreboard do `Details_MythicPlus`, mas nativo, sem addon extra.

O título traz masmorra e nível da chave (ou o nome do chefe), com tempo e se fechou no tempo.
Em M+ os dados vêm da sessão **geral** (a corrida inteira); em raide, do combate que acabou.
Reabre com `/rm score`; desliga nas opções.

### Comandos

Os comandos e seus argumentos são **sempre em inglês**, independentemente do idioma do cliente —
só as descrições da ajuda são traduzidas. Assim um comando copiado de um guia, de um vídeo ou de
um colega funciona em qualquer instalação.

```
/rm                             abre ou fecha a janela
/rm col [n]                     lista as colunas ou liga/desliga uma
/rm move <n> left|right         move uma coluna
/rm preset mplus|raid|damage    troca o conjunto de colunas
/rm score                       placar da última corrida
/rm overall                     alterna combate atual / geral
/rm profile char|account|reset  configuração da conta ou do personagem
/rm reset                       zera as sessões
/rm config                      abre as opções
```

## Estado

**0.8.0 — UI retrabalhada: ícones de classe, zebra, destaque do líder, placar redesenhado,
janela persistente, modo só-em-combate.**

Confirmado in-game na 0.6.0: a leitura do `C_DamageMeter` funciona (dano, DPS, cura, CPS,
interrupções e mortes com números reais), o `.toc` carrega e a ordenação responde. O que faltava
era a casca, refeita nesta versão.

## Roteiro

- [ ] Validar in-game os campos de `C_DamageMeter` e o comportamento em combate
- [ ] Medir o custo do cruzamento em raide de 20 (linhas × colunas consultas por refresh)
- [ ] Drill-down: clicar num nome e ver as magias daquela métrica
- [ ] Histórico de segmentos (`GetAvailableCombatSessions` / `GetCombatSessionFromID`)
- [ ] Colunas específicas de M+: dano em adds prioritários, uso de defensivos, dispels perdidos
- [ ] Placar: pontuação de M+ por jogador e loot recebido (`ENCOUNTER_LOOT_RECEIVED`)
- [ ] Placar: histórico das últimas corridas (`GetAvailableCombatSessions`)
- [ ] Relatório para o chat (só fora de combate — os dados são secret durante)
