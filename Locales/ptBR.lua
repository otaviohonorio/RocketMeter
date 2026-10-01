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
L["CC"] = "Controle"
L["Crowd control used"] = "Controle usado"
L["Session"] = "Sessão"
L["Open the scoreboard of this session"] = "Abrir o placar desta sessão"
L["total"] = "total"
L["per s"] = "por s"
L["share"] = "parte"
L["Interrupts cast"] = "Interrupções lançadas"
L["%s (%d missed)"] = "%s (%d erraram)"
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
L["Left-click: options"] = "Clique: opções"
L["Right-click: scoreboard of the last run"] = "Clique direito: placar da última corrida"
L["Shift-click: show or hide the meter"] = "Shift+clique: mostra ou esconde o medidor"
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
L["lists who the API reports in each metric"] =
    "lista quem a API reporta em cada métrica"

L["error while drawing:"] = "erro ao desenhar:"

-- Log de diagnostico (0.13.0)
L["records a diagnostic snapshot"] = "grava uma foto de diagnóstico"
L["log cleared."] = "log limpo."
L["the log only exists in development builds."] = "o diário só existe na versão de desenvolvimento."
L["snapshot saved (%d entries). Type /reload so the file is written."] =
    "foto gravada (%d entradas). Digite /reload para o arquivo ser escrito."

-- Skin da barra (0.14.0)

L["in combat"] = "em combate"

-- Configurador de layout (0.17.0)
L["Configure"] = "Configurar"

-- Detalhamento por magia (0.37.0)
L["Damage"] = "Dano"
L["Healing"] = "Cura"
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

-- Seção Placar e opção de reino (0.54.0)
L["Scoreboard"] = "Placar"
L["Open at the end of a Mythic+ run"] = "Abrir ao fim de uma corrida de Mítico+"
L["When the keystone ends, the summary of the run opens by itself."] =
    "Quando a chave termina, o resumo da corrida abre sozinho."
L["Open when a raid boss dies"] = "Abrir quando um chefe de raide morrer"
L["When an encounter is defeated, the summary of the fight opens by itself."] =
    "Quando o encontro é vencido, o resumo da luta abre sozinho."
L["Show the realm next to the name"] = "Mostrar o reino ao lado do nome"
L["Off by default: the realm eats the column and the name is what ends up cut."] =
    "Desligado por padrão: o reino come a coluna e quem acaba cortado é o nome."

-- Estado do cadeado em palavras (0.55.0): o icone mudou de FORMA, mas a dica e o canal que
-- nao depende de interpretar um desenho de 14px.
L["Locked — click to unlock and resize"] = "Travado — clique para destravar e redimensionar"
L["Unlocked — drag to move, corner to resize"] = "Destravado — arraste para mover, canto para redimensionar"

-- Corpo do texto configuravel (0.57.0)
L["Text size"] = "Tamanho do texto"

-- Configurador em abas (0.58.0)
L["Font"] = "Fonte"
L["Font outline"] = "Contorno da fonte"
L["Font shadow"] = "Sombra da fonte"
L["A 1px black shadow below the text. Carries the letters over any background."] =
    "Sombra preta de 1px abaixo do texto. Carrega as letras sobre qualquer fundo."
L["the font %s could not be loaded; using the default."] =
    "não deu para carregar a fonte %s; usando a padrão."
L["Columns"] = "Colunas"
L["None"] = "Nenhum"
L["Thin"] = "Fino"
L["Thick"] = "Grosso"
L["Appearance"] = "Aparência"

-- Tres textos independentes (0.60.0)
L["Row text"] = "Texto das linhas"
L["Title"] = "Título"
L["Column header"] = "Cabeçalho das colunas"

-- O placar copiado do Details! Mythic+ Scoreboard (0.66.0)
L["Keystone"] = "Pedra"
L["Loot"] = "Saque"
L["Not in combat: %s"] = "Fora de combate: %s"

-- A visao segue o combate (0.79.0)
L["Follow the combat"] = "Acompanhar o combate"
L["In combat, the current fight; when it ends, back to the overall."] =
    "Em combate, a luta atual; quando ela acaba, volta para o geral."

-- Captura de erro no diario (RocketMeter 0.80.0 / RocketSwap 0.21.0)
L["errors are NOT being captured on this client."] =
    "os erros NAO estao sendo capturados neste cliente."
L["no error captured (capture: %s)."] = "nenhum erro capturado (captura: %s)."
L["%d error(s) captured, %d occurrence(s):"] = "%d erro(s) capturado(s), %d ocorrencia(s):"

-- As duas distancias da linha, configuraveis (0.81.0)
L["Space between columns"] = "Espaço entre colunas"
L["Width of the total column"] = "Largura da coluna de total"

-- Doação (Donate.lua, 26/09)
L["Link copied — paste it in your browser."] = "Link copiado — cole no navegador."
L["Thank you for supporting Rocket Meter! Press Ctrl+C to copy the link, then paste it in your browser."] = "Obrigado por apoiar o Rocket Meter! Aperte Ctrl+C para copiar o link e cole no navegador."
L["Opens the donation link, ready to copy."] = "Abre o link de doação, pronto para copiar."
L["Support the project"] = "Apoiar o projeto"
L["Report a problem"] = "Relatar um problema"
L["Report a problem on"] = "Relatar um problema em"
L["Opens the address to report a problem, ready to copy."] = "Abre o endereço para relatar um problema, pronto para copiar."
L["Rocket Meter %s — report a problem on %s.|n|nPress Ctrl+C to copy the link, then paste it in your browser. Say what you were doing and what happened."] =
    "Rocket Meter %s — relatar um problema em %s.|n|nAperte Ctrl+C para copiar o endereço e cole no navegador. Conte o que você estava fazendo e o que aconteceu."

-- Minha corrida (01/10): a tela individual do jogador.
L["Whole run"] = "Todo o combate"
L["This fight"] = "Luta atual"
L["Trash"] = "Pacotes"
L["trash"] = "pacotes"
L["deaths"] = "mortes"
L["cause unknown"] = "causa desconhecida"
L["avoidable"] = "evitável"
L["%s blow"] = "golpe de %s"
L["hardest: %s"] = "maior dano: %s"
L["Died at %s — %s"] = "Morreu aos %s — %s"
L["avoidable damage"] = "dano evitável"
L["%s of avoidable damage"] = "%s de dano evitável"
L["%d%% of all you took · %s of the group"] = "%d%% de tudo que você tomou · %s do grupo"
L["%dº"] = "%dº"
L["interrupts"] = "interrupções"
L["%d of %d interrupts cut nothing"] = "%d das %d interrupções não cortaram nada"
L["kicked a target that was not casting, or someone cut first"] = "chute em quem não lançava, ou outro cortou antes"
L["%d%% missed"] = "%d%% de erro"
L["cooldowns"] = "recargas"
L["%s: used %d times; %d fitted"] = "%s: usada %d vezes; cabiam %d"
L["cooldown of %s · idle %s in total"] = "recarga de %s · parada %s no total"
L["gaps without casting"] = "vãos sem lançar"
L["%d gaps without casting of more than %d s in combat"] = "%d vãos sem lançar de mais de %d s em combate"
L["%s idle in total · the longest: %d s at %s"] = "%s parado no total · o maior: %d s aos %s"
L["%d/min"] = "%d/min"
L["potions"] = "poções"
L["Potion in %d of %d bosses"] = "Poção em %d dos %d chefes"
L["the healthstone was not used"] = "a pedra de vida não foi usada"
L["healthstone used %d times"] = "pedra de vida usada %d vezes"
L["deaths of the group"] = "mortes do grupo"
L["%d deaths in the group"] = "%d mortes no grupo"
L["the scoreboard says who and when"] = "o placar diz quem e quando"
L["My run"] = "Meu combate"
L["Summary"] = "Resumo"
L["Spells"] = "Magias"
L["This run"] = "Este combate"
L["What cost"] = "O que custou"
L["DAMAGER"] = "DPS"
L["TANK"] = "Tanque"
L["HEALER"] = "Curandeiro"
L["Rhythm"] = "Ritmo"
L["Cooldowns — used / fitted"] = "Recargas — usadas / cabiam"
L["History"] = "Histórico"
L["%dº of the group"] = "%dº do grupo"
L["in total"] = "no total"
L["out of combat only"] = "só fora de combate"
L["Avoidable damage taken"] = "Dano evitável tomado"
L["%d%% of what you took"] = "%d%% do que você tomou"
L["%d cast cut nothing"] = "%d lançadas não cortaram"
L["Death"] = "Morte"
L["at %s"] = "aos %s"
L["Nothing found: no death, no avoidable damage worth the name, cooldowns on time."] = "Nada encontrado: nenhuma morte, dano evitável sem peso, recargas em dia."
L["Looked at: %s."] = "Olhado: %s."
L["(defensive)"] = "(defensivo)"
L["The game's Cooldown Manager lists no cooldown for this spec."] = "O Gerenciador de Recargas do jogo não lista recarga para esta especialização."
L["In combat the meter's numbers are hidden; they come back when it ends."] = "Em combate os números do medidor ficam escondidos; voltam quando ele acaba."
L["Nothing taken."] = "Nada recebido."
L["%d%% avoidable"] = "%d%% evitável"
L["Time casting in combat"] = "Tempo lançando em combate"
L["Casts per minute"] = "Lançamentos por minuto"
L["Potion / healthstone"] = "Poção / pedra de vida"
L["Run"] = "Combate"
L["Avoidable"] = "Evitável"
L["Interr."] = "Interr."
L["No run saved yet."] = "Nenhum combate guardado ainda."
L["No run recorded yet: start a key or a raid."] = "Nenhum combate gravado ainda: comece uma chave ou uma raide."
L["My deaths"] = "Minhas mortes"
L["Killed"] = "Matou"
L["Hardest"] = "Maior dano"
L["Killed and hardest"] = "Matou e maior dano"
L["No death in this scope."] = "Nenhuma morte neste trecho."
L["Blow by blow"] = "Golpe a golpe"
L["Click a death."] = "Clique numa morte."
L["%d blows, the last %s s before the death · %s of life"] = "%d golpes, os últimos %s s antes da morte · %s de vida"
L["The game kept no blow of this death."] = "O jogo não guardou golpe nenhum desta morte."
L["absorbed"] = "absorvido"
L["Timeline"] = "Linha do tempo"
L["Casts"] = "Lançamentos"
L["Role"] = "Papel"
L["Per second"] = "Por segundo"
L["Cooldowns"] = "Recargas"
L["Casts/min"] = "Lanç./min"
L["Click a line to open it."] = "Clique numa linha para abri-la."
L["History — the last %d"] = "Histórico — os últimos %d"
L["by fight: %s, up to %s"] = "por luta: %s, até %s"
L["by fight: the numbers come at the end of each fight"] = "por luta: os números chegam no fim de cada luta"
L["%d%% · %s idle of %s"] = "%d%% · %s parado de %s"
L["%d · %d casts"] = "%d · %d lançamentos"
L["Casts — %d in %s of combat"] = "Lançamentos — %d em %s de combate"
L["%d · %d%% · %.1f/min"] = "%d · %d%% · %.1f/min"
L["No cast in this scope."] = "Nenhum lançamento neste trecho."
L["one shot · %s"] = "um golpe só · %s"
L["%s in %.1f s · %s"] = "%s em %.1f s · %s"
L["This fight's numbers were not kept."] = "Os números desta luta não foram guardados."
L["The game's Cooldown Manager list, with the cooldown of each."] = "A lista do Gerenciador de Recargas do jogo, com a recarga de cada uma."
