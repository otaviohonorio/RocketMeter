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
    ("as colunas voltam a compartilhar uma regua so", "Window.lua",
     u"                local escala = scales[c]",
     u"                local escala = maxAmount",
     "as colunas nao compartilham regua"),

    ("a coluna perde a barra e vira so numero", "Window.lua",
     u"                cell.bar:SetMinMaxValues(0, escala)",
     u"                cell.bar:SetMinMaxValues(0, 1)",
     "as colunas nao compartilham regua"),

    # O clique escreve `sortBy` mas nao manda redesenhar: a coluna fica dourada e a lista nao
    # muda -- o pior sintoma, porque parece que o addon ouviu e discordou.
    ("o clique no cabecalho deixa de reordenar", "Window.lua",
     u"                    ns.db.sortBy = key\n"
     u"                    ns.db.sortDesc = true\n"
     u"                    Window.Refresh(true)",
     u"                    ns.db.sortBy = key\n"
     u"                    ns.db.sortDesc = true",
     "a lista foi reordenada de verdade"),

    ("clicar de novo troca de coluna em vez de inverter", "Window.lua",
     u"                elseif ns.db.sortBy == key then\n"
     u"                    ns.db.sortDesc = not ns.db.sortDesc",
     u"                elseif false then\n"
     u"                    ns.db.sortDesc = not ns.db.sortDesc",
     "e a ordem inverteu"),

    ("o cabecalho de colunas some", "Window.lua",
     u"    BuildColumnHeader()\n\n    for i = 1, ns.db.rows do",
     u"    HideColumnHeader()\n\n    for i = 1, ns.db.rows do",
     "o cabecalho de colunas esta na tela"),

    # A regua deixa de chegar a coluna: todas caem no fallback 1, e a barra de cada uma passa a
    # dizer "esta pessoa e 100% desta metrica" -- todas cheias, nenhuma informacao.
    ("a regua nao chega na coluna", "Data.lua",
     u"            scales[c] = porAttr[def.attr] or nil",
     u"            scales[c] = nil",
     "as colunas nao compartilham regua"),






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


falhas = []
for nome, arquivo, de, para, label in SABOTAGENS:
    tmp = tempfile.mkdtemp(prefix="sab_")
    shutil.copytree(SRC, os.path.join(tmp, "a"), dirs_exist_ok=True)
    tmp = os.path.join(tmp, "a")

    alvo = os.path.join(tmp, arquivo)
    txt = io.open(alvo, encoding="utf-8").read().replace("\r\n", "\n")
    if txt.count(de) != 1:
        print("  ?     %-42s ANCORA NAO BATE (%d)" % (nome, txt.count(de)))
        falhas.append(nome)
        continue
    io.open(alvo, "w", encoding="utf-8", newline="\n").write(txt.replace(de, para, 1))

    saida = rodar(tmp)
    chegou_ao_fim = FIM in saida

    if label is None:
        # Sem label: basta que o harness tenha PARADO. Ele reprova com mensagem propria.
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

print()
print("sabotagens que NAO foram pegas: %d" % len(falhas))
for f in falhas:
    print("  - " + f)
sys.exit(1 if falhas else 0)
