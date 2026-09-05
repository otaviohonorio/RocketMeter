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
L["Profile"] = "Perfil"
L["Settings for this character only"] = "Configuração só deste personagem"
L["Off: every character shares the same setup. On: this character keeps its own."] =
    "Desligado: todos os personagens usam a mesma configuração. Ligado: este guarda a dele."
L["settings for this character only."] = "configuração própria deste personagem."
L["settings shared by the account."] = "configuração compartilhada pela conta."
L["settings restored to the defaults."] = "configuração restaurada para o padrão."
L["moves a column left or right"] = "move uma coluna para a esquerda ou direita"
L["account-wide or per-character settings"] = "configuração da conta ou do personagem"

-- Opções
L["Presets"] = "Conjuntos prontos"
L["Visible columns"] = "Colunas visíveis"
L["Window"] = "Janela"
L["Apply preset"] = "Aplicar conjunto"
L["Changes every column at once."] = "Troca todas as colunas de uma vez."
L["Show as a column."] = "Mostra como coluna."
L["Lock position"] = "Travar posição"
L["Prevents dragging the window by accident."] = "Impede arrastar a janela sem querer."
L["Rows"] = "Linhas"
L["How many players to show."] = "Quantos jogadores mostrar."
L["Scale"] = "Escala"
L["Window size."] = "Tamanho da janela."
L["Scoreboard at the end of M+ and raid"] = "Placar ao fim de M+ e raide"
L["Opens the run summary automatically when it ends."] = "Abre sozinho o resumo da corrida quando ela termina."

-- Painel de colunas e minimapa
L["Columns"] = "Colunas"
L["Configure columns"] = "Configurar colunas"
L["More options"] = "Mais opções"
L["opens the column panel"] = "abre o painel de colunas"
L["Minimap button"] = "Botão no minimapa"
L["Shows the Rocket Meter button on the minimap."] = "Mostra o botão do Rocket Meter no minimapa."
L["Left-click: show or hide the meter"] = "Clique: mostra ou esconde o medidor"
L["Shift-click: scoreboard of the last run"] = "Shift+clique: placar da última corrida"
L["Right-click: options"] = "Clique direito: opções"
L["Drag to move around the minimap."] = "Arraste para mover ao redor do minimapa."

-- Janela e combate
L["Click to switch between the current fight and the overall."] =
    "Clique para alternar entre o combate atual e o geral."
L["Show only in combat"] = "Mostrar só em combate"
L["The window appears when the fight starts and hides a few seconds after it ends."] =
    "A janela aparece quando a luta começa e some alguns segundos depois que ela acaba."

-- Placar
L["Dungeon"] = "Masmorra"
L["Encounter"] = "Encontro"
L["on time"] = "no tempo"
L["over time"] = "fora do tempo"
L["Total time"] = "Tempo total"
L["defeated"] = "derrotado"
L["Click a column header to sort. Drag to move."] =
    "Clique num cabeçalho para ordenar. Arraste para mover."
L["no run recorded in this session yet."] = "nenhuma corrida registrada nesta sessão ainda."

-- Mensagens
L["loaded. Type /rm for the commands."] = "carregado. Digite /rm para ver os comandos."
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
L["Close"] = "Fechar"

-- Colunas novas (0.9.0)
L["Dmg%"] = "Dano%"
L["Heal%"] = "Cura%"
L["TPS"] = "RPS"
L["Share of the group damage"] = "Fatia do dano do grupo"
L["Share of the group healing"] = "Fatia da cura do grupo"
L["Damage taken per second"] = "Dano recebido por segundo"
L["columns migrated to the new format."] = "colunas convertidas para o formato novo."
