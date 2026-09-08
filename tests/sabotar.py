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
    ("as variantes da barra nao mudam nada", "Window.lua",
     u"    row.valuePlate:SetShown(style.plate)",
     u"    row.valuePlate:SetShown(false)",
     "`nativo` mostra a placa"),

    ("o fundo tingido volta a ser transparente", "Window.lua",
     u"                if style.tint > 0 then",
     u"                if false then",
     "`nativo` tinge o fundo da linha"),

    ("secoes viram uma lista so", "Data.lua",
     u"        if def and not seen[def.attr] then",
     u"        if def then",
     "tres metricas viram tres secoes"),

    ("a secao perde a propria regua", "Window.lua",
     u"        local top = secao.session and secao.session.maxAmount",
     u"        local top = 1",
     "as secoes nao compartilham regua"),

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
