# -*- coding: utf-8 -*-
"""Sabota uma coisa de cada vez e confere que o check CERTO reprova.

    python tests/sabotar.py        (da pasta do addon)

POR QUE ISTO EXISTE, e aqui ele tem data: em 07/09/2026 o placar foi para o jogo com a coluna de
pontuacao **sem construtor de celula**. O harness estava VERDE. Ele passava porque o unico
desenho que exercitava era o placar SEM chave -- e sem chave as tres colunas de Mitico+ nem
entram na lista de colunas. O usuario abriu o painel e viu cabecalho, rotulos de coluna e o corpo
vazio; o erro de Lua existia, mas o desenho e embrulhado em `pcall` de proposito, entao ele virou
uma linha de chat no meio do fim de uma chave.

A skill `wow-ui-design` ja avisava: *contar linhas `ok` nao e criterio de aprovacao*. O unico
jeito de saber se um teste testa alguma coisa e QUEBRAR o que ele deveria pegar e ver o defeito
reaparecer exatamente onde ele disse que apareceria.

Cada linha da tabela abaixo e um defeito real que ja existiu ou que a proxima refatoracao pode
reintroduzir. Cada sabotagem roda numa COPIA; nada aqui toca o addon.
"""
import io
import os
import shutil
import subprocess
import sys
import tempfile

SRC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LUA = os.environ.get("LUAJIT") or "C:/Users/ofhon/AppData/Local/Programs/LuaJIT/bin/luajit.exe"
if not os.path.exists(LUA):
    LUA = "luajit"      # o que estiver no PATH

# (nome, arquivo, de, para, label do check que TEM que reprovar)
SABOTAGENS = [
    # ------------------------------------------------------------------ geometria da janela
    # O DESENHO ESCOLHIDO (opcao B): uma linha por pessoa, o numero dentro da barra.
    # O defeito de 08/09: `MinWidth` deixa de contar as colunas e quatro delas caem fora da janela.
    ("MinWidth para de contar as colunas", "Window.lua",
     u"    return PADDING * 2 + RowHeight() + NAME_GUTTER + NAME_MIN_WIDTH + columnsWidth",
     u"    return PADDING * 2 + RowHeight() + NAME_GUTTER + NAME_MIN_WIDTH",
     "e as colunas cabem na janela"),

    # A calha some de UMA das duas contas: e a divergencia que permitiu o defeito original.
    ("a calha some da largura minima", "Window.lua",
     u"    return PADDING * 2 + RowHeight() + NAME_GUTTER + NAME_MIN_WIDTH + columnsWidth",
     u"    return PADDING * 2 + RowHeight() + NAME_MIN_WIDTH + columnsWidth",
     "no minimo, o nome ainda tem o piso exato"),

    ("a largura padrao nasce colada no minimo", "Window.lua",
     u"local DEFAULT_SLACK = 24",
     u"local DEFAULT_SLACK = 0",
     "  e a largura padrao tem folga sobre o minimo"),

    ("toda coluna volta a ter a mesma largura", "Window.lua",
     u'    local escala = ns.RoleSizeSafe("body") / 16',
     u'    base = COLUMN_WIDTH_FIXED\n'
     u'    local escala = ns.RoleSizeSafe("body") / 16',
     "dano (total) e mais largo que interrupcoes (contagem)"),

    # Interrupcoes tambem e `field = "total"`: classificar por formato dava a ela a largura de
    # "1.2B" para escrever "8". Quem separa os dois e a marca `counts` do catalogo.
    ("a coluna de contagem volta a ter largura de total", "Data.lua",
     u"        list[i].counts = CONTAGEM[list[i].attr] or nil",
     u"        list[i].counts = nil",
     "dano (total) e mais largo que interrupcoes (contagem)"),

    ("a largura da coluna para de seguir o corpo da fonte", "Window.lua",
     u'    local escala = ns.RoleSizeSafe("body") / 16',
     u"    local escala = 1",
     "com corpo 20, o texto cabe na caixa dele"),

    # A PISTA existe agora, tingida com a cor da classe a pedido. O que nao pode voltar e o
    # PRETO -- o usuario o reprovou duas vezes ("tira o fundo preto", "o fundo preto e feio").
    ("a pista volta a ser preta", "Window.lua",
     u"    local r, g, b = ns.ClassColor(classFilename)\n"
     u"    texture:SetColorTexture(r, g, b, TRACK_ALPHA)",
     u"    texture:SetColorTexture(0, 0, 0, 0.4)",
     "nenhuma pista e preta"),

    # E ela nao pode aparecer onde nao ha caminho: "se tiver zerado fica sem a pista tingida".
    ("a pista aparece mesmo com valor zerado", "Window.lua",
     u"                ns.ApplyTrackColor(faixa.track, source.classFilename, not vazio)",
     u"                ns.ApplyTrackColor(faixa.track, source.classFilename, true)",
     "quem nao causou dano nao ganha pista de dano"),

    ("a faisca aparece mesmo com valor zerado", "Window.lua",
     u"                ns.ApplySparkColor(faixa.spark, source.classFilename, not vazio)",
     u"                ns.ApplySparkColor(faixa.spark, source.classFilename, true)",
     "  nem faisca"),

    # ⚑ E A GUARDA NAO PODE LER VALOR SECRET. Escrita ao contrario -- "esconde so quando da para
    # ⚑ FALTA UMA SABOTAGEM AQUI, e o motivo e do simulador, nao do codigo.
    #
    # A guarda do zero e escrita ao contrario de proposito ("esconde so quando da para PROVAR que
    # nao ha valor") justamente para nunca comparar um valor opaco. Tirar o `issecretvalue` seria
    # o defeito -- e NO JOGO ele levanta erro, porque comparar valor secret levanta.
    #
    # Aqui nao levanta: o marcador de secret do simulador e uma TABELA, e em Lua 5.1 `tabela == 0`
    # e simplesmente falso, sem metametodo (`__eq` so e chamado entre operandos do mesmo tipo).
    # As duas versoes dao a MESMA resposta no simulador. Representar isso exigiria um userdata, e
    # inventar uma sabotagem que "passa" seria pior que nao ter nenhuma: a unica coisa honesta e
    # registrar que esta linha so o jogo confere.

    # A FAISCA presa na moldura fica parada na borda direita: nao diz nada sobre progresso, e
    # nada estoura. So a ancora denuncia.
    ("a faisca e ancorada na moldura, nao no preenchimento", "Window.lua",
     u'        faixa.spark:SetPoint("LEFT", preenchimento, "LEFT", 0, 0)',
     u'        faixa.spark:SetPoint("LEFT", faixa, "LEFT", 0, 0)',
     "a faisca esta presa no preenchimento pelas duas pontas"),

    # ⚑ O DEFEITO DO PRINT DE 08/09: presa so pela direita, com largura fixa, a faisca fica MAIOR
    # que a barra quando a barra e pequena -- e o excedente sai pela ESQUERDA, lendo como uma seta
    # apontando para tras. Nao da para consertar medindo (GetWidth do preenchimento e secret);
    # so a segunda ancora resolve, e so um teste que confere AS DUAS a protege.
    ("a faisca volta a ter largura fixa, presa so pela direita", "Window.lua",
     u'        faixa.spark:SetPoint("LEFT", preenchimento, "LEFT", 0, 0)\n'
     u'        faixa.spark:SetPoint("RIGHT", preenchimento, "RIGHT", 0, 0)',
     u'        faixa.spark:SetPoint("RIGHT", preenchimento, "RIGHT", 1, 0)\n'
     u'        faixa.spark:SetWidth(10)',
     "a faisca esta presa no preenchimento pelas duas pontas"),

    # ------------------------------------------------------------------ a barra que atravessa
    # IDEIA DO USUARIO, 08/09: "a barra que progride conforme quem ta melhor, ela vai desde a
    # coluna de dano ate o DPS, como se fosse apenas uma barra".

    ("a barra volta a ser uma por coluna", "Window.lua",
     u"        faixa:SetSize(vao.width - GROUP_GAP, height - CELL_INSET * 2)",
     u"        faixa:SetSize(ColumnWidthFor(vao.grupo.key) - GROUP_GAP, height - CELL_INSET * 2)",
     "  e o widget tem essa largura mesmo"),

    # A faixa e ancorada pela DIREITA no vao do grupo. Ancorar pela coluna que ordena poe a barra
    # do dano em cima da coluna do DPS -- ela some por baixo do numero vizinho.
    ("a faixa e ancorada na coluna errada", "Window.lua",
     u'        faixa:SetPoint("RIGHT", row.text, "RIGHT", -vao.offset, 0)',
     u'        faixa:SetPoint("RIGHT", row.text, "RIGHT", 0, 0)',
     "a barra da cura e ancorada no vao dela"),

    ("as familias voltam a compartilhar uma regua so", "Window.lua",
     u"                local escala = at and escalas[at]",
     u"                local escala = maxAmount",
     "familias diferentes nao compartilham regua"),

    ("a barra perde a regua e vira retangulo cheio", "Window.lua",
     u"                faixa.bar:SetMinMaxValues(0, escala)",
     u"                faixa.bar:SetMinMaxValues(0, 1)",
     "familias diferentes nao compartilham regua"),

    # A REGUA que existe e a do TOTAL. Encher a barra com a taxa sobre ela da um fiapo em toda
    # linha -- foi o defeito que a barra unica corrigiu, e ele volta com uma linha.
    ("a barra passa a medir a taxa", "Window.lua",
     u"        encheCom[g] = posicaoDe[vaosDesenho[g].grupo.key]",
     u"        encheCom[g] = posicaoDe[vaosDesenho[g].grupo.keys[#vaosDesenho[g].grupo.keys]]",
     "a barra mede o total do grupo"),

    ("a regua nao chega na coluna", "Data.lua",
     u"            scales[c] = porAttr[def.attr] or nil",
     u"            scales[c] = nil",
     "familias diferentes nao compartilham regua"),

    # ------------------------------------------------------------------ os dois numeros
    # "Volta como estava": cada coluna escreve o numero DELA. A versao mesclada juntava os dois
    # numa string, e o usuario mandou desfazer.

    ("os dois numeros voltam a ser um so", "Window.lua",
     u"            fs:Show()",
     u"            if i == 1 then fs:Show() end",
     "cinco colunas marcadas, cinco numeros"),

    # Cada numero mora na fatia da coluna dele. Sem acumular `dentro`, os dois se empilham na
    # mesma ponta da faixa e um cobre o outro.
    # ------------------------------------------------------------------ a ordem travada
    # PEDIDO: "vamos bloquear para que a coluna de Dano sempre venha primeiro que a DPS".

    # ⚑ OS DOIS NUMEROS NAS PONTAS OPOSTAS. Pedido do usuario: "dano a esquerda, dps a
    # direita". Empilhar os dois na mesma ponta nao levanta erro -- um so cobre o outro, e a
    # linha fica com um numero a menos sem nada avisar.
    ("os dois numeros voltam para a mesma ponta", "Window.lua",
     u'            local lado = MemberAlign(i, quantos)',
     u'            local lado = "RIGHT"',
     "o dano encosta na ponta esquerda"),

    # E QUEM ESTA SOZINHO FICA NO CENTRO -- e o que impede a janela de ter duas gramaticas.
    ("a coluna sozinha encosta numa ponta", "Window.lua",
     u'    if total <= 1 then return "CENTER" end',
     u'    if total <= 1 then return "RIGHT" end',
     "interrupcoes, sozinha, fica centralizada"),

    # O ROTULO TEM QUE IR JUNTO COM O NUMERO. Sem isto o botao fica no lugar certo e o texto
    # dele nao: "Dano" apareceria colado em "DPS" enquanto os numeros ficam nas pontas.
    ("o rotulo nao acompanha a ponta do numero", "Window.lua",
     u'        button.text:SetJustifyH(onde.lado)',
     u'        button.text:SetJustifyH("RIGHT")',
     "o rotulo do dano encosta na mesma ponta"),

    # E O BOTAO TEM QUE COBRIR A FATIA DELE, senao clicar em "DPS" ordena por dano -- defeito
    # que ja voltou uma vez por aqui, quando o cabecalho deixou de ser por grupo.
    ("o botao do cabecalho volta a largura declarada", "Window.lua",
     u'        button:SetWidth(onde.largura)',
     u'        button:SetWidth(ColumnWidthFor(key))',
     "as duas fatias somam a barra do par"),

    ("a ordem dentro da familia deixa de ser travada", "Data.lua",
     u"            if pa ~= pb then return pa < pb end",
     u"            if pa ~= pb then return pa > pb end",
     "migracao converte id em chave"),

    ("a normalizacao deixa de agrupar por familia", "Data.lua",
     u"    local familias, porAttr = {}, {}",
     u"    if true then return columns, false end\n"
     u"    local familias, porAttr = {}, {}",
     "  e completa o par do dano"),

    ("a normalizacao reordena as familias entre si", "Data.lua",
     u"            familias[#familias + 1] = porAttr[def.attr]",
     u"            table.insert(familias, 1, porAttr[def.attr])",
     "migracao converte id em chave"),

    ("o par deixa de ser completado", "Data.lua",
     u"                for _, irma in ipairs(item.keys) do",
     u"                for _, irma in ipairs({ key }) do",
     "  e completa o par do dano"),

    ("marcar uma coluna deixa de normalizar a lista", "Window.lua",
     u"    ns.db.columns = ns.Data.NormalizeColumns(novo)\n"
     u"\n"
     u"    -- A ordenacao pode ter ido embora junto com o item.",
     u"    ns.db.columns = novo\n"
     u"\n"
     u"    -- A ordenacao pode ter ido embora junto com o item.",
     "ligar o par reordena a familia inteira"),

    ("mover deixa de normalizar de volta", "Window.lua",
     u"    ns.db.columns = ns.Data.NormalizeColumns(novo)\n"
     u"\n"
     u"    Window.Rebuild()",
     u"    ns.db.columns = novo\n"
     u"\n"
     u"    Window.Rebuild()",
     "mover devolve a lista agrupada mesmo se ela chegou intercalada"),

    ("a lista salva escapa da normalizacao", "Data.lua",
     u"    local normal = Data.NormalizeColumns(out)\n"
     u"    return normal, changed",
     u"    return out, changed",
     "  e completa o par do dano"),

    # E O CONTRARIO TAMBEM: reagrupar nao pode contar como migracao de FORMATO. O perfil usa esse
    # valor para APAGAR a ordenacao escolhida e anunciar "colunas migradas" no chat -- a cada
    # login, por causa de uma reordenacao que o jogador nao pediu nem percebeu.
    ("reagrupar volta a contar como migracao de formato", "Data.lua",
     u"    local normal = Data.NormalizeColumns(out)\n"
     u"    return normal, changed",
     u"    local normal, reordenou = Data.NormalizeColumns(out)\n"
     u"    return normal, changed or reordenou",
     "  mas nao conta como migracao de formato"),

    # ------------------------------------------------------------------ o item unico
    # PEDIDO: "o dano e dps e cura e cps tem que ser um so item".

    ("o par volta a ser dois itens na configuracao", "Data.lua",
     u"        local par = def.field == \"total\" and taxaDe[def.attr]",
     u"        local par = false",
     "  e completa o par do dano"),

    ("a taxa aparece DUAS vezes na lista de itens", "Data.lua",
     u"        elseif def.field ~= \"perSecond\" or not totalDe[def.attr] then",
     u"        else",
     "  a familia da cura vem depois"),

    ("ligar o item liga so uma das duas colunas", "Window.lua",
     u"    local chaves = item and item.keys or { key }",
     u"    local chaves = { key }",
     "e desligar pelo dano leva o DPS junto"),

    # Com item de duas colunas, "sobra uma" deixou de ser a conta certa: desligar o ultimo item
    # leva as DUAS de uma vez e a janela fica sem coluna nenhuma.
    ("a guarda de coluna minima volta a contar uma so", "Window.lua",
     u"        if #novo == 0 then",
     u"        if #novo == -1 then",
     "desligar o ultimo item nao esvazia a janela"),

    # ------------------------------------------------------------------ cabecalho e ordenacao
    ("o clique no cabecalho deixa de reordenar", "Window.lua",
     u"                    ns.db.sortBy = key\n"
     u"                    ns.db.sortDesc = true\n"
     u"                    Window.Refresh(true)",
     u"                    ns.db.sortBy = key\n"
     u"                    ns.db.sortDesc = true",
     "o dourado esta no DPS"),

    ("clicar de novo troca de coluna em vez de inverter", "Window.lua",
     u"                elseif ns.db.sortBy == key then",
     u"                elseif false then",
     "clicar de novo inverte a ordem"),

    # O cabecalho voltou a ser um por coluna: clicar em "DPS" ordena por DPS. Ler a chave pelo
    # indice de GRUPO foi o defeito que a mescla criou, e a volta desfaz a causa.
    ("o cabecalho volta a nomear a familia em vez da coluna", "Window.lua",
     u"        local label = ns.Data.GetShortLabel(key)",
     u"        local label = ns.Data.GetAttributeLabel(key)",
     "o primeiro e o do dano"),

    ("o cabecalho de colunas some", "Window.lua",
     u"    BuildColumnHeader()\n\n    local vaosDesenho",
     u"    HideColumnHeader()\n\n    local vaosDesenho",
     "o cabecalho de colunas esta na tela"),

    # O dourado e o UNICO sinal de qual coluna ordena. Pintado so na reconstrucao, ele ficava na
    # coluna anterior depois de um clique -- a janela mentindo sobre o que estava mostrando.
    ("o cabecalho volta a ser pintado so na reconstrucao", "Window.lua",
     u"local function BuildColumnHeader()\n    if not headerRow then",
     u"local jaMontado\n"
     u"local function BuildColumnHeader()\n"
     u"    if jaMontado then return end\n"
     u"    jaMontado = true\n"
     u"    if not headerRow then",
     "o dourado esta no DPS"),

    # O CACHE DE GRUPOS NAO PODE ENVELHECER. Se o desenho o LE em vez de refaze-lo, a tela fica
    # com os grupos do desenho anterior sobre os dados do atual.
    ("o desenho le o cache velho de grupos", "Window.lua",
     u"    RefreshGroups()\n\n    -- O CABECALHO E PINTADO NO DESENHO",
     u"    Groups()\n\n    -- O CABECALHO E PINTADO NO DESENHO",
     "a primeira linha tem um numero por coluna"),

    # E o MESMO cache, do outro lado: `MoveColumn` le os grupos ANTES de reescrever a lista, e
    # `ns.db.columns` pode ter mudado sem passar por um desenho (SavedVariables entram assim).
    ("mover le o cache velho de grupos", "Window.lua",
     u"    local lista = RefreshGroups()",
     u"    local lista = Groups()",
     "mover devolve a lista agrupada mesmo se ela chegou intercalada"),

    ("a cor de classe volta para o numero", "Window.lua",
     u"                    fs:SetTextColor(unpack(ns.Skin.text))",
     u"                    if entry.best and entry.best[i] then\n"
     u"                        fs:SetTextColor(LeaderColor(source.classFilename))\n"
     u"                    else\n"
     u"                        fs:SetTextColor(unpack(ns.Skin.text))\n"
     u"                    end",
     "todo numero tem a mesma cor, inclusive o do lider"),

    # ------------------------------------------------------------------ o Picker
    # A tela passava a posicao em `ns.db.columns` onde `MoveColumn` esperava indice de GRUPO: a
    # seta do "DPS" movia a familia da CURA. Nada aparecia errado -- so mexia na coisa errada.
    ("as setas do configurador voltam a passar indice de coluna", "Picker.lua",
     u"    local grupos = ns.Data.GroupColumns(ns.db.columns)",
     u"    for i, id in ipairs(ns.db.columns) do\n"
     u"        if id == item.key then return i, #ns.db.columns end\n"
     u"    end\n"
     u"    local grupos = ns.Data.GroupColumns(ns.db.columns)",
     "a seta move a familia da linha clicada"),

    # ⚑ O MESMO DEFEITO PELO CABECALHO, e foi assim que ele voltou: consertado na tela de
    # configuracao, reintroduzido no cabecalho quando ele deixou de ser por grupo. Dos dez cliques
    # possiveis com {dano, DPS, cura, CPS, interr}, um acertava, um ESTOURAVA a janela e oito
    # moviam a familia errada ou morriam calados.
    ("o cabecalho volta a passar indice de coluna para mover", "Window.lua",
     u"                    local g = GroupIndexFor(key)\n"
     u"                    if g then Window.MoveColumn(g, -1) end",
     u"                    Window.MoveColumn(self.columnIndex, -1)",
     "e move a familia da CURA para a esquerda"),

    ("mover volta a nao validar a origem", "Window.lua",
     u"    if index < 1 or index > #lista then return end\n"
     u"    if target < 1 or target > #lista then return end",
     u"    if target < 1 or target > #lista then return end",
     # ESTOURA, e e o defeito: a troca deixa um BURACO no meio da lista de grupos (o slot de
     # origem vira nil), `#lista` muda de valor e o achatamento indexa nil. `label = None` e o
     # modo da suite para "isto tem que parar o harness" -- reprovar num check seria menos grave
     # do que o que realmente acontece.
     None),

    ("o configurador volta a listar colunas em vez de itens", "Picker.lua",
     u"    local items = ns.Data.GetColumnItems()",
     u"    local items = ns.Data.GetColumns()",
     None),

    ("o chat e a tela discordam do numero da coluna", "Commands.lua",
     u"    local list = ns.Data.GetColumnItems()",
     u"    local list = ns.Data.GetColumns()",
     None),

    # ------------------------------------------------------------------ o contorno medio
    # Ele saiu em 08/09 a pedido ("sempre fica igual ao fino"), com a maquinaria de contorno
    # desenhado junto. O que nao pode acontecer e a opcao voltar sem ela -- ai o contorno nao
    # engrossa, ele SOME, porque `OutlineFor` nao acha a escolha e devolve "".

    ("o medio volta para a lista de escolhas", "Window.lua",
     u'    { value = "thick", flags = "THICKOUTLINE" },',
     u'    { value = "medium", flags = "OUTLINE", halo = true },\n'
     u'    { value = "thick", flags = "THICKOUTLINE" },',
     "sobraram os tres niveis que o motor tem"),

    # ⚑ A MIGRACAO E O QUE IMPEDE O CONTORNO DE SUMIR SOZINHO no proximo login de quem tinha
    # "medium" salvo -- e era o caso do proprio usuario (`text.header.outline = "medium"`).
    ("a migracao do medio salvo some", "Profile.lua",
     u'            if type(papel) == "table" and papel.outline == "medium" then',
     u'            if false then',
     "o medio salvo vira fino"),

    # E ela nao pode voltar para dentro do bloco do formato antigo: quem escolheu "medium" ja
    # tinha `active.text`, por definicao, entao la ela nunca rodaria para quem importa.
    ("a migracao volta para dentro do formato antigo", "Profile.lua",
     u'    if type(active.text) == "table" then\n'
     u'        for _, papel in pairs(active.text) do',
     u'    if false and type(active.text) == "table" then\n'
     u'        for _, papel in pairs(active.text) do',
     "o medio salvo vira fino"),

    ("coluna sem construtor de celula", "Scoreboard.lua",
     u"CellBuilders.score = CellBuilders.value",
     u"-- sabotado",
     "a celula `score` tem construtor"),

    ("erro de Lua no desenho da linha", "Scoreboard.lua",
     u"    cell.text:SetText(ScoreText(entry, index))",
     u"    cell.text:SetText(NaoExisteEssaFuncao(entry, index))",
     "desenhou sem erro de Lua"),

    ("celula construida com o tipo errado", "Scoreboard.lua",
     u'render = "score",    custom = true, label = L["Score"]',
     u'render = "name",     custom = true, label = L["Score"]',
     "celula 5 (score) e do tipo certo"),

    ("largura de coluna fora da copia", "Scoreboard.lua",
     u'{ key = "dps",        width = 100 },',
     u'{ key = "dps",        width = 90 },',
     "  e mede 100"),

    ("ordem das colunas trocada", "Scoreboard.lua",
     u'{ key = "deaths",     width = 80 },\n    { key = "avoidable",  width = 80 },',
     u'{ key = "avoidable",  width = 80 },\n    { key = "deaths",     width = 80 },',
     "coluna 7 e deaths"),

    ("altura da linha fora da copia", "Scoreboard.lua",
     u"local ROW_HEIGHT = 46 ",
     u"local ROW_HEIGHT = 40 ",
     "altura da linha"),

    ("o rodape deixa de fechar os 452", "Scoreboard.lua",
     u"local FOOTER_HEIGHT = 132",
     u"local FOOTER_HEIGHT = 100",
     "altura do painel com cinco linhas"),

    ("a coluna de likes entra na copia", "Scoreboard.lua",
     u'    { key = "portrait",   width = 60,  render = "portrait", custom = true, label = "" },',
     u'    { key = "likes",      width = 34,  render = "value",    custom = true, label = "" },\n'
     u'    { key = "portrait",   width = 60,  render = "portrait", custom = true, label = "" },',
     "quantas colunas"),

    ("retomada volta a afirmar sobre o que nao viu", "Scoreboard.lua",
     u"    local desde = context.knownFrom or 0\n    if desde > 0 then return nil end",
     u"    local desde = 0",
     "o tempo fora de combate some quando o registro e parcial"),

    ("a retomada semeia o eixo no zero", "Run.lua",
     u"        knownFrom = elapsed\n"
     u"        combatTimeline[1] = { elapsed, InCombatLockdown() and true or false }",
     u"        knownFrom = 0\n        combatTimeline[1] = { 0, false }",
     "retomada sabe que so viu do minuto 15 em diante"),

    # A Blizzard escreve "Fillagree" com dois L; "Filigree" (a grafia correta do ingles) some sem
    # avisar. Este teste encerra o harness com mensagem propria, nao com uma linha "ERRO " --
    # entao o criterio aqui e "o harness NAO chegou ao fim".
    ("grafia Filigree no lugar de Fillagree", "Scoreboard.lua",
     u'    "BossBanner-LeftFillagree",',
     u'    "BossBanner-LeftFiligree",',
     None),
]

FIM = "Tudo carregou e rodou sem erro de Lua."


def rodar(tmp):
    r = subprocess.run([LUA, "tests/harness.lua"], cwd=tmp,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return r.stdout.decode("utf-8", "replace")


# ⚑ CADA COPIA E APAGADA NO FIM, e isto ja foi defeito: sem a limpeza, cada rodada deixava uma
# copia inteira do addon no temp do sistema. Depois de 845 copias acumuladas nesta sessao, a suite
# passou a REPROVAR SABOTAGENS DIFERENTES A CADA RODADA -- e uma suite instavel nao vale nada:
# ela nao distingue "o teste nao pega" de "deu azar agora".
#
# O sintoma enganava: parecia que os testes e que estavam fracos.
# ⚑ UMA COPIA POR SUITE, e nao uma por sabotagem -- isto ja foi defeito duas vezes.
#
# A versao antiga fazia `copytree` do addon inteiro a cada sabotagem, e nunca apagava: depois de
# 845 copias acumuladas no temp do sistema, a suite passou a REPROVAR SABOTAGENS DIFERENTES A CADA
# RODADA. E uma suite instavel nao vale nada -- ela deixa de distinguir "o teste nao pega" de "deu
# azar agora", e o sintoma enganava: parecia que os testes e que estavam fracos.
#
# Agora e uma copia so, feita uma vez; cada sabotagem escreve o arquivo, roda, e RESTAURA o
# original a partir do texto guardado em memoria. Vinte copytree viram um.
def preparar():
    base = tempfile.mkdtemp(prefix="sab_")
    destino = os.path.join(base, "a")
    shutil.copytree(SRC, destino)
    return base, destino


def ler(destino, arquivo):
    return io.open(os.path.join(destino, arquivo), encoding="utf-8").read().replace("\r\n", "\n")


def escrever(destino, arquivo, texto):
    io.open(os.path.join(destino, arquivo), "w", encoding="utf-8", newline="\n").write(texto)


base, destino = preparar()
originais = {}

falhas = []
try:
    for entrada in SABOTAGENS:
        nome, arquivo, de, para, label = entrada

        if arquivo not in originais:
            originais[arquivo] = ler(destino, arquivo)
        txt = originais[arquivo]

        if txt.count(de) != 1:
            print("  ?     %-42s ANCORA NAO BATE (%d)" % (nome, txt.count(de)))
            falhas.append(nome)
            continue
        txt = txt.replace(de, para, 1)

        escrever(destino, arquivo, txt)
        try:
            saida = rodar(destino)
        finally:
            # O ORIGINAL VOLTA SEMPRE, inclusive se a rodada estourar: uma sabotagem que vaza para
            # a proxima faria a suite acusar defeitos que nao existem.
            escrever(destino, arquivo, originais[arquivo])

        chegou_ao_fim = FIM in saida

        if label is None:
            if chegou_ao_fim:
                print("  FALHA %-42s o harness passou inteiro com o defeito" % nome)
                falhas.append(nome)
            else:
                print("  ok    %-42s parou o harness" % nome)
            continue

        esperado = "  ERRO  " + label
        if esperado in saida:
            print("  ok    %-42s reprovou em: %s" % (nome, label))
            continue

        outro = [l for l in saida.splitlines() if l.startswith("  ERRO")]

        # ⚑ ESTOURAR NAO E O MESMO QUE REPROVAR, e a suite dizia "nao foi pega" nos dois casos.
        # Um erro de Lua interrompe o harness ANTES do check nomeado, entao a invariante que a
        # linha diz proteger nunca chegou a rodar -- o defeito foi pego por acidente. A mensagem
        # tem que separar as duas coisas, senao o proximo leitor procura um teste que nao existe.
        if not outro and not chegou_ao_fim:
            print("  FALHA %-42s estourou o harness antes de chegar em %r" % (nome, label))
        elif not outro:
            print("  FALHA %-42s o harness passou inteiro com o defeito" % nome)
        else:
            print("  FALHA %-42s esperava reprovar em %r; veio %r" % (nome, label, outro[:1]))
        falhas.append(nome)
finally:
    shutil.rmtree(base, ignore_errors=True)

print()
print("sabotagens que NAO foram pegas: %d" % len(falhas))
for f in falhas:
    print("  - " + f)
sys.exit(1 if falhas else 0)
