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

-- Limpar dados (0.10.0)
L["Clear the data"] = "Limpar dados"
L["Clear the current fight and the overall? This cannot be undone."] =
    "Limpar o combate atual e o geral? Nao da para desfazer."

-- Aparencia (0.11.0)
L["Appearance"] = "Aparência"
L["Font"] = "Fonte"
L["Typeface used by the window."] = "Tipo de letra usado na janela."
L["Font size"] = "Tamanho da fonte"
L["Size of the text in the rows."] = "Tamanho do texto nas linhas."
L["Row height"] = "Altura da linha"
L["Thickness of each bar."] = "Espessura de cada barra."
L["Column width"] = "Largura da coluna"
L["Width reserved for each metric."] = "Espaço reservado para cada métrica."
L["Row icon"] = "Ícone da linha"
L["Specialization"] = "Especialização"
L["Class"] = "Classe"
L["Specialization says more than class: who heals, who tanks."] =
    "A especialização diz mais que a classe: quem cura, quem tanka."

-- Realce do lider por coluna (0.12.0)
L["Highlight the leader of each column"] = "Realçar quem lidera cada coluna"
L["Gold for what is good to lead, red for damage taken and deaths."] =
    "Dourado para o que é bom liderar, vermelho para dano recebido e mortes."
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
L["Bar texture"] = "Textura da barra"
L["Look of the filled bar."] = "Aparência do preenchimento."
L["Bar brightness"] = "Brilho da barra"
L["Lower values darken the bar so the white text reads better."] =
    "Valores menores escurecem a barra e o texto branco fica mais legível."
L["Text outline"] = "Contorno do texto"
L["Outline keeps the text readable over any bar colour."] =
    "O contorno mantém o texto legível sobre qualquer cor de barra."
L["Thin"] = "Fino"
L["Thick"] = "Grosso"
L["None"] = "Nenhum"

L["Row border"] = "Borda na linha"
L["Separates one bar from the next."] = "Separa uma barra da outra."

L["in combat"] = "em combate"

-- Configurador de layout (0.17.0)
L["Configure"] = "Configurar"
L["Window opacity"] = "Opacidade da janela"
L["Bar opacity"] = "Opacidade da barra"
L["Round icons"] = "Ícones redondos"
L["Column header"] = "Faixa de colunas"

L["Fit height to the rows"] = "Ajustar altura ao conteúdo"

-- Painel unico (0.18.0)
L["Open the settings"] = "Abrir as opções"
L["Opacity of the coloured fill."] = "Opacidade do preenchimento colorido."
L["Opacity of the window background."] = "Opacidade do fundo da janela."
L["Circular icon, like the built-in meter."] = "Ícone circular, como no medidor nativo."
L["Strip with the column names."] = "Faixa com os nomes das colunas."
L["The window shrinks to the number of players with data."] =
    "A janela encolhe para o número de jogadores com dados."

-- Detalhamento por magia (0.37.0)
L["Damage"] = "Dano"
L["Healing"] = "Cura"
L["Control"] = "Controle"
L["nothing here"] = "nada aqui"
L["Click to see the spell breakdown."] = "Clique para ver o detalhamento por magia."
L["the spell breakdown of other players is only available out of combat."] =
    "o detalhamento de outros jogadores só fica disponível fora de combate."

L["restart the client: the breakdown module was not loaded yet."] =
    "reinicie o cliente: o módulo de detalhamento ainda não foi carregado."

-- Placar reconstruido (0.51.0)
L["Score"] = "Pont."
L["%d deaths"] = "%d mortes"
L["Simulation — invented data."] = "Simulação — dados inventados."
L["Preview the scoreboard"] = "Ver o placar"
L["Opens the end-of-run panel with invented data, so you can see it without running a dungeon."] =
    "Abre o painel de fim de corrida com dados inventados, para ver como ficou sem precisar rodar uma masmorra."
L["opens the scoreboard with invented data"] = "abre o placar com dados inventados"
L["restart the client: the demo module was not loaded yet."] =
    "reinicie o cliente: o módulo de simulação ainda não foi carregado."

-- Nomes da corrida simulada. Masmorra inventada de proposito: nome de masmorra real daria a
-- entender que o placar sabe algo sobre ela.
L["Ruins of the Ember Court"] = "Ruínas da Corte de Brasas"
L["First boss"] = "Primeiro chefe"
L["Second boss"] = "Segundo chefe"
L["Last boss"] = "Último chefe"

-- Conferencia de atlas (0.51.0). SetAtlas com nome errado falha em silencio; este comando
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
