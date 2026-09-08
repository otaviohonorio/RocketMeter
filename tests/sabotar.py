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
    # O DESENHO ESCOLHIDO (opcao B): uma linha por pessoa, uma barra por coluna, numero dentro.
    # O defeito de 08/09: `MinWidth` deixa de contar as colunas e quatro delas caem fora da janela.
    ("MinWidth para de contar as colunas", "Window.lua",
     u"    return PADDING * 2 + RowHeight() + NAME_GUTTER + NAME_MIN_WIDTH + columnsWidth",
     u"    return PADDING * 2 + RowHeight() + NAME_GUTTER + NAME_MIN_WIDTH",
     "a faixa de classe para antes das colunas"),

    # A calha some de UMA das duas contas: e a divergencia que permitiu o defeito original.
    ("a calha some da largura minima", "Window.lua",
     u"    return PADDING * 2 + RowHeight() + NAME_GUTTER + NAME_MIN_WIDTH + columnsWidth",
     u"    return PADDING * 2 + RowHeight() + NAME_MIN_WIDTH + columnsWidth",
     "no minimo, o nome ainda tem o piso exato"),

    ("a largura padrao nasce colada no minimo", "Window.lua",
     u"local DEFAULT_SLACK = 48",
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

    ("a faixa de classe volta a cruzar a linha toda", "Window.lua",
     u"    row.bar:SetWidth(math.max(1, nomeAteX - 2))",
     u"    row.bar:SetWidth(WindowWidth())",
     "a faixa de classe para antes das colunas"),

    ("o fundo preto das celulas volta", "Window.lua",
     u'            cell.bar = CreateFrame("StatusBar", nil, cell)',
     u'            cell.track = cell:CreateTexture(nil, "BACKGROUND")\n'
     u'            cell.track:SetAllPoints()\n'
     u'            cell.bar = CreateFrame("StatusBar", nil, cell)',
     "nenhuma celula tem trilho preto atras"),

    ("as colunas voltam a compartilhar uma regua so", "Window.lua",
     u"                local escala = scales[c]",
     u"                local escala = maxAmount",
     "as colunas nao compartilham regua"),

    ("a coluna perde a barra e vira so numero", "Window.lua",
     u"                cell.bar:SetMinMaxValues(0, escala)",
     u"                cell.bar:SetMinMaxValues(0, 1)",
     "as colunas nao compartilham regua"),

    ("a cor de classe volta para o numero", "Window.lua",
     u"                cell.text:SetTextColor(unpack(ns.Skin.text))",
     u"                if entry.best and entry.best[c] then\n"
     u"                    cell.text:SetTextColor(LeaderColor(source.classFilename))\n"
     u"                else\n"
     u"                    cell.text:SetTextColor(unpack(ns.Skin.text))\n"
     u"                end",
     "todo numero tem a mesma cor, inclusive o do lider"),

    ("o clique no cabecalho deixa de reordenar", "Window.lua",
     u"                    ns.db.sortBy = key\n"
     u"                    ns.db.sortDesc = true\n"
     u"                    Window.Refresh(true)",
     u"                    ns.db.sortBy = key\n"
     u"                    ns.db.sortDesc = true",
     "e o dourado esta no grupo que ordena"),

    ("clicar de novo troca de coluna em vez de inverter", "Window.lua",
     u"                elseif self.groupHasSort then",
     u"                elseif false then",
     "clicar no grupo que ja ordena inverte a ordem"),

    ("o cabecalho de colunas some", "Window.lua",
     u"    BuildColumnHeader()\n\n    local posicaoDe",
     u"    HideColumnHeader()\n\n    local posicaoDe",
     "o cabecalho de colunas esta na tela"),

    # A regua deixa de chegar a coluna: todas caem no fallback 1, e a barra de cada uma passa a
    # dizer "esta pessoa e 100% desta metrica" -- todas cheias, nenhuma informacao.
    ("a regua nao chega na coluna", "Data.lua",
     u"            scales[c] = porAttr[def.attr] or nil",
     u"            scales[c] = nil",
     "as colunas nao compartilham regua"),







    # ------------------------------------------------------------------ a mescla de colunas
    # IDEIA DO USUARIO, 08/09: "Dano - DPS" num cabecalho so, "65.1M - 48K" numa celula so. Cada
    # linha abaixo e uma forma de a mescla se desfazer sem estourar nada.

    ("o cabecalho volta a nomear uma metrica so", "Window.lua",
     u'    return table.concat(partes, " - ")\nend\n\nlocal function ColumnWidthFor',
     u'    return partes[1]\nend\n\nlocal function ColumnWidthFor',
     "o primeiro junta os dois nomes"),

    ("a celula escreve so o primeiro numero", "Window.lua",
     u'    return table.concat(partes, " - "), false',
     u'    return partes[1], false',
     "a celula do grupo traz total E taxa"),

    # Ordenar por DPS e por dano da a MESMA lista, entao trocar isto nao muda ordem nenhuma: o
    # que quebra e o dourado, que passa a prometer "DPS" e a coluna clicavel a responder "dano".
    ("o grupo passa a ser ordenado pela taxa", "Data.lua",
     u'            grupo.keys[#grupo.keys + 1] = def.key',
     u'            grupo.keys[#grupo.keys + 1] = def.key\n'
     u'            grupo.key = def.key',
     "o grupo e ordenado pelo total"),

    # O DEFEITO QUE A MESCLA CRIOU: `columnIndex` virou indice de GRUPO, e o handler continuava
    # lendo `ns.db.columns` com ele. Com {dano, DPS, cura, CPS, interr} o terceiro cabecalho e
    # "Interr" e a terceira coluna e "cura" -- clicar em um ordenava pelo outro.
    ("o clique volta a ler a coluna pelo indice do grupo", "Window.lua",
     u"                local key = self.sortKey",
     u"                local key = ns.db.columns[self.columnIndex]",
     "e ordena pela metrica DELE"),

    ("mover separa o total da taxa", "Window.lua",
     u"    lista[index], lista[target] = lista[target], lista[index]",
     u"    ns.db.columns[index], ns.db.columns[target] =\n"
     u"        ns.db.columns[target], ns.db.columns[index]",
     "mover trocou os dois primeiros grupos"),

    # O CACHE DE GRUPOS NAO PODE ENVELHECER. Ele existe para os quatro consumidores de um mesmo
    # desenho verem a mesma lista; se o desenho o LE em vez de refaze-lo, a tela fica com os
    # grupos do desenho anterior sobre os dados do atual.
    ("o desenho le o cache velho de grupos", "Window.lua",
     u"    local gruposDesenho = RefreshGroups()",
     u"    local gruposDesenho = Groups()",
     "a primeira linha tem uma celula por coluna"),

    # O dourado e o UNICO sinal de qual coluna ordena. Pintado so na reconstrucao, ele ficava na
    # coluna anterior depois de um clique -- a janela mentindo sobre o que estava mostrando.
    ("o cabecalho volta a ser pintado so na reconstrucao", "Window.lua",
     u"local function BuildColumnHeader()\n    if not headerRow then",
     u"local jaMontado\n"
     u"local function BuildColumnHeader()\n"
     u"    if jaMontado then return end\n"
     u"    jaMontado = true\n"
     u"    if not headerRow then",
     "e o dourado esta no grupo que ordena"),

    # A barra mede o TOTAL. As duas metricas dariam a mesma proporcao, mas so o total e o numero
    # que o cabecalho dourado promete estar ordenando.
    # ⚑ A MAIS IMPORTANTE DA MESCLA, e esta sabotagem corrigiu o comentario que eu tinha
    # escrito: sem a guarda NADA estoura. `FormatCell` recusa valor secret e devolve traco, entao
    # a celula mesclada mostra "- - -" em combate -- o numero some, em silencio, na hora em que o
    # medidor serve para alguma coisa. Defeito silencioso e pior que erro de Lua: erro tem log.
    ("a celula junta valor secret", "Window.lua",
     u"        if valor ~= nil and issecretvalue(valor) then return valor, true end",
     u"        -- sabotado",
     "a celula do grupo opaco nao junta numeros"),

    # O dourado tem que seguir o GRUPO. Com `sortBy = "dps"` nenhum grupo tem `key == sortBy`,
    # e a janela ordenava sem dizer por qual coluna.
    ("o dourado volta a exigir a coluna exata", "Window.lua",
     u"        if GroupHas(grupo, ns.db.sortBy) then",
     u"        if grupo.key == ns.db.sortBy then",
     "ordenado por DPS, o grupo do dano fica dourado"),

    ("clicar no grupo que ordena pela taxa troca em vez de inverter", "Window.lua",
     u"                elseif self.groupHasSort then",
     u"                elseif ns.db.sortBy == key then",
     "clicar no grupo que ja ordena inverte a ordem"),

    # A largura do grupo TEM que acompanhar o corpo da fonte: congelada, ela cabe o texto no
    # corpo padrao e o estoura em qualquer corpo maior -- e o corpo e ajustavel pelo jogador.
    ("a largura da coluna para de seguir o corpo da fonte", "Window.lua",
     u'    local escala = ns.RoleSizeSafe("body") / 16',
     u"    local escala = 1",
     "  e o texto mesclado cabe nela"),

    # E a fatia do segundo numero nao pode encolher a ponto de o texto nao caber.
    ("o segundo numero ganha uma fatia pequena demais", "Window.lua",
     u"        largura = largura + math.floor(ColumnWidthFor(grupo.keys[i]) * 0.62 + 0.5)",
     u"        largura = largura + math.floor(ColumnWidthFor(grupo.keys[i]) * 0.10 + 0.5)",
     "  e o texto mesclado cabe nela"),

    ("a barra passa a medir a taxa", "Window.lua",
     u"                local principal = entry.values[indices[c][1]]",
     u"                local principal = entry.values[indices[c][#indices[c]]]",
     "a barra usa o valor do total"),

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
        else:
            outro = [l for l in saida.splitlines() if l.startswith("  ERRO")]
            print("  FALHA %-42s esperava reprovar em %r; veio %r" % (nome, label, outro[:1]))
            falhas.append(nome)
finally:
    shutil.rmtree(base, ignore_errors=True)

print()
print("sabotagens que NAO foram pegas: %d" % len(falhas))
for f in falhas:
    print("  - " + f)
sys.exit(1 if falhas else 0)
