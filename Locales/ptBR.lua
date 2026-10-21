-- RocketMeter | Locales/ptBR.lua
local ADDON, ns = ...

if GetLocale() ~= "ptBR" then return end

local L = ns.L

-- Cabeçalhos de coluna (curtos: precisam caber em ~50px)
L["Dmg"] = "Dano"
L["DPS"] = "DPS"
L["Heal"] = "Cura"
L["HPS"] = "CPS"
L["Absorb"] = "Absorv."
L["Taken"] = "Receb."
L["Avoid"] = "Evitáv."
L["Interr"] = "Interr."
L["Dispel"] = "Dissip."
L["Deaths"] = "Mortes"
L["Enemies"] = "Inimig."

-- Nomes longos (usados no tooltip e nas opções)
L["Total damage"] = "Dano total"
L["Damage done"] = "Dano causado"         -- (20/10) igual ao DAMAGE_METER_TYPE_DAMAGE_DONE do jogo; aqui para o harness, que nao tem as globais
L["Damage per second"] = "Dano por segundo"
L["Total healing"] = "Cura total"
L["Healing per second"] = "Cura por segundo"
L["Absorbs"] = "Absorções"
L["Damage taken"] = "Dano recebido"
L["Avoidable damage"] = "Dano evitável"
L["Interrupts"] = "Interrupções"
L["Crowd control used"] = "Controle usado"
L["Session"] = "Sessão"
L["Open the scoreboard of this session"] = "Abrir o placar desta sessão"
L["Click: your own performance in this run"] = "Clique: o seu desempenho nesta corrida"
L["total"] = "total"
L["per s"] = "por s"
L["share"] = "parte"
L["Interrupts cast"] = "Interrupções lançadas"
L["%s (%d missed)"] = "%s (%d sem efeito)"
L["Dispels"] = "Dissipações"
L["Player deaths"] = "Mortes"
L["Damage on enemies"] = "Dano nos inimigos"

-- Janela
L["Current fight"] = "Combate atual"
L["Overall"] = "Geral"

-- Conjuntos
L["Mythic+"] = "Mítico+"
L["Raid"] = "Raide"
L["Damage only"] = "Só dano"

-- Ordenação e perfil
L["settings for this character only."] = "configuração própria deste personagem."
L["settings shared by the account."] = "configuração compartilhada pela conta."
L["settings restored to the defaults."] = "configuração restaurada para o padrão."
L["moves a column left or right"] = "move uma coluna para a esquerda ou direita"
L["account-wide or per-character settings"] = "configuração da conta ou do personagem"

-- Opções
L["Lock position"] = "Travar posição"
L["Rows"] = "Linhas"

-- Painel de colunas e minimapa

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
L["(click a column header to sort by it)"] = "(clique num cabeçalho de coluna para ordenar por ela)"

-- Colunas novas (0.9.0)
L["Dmg%"] = "Dano%"
L["Heal%"] = "Cura%"
L["TPS"] = "RPS"
L["Share of the group damage"] = "Parte do dano do grupo"
L["Share of the group healing"] = "Parte da cura do grupo"
L["Damage taken per second"] = "Dano recebido por segundo"
L["columns migrated to the new format."] = "colunas convertidas para o formato novo."

-- Limpar dados (0.10.0)
L["Clear the data"] = "Limpar dados"
L["Clear the current fight and the overall? This cannot be undone."] =
    "Limpar o combate atual e o geral? Não dá para desfazer."

-- Realce do lider por coluna (0.12.0)

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
L["another player's screen opens only out of combat."] =
    "a tela de outro jogador só abre fora de combate."

L["restart the client: the breakdown module was not loaded yet."] =
    "reinicie o cliente: o módulo de detalhamento ainda não foi carregado."

-- Placar reconstruido (0.51.0)
L["Score"] = "Pont."
L["%d deaths"] = "%d mortes"
L["%d death"] = "%d morte"
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
L["locale %s, %d game label(s):"] = "idioma %s, %d rótulo(s) vindos do jogo:"
L["%d game label(s) are not usable here."] = "%d rótulo(s) do jogo não servem neste cliente."

-- Seção Placar e opção de reino (0.54.0)
L["Scoreboard"] = "Placar"
L["Open at the end of a Mythic+ run"] = "Abrir ao fim de uma corrida de Mítico+"
L["When the keystone ends, the summary of the run opens by itself."] =
    "Quando a chave termina, o resumo da corrida abre sozinho."
L["Open when a raid boss dies"] = "Abrir quando um chefe de raide morrer"
L["When an encounter is defeated, the summary of the fight opens by itself."] =
    "Quando o encontro é vencido, o resumo da luta abre sozinho."
L["Record the combat log in instances"] = "Gravar o registro de combate nas instâncias"
L["On in dungeons, raids and delves, off when leaving: the file Warcraft Logs uploads (its own app sends it; it also asks for the game's advanced combat log). A log you turned on yourself is left alone."] =
    "Liga em masmorras, raides e imersões e desliga ao sair: é o arquivo que o Warcraft Logs envia (pelo programa dele, que também pede o registro de combate avançado do jogo). O registro que você mesmo ligou fica como está."
L["Specialization icon"] = "Ícone da especialização"
L["Square"] = "Quadrado"
L["Round"] = "Redondo"
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
    "não foi possível carregar a fonte %s; usando a padrão."
L["Columns"] = "Colunas"
L["None"] = "Nenhum"
L["Thin"] = "Fino"
L["Thick"] = "Grosso"
L["Appearance"] = "Aparência"

-- Tres textos independentes (0.60.0)
L["Row text"] = "Texto das linhas"
L["Title"] = "Título"
L["Column header"] = "Cabeçalho das colunas"

-- O placar de Mítico+ (0.66.0)
L["Keystone"] = "Pedra"
L["Loot"] = "Saque"
L["Not in combat: %s"] = "Fora de combate: %s"

-- A visao segue o combate (0.79.0)
L["Follow the combat"] = "Acompanhar o combate"
L["In combat, the current fight; when it ends, back to the overall."] =
    "Em combate, a luta atual; quando ela acaba, volta para o geral."

-- Captura de erro no diario (RocketMeter 0.80.0 / RocketSwap 0.21.0)
L["errors are NOT being captured on this client."] =
    "os erros NÃO estão sendo capturados neste cliente."
L["no error captured (capture: %s)."] = "nenhum erro capturado (captura: %s)."
L["%d error(s) captured, %d occurrence(s):"] = "%d erro(s) capturado(s), %d ocorrencia(s):"

-- As duas distancias da linha, configuraveis (0.81.0)
L["Space between columns"] = "Espaço entre colunas"
L["Width of the total column"] = "Largura da coluna de total"

-- Doação (Donate.lua, 26/09)
L["Link copied — paste it in your browser."] = "Link copiado — cole no navegador."
L["Thank you for supporting Rocket Meter! Press Ctrl+C to copy the link, then paste it in your browser."] = "Obrigado por apoiar o Rocket Meter! Aperte Ctrl+C para copiar o link e cole no navegador."
L["Click: open the donation link, ready to copy"] = "Clique: abrir o link de doação, pronto para copiar"
L["Support the project"] = "Apoiar o projeto"
L["Report a problem"] = "Relatar um problema"
L["Report a problem on"] = "Relatar um problema em"
L["Click: choose where to report a problem"] = "Clique: escolher onde relatar um problema"
L["Rocket Meter %s — report a problem on %s.|n|nPress Ctrl+C to copy the link, then paste it in your browser. Say what you were doing and what happened."] =
    "Rocket Meter %s — relatar um problema em %s.|n|nAperte Ctrl+C para copiar o endereço e cole no navegador. Conte o que você estava fazendo e o que aconteceu."

-- Minha corrida (01/10): a tela individual do jogador.
L["Whole run"] = "Todo o combate"
L["Open world"] = "Mundo aberto"
L["Other casts"] = "Outros lançamentos"
L["/min"] = "/min"
L["Total"] = "Total"
L["%"] = "%"
L["Player"] = "Jogador"
L["In combat the game only lets your own spells be read."] = "Em combate o jogo só deixa ler as suas próprias magias."
L["No spell to show yet."] = "Nenhuma magia para mostrar ainda."
L["Healing and absorbs"] = "Cura e absorção"
L["+ %s absorbed"] = "+ %s absorvido"
L["Delve"] = "Imersão"
L["Tier %d"] = "Grau %d"
L["Nothing recorded yet: it starts at your next fight."] = "Nada gravado ainda: a gravação começa na sua próxima luta."
L["%d%% of all you took"] = "%d%% de tudo que você recebeu"
L["Your talents: direct damage"] = "Seus talentos: dano direto"
L["Your talents: direct healing"] = "Seus talentos: cura direta"
L["Your talents: damage absorbed"] = "Seus talentos: dano absorvido"
L["%s (%d%% of the total)"] = "%s (%d%% do total)"
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
L["interrupts"] = "interrupções"
L["%d of %d interrupts cut nothing"] = "%d das %d interrupções sem efeito"
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
L["DAMAGER"] = "DPS"
L["TANK"] = "Tanque"
L["HEALER"] = "Curandeiro"
L["History"] = "Histórico"
L["#%d in the group"] = "%dº do grupo"
L["in total"] = "no total"
L["out of combat only"] = "só fora de combate"
L["%d cast cut nothing"] = "%d sem efeito"
L["Death"] = "Morte"
L["at %s"] = "aos %s"
L["In combat the meter's numbers are hidden; they come back when it ends."] = "Em combate os números do medidor ficam escondidos; voltam quando ele acaba."
L["Nothing taken."] = "Nada recebido."
L["%d%% avoidable"] = "%d%% evitável"
L["Casts per minute"] = "Lançamentos por minuto"
L["Run"] = "Combate"
L["Avoidable"] = "Evitável"
L["Interr."] = "Interr."
L["No run saved yet."] = "Nenhum combate guardado ainda."
L["No death in this scope."] = "Nenhuma morte neste trecho."
L["Blow by blow"] = "Golpe a golpe"
L["The game kept no blow of this death."] = "O jogo não guardou golpe nenhum desta morte."
L["absorbed"] = "absorvido"
L["Casts"] = "Lançamentos"
L["Role"] = "Papel"
L["Per second"] = "Por segundo"
L["Cooldowns"] = "Recargas"
L["Casts/min"] = "Lanç./min"
L["Click a line to open it."] = "Clique numa linha para abri-la."
L["History — the last %d"] = "Histórico — os últimos %d"
L["Casts — %d in %s of combat"] = "Lançamentos — %d em %s de combate"
L["No cast in this scope."] = "Nenhum lançamento neste trecho."
L["This fight's numbers were not kept."] = "Os números desta luta não foram guardados."

-- Cooldowns used only when needed (01/10).

-- The screen of another player (01/10).
L["Share of the group"] = "Parte do grupo"
L["No death."] = "Nenhuma morte."
L["time not given by the game"] = "hora não informada pelo jogo"
L["Casts, cooldowns, rhythm and the blows of a death are only readable for your own character: the game hides them for other players."] =
    "Lançamentos, recargas, ritmo e os golpes de uma morte só podem ser lidos do seu próprio personagem: o jogo os esconde para os outros jogadores."

-- the minimap tooltip, the same in every Rocket addon (13/10)
L["Click: open the options"] = "Clique: abrir as opções"
L["Shift-click: show or hide the meter"] = "Shift + clique: mostrar ou esconder o medidor"
L["Right-click: open the scoreboard of the last run"] = "Clique direito: abrir o placar da última corrida"

L["Not counted: automatic effects, the world and delves"] = "Fora da conta: efeitos automáticos, do mundo e das imersões"

L["columns that no longer exist were removed."] = "as colunas que não existem mais foram retiradas."
L["shows or hides the meter"] = "mostra ou esconde o medidor"
L["opens or closes the settings"] = "abre ou fecha a configuração"
L["Show the minimap button"] = "Mostrar o botão do minimapa"
L["The addon compartment, by the minimap, keeps opening the meter without it."] = "Sem ele, o compartimento de addons, ao lado do minimapa, continua abrindo o medidor."
L["Click: sort by this column"] = "Clique: ordenar por esta coluna"
L["Click again: reverse the order"] = "Clique de novo: inverter a ordem"
L["Shift-click: move left"] = "Shift + clique: mover para a esquerda"
L["Ctrl-click: move right"] = "Ctrl + clique: mover para a direita"
L["Click: open this player's screen"] = "Clique: abrir a tela deste jogador"

-- (20/10) As abas do Warcraft Logs no Meu combate
L["Gear"] = "Equipamento"
L["Nothing in this scope."] = "Nada a mostrar aqui."
L["This run was saved before the sheet and the gear were kept with it."] = "Este combate foi guardado antes de a ficha e o equipamento serem guardados com ele."
L["Time"] = "Tempo"

-- (20/10) O Meu combate igual ao Warcraft Logs: as abas e as colunas do site, nas palavras do jogo e da comunidade
L["Name"] = "Nome"
L["Amount"] = "Quantia"
L["Avg cast"] = "Por lançamento"
L["CPM"] = "Por minuto"
L["Count"] = "Contagem"
L["DTPS"] = "DTPS"
L["Slot"] = "Espaço"
L["Item level"] = "Nível do item"
L["Gems and enchants"] = "Gemas e encantamentos"
L["Damage done by ability"] = "Dano causado por habilidade"
L["Healing done by ability"] = "Cura realizada por habilidade"
L["Damage taken by ability"] = "Dano recebido por habilidade"
L["Killing blow"] = "Golpe fatal"
L["Window"] = "Janela"
L["Last three hits"] = "Últimos três golpes"
L["one shot"] = "um golpe só"
L["Ability"] = "Habilidade"
L["Source"] = "Origem"
L["Before death"] = "Antes da morte"
L["Health"] = "Vida"
L["%s of life"] = "%s de vida"
L["Total interrupts"] = "Total de interrupções"
L["Total dispels"] = "Total de dissipações"
L["Interrupted (the game's count)"] = "Interrompidas (contagem do jogo)"
L["No interrupt in this scope."] = "Nenhuma interrupção aqui."
L["No dispel in this scope."] = "Nenhuma dissipação aqui."
L["one point per fight: the game gives no curve"] = "um ponto por luta: o jogo não entrega a curva"
L["Hits, critical hits and uptime exist only in the game's combat log file, which an addon cannot read."] =
    "Acertos, críticos e tempo ativo existem só no arquivo do registro de combate do jogo, que um addon não consegue ler."
L["The heals and the shields in one list, as Warcraft Logs shows them; a shield is the game's \"Absorbs\"."] =
    "As curas e os escudos numa lista só, como o Warcraft Logs mostra; escudo é o que o jogo chama de \"Absorções\"."
L["This run was saved before the spells were kept with it."] = "Este combate foi salvo antes de as magias serem guardadas com ele."
