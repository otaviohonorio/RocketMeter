-- RocketMeter | Locales/ptBR.lua
local ADDON, ns = ...

if GetLocale() ~= "ptBR" then return end

local L = ns.L

-- Cabeçalhos de coluna (curtos: precisam caber em ~50px)
L["Dmg"] = "Dano"
L["DPS"] = "DPS"
L["Heal"] = "Cura"
L["HPS"] = "CPS"
L["Absorb"] = "Absor"
L["Taken"] = "Recebi"
L["Avoid"] = "Evitáv"
L["Interr"] = "Interr"
L["Dispel"] = "Dissip"
L["Deaths"] = "Mortes"
L["Enemies"] = "Inimig"

-- Nomes longos (usados no tooltip e nas opções)
L["Total damage"] = "Dano total"
L["Damage per second"] = "Dano por segundo"
L["Total healing"] = "Cura total"
L["Healing per second"] = "Cura por segundo"
L["Absorbs"] = "Absorções"
L["Damage taken"] = "Dano recebido"
L["Avoidable damage"] = "Dano evitável"
L["Interrupts"] = "Interrupções"
L["Dispels"] = "Dissipações"
L["Player deaths"] = "Mortes"
L["Damage on enemies"] = "Dano nos inimigos"

-- Janela
L["Current fight"] = "Combate atual"
L["Overall"] = "Geral"
L["Click to sort by this column."] = "Clique para ordenar por esta coluna."

-- Conjuntos
L["Mythic+"] = "Mítico+"
L["Raid"] = "Raide"
L["Damage only"] = "Só dano"

-- Ordenação e perfil
L["Click again to reverse the order."] = "Clique de novo para inverter a ordem."
L["Shift-click moves it left, Ctrl-click moves it right."] =
    "Shift+clique move para a esquerda, Ctrl+clique para a direita."
L["settings for this character only."] = "configuração própria deste personagem."
L["settings shared by the account."] = "configuração compartilhada pela conta."
L["settings restored to the defaults."] = "configuração restaurada para o padrão."
L["moves a column left or right"] = "move uma coluna para a esquerda ou direita"
L["account-wide or per-character settings"] = "configuração da conta ou do personagem"

-- Opções
L["Lock position"] = "Travar posição"
L["Rows"] = "Linhas"

-- Painel de colunas e minimapa
L["Configure columns"] = "Configurar colunas"
L["opens the column panel"] = "abre o painel de colunas"
L["Left-click: show or hide the meter"] = "Clique: mostra ou esconde o medidor"
L["Shift-click: scoreboard of the last run"] = "Shift+clique: placar da última corrida"
L["Right-click: options"] = "Clique direito: opções"
L["Drag to move around the minimap."] = "Arraste para mover ao redor do minimapa."

-- Janela e combate
L["Click to switch between the current fight and the overall."] =
    "Clique para alternar entre o combate atual e o geral."

-- Placar
L["Dungeon"] = "Masmorra"
L["Encounter"] = "Encontro"
L["on time"] = "no tempo"
L["over time"] = "fora do tempo"
L["defeated"] = "derrotado"
L["Click a column header to sort. Drag to move."] =
    "Clique num cabeçalho para ordenar. Arraste para mover."
L["no run recorded in this session yet."] = "nenhuma corrida registrada nesta sessão ainda."

-- Mensagens
L["the native meter (C_DamageMeter) is not available on this client."] =
    "o medidor nativo (C_DamageMeter) não está disponível neste cliente."
L["at least one column must stay."] = "é preciso manter ao menos uma coluna."
L["sessions cleared."] = "sessões zeradas."
L["showing the current fight."] = "mostrando o combate atual."
L["showing the overall."] = "mostrando o geral."
L["columns applied:"] = "colunas aplicadas:"
L["column toggled:"] = "coluna alternada:"
L["available presets:"] = "conjuntos disponíveis:"
L["columns (type the number to toggle):"] = "colunas (número liga/desliga):"

-- Ajuda
L["version"] = "versão"
L["commands:"] = "comandos:"
L["opens or closes the window"] = "abre ou fecha a janela"
L["lists the columns or toggles one"] = "lista as colunas ou liga/desliga uma"
L["switches the column preset"] = "troca o conjunto de colunas"
L["opens the scoreboard of the last run"] = "abre o placar da última corrida"
L["switches current fight / overall"] = "alterna combate atual / geral"
L["clears the sessions"] = "zera as sessões"
L["opens the options"] = "abre as opções"
L["(click a column header to sort by it)"] = "(clique num cabeçalho de coluna para ordenar por ela)"

-- Colunas novas (0.9.0)
L["Dmg%"] = "Dano%"
L["Heal%"] = "Cura%"
L["TPS"] = "RPS"
L["Share of the group damage"] = "Fatia do dano do grupo"
L["Share of the group healing"] = "Fatia da cura do grupo"
L["Damage taken per second"] = "Dano recebido por segundo"
L["columns migrated to the new format."] = "colunas convertidas para o formato novo."

-- Limpar dados (0.10.0)
L["Clear the data"] = "Limpar dados"
L["Clear the current fight and the overall? This cannot be undone."] =
    "Limpar o combate atual e o geral? Nao da para desfazer."

-- Realce do lider por coluna (0.12.0)
L["The leader of each column is highlighted, out of combat."] =
    "Quem lidera cada coluna fica realçado, fora de combate."

L["prints what the API is returning"] = "mostra o que a API está devolvendo"

L["error while drawing:"] = "erro ao desenhar:"

-- Log de diagnostico (0.13.0)
L["records a diagnostic snapshot"] = "grava uma foto de diagnóstico"
L["log cleared."] = "log limpo."
L["snapshot saved (%d entries). Type /reload so the file is written."] =
    "foto gravada (%d entradas). Digite /reload para o arquivo ser escrito."

-- Skin da barra (0.14.0)

L["in combat"] = "em combate"

-- Configurador de layout (0.17.0)
L["Configure"] = "Configurar"

-- Detalhamento por magia (0.37.0)
L["Damage"] = "Dano"
L["Healing"] = "Cura"
L["Control"] = "Controle"
L["nothing here"] = "nada aqui"
L["the spell breakdown of other players is only available out of combat."] =
    "o detalhamento de outros jogadores só fica disponível fora de combate."

L["restart the client: the breakdown module was not loaded yet."] =
    "reinicie o cliente: o módulo de detalhamento ainda não foi carregado."

-- Placar reconstruido (0.51.0)
L["Score"] = "Pont."
L["%d deaths"] = "%d mortes"
L["Simulation — invented data."] = "Simulação — dados inventados."
L["opens the scoreboard with invented data"] = "abre o placar com dados inventados"
L["restart the client: the demo module was not loaded yet."] =
    "reinicie o cliente: o módulo de simulação ainda não foi carregado."

-- entender que o placar sabe algo sobre ela.
L["Ruins of the Ember Court"] = "Ruínas da Corte de Brasas"
L["First boss"] = "Primeiro chefe"
L["Second boss"] = "Segundo chefe"
L["Last boss"] = "Último chefe"

-- troca "acho que existe" por um dado.
L["checks whether the panel art exists"] = "confere se a arte do painel existe"
L["checking %d atlas name(s):"] = "conferindo %d nome(s) de atlas:"
L["%d name(s) do not exist on this client."] = "%d nome(s) não existem neste cliente."

-- Placares guardados (0.52.0)
L["Last Mythic+"] = "Último Mítico+"
L["Last raid"] = "Última raide"
L["Opens the scoreboard of the last Mythic+ run finished on this character."] =
    "Abre o placar da última corrida de Mítico+ concluída neste personagem."
L["Opens the scoreboard of the last raid boss defeated on this character."] =
    "Abre o placar do último chefe de raide derrotado neste personagem."
L["opens the last Mythic+ scoreboard"] = "abre o último placar de Mítico+"
L["opens the last raid scoreboard"] = "abre o último placar de raide"
L["no Mythic+ run recorded yet."] = "nenhuma corrida de Mítico+ registrada ainda."
L["no raid encounter recorded yet."] = "nenhum chefe de raide registrado ainda."
L["%d min ago"] = "há %d min"
L["%d h ago"] = "há %d h"
L["%d d ago"] = "há %d dia(s)"

-- Conferencia dos rotulos que vem do jogo (0.53.0). Mesmo motivo do /rm atlas: a falha e
-- silenciosa — a global some e o rotulo so continua em ingles.
L["checks the labels taken from the game"] = "confere os rotulos que vem do jogo"
L["locale %s, %d game label(s):"] = "idioma %s, %d rotulo(s) vindos do jogo:"
L["%d game label(s) are not usable here."] = "%d rotulo(s) do jogo nao servem neste cliente."
