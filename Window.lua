-- RocketMeter | Window.lua
--
-- A linha é uma BARRA, não uma célula de planilha: fundo escuro, preenchimento na cor da
-- classe proporcional ao valor, ícone e nome por cima, número à direita — o formato do medidor
-- nativo do jogo. As métricas extras entram como colunas à direita, que é o ganho sobre abrir
-- uma janela por métrica.
--
-- Fonte, tamanho, altura de linha e largura são configuráveis; a janela redimensiona pela alça
-- do canto. Fecha só no X — nunca no ESC.
local ADDON, ns = ...
local L = ns.L

local Window = {}
ns.Window = Window

-- APARENCIA FIXA. Nada aqui e configuravel: primeiro o padrao precisa estar certo.
-- Os valores saem da referencia (Details com a skin do medidor nativo).
-- A FONTE DO CHAT DO JOGO, porque foi a referência que o usuário deu: *"olha na primeira
-- imagem como tá o meu chat, como fica bem legível ele"*.
--
-- Não é palpite sobre qual é: `ChatFontNormal` herda de `NumberFont_Shadow_Med`, que é
-- `Fonts\ARIALN.TTF` com `height="14"` e sombra (1,−1) preta
-- (`Blizzard_Fonts_Shared/Mainline/Fonts.xml:775-777`). A sombra já era a nossa; faltavam a
-- família e o corpo.
--
-- A troca de família resolve a tensão que a 0.50.0 deixou registrada. Lá, copiar o corpo do
-- medidor nativo (16, em Friz) foi reprovado in-game: a janela dele mostra UMA métrica, a nossa
-- mostra seis colunas, e mais corpo virava mais tinta. Arial Narrow é **condensada** — rende
-- caixa alta maior (12px contra os 9px do Friz 13) gastando MENOS largura por caractere. Cresce
-- na altura, que é onde faltava, e encolhe na largura, que é onde faltava espaço.
local FONT = "Fonts\\ARIALN.TTF"

-- AS FONTES QUE O JOGO TRAZ, para o alfabeto romano. Só entram nomes que aparecem nas
-- declarações de `Blizzard_Fonts_Shared` — inventar caminho de fonte não dá erro visível, dá
-- texto que some.
--
-- Morpheus e Skurri são decorativas (título de missão e texto de combate) e ficam ruins numa
-- coluna de números; entram porque a escolha é do jogador, não minha.
ns.FONT_CHOICES = {
    { path = "Fonts\\ARIALN.TTF",   label = "Arial Narrow" },
    { path = "Fonts\\FRIZQT__.TTF", label = "Friz Quadrata" },
    { path = "Fonts\\MORPHEUS.TTF", label = "Morpheus" },
    { path = "Fonts\\skurri.ttf",   label = "Skurri" },
}

-- Contorno: os três níveis que o WoW tem, com os nomes que o jogador entende. Mesma escala do
-- Chattynator (nenhum / fino / grosso), que é a referência que ele pediu.
-- A ESPESSURA DO MEIO-TERMO, e ela e continua: as copias ficam a 1px do glifo, entao o envelope
ns.OUTLINE_CHOICES = {
    { value = "none",  flags = "" },
    { value = "thin",  flags = "OUTLINE" },
    { value = "thick", flags = "THICKOUTLINE" },
}
-- Medido no print oficial lado a lado: os dígitos do medidor nativo têm 11px de altura de
-- caixa alta; os nossos, com corpo 13, tinham 9px. FRIZQT rende ~0,69px de caixa por ponto,
-- então 11px pediria corpo 16 — e 16 foi testado in-game e reprovado por ficar grande.
--
-- O motivo de não copiar o número dele: a janela da Blizzard mostra **uma** métrica, a nossa
-- mostra seis colunas de números. A mesma altura de letra rende muito mais tinta aqui, e o
-- que lá é confortável aqui vira bloco. Igualar o corpo não igualaria a densidade.
--
-- A busca foi 16 -> 14 -> 13 -> 12 -> **13**, cada degrau visto in-game. O 12 foi testado e o
-- usuário voltou: "aumenta para 13px, acho que fica melhor o tamanho do texto para a janela de
-- combate". 13 é o valor final desta janela.
--
-- Vale para a linha INTEIRA: nome e todas as células, com ou sem realce, na coluna ordenada ou
-- não. Isso tira o corpo de fonte da lista de sinais de realce — o que sobra para marcar o
-- líder de uma coluna é a cor (a da própria classe, clareada) e, para a coluna ordenada, o
-- dourado no cabeçalho. Tamanho variando dentro da mesma linha fazia a régua dos números dançar.
--
-- Em px de caixa alta, pela taxa medida (~0,69px por ponto): 13 rende 9px, 12 rendia ~8px.
-- CORPO PADRÃO. 16, e não os 17 do chat: o chat ocupa a largura da tela com uma coluna de
-- texto, e esta janela carrega seis colunas de número na mesma altura de linha. É a mesma
-- correção que a 0.50.0 fez na outra direção — medida de fora vale como ponto de partida, não
-- como alvo, porque a densidade das duas telas é diferente.
local FONT_SIZE_DEFAULT = 16

-- LIMITES DO CORPO CONFIGURÁVEL, e os dois saem de conta, não de gosto.
--
-- TETO 20 — vem da LARGURA DA CÉLULA. A célula tem 50px (`COLUMN_WIDTH_FIXED` menos 8), e o
-- texto mais longo que `Data.FormatAmount` produz tem 5 caracteres ("-339M", "10.0K"). Em Arial
-- Narrow um dígito avança ~0,5 do corpo, então 5 dígitos ocupam ~2,5×corpo:
--
--     2,5 × 20 = 50px   ← exatamente a célula
--
-- Um ponto acima disso e o número volta a virar reticências, que foi a reclamação da 0.54.0.
-- Por isso o teto é 20 e não um número redondo escolhido no olho.
--
-- PISO 10 — abaixo daí a caixa alta fica em ~7px e o texto deixa de ser lido de relance numa
-- janela que fica no canto da tela. Não há razão aritmética exata aqui; é o ponto onde a
-- própria função do addon se perde.
-- Geometria da linha. Sobe para ca porque `ns.RowHeightFor` a usa, e `local` declarado depois
-- de uma funcao resolve como GLOBAL dentro dela -- ou seja, nil.
-- QUANTO O NUMERO E A TAXA RESERVAM a direita da barra. E reserva fixa, nao medicao: medir o
-- texto a cada quadro daria uma largura que muda conforme o numero cresce ("9K" -> "12K" ->
-- "134K"), e o nome ficaria pulando de tamanho no meio da luta.
--
-- 96 = ~56 para o total (cabe "1.2B") + ~34 para a taxa + a folga entre os dois.
-- A CALHA entre o fim do nome e a primeira coluna. Ela ja existia como um `10` solto dentro da
-- conta do nome; virou constante porque agora DUAS contas dependem dela -- a area do nome e a
-- largura minima da janela --, e um `10` digitado em dois lugares e a receita para elas
-- divergirem, que e exatamente o defeito que este arquivo acabou de ter.
local NAME_GUTTER = 10

local NUMBER_RESERVE = 96

-- A CELULA DE COLUNA, agora que ela e uma barra.
--
-- `CELL_GAP` separa uma coluna da vizinha: sem ele as barras encostam e viram uma faixa continua,
-- e o olho perde onde uma metrica termina e a outra comeca -- que e justamente a leitura que este
-- desenho existe para dar.
--
-- `CELL_INSET` deixa a barra um pouco mais baixa que a linha, para as barras de linhas vizinhas
-- nao se tocarem na vertical.
--
-- O TRILHO ESCURO ATRAS DA BARRA SAIU, a pedido do usuario: *"tira o fundo preto com algum
-- percentual de opacidade"*.
--
-- Ele existia para dar chao ao numero na parte VAZIA da barra -- que e onde o numero cai para
-- todo mundo menos o lider da coluna. Sem ele, essa parte e o cenario do jogo.
--
-- ⚠️ Entao o que sustenta a leitura passa a ser SO a sombra do texto. E a mesma aposta que a
-- janela ja faz no nome e no relogio (`ROW_BG_ALPHA = 0`, `WINDOW_ALPHA = 0`) e que o usuario ja
-- aprovou la; se o numero ficar ruim sobre cenario claro, o conserto e o contorno/sombra DELE, e
-- nao trazer a caixa de volta -- foi ela que ele mandou tirar.
-- A FOLGA ENTRE FAMILIAS. Queixa do usuario: *"me incomodou a divisao das colunas, ta muito em
-- cima da anterior o comando da proxima, mais ainda o interrupt, comeca em cima do CPS"*.
--
-- Ele esta descrevendo a lei da proximidade quebrada. Dano+DPS sao UMA barra e Cura+CPS sao
-- outra, mas o espaco entre as duas familias era o mesmo 4px que separava qualquer coisa: sem
-- diferenca de vao, o olho nao tem como saber onde uma metrica acaba e a outra comeca.
--
-- 10 nao e numero novo: e o `NAME_GUTTER`, que ja e a calha entre o NOME e as metricas -- ou
-- seja, o vao que este addon ja usa para dizer "aqui muda de assunto". Uma familia e outro
-- assunto pelo mesmo motivo. Um vocabulario de vao so, em vez de dois.
--
-- ⚑ E ELE SAI DA ESQUERDA DO GRUPO, nao dos dois lados. Tirando dos dois, a borda direita da
-- barra se afastaria da borda direita da coluna e o CABECALHO (que e ancorado na coluna, nao no
-- grupo) deixaria de ficar em cima do numero que ele nomeia. Saindo so da esquerda, o vao aparece
-- exatamente onde ele precisa aparecer -- entre uma familia e a anterior -- e o alinhamento de
-- cabecalho com numero fica intacto.
local GROUP_GAP = 10
local CELL_GAP = 4
local CELL_INSET = 2

local ROW_HEIGHT_FIXED = 25   -- medido no nativo: linha de y=68 a y=92
local COLUMN_WIDTH_FIXED = 58
-- ⚑ ESTES 3px ERAM A FAIXA DE COR DE CLASSE no rodape da linha, removida a pedido do usuario
-- em 08/09/2026 (*"remove a linha da cor da classe da coluna do nome"*). Eles FICARAM, e de
-- proposito: tira-los reduz a altura da linha de 29 para 26 no corpo padrao e re-espaca a janela
-- inteira -- uma mudanca visivel que ninguem pediu. Hoje sao respiro no rodape.
--
-- O nome mudou junto: constante que descreve o que nao existe mais e a forma mais barata de a
-- proxima pessoa procurar uma faixa que nao esta la.
local ROW_BOTTOM_ROOM = 3

local FONT_SIZE_MIN = 10
local FONT_SIZE_MAX = 20

-- Abaixo daqui o contorno SAI sozinho. Um contorno de 1px sobre uma caixa alta de ~9px é 11% da
-- altura da letra e fecha os vazados do "a", do "e" e do "8" — vira mancha. É a mesma razão pela
-- qual o placar (corpo 12) nunca teve contorno.
local OUTLINE_MIN_SIZE = 13

-- TRÊS TEXTOS INDEPENDENTES, cada um com corpo, contorno e sombra próprios.
--
-- Eles eram deltas de um corpo único (−2, −3, −4), e o usuário reprovou pelo motivo certo:
-- *"mudo um e ele faz pra tudo e fica ruim"*. Um cabeçalho de coluna e o corpo de uma linha
-- de número não têm por que andar juntos — o primeiro é rótulo estático que se lê uma vez, o
-- segundo muda a cada segundo e é o que se lê de relance.
--
-- Os deltas viram apenas o PADRÃO de cada papel; a partir daí cada um é seu.
local ROLES = { "body", "title", "header" }

local ROLE_DEFAULTS = {
    body   = { size = 16, outline = "thin", shadow = true },
    title  = { size = 14, outline = "thin", shadow = true },
    header = { size = 12, outline = "none", shadow = true },
}

-- O relógio mora na barra de título e acompanha o título, um ponto abaixo. Não virou um quarto
-- controle porque ninguém pensa nele como um texto separado — é a hora do título.
local CLOCK_DELTA = -1

---Altura da linha para um dado corpo.
---
---25px é a medida tirada do medidor nativo e continua sendo o **piso**. Com o corpo
---configurável ela não pode ser só isso: em 20 o texto passa de 20px entre caixa alta,
---descendentes e contorno, e ainda há 3px de respiro no rodapé — sem crescer junto, o texto
---encostaria na linha de baixo e na de cima.
---
---O fator 1,45 cobre caixa alta + descendente em Arial Narrow; os +2 são a folga do contorno.
function ns.RowHeightFor(size)
    local needed = math.ceil(size * 1.45) + 2 + ROW_BOTTOM_ROOM
    if needed > ROW_HEIGHT_FIXED then return needed end
    return ROW_HEIGHT_FIXED
end

---Reescreve em `ns.Skin` os valores que dependem do corpo.
---
---`ns.Skin` é uma TABELA lida por outras telas, e elas leem o campo, não uma função. Com o
---corpo fixo isso bastava; agora precisa ser refeito a cada mudança, senão o placar continuaria
---calculando o delta dele contra o corpo antigo.
function ns.RefreshSkin()
    ns.Skin.font = ns.FontPath()
    ns.Skin.fontSize = ns.RoleSize("body")
    ns.Skin.titleFontSize = ns.RoleSize("title")
    ns.Skin.clockFontSize = ns.RoleSize("title") + CLOCK_DELTA
    ns.Skin.colheadFontSize = ns.RoleSize("header")
    ns.Skin.fontOutline = ns.OutlineFor("body")
    ns.Skin.rowHeight = ns.RowHeightFor(ns.RoleSize("body"))
end

---A configuracao de um papel, sempre completa e sempre dentro dos limites.
---
---Le da configuracao a cada chamada em vez de guardar: assim o passo do configurador aparece
---na tela sem `/reload`. E cai no padrao do papel quando a chave nao existe -- que e o caso de
---quem atualiza o addon antes de a migracao rodar.
---A configuracao de um papel de texto. **Ela nunca devolve tabela incompleta** -- e a garantia
---existe porque a falta dela virou travamento intermitente.
---
---⚠️ SINTOMA NAO EXPLICADO, e fica registrado assim de proposito. Em ~3 de 12 rodadas do harness,
---`ns.OutlineFor("body")` recebia daqui um `config` com `size` E `outline` nil e estourava em
---`size < OUTLINE_MIN_SIZE` ("attempt to compare nil with number"), sempre em pontos diferentes
---do teste. Investiguei com instrumentacao, nao com teoria:
---
---  * `ns.db.text.body` estava INTEGRO no instante da falha (size 16, outline "thin");
---  * `ROLE_DEFAULTS.body` tambem: 25 rodadas com uma armadilha de escrita e nenhuma disparou,
---    e uma checagem dentro desta funcao nunca viu `base.size` deixar de ser numero.
---
---Ou seja: as duas fontes estavam certas e a saida veio errada. Nao encontrei o mecanismo, e por
---isso o comentario diz isso em vez de inventar uma causa -- a proxima pessoa merece saber que a
---blindagem abaixo e uma REDE, e que o buraco continua aberto.
---
---A rede e barata e correta por si: quem le uma configuracao tem direito a uma configuracao
---completa, e nenhum caminho daqui deveria produzir campo faltando.
---O CORPO de um papel, garantidamente numero.
---
---Existe porque `ns.RoleConfig(role).size` chegou nil em TRES chamadores diferentes
---(`ApplyRoleFont` e `OutlineFor`), em ~3 de 30 rodadas do harness, e a
---investigacao nao achou o mecanismo -- ver o comentario longo em `RoleConfig`. Enquanto ele nao
---for achado, ninguem le `.size` cru: le por aqui.
function ns.RoleSizeSafe(role)
    local config = ns.RoleConfig(role)
    local size = config and config.size
    if type(size) ~= "number" then return FONT_SIZE_MIN end
    return size
end

function ns.RoleConfig(role)
    local base = ROLE_DEFAULTS[role] or ROLE_DEFAULTS.body
    -- Ate o `base` passa a ser conferido: se o padrao chegar quebrado, o piso de fonte responde.
    local baseSize = type(base.size) == "number" and base.size or FONT_SIZE_MIN
    local baseOutline = base.outline or "none"

    local saved = ns.db and ns.db.text and ns.db.text[role]
    if type(saved) ~= "table" then
        return { size = baseSize, outline = baseOutline, shadow = base.shadow ~= false }
    end

    local size = saved.size
    if type(size) ~= "number" then size = baseSize end
    if size < FONT_SIZE_MIN then size = FONT_SIZE_MIN end
    if size > FONT_SIZE_MAX then size = FONT_SIZE_MAX end

    return {
        size = size,
        outline = saved.outline or baseOutline,
        shadow = saved.shadow ~= false,
    }
end

function ns.RoleSize(role)
    return ns.RoleConfig(role).size
end

ns.ROLES = ROLES
ns.ROLE_DEFAULTS = ROLE_DEFAULTS

---O contorno de um PAPEL, ja considerando o corpo dele.
---
---Recebe o papel e nao o tamanho porque agora cada texto tem contorno proprio -- era isso que
---faltava, e o usuario reprovou o contorno unico com a razao certa: "quero mexer no contorno de
---cada um tambem".
function ns.OutlineFor(role)
    local config = ns.RoleConfig(role)
    -- CINTO ALEM DO SUSPENSORIO, e o motivo esta no comentario de `RoleConfig`: esta comparacao
    -- estourou em producao com `size` nil, e a origem nao foi encontrada. Enquanto ela nao for,
    -- a janela nao pode deixar de desenhar por causa disso.
    local size = ns.RoleSizeSafe(role)
    local wanted = config.outline

    local flags = ""
    for _, choice in ipairs(ns.OUTLINE_CHOICES) do
        if choice.value == wanted then flags = choice.flags end
    end

    -- DEGRAU ABAIXO DO LIMIAR, em vez de obedecer cru. O jogador escolhe a intenção; o que ele
    -- não tem como prever é que o cabeçalho de coluna sai quatro pontos menor que a linha, e
    -- que num corpo pequeno o contorno fecha os vazados do "a", do "e" e do "8". Então cada
    -- texto que cair abaixo do limiar desce um nível — só ele, não a janela toda.
    if size < OUTLINE_MIN_SIZE then
        if flags == "THICKOUTLINE" then return "OUTLINE" end
        return ""
    end
    return flags
end

---A sombra de um papel: alfa 0.8 quando ligada, 0 quando nao.
function ns.ShadowAlphaFor(role)
    return ns.RoleConfig(role).shadow and 0.8 or 0
end

---O corpo escolhido, sempre dentro dos limites.
---
---Lê da configuração a cada chamada em vez de guardar numa constante: assim o passo do
---configurador aparece na tela sem `/reload`.
local FontSize
function ns.FontSize() return FontSize() end

---O corpo das LINHAS. Ficou como atalho para `ns.RoleSize("body")` porque metade do arquivo já
---o chamava, e trocar tudo por um nome mais longo só faria diferença de digitação.
function FontSize()
    return ns.RoleSize("body")
end

-- O PLACAR não segue esta janela. Ele foi visto e aprovado com corpo 12, e a subida para 13
-- foi pedida para "a janela de combate" — mudar as duas juntas desfaria uma aprovação que já
-- existe. Mesma razão de `PANEL_FONT_SIZE`: tela diferente, densidade diferente, corpo próprio.
local SCOREBOARD_FONT_SIZE = 12
-- O título da faixa e o cabeçalho de colunas são valores ABSOLUTOS, não deltas: não seguem o
-- corpo da linha. No nativo o título mede 9px de caixa contra 11px da linha, e é essa diferença
-- que dá a hierarquia da janela dele.
--
-- TÍTULO, RELÓGIO E CABEÇALHO ACOMPANHAM A LINHA, como deltas — não como números soltos.
--
-- Eram três absolutos, herdados de quando a linha era 13. Toda vez que o corpo da linha mudava
-- (e ele mudou seis vezes), a hierarquia se desfazia sozinha: chegou ao ponto de o título (13)
-- **empatar** com a linha (13), quando no medidor nativo ele é menor — é justamente o menor que
-- dá a hierarquia. O comentário antigo aqui dizia "se ficar gritando, o conserto é aqui", o que
-- é a descrição de um valor que devia ser derivado e não era.
--
-- Como delta, a relação sobrevive à próxima mudança de corpo sem ninguém lembrar dela. Medido
-- no nativo: título ~0,82 do conteúdo, que com a linha em 16 dá 13–14.

-- Calculados no momento da leitura, nao uma vez na carga: com o corpo configuravel, guardar
-- o resultado congelaria a hierarquia no valor que valia quando o arquivo carregou.
-- O painel de detalhamento não tem equivalente no medidor da Blizzard, então não segue o corpo
-- da linha: ele mantém o próprio, que é o que já estava aprovado. Crescer junto por herança
-- seria mudar uma tela que ninguém pediu para mudar.
local PANEL_FONT_SIZE = 13
local PANEL_ROW_HEIGHT = 22
-- CONTORNO LIGADO, e a decisão é do usuário — não minha inferência.
--
-- Eu tinha medido o print do chat dele e concluído "não tem contorno, só sombra". Errado: o
-- chat não é o da Blizzard, é o **Chattynator**, e a fonte foi ajustada por ele. A configuração
-- está em disco e diz o que ele escolheu:
--
--     ["message_font"]         = "default"    -- Chattynator: fonts.default = "ChatFontNormal"
--     ["message_font_size"]    = 17           -- GetFontScalingFactor() = 17/14
--     ["message_font_outline"] = "thin"       -- Chattynator: "thin" -> "OUTLINE"
--     ["show_font_shadow"]     = true         -- -> "SHADOW"
--
-- (`SavedVariables/Chattynator.lua` e `Chattynator/Core/Fonts.lua:6-28,59`.)
--
-- Ou seja: `OUTLINE` **de verdade**, mais sombra, em corpo 17. Isso reverte duas conclusões
-- anteriores deste arquivo, e vale registrar por quê:
--
--   * "`OUTLINE` em tudo ficou pesado" (0.48.0) foi medido em **Friz 13**. Em Arial Narrow 17
--     o traço do contorno é o mesmo 1px sobre um glifo bem maior — proporcionalmente muito
--     mais leve. O que pesava era a razão contorno/glifo, não o contorno.
--   * O halo desenhado existia para dar meio-termo entre "nada" e `OUTLINE`. Com o corpo maior
--     o meio-termo deixou de ser necessário, e ele continua desligado — somar os dois dobraria
--     o traço.
-- Não há mais constante de contorno: quem decide é `ns.OutlineFor(corpo)`, porque com o corpo
-- configurável a resposta certa depende do tamanho de cada texto. Chamar `ns.ApplyFont` sem o
-- terceiro argumento é o jeito normal; passar `""` é para quem quer explicitamente nenhum
-- (as cópias do halo).
-- O nome do reino entra sempre um ponto abaixo do nome do personagem. Fora do próprio reino o
-- servidor devolve "Nome-Reino", e no corpo cheio os dois competiam: o print de 05/09 mostrava
-- "Magicpandá-Tic…" — nome e reino brigando pela mesma largura, e as reticências comendo os
-- dois. Hierarquia por corpo resolve sem esconder de onde a pessoa é.
local REALM_FONT_DELTA = -1
ns.REALM_FONT_DELTA = REALM_FONT_DELTA
-- Medição do print lado a lado corrige o que eu havia concluído antes: a linha do medidor
-- nativo mede RGB(23,42,51) e o cenário ao lado dela RGB(27,46,54) — ou seja, **ela também é
-- transparente**. Então o preto ao redor das letras dele não vem de fundo escuro: é contorno
-- de verdade. Entorno dos glifos: mediana 10 no nome e 0 nos números. O nosso nome já mede 0,
-- os números mediam 34 — o halo estava certo, faltava corpo de fonte para ele cobrir.
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"
-- Estes números vêm do `styleConfig` da skin Details_Midnight, que está instalada:
--   wallpaperAlpha = 0.4      -> fundo da janela
--   barBackgroundAlpha = 0.4  -> fundo escuro atrás do preenchimento
--   barHeight = 20, barSpacingBetween = 1, barFontSize = 12
local BAR_BRIGHTNESS = 0.7          -- escurece a cor da classe para o texto branco ler
-- A faixa fina do nativo **não é chapada**. Medida ao longo dela, sobre a mesma cor de classe
-- que a nossa usa (163,164,255): 52% na ponta esquerda, 67% no meio, 84% na direita. A nossa
-- estava chapada em 100% — era exatamente essa a diferença de "o nosso tá mais claro".
-- A PISTA e a FAISCA.
--
-- `TRACK_ALPHA` = 0,15: a referencia deste projeto tinge o fundo da linha com a cor da classe a
-- ~18%, e 15 e o mesmo gesto um ponto mais discreto -- aqui a pista divide espaco com os numeros,
-- que la ficam sobre a barra cheia.
--
-- `SPARK_ALPHA` = 0,35 e o pico do degrade, no lado da ponta.
--
-- Ele CAIU de 0,55 quando o brilho deixou de ter largura fixa. Com 10px de rastro, 0,55 era o
-- pico de uma manchinha; agora o degrade se estica pelo preenchimento inteiro, e o mesmo 0,55
-- lavaria a barra do lider de branco. 0,35 mantem a ponta nitidamente mais clara que o meio sem
-- apagar a cor da classe embaixo -- que e o que a barra tem para dizer quem e quem.
-- O respiro entre o numero e a borda da barra. 3px e o mesmo recuo que o texto ja tinha
-- quando era alinhado a direita -- o que mudou foi a ponta, nao a margem.
local TEXT_INSET = 3

-- O respiro ALEM do recuo, para o numero nao encostar no vizinho quando a fonte e larga. 4px e a
-- mesma folga que separa duas celulas hoje (`CELL_GAP`), aplicada ao texto.
local TEXT_ROOM = 4

-- ⚑ O CORPO DA FONTE NAO E UM SINAL. Nao virou um agora, e nao pode voltar a ser.
--
-- E decisao do usuario de 05/09/2026, ja escrita neste arquivo -- e que eu desrespeitei em 09/09
-- ao por o companheiro do par tres pontos menor. Ele mandou desfazer no mesmo dia, com print:
-- *"o texto cada um parece em uma escala ou tamanho de fonte diferente, ficou bizarro, esse tipo
-- de erro nao pode mais acontecer"*.
--
-- Duas razoes, e a segunda so apareceu na tela:
--
-- 1. **A regua vertical danca.** Numeros de uma mesma coluna mudando de tamanho de linha para
--    linha tiram a referencia que faz uma tabela ser legivel de relance.
-- 2. **O degrau cruzava o limiar do CONTORNO.** Com corpo 13 e `OUTLINE_MIN_SIZE` tambem 13, o
--    companheiro caia para 10 e perdia o contorno JUNTO com o tamanho -- duas mudancas de uma
--    vez, e e por isso que leu como "escalas diferentes" em vez de hierarquia.
--
-- A hierarquia que sobra e a COR, que nao mexe em metrica nenhuma. Mais fraca de proposito: e o
-- preco de nao mexer no corpo, e o corpo nao esta em jogo.
--
-- A constante fica em ZERO, e nao some, para o proximo que pensar em usar o corpo como sinal ler
-- isto antes de tentar.
local PAIR_DELTA = 0

-- O SEPARADOR do trio. Um ponto medio, na cor apagada, entre numeros vizinhos.
--
-- So aparece com TRES membros, a pedido do usuario. Com dois ele seria pior que nada: eles estao
-- nas duas pontas da barra, longe um do outro, e um ponto solto no meio nao separaria nada --
-- pareceria sujeira. Com tres, os vizinhos se aproximam e a marca passa a ter trabalho.
local DOT_TEXT = "\194\183"     -- U+00B7 MIDDLE DOT, em UTF-8
local DOT_DELTA = -4

local TRACK_ALPHA = 0.15
local SPARK_ALPHA = 0.35

local BAR_GRADIENT_MIN = 0.52
local BAR_GRADIENT_MAX = 0.84
-- Fundo da linha totalmente transparente: com a janela sem fundo, um preto parcial atrás de
-- cada linha é meio-termo — aparece como um retângulo cinza flutuando sobre o cenário. Quem
-- sustenta a leitura é a sombra do texto, e a separação entre linhas vem da faixa de progresso.
local ROW_BG_ALPHA = 0
local ROW_BG_TINT = 0.22            -- quanto da cor da classe entra nesse fundo

-- Fundo invisível: é a variante "No Background" da skin (`wallpaperAlpha = 0.0`).
-- Quem sustenta a leitura é a sombra do texto; a separação vem da faixa de progresso.
local WINDOW_ALPHA = 0

-- Proporção da referência: a skin usa faixa de 32px com texto de 13pt, ou seja, o texto
-- ocupa ~40% da altura. Com 20px e 13pt eu tinha 65% — daí a sensação de apertado.
-- Exposto para os outros painéis (detalhamento, placar) seguirem a mesma linguagem sem
-- copiar valores — cópia é o que faz as telas divergirem com o tempo.
ns.Skin = {
    font = FONT,
    fontSize = ROLE_DEFAULTS.body.size,
    -- O contorno da JANELA DE COMBATE. O placar (corpo 12) e o painel de detalhamento (13)
    -- passam `""` de propósito: 1px de contorno sobre um glifo de ~8px fecha os vazados da
    -- letra, e os dois já foram vistos e aprovados sem ele. Se um dia tiverem que acompanhar,
    -- o conserto é trocar o `""` deles por `ns.Skin.fontOutline`.
    fontOutline = "OUTLINE",
    -- Corpos com valor próprio, expostos para as outras telas não redigitarem o literal: o
    -- placar tinha um `11` cravado no código que precisaria ser caçado à mão se este mudasse.
    colheadFontSize = ROLE_DEFAULTS.header.size,
    titleFontSize = ROLE_DEFAULTS.title.size,
    clockFontSize = ROLE_DEFAULTS.title.size + CLOCK_DELTA,
    -- Limites do corpo, expostos para o configurador não redigitar os números.
    fontSizeMin = FONT_SIZE_MIN,
    fontSizeMax = FONT_SIZE_MAX,
    rowsMin = 1,
    rowsMax = 20,
    -- Exposta porque é dela que sai o teto do corpo: o texto mais longo de uma célula tem que
    -- caber aqui, e é isso que o harness confere.
    columnWidth = COLUMN_WIDTH_FIXED,
    -- A folga entre familias de metrica. Exposta porque o teste afirma sobre ela, e travar
    -- o numero no teste faria a proxima mudanca de folga reprovar por design.
    groupGap = GROUP_GAP,
    scoreboardFontSize = SCOREBOARD_FONT_SIZE,
    barTexture = BAR_TEXTURE,
    barBrightness = BAR_BRIGHTNESS,
    rowHeight = ROW_HEIGHT_FIXED,
    panelRowHeight = PANEL_ROW_HEIGHT,
    rowSpacing = 1,
    rowBackground = { 0, 0, 0, ROW_BG_ALPHA },
    -- O painel de leitura tem fundo próprio, então lá as linhas ganham um preto leve para
    -- se separarem. Na janela transparente isso viraria listra cinza — por isso dois valores.
    panelRowBackground = { 0, 0, 0, 0.25 },
    windowAlpha = WINDOW_ALPHA,
    -- A janela é overlay sobre o jogo e fica transparente; painel de leitura pede fundo,
    -- senão o texto disputa com o cenário. Daí dois alfas em vez de um.
    panelAlpha = 0.70,
    -- O placar é o mais opaco dos três: ele abre por cima de tudo no fim da corrida, ocupa
    -- meia tela e carrega arte de fundo da masmorra. Valor próprio, não `panelAlpha + 0.22`
    -- somado no lugar de uso — token que vira conta perde a função de fonte única de verdade.
    scoreboardAlpha = 0.92,
    headerAtlas = "ui-damagemeters-header-bar",
    -- SEM RECORTE NENHUM — nem vertical nem horizontal.
    --
    -- Vertical: o recorte de 4/60 que eu usava comia as fileiras de borda do atlas. No nativo
    -- elas aparecem inteiras — dourado fraco de 2px em cima e forte de 2px embaixo, pico
    -- RGB(197,169,3); com o recorte o nosso pico caía para 131.
    --
    -- Horizontal: o 0.045..0.965 veio da skin Details_Midnight e eu o mantive sem conferir,
    -- com a justificativa de que "as pontas são os cantos". Medido no PNG do próprio atlas
    -- (`Details_Midnight/Textures/ui-damagemeters-header-bar-2x.png`, 560x56), as pontas são
    -- **a rampa de alfa** — o afunilamento que faz a faixa parecer uma fita:
    --
    --     x 0..16    alfa 0        (padding transparente)
    --     x 17..~70  alfa 0 -> 154 (a rampa: a ponta afunilada)
    --     x ~70..484 alfa 154      (o corpo)
    --     x 484..545 alfa 154 -> 0 (a rampa do outro lado)
    --
    -- 0.045 de 560 é x=25, ou seja **no meio da rampa**, onde o alfa já vale 40. Cortar ali
    -- descarta o afunilamento e deixa uma parede vertical de alfa 40 — o corte reto que o
    -- usuário circulou no print de 05/09 comparando com o rastreador de missões, que mostra
    -- a mesma arte com a ponta inteira.
    headerCrop = { 0, 1, 0, 1 },
    gold = { 1, 0.82, 0 },
    cream = { 1, 0.88, 0.62 },
    text = { 0.86, 0.87, 0.90 },
    dim = { 0.68, 0.69, 0.72 },
}

---Aplica a arte do cabeçalho da Blizzard numa textura, com o mesmo recorte da referência.
function ns.ApplyHeaderArt(texture)
    local info = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(ns.Skin.headerAtlas)

    if info and (info.file or info.filename) then
        texture:SetTexture(info.file or info.filename)
        local l, r = info.leftTexCoord or 0, info.rightTexCoord or 1
        local t, b = info.topTexCoord or 0, info.bottomTexCoord or 1
        local w, h = r - l, b - t
        local crop = ns.Skin.headerCrop
        texture:SetTexCoord(l + w * crop[1], l + w * crop[2], t + h * crop[3], t + h * crop[4])

        -- Sem tingimento: a arte é a mesma do medidor nativo, e ele a desenha crua. O 0.78
        -- que eu aplicava para escurecer o corpo da faixa apagava as bordas douradas junto —
        -- corpo nosso 32 contra 35 dele (acerto de 3), borda nossa 131 contra 197 dele (erro
        -- de 66). Trocar acerto de 3 por erro de 66 é o negócio errado.
        texture:SetVertexColor(1, 1, 1)
        return true
    end

    texture:SetColorTexture(0.13, 0.11, 0.07, 0.95)
    return false
end

local HEADER_HEIGHT = 27        -- medido no nativo: faixa de y=41 a y=67
local COLHEAD_HEIGHT = 12
local NAME_MIN_WIDTH = 96
-- Largura minima do botao que troca sessao ("Combate atual" / "Geral"). E MINIMA, nao fixa:
-- quando o indicador de rolagem entra no texto o botao cresce junto (ver Window.Draw).
local SEGMENT_MIN_WIDTH = 120
local PADDING = 3
-- No nativo o texto fica **centrado na linha**, não erguido: centro dos glifos em y=81 contra
-- centro da linha em y=80,5. A folga até a faixa colorida sai de a linha ser mais alta (25px),
-- não de empurrar o texto para cima — lá sobra 1px entre a base da letra e a faixa.
local TEXT_LIFT = 0
local MIN_ROWS = 1              -- uma linha ainda é útil: só você, no boneco de treino
local MAX_ROWS = 20             -- tamanho de uma raide; acima disso a janela toma a tela
local GRIP = 14

-- O CADEADO PRECISA MUDAR DE FORMA, NÃO DE COR.
--
-- Até a 0.54.0 os dois estados usavam a MESMA textura e só trocavam o tom: dourado quando
-- travado, cinza quando não. Num glifo de 14px isso não se lê — o usuário disse que não
-- conseguia perceber. E a lição já estava registrada neste projeto, na saga do realce de
-- líder: **cor sozinha ficou fraca**.
--
-- Não existe cadeado na família `common-icon-*` (conferido: são 26 glifos e nenhum é).
-- `Interface\Buttons\LockButton-Locked-Up` / `-Unlocked-Up` existem e formam par aberto/
-- fechado, mas são **arte de botão** com moldura e relevo — foram reprovados na 0.43.1 pelo
-- efeito "botão de Windows XP no meio de ícones planos".
--
-- A saída é dizer a mesma coisa por outro par:
--
--   destravado → `common-icon-move`, a cruz de setas. Glifo plano, da MESMA família dos
--                outros botões do cabeçalho, e diz exatamente o que o estado significa:
--                "dá para arrastar". Confirmado na fonte do 12.1.0, em
--                `Blizzard_HouseEditor/Blizzard_HouseEditorLayoutModePin.xml:289`, usado
--                como `iconAtlas`.
--   travado    → o cadeado de sempre, que já está na tela e portanto é sabidamente válido.
--
-- As duas formas são inconfundíveis a 14px. Se o atlas não existir neste cliente, a reserva
-- é o comportamento antigo (mesmo ícone, tons diferentes) — nunca um botão vazio. `/rm atlas`
-- diz qual dos dois caminhos está valendo.
local LOCK_ICON = "Interface\\PetBattles\\PetBattle-LockIcon"
local UNLOCK_ATLAS = "common-icon-move"

local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

function ns.BarTexture()
    return BAR_TEXTURE
end

---Este atlas existe neste cliente?
---
---`SetAtlas` com um nome que não existe **falha em silêncio**: a textura fica como estava e
---nada avisa. Perguntar antes é o que separa "o ícone mudou" de "o ícone continua igual e eu
---não sei por quê". Mesma guarda que o placar já usa; `/rm atlas` lista os nomes conferidos.
function ns.AtlasExists(name)
    if name == nil then return false end
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
    return info ~= nil
end

-- Onde cada coluna mora dentro do grupo dela, do ultimo desenho do cabecalho. Guardado para a
-- porta de teste poder comparar o rotulo com o numero -- sem isso, "eles comecam no mesmo x"
-- seria uma conta refeita, e conta refeita concorda consigo mesma.
local ondeFicaCache = {}

---A margem DIREITA de um frame, lida das ancoras dele.
---
---⚑ EXISTE PARA AS PORTAS DE TESTE NAO MEDIREM A FORMULA. A primeira versao de `inkX` repetia
---`PADDING` a mao dos dois lados -- e com isso a sabotagem "o cabecalho volta a ter margem
---propria" passava batida: mudar o `SetPoint` do `headerRow` nao mexia num numero que nao vinha
---dele. Conta refeita concorda consigo mesma.
local function MargemDireita(frame_)
    for i = 1, (frame_.GetNumPoints and frame_:GetNumPoints() or 0) do
        local ponto, _, _, x = frame_:GetPoint(i)
        if ponto == "TOPRIGHT" or ponto == "RIGHT" or ponto == "BOTTOMRIGHT" then
            return -(x or 0)
        end
    end
    return PADDING
end

local frame, headerRow, rows
local dirty, throttle = false, 0
local visibleRows = -1
local scrollOffset = 0      -- quantas linhas foram roladas para fora do topo
local totalRows = 0         -- quantos atores existem ao todo, para limitar a rolagem

--------------------------------------------------------------------------------
-- Fonte e cor
--------------------------------------------------------------------------------
---A fonte escolhida, ou a padrão se a escolhida não estiver mais disponível.
---
---Uma fonte vinda de outro addon (via LibSharedMedia) some quando aquele addon é desinstalado,
---e o caminho gravado aqui continua apontando para um arquivo que não existe. `SetFont` com
---caminho inválido **não desenha** — o texto some, sem erro. Por isso a escolha é sempre
---validada antes de virar o padrão de desenho (ver `ns.ApplyFont`).
function ns.FontPath()
    local chosen = ns.db and ns.db.font
    if type(chosen) == "string" and chosen ~= "" then return chosen end
    return FONT
end

---A fonte que REALMENTE desenha. Se a escolhida falhar, cai na padrão e avisa uma vez.
local fontWarned
local function SafeSetFont(fontString, path, size, flags)
    local ok = pcall(fontString.SetFont, fontString, path, size, flags)
    -- `SetFont` devolve `false` quando o arquivo não serve (`RequiresValidFontAsset = true` na
    -- documentação da API). Testar os dois cobre as duas formas de falhar.
    if ok and fontString:GetFont() then return true end

    if path ~= FONT then
        if not fontWarned then
            fontWarned = true
            ns.Print(format(L["the font %s could not be loaded; using the default."],
                tostring(path)))
        end
        return pcall(fontString.SetFont, fontString, FONT, size, flags)
    end
    return false
end

---Aplica a fonte de um PAPEL. `delta` ajusta o corpo para textos secundários do mesmo papel
---(o relógio, o reino), que continuam acompanhando o papel a que pertencem.
---
---A assinatura leva o papel, e não o tamanho, e é isso que permite os três textos
---independentes: cada chamada diz **quem ela é**, e a configuração daquele papel decide corpo,
---contorno e sombra. Com um corpo só, mexer num mexia em todos — que foi a reprovação.
function ns.ApplyRoleFont(fontString, role, delta, flagsOverride)
    local config = ns.RoleConfig(role)
    local size = ns.RoleSizeSafe(role) + (delta or 0)
    if size < 6 then size = 6 end

    local flags = flagsOverride
    if flags == nil then flags = ns.OutlineFor(role) end

    SafeSetFont(fontString, ns.FontPath(), size, flags)

    -- Sombra de 1px carrega o texto branco sobre a barra colorida sem o peso do contorno.
    -- Alfa 0.8, não 1: é o que o Chattynator usa no ramo `"SHADOW"` (`Core/Fonts.lua`), e a
    -- referência de legibilidade foi a janela de chat dele. Preto cheio somado ao contorno
    -- engrossa o traço duas vezes no mesmo pixel.
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, config.shadow and 0.8 or 0)

end

---O corpo das linhas, para quem tem corpo próprio e só precisa herdar contorno e sombra: o
---placar e o painel de detalhamento entram por aqui.
function ns.ApplyFont(fontString, delta, flags)
    local size = ns.RoleSize("body") + (delta or 0)
    if size < 6 then size = 6 end

    if flags == nil then flags = ns.OutlineFor("body") end

    SafeSetFont(fontString, ns.FontPath(), size, flags)
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, ns.ShadowAlphaFor("body"))
end

---Fonte do painel de leitura, que tem corpo próprio (ver `PANEL_FONT_SIZE`).
function ns.ApplyPanelFont(fontString, delta, flags)
    -- `FontSize()`, nao a constante: o delta e relativo ao corpo VIGENTE da janela. Com a
    -- constante, mexer no corpo da janela arrastaria junto um painel que tem corpo proprio.
    ns.ApplyFont(fontString, (delta or 0) + PANEL_FONT_SIZE - FontSize(), flags)
end

---Fonte do placar de fim de corrida, que também tem corpo próprio.
function ns.ApplyScoreboardFont(fontString, delta, flags)
    ns.ApplyFont(fontString, (delta or 0) + SCOREBOARD_FONT_SIZE - FontSize(), flags)
end

--------------------------------------------------------------------------------
-- Contorno com espessura ajustável
--------------------------------------------------------------------------------
-- O WoW só tem três níveis de contorno (nenhum, `OUTLINE`, `THICKOUTLINE`) — nada entre eles.
-- Para um meio-termo, o contorno é **desenhado**: cópias pretas do texto deslocadas 1px atrás

--
-- ESTÁ DESLIGADO (lista vazia), e o motivo é medido, não de gosto.
--
-- O usuário apontou a janela de chat dele como o padrão de legibilidade — "olha na primeira
-- imagem como tá o meu chat". Medido no print de 05/09/2026: o chat **não tem contorno**, só
-- `SetShadowOffset(1, -1)` preto, que é exatamente a sombra que `ns.ApplyFont` já aplica. O
-- que sobrava aqui era o halo POR CIMA dela.
--
-- E ele era assimétrico: `{-1,0}` e `{0,1}` põem cópia à esquerda e acima, enquanto a sombra
-- fica embaixo à direita. Três lados cobertos, um não — daí "umas colunas parece tá com mais
-- borda a fonte, outras não". Não era impressão: dependia de qual lado do glifo encostava no
-- vizinho, e mudava de coluna para coluna.
--
-- Isso foi escrito na 0.49.0 e terminava em "se um dia fizer falta". Fez: o usuário testou os
-- dois contornos e pediu o meio-termo — "são bem gritantes as diferenças, senti falta de um
-- 'meio termo' dos dois". A máquina volta, com as DUAS correções que a desligaram:
--
--   1. Simetria: os dois deslocamentos de antes ({-1,0} e {0,1}) cobriam esquerda e topo e
--      deixavam direita e base para a sombra — três lados de um jeito, um de outro. Era isso o
--      "umas colunas parece tá com mais borda a fonte, outras não": não era impressão,
--      dependia de qual lado do glifo encostava no vizinho.
--   2. Só entra quando o papel pede ("medium"). Antes ele somava com a sombra em todo texto, e
--      dois traços no mesmo pixel engrossam duas vezes.
--
-- E A PRIMEIRA TENTATIVA DO MÉDIO ESTAVA GEOMETRICAMENTE ERRADA — relato: "o contorno médio tá
-- igual ao fino". Estava mesmo, e por construção. Ela punha quatro cópias deslocadas **1px**,
-- que é EXATAMENTE onde o `OUTLINE` do próprio texto já pinta preto sólido. As cópias caíam
-- debaixo do que já estava lá e não podiam aparecer. Deslocar não engrossa nada enquanto o
-- deslocamento couber dentro do contorno que já existe.
--
-- A CONSTRUÇÃO CERTA NÃO DESLOCA: ela empilha. `OUTLINE` pinta um anel de 1px; `THICKOUTLINE`
-- pinta um de 2px. O meio-termo é o anel de 2px **em opacidade parcial** por baixo do de 1px
-- sólido:
--
--     cópia  (atrás, alfa α):  THICKOUTLINE  → preto de 0 a 2px
--     texto  (na frente):      OUTLINE       → preto de 0 a 1px, sólido, + o glifo por cima
--     visto:                   sólido até 1px, α de 1px a 2px
--
-- O corpo preto da cópia fica escondido debaixo do glifo do original, que é do mesmo tamanho,
-- mesma fonte e mesma posição — sobra só o anel externo, que é o que se queria. E custa **uma**
-- cópia, não quatro: com deslocamento zero não há lado descoberto, então a simetria deixa de ser
-- um problema a resolver e passa a ser consequência.
---Separa `"Nome-Reino"` em nome e reino.
---
---O reino **não some**. A primeira tentativa foi apagá-lo com `Ambiguate`, e estava errada: o
---usuário quer ver de onde a pessoa é (decisão de 05/09/2026). O problema do print daquele dia
---— `Magicpandá-Tic…`, `Huntwave-Stor…` — não era o reino existir, era ele ocupar a mesma
---largura de letra do nome e empurrar os dois para as reticências. A solução é hierarquia, não
---remoção: o reino entra **um ponto menor** que o nome.
---
---Em combate o nome pode ser secret. `string.match` num secret é proibido, então nesse caso ele
---volta inteiro no primeiro retorno e sem reino — o widget sabe desenhar o valor cru, que é
---exatamente o comportamento certo.
---@return string|nil name
---@return string|nil realm  sem o hífen; nil quando não há reino no nome
function ns.SplitName(full)
    if full == nil or issecretvalue(full) or type(full) ~= "string" then
        return full, nil
    end

    -- O hífen separa; nome de personagem não tem hífen, nome de reino pode ter espaço.
    local name, realm = full:match("^([^%-]+)%-(.+)$")
    if name and realm ~= "" then return name, realm end
    return full, nil
end

---Escreve nome e reino numa linha, repartindo a largura entre os dois.
---
---A repartição não dá para ser fixa: ela depende do texto. `row.name` recebe a largura do
---próprio texto (limitada pela área) para o reino colar logo depois; sem isso o reino
---apareceria no fim da caixa do nome, com um vão no meio. O que sobra vai para o reino, que
---corta em reticências quando não couber — cortar o reino é aceitável, cortar o nome não.
---
---Quem tem os dois campos é `row` porque a janela e o placar montam a linha do mesmo jeito;
---a função vive aqui para as duas telas não divergirem.
---@param row table linha com `name`, `realm` e `nameArea`
---Escreve o nome (e, se o jogador quiser, o reino) dentro da área da linha.
---
---**A largura do halo tem que ser mexida junto com a do texto, nos DOIS ramos.** Só o ramo
---com reino fazia isso; o ramo sem reino trocava a largura do texto e deixava as cópias
---pretas com a largura da linha anterior. Como o halo é o contorno, o efeito era o nome sair
---com um traçado diferente dos outros — e aparecia justamente no personagem do próprio
---jogador, que é quem costuma estar no mesmo reino e portanto não tem sufixo.
local function SetNameWidth(row, width)
    row.name:SetWidth(width)

end

local function SetRealmWidth(row, width)
    row.realm:SetWidth(width)

end

function ns.DrawName(row, full)
    local name, realm = ns.SplitName(full)

    -- O reino é opcional e vem DESLIGADO: ele come a largura do que importa e, com a coluna
    -- estreita, transformava "Frenchmiku-Tichondrius" em "Frenchmiku-Tich…". Quem joga em
    -- grupo cross-realm e quer ver de onde a pessoa é liga em `/rm columns`.
    if not ns.db.showRealm then realm = nil end

    local area = row.nameArea or 0
    SetNameWidth(row, area)
    row.name:SetText(name)
    row.name:SetTextColor(1, 1, 1)

    if not realm or area <= 0 then
        row.realm:SetText("")
        SetRealmWidth(row, 0)
        return
    end

    -- `GetStringWidth` mede o texto ignorando a caixa, então serve para saber quanto ele
    -- realmente ocupa antes de decidir a divisão.
    local used = row.name:GetStringWidth() or 0
    if used > area then used = area end
    SetNameWidth(row, used)

    local left = area - used
    if left < 12 then
        -- Nome sozinho já toma a área: o reino não cabe e some. Melhor sumir inteiro do que
        -- aparecer como um hífen solto seguido de reticências.
        row.realm:SetText("")
        SetRealmWidth(row, 0)
        return
    end

    SetRealmWidth(row, left)
    row.realm:SetText("-" .. realm)
    row.realm:SetTextColor(unpack(ns.Skin.dim))
end

---Em combate `classFilename` pode ser secret, e indexar tabela com chave secret é proibido.
local function SafeClass(classFilename)
    if classFilename == nil or issecretvalue(classFilename) then
        return nil
    end
    return classFilename
end

function ns.ClassColor(classFilename)
    local class = SafeClass(classFilename)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then
        return color.r, color.g, color.b
    end
    return 0.45, 0.5, 0.62
end

---Cor do preenchimento da barra.
---
---A cor pura da classe é clara demais atrás de texto branco — no medidor da Blizzard e no
---Details a barra é uma versão **escurecida** dela. `barBrightness` controla o quanto.
function ns.BarColor(classFilename)
    local r, g, b = ns.ClassColor(classFilename)
    return r * BAR_BRIGHTNESS, g * BAR_BRIGHTNESS, b * BAR_BRIGHTNESS
end

---Pinta a faixa fina com o degradê horizontal do medidor nativo.
---
---A faixa dele escurece para a esquerda: 52% da cor da classe no início, 84% no fim. Chapar em
---100%, como eu fazia, é o que deixava a nossa visivelmente mais clara que a dele.
---
---Ordem importa: `SetStatusBarColor` mexe na cor de vértice, e é ela que o degradê substitui —
---chamar na ordem inversa apagaria o degradê.
function ns.ApplyBarColor(bar, classFilename)
    local r, g, b = ns.ClassColor(classFilename)
    local texture = bar:GetStatusBarTexture()

    if texture and texture.SetGradient and CreateColor then
        bar:SetStatusBarColor(1, 1, 1)
        texture:SetGradient("HORIZONTAL",
            CreateColor(r * BAR_GRADIENT_MIN, g * BAR_GRADIENT_MIN, b * BAR_GRADIENT_MIN, 1),
            CreateColor(r * BAR_GRADIENT_MAX, g * BAR_GRADIENT_MAX, b * BAR_GRADIENT_MAX, 1))
        bar.__gradient = true
        return
    end

    -- Cliente sem degradê: a média das duas pontas é o tom que o olho lê no conjunto.
    local k = (BAR_GRADIENT_MIN + BAR_GRADIENT_MAX) / 2
    bar:SetStatusBarColor(r * k, g * k, b * k)
end

---A PISTA de uma barra: o caminho todo, na cor da classe, bem apagado.
---
---⚠️ NÃO É O FUNDO PRETO. O usuário reprovou aquele duas vezes (*"tira o fundo preto com algum
---percentual de opacidade"*, *"o fundo preto é feio"*) e pediu esta (*"eu quero ... Pista
---tingida. Sem fundo preto"*). A diferença não é de opacidade, é de cor: preto empilha um bloco
---escuro por linha e some com a transparência da janela; a cor da classe apagada lê como o
---**resto do caminho** da própria barra.
---
---`mostrar = false` deixa a pista invisível — é o caso "zerado", em que não há caminho nenhum.
function ns.ApplyTrackColor(texture, classFilename, mostrar)
    if not mostrar then
        texture:SetColorTexture(0, 0, 0, 0)
        return
    end
    local r, g, b = ns.ClassColor(classFilename)
    texture:SetColorTexture(r, g, b, TRACK_ALPHA)
end

---A FAÍSCA: o preenchimento se acende em direção à ponta.
---
---Ela é branca e aditiva, com o alfa subindo da esquerda para a direita — o brilho mora no
---**fim**, que é onde a barra chegou. E ela ocupa exatamente o preenchimento, nem mais nem
---menos: as duas pontas são presas nele, então uma barra de 2px tem 2px de brilho. Não é cor de classe: cor de classe é vocabulário reservado
---neste projeto (dourado lê como "ladino", não como "líder"), e branco aditivo sobre a própria
---barra clareia a cor que já está lá em vez de introduzir outra.
---
---A amplitude sai da escada medida no cliente: a Blizzard usa alfa até **0,15** para "disponível,
---discreto" (talento selecionável) e **0,45→0,55 em 14s** para ambiente, contra 0,75→0,20 em meio
---segundo para vida baixa. Um destaque que aparece em vinte linhas ao mesmo tempo pertence ao
---primeiro grupo, não ao terceiro.
function ns.ApplySparkColor(texture, classFilename, mostrar)
    if not mostrar then
        texture:Hide()
        return
    end

    texture:SetColorTexture(1, 1, 1, 1)
    if texture.SetGradient and CreateColor then
        texture:SetGradient("HORIZONTAL",
            CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, SPARK_ALPHA))
    else
        -- Cliente sem degradê: o rastro vira um brilho chapado, mais fraco para compensar.
        texture:SetColorTexture(1, 1, 1, SPARK_ALPHA * 0.5)
    end
    texture:Show()
end

---Fundo da linha: a mesma cor, bem apagada, para a parte vazia não ser um buraco preto.
---Fundo da linha: **preto fixo**, não tingido pela classe.
---A skin usa `texture_background_class_color = false` com
---`barBackgroundColor = {0, 0, 0, 0.4}` — tingir pela classe, como eu fazia, deixava a parte
---vazia da barra colorida e embaralhava a leitura de quem tinha pouco.
function ns.RowBackdropColor()
    return 0, 0, 0, ROW_BG_ALPHA
end

local function ApplyClassIcon(texture, classFilename)
    local class = SafeClass(classFilename)
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        texture:SetTexture(CLASS_ICONS)
        texture:SetTexCoord(unpack(coords))
        texture:Show()
        return true
    end
    texture:Hide()
    return false
end

---Ícone da linha: especialização por padrão (diz mais que a classe — quem é o healer, quem
---tanka), com a classe como reserva quando a spec não veio.
-- Sem máscara: `SetMask` e `SetTexCoord` não convivem ("Cannot set tex coords when texture
-- has mask"), e a referência usa ícone quadrado mesmo. Duas texturas por linha: uma para o
-- ícone de especialização (id inteiro) e outra para o de classe (recorte de atlas).

---@param spec texture redonda, para o ícone de especialização (id inteiro, sem recorte)
---@param class texture com texcoord, para o recorte do atlas de classes
function ns.ApplyRowIcon(spec, class, source)
    local specIcon = source.specIconID
    if specIcon ~= nil and not issecretvalue(specIcon) and specIcon ~= 0 then
        spec:SetTexture(specIcon)
        spec:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- tira a borda preta do ícone
        spec:Show()
        class:Hide()
        return
    end

    local name = SafeClass(source.classFilename)
    local coords = name and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[name]
    if coords then
        class:SetTexture(CLASS_ICONS)
        class:SetTexCoord(unpack(coords))
        class:Show()
        spec:Hide()
        return
    end

    spec:Hide()
    class:Hide()
end

--------------------------------------------------------------------------------
-- Geometria
--------------------------------------------------------------------------------
local function RowHeight()
    return ns.RowHeightFor(FontSize())
end

-- A LARGURA DE CADA COLUNA, POR FAMILIA DE FORMATO.
--
-- Pedido do usuario: *"precisa aumentar um pouco a largura das colunas, principalmente nas colunas
-- onde o resultado e maior, Dano e Cura por exemplo"*.
--
-- Ele apontou o defeito pela consequencia: a largura era **uma so para todas** (58), entao a
-- coluna que escreve "339M" e a que escreve "8" recebiam o mesmo espaco -- a primeira apertada, a
-- segunda com metade dela vazia. Largura uniforme so faz sentido com conteudo uniforme.
--
-- ⚠️ OS NUMEROS SAO RELATIVOS AOS 58 QUE JA ESTAVAM NA TELA, e nao uma medicao de glifo. Eu tentei
-- derivar de largura de caractere primeiro e a conta deu larguras MENORES que as atuais -- porque
-- a largura do digito depende da fonte escolhida (o padrao e Friz Quadrata, mas o usuario roda
-- Arial Narrow), e isso eu nao consigo medir daqui. Ancorar no valor que ja funcionava e honesto;
-- inventar uma medicao seria pior que assumir a referencia.
--
--   total      "339M", "1.2B"   -> +18   e a coluna que ele citou (Dano, Cura, Recebido)
--   perSecond  "299K"           -> +6    um digito a menos que o total
--   percent    "100%"           -> +6
--   count      "19"             -> −10   dois digitos nao precisam de 58
-- A LARGURA POR FORMATO, e os tres pedidos de 08/09 cabem nesta tabela e no `DEFAULT_SLACK`:
-- *"a coluna do nome ta meio grande, acho que da pra reduzir um pouco so e aumentar as outras,
-- alem de deixa os nomes das colunas mescladas um pouco mais perto"*.
--
-- **O TOTAL CRESCE** (76 -> 92) porque e onde a barra mora. A largura aqui nao e sobre caber o
-- texto -- "1.2B" sempre coube -- e sobre RESOLUCAO da barra: 16px a mais e a diferenca entre
-- distinguir 78% de 84% e nao distinguir.
--
-- **A TAXA ENCOLHE** (64 -> 56), e e isso que aproxima os rotulos. O cabecalho e alinhado a
-- direita da coluna dele, entao o que separa "Dano" de "DPS" e exatamente a largura da coluna do
-- DPS: estreita-la puxa os dois um para o outro. Os dois numeros do par passam a se agrupar na
-- metade direita da barra, que e como o par deve ser lido -- uma dupla, nao duas colunas.
--
-- **A CONTAGEM CRESCE** (48 -> 56) porque ela era a mais apertada e e onde o par nao existe.
--
-- A conta fecha na largura de hoje: 92+56+92+56+56 = 352 contra 328, e os 24 a mais saem do
-- `DEFAULT_SLACK`. A janela continua em 517.
local COLUMN_WIDTH_BY_FIELD = {
    total = 92,
    perSecond = 56,
    percent = 56,
    count = 56,
}

---A largura de UMA coluna, pelo formato do que ela escreve.
---
---Acompanha o corpo da fonte: quem aumenta o texto aumenta a coluna junto, senao o numero cresce
---dentro de uma caixa que nao cresceu -- que e o mesmo defeito, so que causado pela configuracao.
---Os GRUPOS que a janela desenha, em cache por desenho.
---
---`ns.db.columns` continua sendo a lista que o jogador marca; o que vai para a tela e o
---agrupamento dela por metrica. Recalcular a cada uso seria barato, mas o cache mantem os quatro
---consumidores (offsets, cabecalho, celula, desenho) olhando exatamente a mesma lista -- e foi
---justamente duas contas divergirem que custou a versao passada.
local grupos = {}

local function RefreshGroups()
    grupos = ns.Data.GroupColumns(ns.db.columns)
    return grupos
end

local function Groups()
    if #grupos == 0 then RefreshGroups() end
    return grupos
end

ns.WindowGroups = Groups

---O que a CELULA de um grupo escreve: "65.1M - 48K".
---
---Cada metrica formata o proprio numero (`SetCellText` sabe de porcentagem, de valor secret e das
---faixas K/M/B), e o resultado e juntado com o mesmo separador do cabecalho -- e o que faz o
---jogador ler "Dano - DPS" em cima e "65.1M - 48K" embaixo como a mesma dupla.
---
---O grupo contem esta coluna?
---
---Serve a barra unica: ela precisa saber se a metrica que ORDENA a janela e uma das dela, para
---desenhar a proporcao daquela -- e nao a do total, que daria a barra mais longa a quem nao esta
---no topo da lista.
local function GroupHas(grupo, key)
    for i = 1, #grupo.keys do
        if grupo.keys[i] == key then return true end
    end
    return false
end

---O indice do GRUPO a que uma coluna pertence.
---
---⚑ EXISTE PORQUE O CABECALHO E MOVER FALAM LINGUAS DIFERENTES. `button.columnIndex` e posicao
---em `ns.db.columns`; `Window.MoveColumn` indexa a lista de GRUPOS. Com um par total+taxa ligado
---as duas listas tem tamanhos diferentes -- sempre -- e o clique passava o indice errado.
---
---O mesmo defeito ja tinha sido corrigido na tela de configuracao (`Picker.IndexOf`) e voltou
---pelo cabecalho quando ele deixou de ser por grupo. A traducao mora aqui agora, num lugar so.
local function GroupIndexFor(key)
    local lista = ns.Data.GroupColumns(ns.db.columns)
    for i = 1, #lista do
        if GroupHas(lista[i], key) then return i end
    end
    return nil
end

-- O TEXTO MAIS LONGO que cada formato chega a escrever. Nao e chute: sao as faixas que
-- `Data.FormatAmount` produz (uma casa decimal, corte em K/M/B) e `Data.FormatPercent`.
local COLUMN_SAMPLE = {
    total = "999.9M",
    perSecond = "999.9K",
    percent = "100.0%",
    count = "999",
}

-- A REGUA: uma FontString escondida, so para medir. O resultado e cacheado por
-- fonte+corpo, entao a medicao acontece uma vez por mudanca de aparencia -- nao por desenho.
local regua, larguraCache, larguraChave = nil, {}, nil

local function MedirTexto(texto)
    if not regua then
        regua = UIParent:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        regua:Hide()
    end
    ns.ApplyRoleFont(regua, "body", 0)
    regua:SetText(texto)
    local w = regua:GetStringWidth()
    return (type(w) == "number" and w > 0) and w or nil
end

---A largura de UMA coluna.
---
---⚑ ELA DEIXOU DE ESCALAR COM O CORPO DA FONTE, e passou a MEDIR o texto. Queixa do usuario,
---08/09: *"percebi que trocar tamanho de fonte e a fonte bagunca muito a largura das colunas, as
---vezes ate desproporcional"*.
---
---Ele descreveu o sintoma; a causa sao dois erros na mesma linha antiga
---(`base * RoleSizeSafe("body") / 16`):
---
---1. **A largura escalava com o CORPO**, mas ela existe para dar RESOLUCAO A BARRA -- 92px contra
---   56px e a diferenca entre distinguir 78% de 84% e nao distinguir. Resolucao de barra nao tem
---   nada a ver com o tamanho da letra. Escalando, trocar o corpo de 13 para 20 inflava a janela
---   inteira em ~54%, e era isso o "desproporcional".
---2. **A FAMILIA da fonte nao entrava na conta.** O fator saia de 16 assumindo as proporcoes da
---   Arial Narrow; numa fonte larga (FRIZQT, Morpheus) o mesmo corpo pede muito mais tinta, e o
---   texto transbordava sem nada avisar. Numa estreita, sobrava ar.
---
---Agora sao duas exigencias independentes, e a largura e a maior das duas:
---
---    resolucao   -- `COLUMN_WIDTH_BY_FIELD`, FIXA, porque e sobre a barra
---    o texto     -- MEDIDO na fonte e no corpo que estao valendo, mais o respiro
---
---Isso responde tambem o que ele ofereceu como alternativa (*"podemos por limite no tamanho da
---fonte... o limite por fonte pode mudar"*): com a coluna medindo o proprio texto, o limite deixa
---de ser necessario -- ela acompanha qualquer fonte em qualquer corpo, em vez de supor uma.
local function ColumnWidthFor(key)
    local def = ns.Data.GetColumn(key)

    -- METRICA DE CONTAGEM VEM PRIMEIRO, e nao pelo `field`: interrupcoes e dissipacoes tambem sao
    -- `total`, so que de uma contagem -- entao classificar por formato dava a elas a largura de
    -- "1.2B" para escrever "8". Quem sabe disso e o catalogo, que marca a metrica com `counts`.
    local formato = "total"
    if def and def.counts then
        formato = "count"
    elseif def and def.field then
        formato = def.field
    end

    local chave = tostring(ns.FontPath()) .. ":" .. tostring(ns.RoleSizeSafe("body"))
    if chave ~= larguraChave then
        larguraCache, larguraChave = {}, chave
    end
    if larguraCache[formato] then return larguraCache[formato] end

    local resolucao = COLUMN_WIDTH_BY_FIELD[formato] or COLUMN_WIDTH_FIXED

    -- O TEXTO, medido. Se a regua nao responder (cliente sem `GetStringWidth`, fonte que nao
    -- carregou), a resolucao sozinha decide -- que e exatamente o comportamento de antes desta
    -- mudanca. Reserva que piora nada.
    local tinta = MedirTexto(COLUMN_SAMPLE[formato] or COLUMN_SAMPLE.total)
    local pedidoDoTexto = tinta and math.ceil(tinta + TEXT_INSET * 2 + TEXT_ROOM) or 0

    local largura = math.max(resolucao, pedidoDoTexto)

    -- PISO: abaixo disto o rotulo do cabecalho ("Interr", "Dissip") nao cabe, e coluna cujo nome
    -- nao se le nao serve para nada.
    if largura < 44 then largura = 44 end

    larguraCache[formato] = largura
    return largura
end

---A largura de um GRUPO: a SOMA das colunas dele.
---
---Cada coluna volta a ter o proprio numero (a versao que juntava os dois numa string so foi
---desfeita a pedido), entao o grupo ocupa exatamente o espaco das colunas dele. O que ele ganha e
---outra coisa: **uma barra so**, que atravessa da coluna do total ate a da taxa.
local function GroupWidth(grupo)
    local largura = 0
    for i = 1, #grupo.keys do
        largura = largura + ColumnWidthFor(grupo.keys[i])
    end
    return largura
end

---O deslocamento de cada coluna a partir da DIREITA, e a largura total.
---
---Cada coluna tem a largura DELA agora, entao o deslocamento acumulado nao e mais
---`indice * largura`: e a soma das larguras das colunas a direita dela.
---ONDE CADA NUMERO DE UM GRUPO FICA DENTRO DA BARRA DELE.
---
---Ideia do usuario, 08/09: *"se cada um ficasse alinhado em cada canto, ou seja, dano a esquerda,
---dps a direita"*, e logo depois *"quando a coluna tiver apenas um valor, fica centralizado"*.
---
---⚑ O QUE MUDA E O PRINCIPIO QUE UNE OS DOIS NUMEROS. Antes eles eram alinhados a direita, cada
---um na caixa da coluna dele, e o que os juntava seria a PROXIMIDADE -- so que nao juntava: o vao
---entre eles era o RESIDUO da largura da taxa, media 35,8px e variava 11px por linha, enquanto o
---vao entre familias diferentes era 33. Dois numeros da mesma familia ficavam mais longe entre si
---que dois de familias diferentes -- razao 0,92, invertida.
---
---Agora eles vao para as PONTAS, e quem os une e a REGIAO COMUM: duas coisas nas duas
---extremidades de um recipiente pertencem ao recipiente. So funciona porque a barra ganhou pista
---tingida na 0.73.0 -- sem recipiente visivel, seriam dois numeros soltos no escuro.
---
---E a regra se estende sozinha, o que e o teste de que ela e uma regra e nao um caso:
---
---    1 membro   -> centro                 (interrupcoes, mortes, absorvido)
---    2 membros  -> esquerda, direita      (dano + DPS)
---    3 membros  -> esquerda, centro, direita  (dano + DPS + dano%, que vem em duas predefinicoes)
---
---Sem isso a janela ficaria com duas gramaticas -- uma para quem tem par e outra para quem nao
---tem --, que costuma sair pior que o problema original.
---
---@return string justificacao "LEFT", "CENTER" ou "RIGHT"
local function MemberAlign(indice, total)
    if total <= 1 then return "CENTER" end
    if indice == 1 then return "LEFT" end
    if indice == total then return "RIGHT" end
    return "CENTER"
end

---A FATIA de um membro dentro da barra do grupo: onde ela comeca (da direita) e quanto ocupa.
---
---Serve ao CABECALHO, e por isso existe. O rotulo tem que ficar em cima do numero que ele nomeia
---e o botao em cima da fatia que ele ordena -- senao clicar em "DPS" ordenaria por dano, que e
---exatamente o defeito que ja voltou uma vez por aqui.
---
---A fatia e proporcional a largura declarada da coluna (`COLUMN_WIDTH_BY_FIELD`), e nao um terco
---cego: assim o total, que pede mais espaco, tambem ganha o alvo de clique maior -- e ele e o
---primario da familia.
---
---@return number offset a partir da direita da faixa, number largura
local function MemberSlice(grupo, indice, larguraFaixa)
    local soma = 0
    for _, key in ipairs(grupo.keys) do soma = soma + ColumnWidthFor(key) end
    if soma <= 0 then return 0, larguraFaixa end

    local depois = 0
    for i = #grupo.keys, indice + 1, -1 do
        depois = depois + ColumnWidthFor(grupo.keys[i])
    end

    local escala = larguraFaixa / soma
    local offset = math.floor(depois * escala + 0.5)
    local largura = math.floor(ColumnWidthFor(grupo.keys[indice]) * escala + 0.5)
    return offset, largura
end

---O deslocamento de cada COLUNA a partir da direita, e a largura total.
---
---E por coluna outra vez: o cabecalho e o numero voltaram a ser um por coluna. O que anda por
---grupo e so a barra, e o vao dela sai de `GroupSpans`, que le estes mesmos offsets -- as duas
---contas nao podem divergir porque so existe uma.
local function ColumnOffsets()
    local columns = ns.db.columns
    local offsets, running = {}, 0
    for c = #columns, 1, -1 do
        offsets[c] = running
        running = running + ColumnWidthFor(columns[c])
    end
    return offsets, running
end

---O VAO DE CADA GRUPO: onde a barra unica comeca e quanto ela atravessa.
---
---Ideia do usuario: *"a barra que progride conforme quem ta melhor, ela vai desde a coluna de
---dano ate o DPS, e mesma coisa pra Cura e CPS, como se fosse apenas uma barra"*.
---
---⚑ ISTO SO FECHA PORQUE A ORDEM E TRAVADA. As colunas de uma familia sao contiguas em
---`ns.db.columns` (`Data.NormalizeColumns` garante), entao um grupo e uma FAIXA CONTINUA -- da
---borda direita da ultima coluna dele ate a borda esquerda da primeira. Com a lista intercalada
---que a versao anterior permitia ({dano, cura, DPS}), a barra do dano teria que atravessar por
---baixo de um numero de cura, e "uma barra so" deixaria de querer dizer alguma coisa.
---
---@return table vaos `{ grupo, offset (da direita), width }`, na ordem da tela
local function GroupSpans()
    local offsets = ColumnOffsets()
    local columns = ns.db.columns

    local posicaoDe = {}
    for i = 1, #columns do posicaoDe[columns[i]] = i end

    local vaos = {}
    for _, grupo in ipairs(Groups()) do
        local largura, ultima = 0, nil
        for _, key in ipairs(grupo.keys) do
            local at = posicaoDe[key]
            if at then
                largura = largura + ColumnWidthFor(key)
                if ultima == nil or at > ultima then ultima = at end
            end
        end
        if ultima then
            vaos[#vaos + 1] = { grupo = grupo, offset = offsets[ultima], width = largura }
        end
    end
    return vaos
end

---A largura minima da janela.
---
---Ela somava a largura das colunas (7 x 58 = 406), o que fazia a janela nascer com 508px de
---largura minima por causa de colunas que nao sao mais desenhadas. Agora e o que a LINHA precisa:
---icone, um nome legivel e o espaco do numero.
---A largura minima: abaixo dela a janela nao cabe o que ela desenha.
---
---⚠️ ELA VOLTOU A SOMAR AS COLUNAS, e a historia disso e a licao: quando o desenho em SECOES
---tirou as colunas da tela, eu tirei a soma delas daqui -- e escrevi no comentario que "as
---colunas nao sao mais desenhadas". Depois o desenho voltou a ter colunas e a soma nao voltou
---junto. **A premissa venceu e o comentario ficou**, afirmando como fato uma coisa que deixara de
---ser verdade.
---
---O estrago era grande e silencioso: com o conjunto padrao de Mitico+ (7 colunas x 58 = 406px)
---numa janela de 340, a area do nome dava **−111** e o clamp a punha em 40px; a primeira celula
---era ancorada em x = −70, ou seja INTEIRA fora da janela, e como nada recorta, ela desenhava por
---cima do icone, do nome e do cenario. Quatro das sete colunas caiam fora.
---
---E nao era so instalacao limpa: com a largura que o usuario ja tinha arrastado (491px, 6
---colunas), trocar para o conjunto de Mitico+ dava area de nome 44 -- dentro do clamp, nomes
---cortados, sem nenhum reset.
---
---A CALHA ENTRA NA CONTA, e esquece-la reproduz um defeito que este arquivo ja documentou: sem
---ela o minimo garante 96 para o nome, mas o layout desconta a calha DESSES 96 e sobram 86 -- o
---mesmo 86 do comentario de `DEFAULT_WIDTH`.
local function MinWidth()
    local _, columnsWidth = ColumnOffsets()
    return PADDING * 2 + RowHeight() + NAME_GUTTER + NAME_MIN_WIDTH + columnsWidth
end

-- A FOLGA da largura padrao sobre o minimo.
--
-- A padrao NAO PODE SER O MINIMO: o minimo garante `NAME_MIN_WIDTH` (96) para o nome, que e o
-- piso de legibilidade, nao um tamanho confortavel. Nascer no piso significa nascer no limite.
--
-- 48 sai de medicao: "Frenchmiku-Tichondrius" -- nome com reino, que e o caso longo real do grupo
-- do usuario -- mede ~139px em Arial Narrow 16, contra os 96 do piso. A folga cobre a diferenca.
--
-- E ela e SOMADA ao minimo, nao um numero absoluto: o minimo depende de quantas colunas o jogador
-- marcou, entao uma largura padrao fixa voltaria a nao caber assim que ele marcasse mais uma.
-- A FOLGA DA LARGURA PADRAO, e ela vai INTEIRA para o nome.
--
-- ⚑ E POR ISSO QUE A COLUNA DO NOME NAO E UMA CONSTANTE. Ela e o que sobra:
-- `nameArea = largura - colunas - icone - calha`, e a largura padrao e `MinWidth + DEFAULT_SLACK`
-- -- onde `MinWidth` ja embute `NAME_MIN_WIDTH`. Substituindo, a area do nome na largura padrao e
-- sempre `NAME_MIN_WIDTH + DEFAULT_SLACK`, **independente do tamanho das colunas**. Aumentar as
-- colunas sozinho nao encolheria o nome em um pixel: a janela cresceria junto.
--
-- Entao o pedido *"a coluna do nome ta meio grande"* se atende aqui, e so aqui. 24 deixa a area
-- em 120px: um nome de 12 caracteres (o limite do jogo) ocupa ~77px no corpo padrao, entao ainda
-- sobram 43 para o reino e para o respiro. 48 era mais ar do que o nome mais longo pede.
local DEFAULT_SLACK = 24

local function WindowWidth()
    local saved = ns.db.width or 0
    local minimum = MinWidth()
    if saved <= 0 then saved = minimum + DEFAULT_SLACK end
    return saved > minimum and saved or minimum
end

local function ColumnHeaderHeight()
    return COLHEAD_HEIGHT
end

---Altura da janela para N linhas.
---
---A janela **mantém o tamanho que o usuário deu**, como no Details: as barras preenchem de cima
---para baixo e o resto fica de fundo. Encolher para o conteúdo, como eu tinha feito, tornava a
---alça inútil — com um jogador só, arrastar não mudava nada e parecia travado.
local function WindowHeight(rowCount)
    return HEADER_HEIGHT + ColumnHeaderHeight() + rowCount * (RowHeight() + 1) + PADDING
end

-- A altura que o ultimo desenho aplicou. Ela vem ANTES de quem a le -- foi a setima armadilha de
-- declaracao abaixo do uso desta sessao, e a que deixou uma correcao inteira inerte.
local alturaDesenhada

---A altura que a janela deve ter AGORA. Quatro caminhos (soltar a alca, mudar colunas, mudar a
---fonte, arrastar) chamavam a formula direto e discordavam do desenho; um lugar so decide, e ele
---pergunta ao que foi desenhado.
local function CurrentHeight()
    return alturaDesenhada or WindowHeight(ns.db.rows)
end

Window.__WindowHeight = WindowHeight
Window.__CurrentHeight = function() return CurrentHeight() end

---Quanto uma linha ocupa de altura, com a separação.
local function RowStep()
    return RowHeight() + 1
end

---Quantas linhas INTEIRAS cabem nesta altura.
---
---E a INVERSA EXATA de `WindowHeight`, e tem que continuar sendo: a alca chama esta, o desenho
---chama aquela, e se as duas discordarem o arraste nao converge -- a janela cresce, o desenho
---cresce mais, e a alca pede mais ainda. Foi o que aconteceu enquanto uma delas media secoes e a
---outra media colunas.
---
---`floor`, e nao `floor(x + 0.5)`: arredondar para o mais proximo aceita uma altura em que a
---ultima linha **nao cabe**, e o jogador ve meia linha. O pedido foi literal -- "para nao cortar
---a linha de um jogador".
local function RowsThatFit(height)
    local usable = height - HEADER_HEIGHT - ColumnHeaderHeight() - PADDING
    local n = math.floor(usable / RowStep())
    if n < MIN_ROWS then n = MIN_ROWS end
    if n > MAX_ROWS then n = MAX_ROWS end
    return n
end

-- Ganchos para o harness: a geometria é a parte testável desta tela, e sem isso o teste teria
-- que recalcular as fórmulas por fora — o que confirmaria a cópia, não o código.
Window.__WindowHeight = WindowHeight
Window.__RowsThatFit = RowsThatFit
Window.__RowStep = RowStep

--------------------------------------------------------------------------------
-- Cabeçalho das colunas
--------------------------------------------------------------------------------
---Esconde o cabecalho de colunas do desenho antigo, se ele chegou a existir.
---
---A funcao que o CONSTROI continua no arquivo de proposito: ela e a unica descricao de como o
---layout de colunas era, e apagar isso agora tornaria impossivel comparar os dois se o desenho
---em secoes for reprovado. Ela so nao e mais chamada.
local function HideColumnHeader()
    if headerRow then headerRow:Hide() end
end

local function BuildColumnHeader()
    if not headerRow then
        headerRow = CreateFrame("Frame", nil, frame)
        headerRow.labels = {}
        -- Sem fundo: com a janela transparente, uma faixa escura aqui vira um segundo
        -- retângulo opaco logo abaixo do título e pesa a tela.
        headerRow.bg = headerRow:CreateTexture(nil, "BACKGROUND")
        headerRow.bg:SetAllPoints()
        headerRow.bg:SetColorTexture(0, 0, 0, 0)
    end

    headerRow:ClearAllPoints()
    -- ⚑ A MESMA MARGEM DA LINHA, e nao `PADDING + 2`.
    --
    -- Enquanto o numero era alinhado a direita e o rotulo tambem, 2px de diferenca passavam
    -- despercebidos. Com os dois encostando na ESQUERDA (0.76.0), a diferenca virou desencontro
    -- visivel -- e foi o que o usuario relatou com print em 09/09: *"o alinhamento do titulo do
    -- header com o comeco no inicio da barra, nao ta bem alinhado"*.
    --
    -- Duas referencias diferentes para coisas que precisam se alinhar e divergencia esperando
    -- acontecer. Agora o cabecalho e a linha partem do mesmo `PADDING`.
    headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -HEADER_HEIGHT)
    headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -HEADER_HEIGHT)
    headerRow:SetHeight(COLHEAD_HEIGHT)

    for _, button in pairs(headerRow.labels) do
        button:Hide()
    end

    local offsets = ColumnOffsets()

    -- ONDE CADA COLUNA MORA DENTRO DO GRUPO DELA. O cabecalho deixou de poder ser posicionado
    -- pelo acumulado das colunas: os numeros agora vao para as PONTAS da barra, e o rotulo tem
    -- que ir junto.
    ondeFicaCache = {}
    local ondeFica = ondeFicaCache
    for _, vao in ipairs(GroupSpans()) do
        local larguraFaixa = vao.width - GROUP_GAP
        for i, key in ipairs(vao.grupo.keys) do
            local off, larg = MemberSlice(vao.grupo, i, larguraFaixa)
            ondeFica[key] = {
                -- ⚑ SEM `GROUP_GAP / 2`. A folga entre familias sai INTEIRA da esquerda do
                -- grupo (`faixa:SetPoint("RIGHT", ..., -vao.offset)`), e este calculo tinha ficado
                -- no modelo antigo, que a dividia entre os dois lados. Sao 5px que deslocavam
                -- todo rotulo para a esquerda do numero que ele nomeia.
                offset = vao.offset + off,
                largura = larg,
                lado = MemberAlign(i, #vao.grupo.keys),
            }
        end
    end

    for c = 1, #ns.db.columns do
        local button = headerRow.labels[c]
        if not button then
            button = CreateFrame("Button", nil, headerRow)
            button:SetHeight(COLHEAD_HEIGHT)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.text:SetPoint("RIGHT", -4, 0)

            button:SetScript("OnClick", function(self)
                -- `columnIndex` e `sortKey` voltaram a falar da mesma coluna: ha um cabecalho
                -- por coluna outra vez. O `sortKey` fica porque e ele que separa "qual posicao na
                -- tela" de "qual metrica" -- ler `ns.db.columns[indice]` aqui dentro foi o que
                -- quebrou quando o indice passou a ser de grupo.
                local key = self.sortKey
                if IsShiftKeyDown() then
                    -- O GRUPO da coluna clicada, nao a posicao dela na lista: total e taxa andam
                    -- juntos, entao mover e sempre operacao de familia.
                    local g = GroupIndexFor(key)
                    if g then Window.MoveColumn(g, -1) end
                elseif IsControlKeyDown() then
                    local g = GroupIndexFor(key)
                    if g then Window.MoveColumn(g, 1) end
                elseif ns.db.sortBy == key then
                    ns.db.sortDesc = not ns.db.sortDesc
                    Window.Refresh(true)
                else
                    ns.db.sortBy = key
                    ns.db.sortDesc = true
                    Window.Refresh(true)
                end
            end)
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(ns.Data.GetAttributeLabel(self.sortKey), 1, 1, 1)
                GameTooltip:AddLine(L["Click to sort by this column."], 0.7, 0.7, 0.7)
                GameTooltip:AddLine(L["Click again to reverse the order."], 0.7, 0.7, 0.7)
                GameTooltip:AddLine(L["Shift-click moves it left, Ctrl-click moves it right."], 0.7, 0.7, 0.7)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["The leader of each column is highlighted, out of combat."], 0.5, 0.7, 1, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)
            headerRow.labels[c] = button
        end

        local key = ns.db.columns[c]
        -- Posicao na TELA (uma por coluna), que e o que o teste clica. Nao serve para mover:
        -- para isso existe `GroupIndexFor`.
        button.columnIndex = c
        button.sortKey = key
        local onde = ondeFica[key] or { offset = offsets[c],
            largura = ColumnWidthFor(key), lado = "RIGHT" }
        button:SetWidth(onde.largura)
        button:ClearAllPoints()
        button:SetPoint("RIGHT", headerRow, "RIGHT", -onde.offset, 0)

        -- O ROTULO ENCOSTA NA MESMA PONTA QUE O NUMERO. Sem isto o botao estaria no lugar certo
        -- e o texto dele nao -- "Dano" apareceria a direita da fatia do dano, colado no "DPS", e
        -- os dois rotulos voltariam a se juntar no meio enquanto os numeros ficam nas pontas.
        button.text:ClearAllPoints()
        button.text:SetJustifyH(onde.lado)
        if onde.lado == "LEFT" then
            button.text:SetPoint("LEFT", button, "LEFT", TEXT_INSET, 0)
        elseif onde.lado == "RIGHT" then
            button.text:SetPoint("RIGHT", button, "RIGHT", -TEXT_INSET, 0)
        else
            button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
        end
        ns.ApplyRoleFont(button.text, "header", 0)

        local label = ns.Data.GetShortLabel(key)
        if key == ns.db.sortBy then
            -- Só a cor marca a coluna ordenada: o dourado já diz tudo, e uma seta aqui
            -- repetia a informação ocupando espaço.
            button.text:SetText(label)
            button.text:SetTextColor(1, 0.82, 0)
        else
            button.text:SetText(label)
            button.text:SetTextColor(0.78, 0.74, 0.60)
        end
        button:Show()
    end
end

--------------------------------------------------------------------------------
-- Linhas: cada uma é uma barra
--------------------------------------------------------------------------------
local function BuildRow(index)
    local row = rows[index]
    if not row then
        row = CreateFrame("Button", nil, frame, "BackdropTemplate")

        -- Sem isto o clique atravessa a linha e cai no frame da janela: o mouse precisa ser
        -- habilitado explicitamente, mesmo em Button criado por código.
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp")

        row:SetScript("OnClick", function(self)
            if not self.source then return end

            -- Arquivo .lua novo no .toc só entra depois de sair para a tela de personagens;
            -- com /reload o módulo fica ausente e o clique morreria calado.
            if not ns.Breakdown then
                ns.Print(L["restart the client: the breakdown module was not loaded yet."])
                return
            end

            local ok, err = pcall(ns.Breakdown.Show, self.source, ns.db.sessionType, frame)
            if not ok then
                ns.Print("|cffff5555" .. L["error while drawing:"] .. "|r " .. tostring(err))
            end
        end)

        -- Realce ao passar o mouse, no lugar de tooltip: mostra que a linha é clicável sem
        -- cobrir a tela com uma caixa de texto.
        row:SetScript("OnEnter", function(self)
            if self.hover then self.hover:Show() end
        end)
        row:SetScript("OnLeave", function(self)
            if self.hover then self.hover:Hide() end
        end)
        row:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })

        -- RECORTA O QUE PASSAR DA BORDA. E REDE, NAO CONSERTO -- e a diferenca importa: com a
        -- conta certa nada passa, e com ela errada isto transforma "coluna desenhando sobre o
        -- cenario" em "coluna que some calada". A segunda e mais dificil de diagnosticar.
        --
        -- Entra mesmo assim porque o desenho depende de uma aritmetica que ja venceu uma vez, e
        -- porque o proprio medidor nativo recorta a entrada dele (`DamageMeterEntry.xml:3`).
        if row.SetClipsChildren then row:SetClipsChildren(true) end

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(0, 0, 0, 0)

        -- Como no medidor nativo: nada de preenchimento tomando a linha inteira. O valor
        -- aparece como uma **linha fina no rodapé**, na cor da classe.
        --
        -- Isso muda mais do que a estética: com o fundo neutro, a cor da classe fica livre
        -- para ser usada no texto da coluna liderada — o que antes era impossível, porque
        -- texto colorido sobre barra da mesma cor some.
        -- Camada de texto ACIMA das barras das colunas. Sem isso o texto some: StatusBar e
        -- frame filho, e frame filho desenha por cima dos FontStrings do pai — foi exatamente
        -- o bug da 0.11.0, em que a linha aparecia como uma barra vazia.
        row.text = CreateFrame("Frame", nil, row)
        row.text:SetAllPoints()
        row.text:SetFrameLevel(row:GetFrameLevel() + 2)

        row.hover = row.text:CreateTexture(nil, "ARTWORK")
        row.hover:SetAllPoints()
        row.hover:SetColorTexture(1, 1, 1, 0.10)
        row.hover:Hide()

        -- Ícone quadrado ocupando a linha inteira, como na referência: a skin usa
        -- `icon_mask = ""` e `icon_size_offset = 0`. A máscara circular que eu tinha posto
        -- encolhia o ícone e o deixava solto no meio da barra.
        row.icon = row.text:CreateTexture(nil, "OVERLAY")
        row.icon:SetPoint("LEFT", 0, 0)

        -- Segunda textura só para o ícone de classe, que precisa de texCoord.
        row.iconClass = row.text:CreateTexture(nil, "OVERLAY")
        row.iconClass:SetPoint("LEFT", 0, 0)
        row.iconClass:Hide()

        row.name = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        -- 2px acima do centro: abre respiro entre o texto e a faixa colorida do rodapé.
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, TEXT_LIFT)
        row.name:SetJustifyH("LEFT")
        -- Nome comprido corta em vez de quebrar linha ou invadir a coluna de números.
        row.name:SetWordWrap(false)

        -- O reino é uma SEGUNDA FontString, não parte da primeira: o corpo menor é o que o
        -- separa do nome, e uma FontString só tem um corpo. Ela é colada ao fim do texto do
        -- nome, não à caixa dele — por isso a largura do nome é ajustada ao conteúdo no
        -- desenho (ver `Window.Draw`), senão o reino apareceria lá na frente, no fim da caixa.
        row.realm = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.realm:SetPoint("LEFT", row.name, "RIGHT", 0, TEXT_LIFT)
        row.realm:SetJustifyH("LEFT")
        row.realm:SetWordWrap(false)

        -- O VALOR VAI DENTRO DA BARRA, encostado a direita. Pedido do usuario: *"o texto hoje
        -- das colunas pode ficar dentro das barras para maximizar o uso de espaco"* -- e e o que
        -- o medidor nativo faz, nome de um lado e numero do outro, os dois sobre a barra.
        --
        -- Uma faixa por GRUPO (a barra que atravessa), cada uma com os numeros das colunas dela.
        -- Total e taxa sao DOIS numeros com o mesmo corpo: eles dividem a barra, nao a hierarquia
        -- -- fazer a taxa menor e cinza a rebaixaria a nota de rodape, e ela e a segunda metade da
        -- mesma leitura.
        row.groups = {}
        rows[index] = row
    end

    local height = RowHeight()
    row:SetHeight(height)
    row:ClearAllPoints()
    local offsetY = -(HEADER_HEIGHT + ColumnHeaderHeight() + (index - 1) * (height + 1))
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, offsetY)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, offsetY)

    if row.SetBackdropBorderColor then
        -- Sem borda em volta da linha: quem separa uma linha da outra e o vao de 1px.
        row:SetBackdropBorderColor(0, 0, 0, 0)
    end

    local iconSize = height          -- preenche a linha inteira, como no Details
    row.icon:SetSize(iconSize, iconSize)
    row.iconClass:SetSize(iconSize, iconSize)

    -- BARRA CHEIA, e vale explicar por que ela voltou.
    --
    -- Ela ja tinha sido reprovada: *"a cor de fundo de cada classe fica ruim para ver os numeros
    -- da tabela, tem que tirar"* -- e estava certo, NAQUELE contexto: uma tabela com seis colunas
    -- de numero em cima de cor de classe saturada. Aqui a linha tem um nome e dois numeros, que e
    -- o desenho do medidor nativo, e o pedido foi justamente por o numero dentro da barra.
    --
    -- O que torna isso legivel esta medido na skill: preenchimento **escurecido** (~0.65 da cor
    -- da classe), fundo de linha tingido para a parte vazia nao virar buraco, e sombra no texto.
    -- Sem as tres, e a reprovacao de antes de novo.
    -- A FAIXA DE CLASSE PASSA A COBRIR SO A COLUNA DO NOME, a pedido do usuario.
    --
    -- E a resposta para uma pergunta que estava aberta: a cor de classe aparecia em TRES lugares
    -- na mesma linha -- icone, barra de cada coluna, e esta faixa cruzando a linha inteira. Tres
    -- vezes a mesma informacao, e a faixa era a que mais competia, porque passava por baixo dos
    -- numeros de todas as colunas.
    --
    -- Agora a identidade mora onde a pessoa e identificada: sob o icone e o nome. Da coluna do
    -- nome para a direita e so metrica.
    --
    -- Ela CONTINUA sendo uma barra de progresso da metrica ordenada, nao um retangulo chapado:
    -- e o que da forma vertical a lista, e agora essa forma vive no mesmo bloco que o nome.
    -- A AREA DO NOME E CALCULADA UMA VEZ, AQUI, e nao la embaixo: a faixa de classe precisa dela
    -- para saber onde parar, e ler `row.nameArea` antes de ele ser escrito devolvia o valor da
    -- chamada ANTERIOR (nil na primeira). Um numero calculado em dois momentos e a mesma
    -- divergencia que ja custou uma versao neste arquivo.
    local _, columnsWidth = ColumnOffsets()
    row.nameArea = WindowWidth() - PADDING * 2 - columnsWidth - iconSize - NAME_GUTTER
    if row.nameArea < 40 then row.nameArea = 40 end

    ns.ApplyRoleFont(row.name, "body", 0)
    -- O reino sempre um ponto abaixo do nome (decisao do usuario, 05/09/2026): com a linha
    -- em 12, o reino fica em 11. E delta, nao valor fixo — se o corpo da linha mudar de novo,
    -- a diferenca de um ponto acompanha sozinha.
    ns.ApplyRoleFont(row.realm, "body", REALM_FONT_DELTA)

    -- CADA COLUNA E UMA BARRA COM O NUMERO DENTRO.
    --
    -- E o desenho que o usuario escolheu, e o que ele resolve: **tres classificacoes na mesma
    -- linha**. Cada coluna e escalada pela regua da PROPRIA metrica, entao o lider daquela coluna
    -- e a unica barra cheia dela. Nenhuma comparacao em Lua -- o que importa, porque em combate
    -- os valores sao secret e comparar levanta erro. A geometria responde o que o Lua nao pode.
    --
    -- A barra e um frame filho da celula e o numero fica ACIMA dela, na camada de texto: frame
    -- filho desenha por cima de FontString do pai, e foi assim que a 0.11.0 saiu com barras
    -- vazias.
    -- UMA BARRA POR GRUPO, ATRAVESSANDO AS COLUNAS DELE.
    --
    -- Ideia do usuario: *"a barra que progride conforme quem ta melhor, ela vai desde a coluna de
    -- dano ate o DPS, e mesma coisa pra Cura e CPS, como se fosse apenas uma barra"*.
    --
    -- A estrutura que isso pede tem tres niveis, e nao dois: a FAIXA (o frame do grupo, que e o
    -- vao inteiro), a BARRA dentro dela (`SetAllPoints`, entao atravessa o vao) e um NUMERO por
    -- coluna por cima. Antes eram dois niveis porque celula e coluna eram a mesma coisa.
    --
    -- ⚑ O TEXTO E FILHO DA CAMADA DE CIMA, NUNCA DA FAIXA. StatusBar e frame filho e desenha
    -- acima de qualquer FontString do proprio pai -- e o bug 0.11.0 (linhas como barras vazias)
    -- registrado logo acima. `faixa.top` existe so para vencer a barra em nivel de frame.
    local vaos = GroupSpans()

    for _, faixa in pairs(row.groups) do
        faixa:Hide()
    end

    for gi = 1, #vaos do
        local vao = vaos[gi]
        local faixa = row.groups[gi]
        if not faixa then
            faixa = CreateFrame("Frame", nil, row.text)

            -- A PISTA: o resto do caminho, na PROPRIA cor da classe, bem apagada.
            --
            -- Pedido do usuario, em duas etapas: primeiro *"tira o fundo preto com algum
            -- percentual de opacidade"*, depois *"o fundo preto e feio"* e *"eu quero ... Pista
            -- tingida. Sem fundo preto"*. Ele nao rejeitou a ideia de pista -- rejeitou o PRETO.
            --
            -- Tingir com a cor da classe resolve as duas coisas: a parte vazia deixa de ser um
            -- buraco e vira "o resto do caminho", na mesma familia de cor da barra. E e o que a
            -- referencia deste projeto faz -- a skin do medidor tinge o fundo da linha com a cor
            -- a ~18%, em vez de empilhar retangulo preto.
            faixa.track = faixa:CreateTexture(nil, "BACKGROUND")
            faixa.track:SetAllPoints()

            faixa.bar = CreateFrame("StatusBar", nil, faixa)
            faixa.bar:SetAllPoints()
            faixa.bar:SetStatusBarTexture(ns.BarTexture())
            faixa.bar:SetMinMaxValues(0, 1)
            faixa.bar:SetValue(0)

            -- A FAISCA, na camada mais alta da barra: um rastro que se acende ate a ponta.
            --
            -- Sem atlas de proposito. O degrade de alfa numa textura branca em `ADD` da o brilho
            -- sem depender de arte que pode nao existir neste cliente -- e atlas que nao existe
            -- falha em SILENCIO, o que ja custou um cabecalho azul neste projeto.
            faixa.spark = faixa:CreateTexture(nil, "OVERLAY")
            faixa.spark:SetTexture("Interface\\Buttons\\WHITE8X8")
            faixa.spark:SetBlendMode("ADD")

            faixa.top = CreateFrame("Frame", nil, faixa)
            faixa.top:SetAllPoints()
            faixa.top:SetFrameLevel(faixa.bar:GetFrameLevel() + 2)

            -- ⚑ OS NUMEROS SAO INDEXADOS POR POSICAO DENTRO DO GRUPO, nao pela posicao da coluna
            -- na lista. A vaga (grupo 1, numero 2) pertence a esta faixa para sempre; um indice
            -- global mudaria de faixa quando o jogador desmarcasse uma coluna, e widget que troca
            -- de pai no meio do caminho e como se ganham defeitos que so aparecem ao mexer nas
            -- colunas -- os mais caros de reproduzir.
            faixa.texts = {}
            row.groups[gi] = faixa
        end

        faixa:SetSize(vao.width - GROUP_GAP, height - CELL_INSET * 2)
        faixa:ClearAllPoints()
        faixa:SetPoint("RIGHT", row.text, "RIGHT", -vao.offset, 0)
        faixa.bar:SetStatusBarTexture(ns.BarTexture())

        -- A FAISCA E REANCORADA A CADA RECONSTRUCAO, e nao so no nascimento.
        --
        -- Ela se prende a TEXTURA DE PREENCHIMENTO, e e isso que a faz acompanhar a ponta sozinha:
        -- quem redimensiona a textura e o motor, entao a faisca anda sem o Lua ler valor nenhum.
        -- E o unico destaque que sobrevive a valor secret, e a fonte do 12.1.0 prova em seis
        -- lugares (linha do tempo de encontro, gerenciador de recargas, barra de honra, barras de
        -- widget) -- num deles movido por valor secret.
        --
        -- Reancorar aqui e barato (uma vez por linha por reconstrucao) e nos poupa de depender de
        -- a textura sobreviver a `SetStatusBarTexture` logo acima.
        -- ⚑ AS DUAS PONTAS PRESAS NO PREENCHIMENTO, e nao so a direita com largura fixa.
        --
        -- Defeito relatado em 08/09, com print: *"o brilho quando a barra ta quase num tamanho
        -- minimo, ta ficando parecendo que vai andar pra tras"*. E era exatamente isso. Com
        -- largura fixa de 10px e uma barra de ~2px (2.9M contra 224M do lider), o rastro saia
        -- pela ESQUERDA da barra -- e como ele e claro na direita e some na esquerda, lia como
        -- uma seta apontando para tras.
        --
        -- Nao da para consertar medindo: `GetWidth()` na textura de preenchimento e SECRET,
        -- porque ela e ancorada por valor opaco (`SecretWhenAnchoringSecret`). "Esconde quando o
        -- rastro for maior que a barra" e uma comparacao que o Lua nao pode fazer.
        --
        -- Prendendo as DUAS pontas, a largura do brilho passa a SER a do preenchimento -- por
        -- construcao, em qualquer tamanho, sem o Lua saber qual e. Barra pequena, brilho pequeno;
        -- e nunca ha nada a esquerda do inicio.
        faixa.spark:ClearAllPoints()
        local preenchimento = faixa.bar:GetStatusBarTexture()
        faixa.spark:SetPoint("LEFT", preenchimento, "LEFT", 0, 0)
        faixa.spark:SetPoint("RIGHT", preenchimento, "RIGHT", 0, 0)
        faixa.spark:SetHeight(height - CELL_INSET * 2)

        -- TODO NUMERO SE ESCONDE ANTES, e so os deste desenho voltam.
        --
        -- `faixa.texts` sobrevive entre desenhos (e o cache das vagas). Sem esconder tudo, uma
        -- vaga que o desenho atual nao toca fica na tela com o texto do desenho anterior -- e o
        -- teste, que le o widget, contaria um numero que ninguem escreveu.
        for _, fs in ipairs(faixa.texts) do fs:Hide() end

        -- CADA NUMERO NUMA PONTA DA BARRA (ver `MemberAlign`). A caixa de cada um e a fatia
        -- proporcional a largura declarada da coluna dele -- assim `COLUMN_WIDTH_BY_FIELD`
        -- continua governando quanto espaco cada metrica pede, mesmo que a POSICAO agora venha
        -- da ponta e nao do acumulado.
        local quantos = #vao.grupo.keys
        local larguraFaixa = vao.width - GROUP_GAP

        for i = 1, quantos do
            local fs = faixa.texts[i]
            if not fs then
                fs = faixa.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetWordWrap(false)
                faixa.texts[i] = fs
            end

            -- CORPO UNICO NA LINHA INTEIRA, sem excecao. Ver `PAIR_DELTA`.
            ns.ApplyRoleFont(fs, "body", PAIR_DELTA)

            local lado = MemberAlign(i, quantos)
            fs:SetJustifyH(lado)
            fs:ClearAllPoints()

            -- A CAIXA NUNCA PASSA DA METADE (ou do terco) da faixa: com dois textos ancorados em
            -- pontas opostas, caixas generosas demais se sobrepoem no meio -- e sobreposicao de
            -- texto nao levanta erro, so fica ilegivel.
            local fatia = math.floor((larguraFaixa - 6) / quantos)
            fs:SetWidth(fatia)

            if lado == "LEFT" then
                fs:SetPoint("LEFT", faixa, "LEFT", TEXT_INSET, 0)
            elseif lado == "RIGHT" then
                fs:SetPoint("RIGHT", faixa, "RIGHT", -TEXT_INSET, 0)
            else
                fs:SetPoint("CENTER", faixa, "CENTER", 0, 0)
            end
            fs:Show()
        end

        -- OS PONTINHOS DO TRIO, entre numeros vizinhos. Ver `DOT_TEXT`.
        faixa.dots = faixa.dots or {}
        for _, d in ipairs(faixa.dots) do d:Hide() end

        if quantos >= 3 then
            for i = 1, quantos - 1 do
                local d = faixa.dots[i]
                if not d then
                    d = faixa.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    d:SetJustifyH("CENTER")
                    faixa.dots[i] = d
                end
                ns.ApplyRoleFont(d, "body", DOT_DELTA)
                d:SetText(DOT_TEXT)
                d:SetTextColor(unpack(ns.Skin.dim))

                -- NA FRONTEIRA ENTRE AS DUAS FATIAS, que e onde a separacao e necessaria.
                local off = select(1, MemberSlice(vao.grupo, i, larguraFaixa))
                d:ClearAllPoints()
                d:SetPoint("CENTER", faixa, "RIGHT", -off, 0)
                d:Show()
            end
        end

        for i = #vao.grupo.keys + 1, #faixa.texts do faixa.texts[i]:SetText("") end

        faixa:Show()
    end

    -- A AREA DO NOME e o que sobra depois das colunas -- e agora as colunas EXISTEM de novo,
    -- entao descontar a largura delas voltou a ser a conta certa. (Na 0.67.x ela descontava 406px
    -- de colunas que nao estavam mais sendo desenhadas, e o nome ficava com 57px.)
    row.name:SetWidth(row.nameArea)
    row.realm:SetWidth(0)
    return row
end

--------------------------------------------------------------------------------
-- Montagem
--------------------------------------------------------------------------------
function Window.Create()
    -- `ns.Skin` nasce com o padrao (os arquivos carregam antes de `ns.db` existir). Aqui a
    -- configuracao ja foi lida, entao os valores derivados do corpo precisam ser refeitos --
    -- senao o placar calcularia o delta dele contra o corpo errado durante a sessao inteira.
    ns.RefreshSkin()

    if frame then return frame end

    frame = CreateFrame("Frame", ADDON .. "Frame", UIParent, "BackdropTemplate")
    frame:SetSize(WindowWidth(), WindowHeight(1))
    frame:SetScale(ns.db.scale)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.03, 0.03, 0.04, WINDOW_ALPHA)
    frame:SetBackdropBorderColor(0, 0, 0, 0)      -- sem retângulo preto em volta


    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)

    -- A referência (medidor nativo / Details com a skin dele) tem faixa bege-oliva com
    -- texto escuro. Tenta o atlas do jogo; se ele não existir neste cliente, desenha o
    -- mesmo tom à mão para o resultado ser igual de qualquer jeito.
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()

    -- A arte é o atlas do medidor nativo, recortada como na skin de referência.
    ns.ApplyHeaderArt(header.bg)

    header.segment = CreateFrame("Button", nil, header)
    header.segment:SetSize(SEGMENT_MIN_WIDTH, HEADER_HEIGHT - 6)
    header.segment:SetPoint("LEFT", 7, 1)
    header.segment.text = header.segment:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.segment.text:SetPoint("LEFT")
    header.segment.text:SetTextColor(1, 0.82, 0)      -- dourado padrão da Blizzard
    header.segment:SetScript("OnClick", function()
        ns.db.sessionType = ns.db.sessionType == 0 and 1 or 0
        Window.Refresh(true)
    end)
    header.segment:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Click to switch between the current fight and the overall."], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    header.segment:SetScript("OnLeave", GameTooltip_Hide)

    header.clock = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.clock:SetPoint("LEFT", header.segment, "RIGHT", 6, 0)
    header.clock:SetTextColor(0.85, 0.72, 0.36)

    frame.header = header

    -- Um só tratamento para todos os ícones: mesmo tamanho, mesmo tom, mesma reação ao
    -- mouse. A família vem do próprio jogo — `questlog-icon-setting` é a engrenagem do
    -- rastreador de missões, da mesma UI de onde sai a arte da faixa de título.
    local ICON_TINT = { 0.78, 0.73, 0.58 }
    local ICON_HOVER = { 1, 0.95, 0.80 }

    local function HeaderButton(spec, tooltip, onClick)
        local b = CreateFrame("Button", nil, header)
        b:SetSize(14, 14)

        -- Uma textura vazia primeiro: `SetAtlas` precisa de textura existente para atuar.
        b:SetNormalTexture(spec.texture or "Interface\\Buttons\\WHITE8X8")
        local tex = b:GetNormalTexture()
        if tex and spec.atlas and tex.SetAtlas then
            tex:SetAtlas(spec.atlas, false)
        end
        if tex then
            -- Dessaturar primeiro: cada atlas traz cor própria (o X é vermelho, a engrenagem
            -- puxa dourado) e o `SetVertexColor` **multiplica** em cima dela — sem tirar a cor
            -- de origem, os botões nunca ficam do mesmo tom.
            if tex.SetDesaturated then tex:SetDesaturated(true) end
            tex:SetVertexColor(ICON_TINT[1], ICON_TINT[2], ICON_TINT[3])
        end

        b.SetTint = function(_, color)
            local t = b:GetNormalTexture()
            if t then t:SetVertexColor(color[1], color[2], color[3]) end
        end

        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            self:SetTint(ICON_HOVER)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            -- `tooltipText` sobrescreve o texto fixo quando o botao tem estado. E o segundo
            -- canal do cadeado: mesmo que o icone nao seja lido, a dica diz em palavras.
            GameTooltip:SetText(self.tooltipText or tooltip, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self:SetTint(self.activeTint or ICON_TINT)
            GameTooltip_Hide()
        end)

        b.baseTint = ICON_TINT
        return b
    end

    -- Sem botão de fechar: ninguém fecha o medidor no meio do jogo, e um X ao lado do
    -- ícone de limpar dados convida ao clique errado — um esconde a janela, o outro apaga
    -- o que foi registrado. Para esconder: `/rm` ou clique no botão do minimapa.

    frame.gearButton = HeaderButton(
        { atlas = "questlog-icon-setting", texture = "Interface\\Buttons\\UI-OptionsButton" },
        L["Configure columns"], function() ns.Picker.Toggle(frame) end)
    frame.gearButton:SetPoint("RIGHT", header, "RIGHT", -5, 0)

    frame.resetButton = HeaderButton(
        { atlas = "common-icon-undo", texture = "Interface\\Buttons\\UI-RefreshButton" },
        L["Clear the data"], function() ns.Data.RequestReset() end)
    frame.resetButton:SetPoint("RIGHT", frame.gearButton, "LEFT", -5, 0)

    frame.lockButton = HeaderButton(
        { texture = LOCK_ICON },
        L["Lock position"], function()
            ns.db.locked = not ns.db.locked
            Window.ApplyLock()
        end)
    frame.lockButton:SetPoint("RIGHT", frame.resetButton, "LEFT", -5, 0)

    if ns.db.pos then
        frame:SetPoint(ns.db.pos.point, UIParent, ns.db.pos.relPoint, ns.db.pos.x, ns.db.pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not ns.db.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    -- Sem atalho de configuração no clique: o botão direito atravessava a linha e caía aqui,
    -- abrindo as opções quando o usuário só queria o detalhamento. A engrenagem do cabeçalho e
    -- o botão do minimapa já dão acesso.

    -- Rolagem pela roda do mouse, sem barra: a barra ocuparia largura e apareceria mesmo
    -- quando não há o que rolar, que é o caso quase sempre.
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maximum = totalRows - ns.db.rows
        if maximum < 0 then maximum = 0 end

        local wanted = scrollOffset - delta
        if wanted < 0 then wanted = 0 end
        if wanted > maximum then wanted = maximum end

        if wanted ~= scrollOffset then
            scrollOffset = wanted
            Window.Refresh(true)
        end
    end)

    -- Alça de redimensionamento: largura livre, altura em número de linhas.
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        -- Máximo generoso: quem arrasta decide, o limite é só para não virar tela cheia.
        frame:SetResizeBounds(MinWidth(), WindowHeight(MIN_ROWS), 1400, WindowHeight(MAX_ROWS))
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(GRIP, GRIP)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function()
        if ns.db.locked then return end
        frame.sizing = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        frame.sizing = false
        ns.db.width = frame:GetWidth()
        Window.SetRows(RowsThatFit(frame:GetHeight()))
        frame:SetHeight(CurrentHeight())
    end)

    -- ENCAIXE AO VIVO. Antes o ajuste só acontecia ao SOLTAR o mouse, então a linha ficava
    -- cortada o arraste inteiro e só se acertava no fim — o que dá a impressão de que a janela
    -- não obedece. Aqui a altura vira número de linhas a cada quadro do arraste, e a janela
    -- acompanha em passos de uma linha.
    --
    -- `frame.sizing` evita reentrada: `SetHeight` dispara `OnSizeChanged` de novo.
    frame:SetScript("OnSizeChanged", function(self)
        if not self.sizing or self.snapping then return end
        local wanted = RowsThatFit(self:GetHeight())
        if wanted == ns.db.rows then return end

        self.snapping = true
        Window.SetRows(wanted)
        self.snapping = false
    end)

    frame.grip = grip

    -- Gancho para o harness: sem ele o teste do cadeado teria que redescobrir o frame por
    -- `_G`, e passaria a testar o simulador em vez do addon.
    Window.__frame = frame

    rows = {}
    Window.Rebuild()
    Window.ApplyLock()

    frame:SetScript("OnUpdate", function(_, elapsed)
        if not dirty then return end
        throttle = throttle + elapsed
        if throttle < 0.2 then return end
        throttle, dirty = 0, false
        Window.SafeDraw()
    end)

    return frame
end

---Refaz cabeçalho, linhas e medidas — depois de mudar colunas, fonte, tamanho ou largura.
function Window.Rebuild()
    if not frame then return end

    RefreshGroups()

    frame:SetBackdropColor(0.03, 0.03, 0.04, WINDOW_ALPHA)
    frame:SetBackdropBorderColor(0, 0, 0, 0)

    -- Sem contorno no cabeçalho: texto escuro sobre faixa clara fica sujo com outline.
    -- Título e relógio têm corpo próprio: no nativo eles são menores que o texto da linha.
    ns.ApplyRoleFont(frame.header.segment.text, "title", 0)
    ns.ApplyRoleFont(frame.header.clock, "title", CLOCK_DELTA)

    for i = 1, ns.db.rows do
        BuildRow(i)
    end
    for i = ns.db.rows + 1, #rows do
        rows[i]:Hide()
    end

    frame:SetWidth(WindowWidth())
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MinWidth(), WindowHeight(MIN_ROWS), 1400, WindowHeight(MAX_ROWS))
    end

    visibleRows = -1
    Window.Refresh(true)
end

function Window.Refresh(immediate)
    if not frame then return end
    if immediate then
        dirty, throttle = false, 0
        Window.SafeDraw()
    else
        dirty = true
    end
end

---Desenha protegido. Um erro dentro de OnUpdate deixaria a janela congelada e sem pista
---nenhuma — este envelope transforma isso numa mensagem, uma única vez por erro.
local lastError
function Window.SafeDraw()
    local ok, err = pcall(Window.Draw)
    if not ok and err ~= lastError then
        lastError = err
        ns.Print("|cffff5555" .. L["error while drawing:"] .. "|r " .. tostring(err))
    end
end

function Window.GetLastError()
    return lastError
end

-- Como realçar quem lidera cada coluna sem inventar cor nem enfeite:
--
--   1ª tentativa — cor dourada: virava "amarelo de ladino", competia com a cor de classe.
--   2ª tentativa — seta ao lado: ancorada no vão entre colunas, parecia sujeira solta.
--   3ª e atual  — **brilho**: o líder em branco puro, os demais levemente apagados.
--
-- Brilho é neutro (não carrega significado de classe), não ocupa espaço e o olho encontra
-- sozinho o número mais forte de cada coluna. É a mesma hierarquia que a UI do jogo usa para
-- separar informação principal de secundária.
-- Equilíbrio entre "todo mundo legível" e "dá para achar o líder":
--
--   O cinza 0.66 da tentativa anterior destacava o líder às custas dos outros, que ficaram
--   difíceis de ler. A diferença de brilho sozinha só funciona se o piso for baixo demais.
--
-- Agora o piso sobe para 0.86 (legível de verdade) e o líder ganha, além do branco puro, uma
-- **placa neutra** atrás — branco a 8%, sem cor, sem ícone, sem ocupar espaço extra.
-- O líder é pintado com a **cor da própria classe** — e isso não repete o erro do dourado:
-- lá a cor era arbitrária e parecia dizer "ladino"; aqui ela diz exatamente o que a cor de
-- classe sempre diz, "este jogador". O vocabulário é usado, não contrariado.
--
-- Só que cor de classe crua não serve para texto: vermelho de cavaleiro da morte e roxo de
-- bruxo são escuros demais sobre fundo escuro. A cor é **clareada em direção ao branco**, o
-- que preserva a identidade e garante a leitura.
-- Com a linha fina no rodapé, o fundo da linha ficou **neutro** — e aí a cor da classe pode
-- voltar para o texto da coluna liderada. Era o objetivo desde o começo e não funcionava
-- enquanto a barra preenchida ocupava o fundo com a mesma cor.
--
-- Continua valendo o cuidado de sempre: cor crua é escura demais para algumas classes
-- (cavaleiro da morte, bruxo). Um **piso de luminância** corrige só quem precisa, e só o
-- necessário — clarear todas por igual devolveria o tom lavado que já foi reprovado.
-- Piso de luminância do realce. Baixou de 0.55 para 0.45 junto com a troca de "misturar com
-- branco" por "multiplicar": o pedido foi *"precisa tá mais escuro"*, e multiplicando dá para
-- descer o piso sem perder legibilidade, porque a cor deixa de ficar lavada.
local LEADER_MIN_LUMA = 0.45
local LEADER_FALLBACK = { 1, 0.88, 0.62 }
-- Glifos do nativo medem ~227/255; os nossos números mediam ~210. 0.88 fecha a diferença.
local NORMAL = { 0.88, 0.88, 0.90 }

local function Luminance(r, g, b)
    return 0.299 * r + 0.587 * g + 0.114 * b
end

local function LeaderColor(classFilename)
    local class = SafeClass(classFilename)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not color then
        return LEADER_FALLBACK[1], LEADER_FALLBACK[2], LEADER_FALLBACK[3]
    end

    local r, g, b = color.r, color.g, color.b
    local luma = Luminance(r, g, b)
    if luma >= LEADER_MIN_LUMA then
        return r, g, b
    end

    -- MULTIPLICA, não mistura com branco.
    --
    -- Misturar com branco (`r + (1-r)*k`) clareia mas **dessatura**, e vermelho escuro
    -- dessaturado é literalmente rosa. Medido nas cores de classe do 12.x: o Cavaleiro da
    -- Morte é RGB(196,31,59) com saturação 0.84; a mistura o levava a RGB(216,105,124) com
    -- saturação 0.51 — foi isso que o usuário viu como "parece até rosa".
    --
    -- Multiplicar os três canais pelo mesmo fator mantém a razão entre eles, e razão constante
    -- é matiz e saturação constantes (em HSV, é subir o V sem tocar em H e S). O mesmo Cavaleiro
    -- vira RGB(255,39,76): vermelho vivo, saturação 0.84 intacta — e **mais escuro** que antes
    -- (luma 0.42 contra 0.55), que foi o outro pedido.
    --
    -- Só quatro classes chegam aqui (Cavaleiro da Morte, Caça-Demônios, Evocador e Xamã); as
    -- outras nove já passam do piso e saem sem tocar.
    local k = LEADER_MIN_LUMA / luma
    r, g, b = r * k, g * k, b * k
    if r > 1 then r = 1 end
    if g > 1 then g = 1 end
    if b > 1 then b = 1 end
    return r, g, b
end

-- Exposta para o harness: e a unica parte do realce que da para verificar fora do jogo, e foi
-- justamente aqui que a formula antiga produzia o rosa.
ns.LeaderColor = LeaderColor

---Estiliza a célula de quem lidera a coluna. O realce mora **só na cor**: o tom da própria
---classe, clareado o bastante para ler. Sem placa atrás — ela clareava a célula inteira e
---virava um bloco estranho no meio da linha.
---
---`OUTLINE` foi testado e reprovado: engrossa o traço da letra, o que é peso na tinta e não
---hierarquia — fica pesado mesmo numa célula só.
---
---**Corpo de fonte saiu da lista de sinais** (decisão do usuário, 05/09/2026): a linha inteira
---fica em `FONT_SIZE`, com ou sem realce. O +1pt que existia aqui dava presença ao líder, mas
---ao custo de os números de uma mesma coluna mudarem de tamanho de linha para linha — a régua
---vertical dançava. Se o realce ficar fraco demais in-game, o próximo sinal a tentar é a placa
---neutra atrás da célula, não o corpo.
---@param delta number|nil ajuste de corpo para telas com tipografia própria (o placar usa -1)
function ns.StyleCell(row, index, isBest, delta)
    local cell = row.cells[index]
    local highlight = isBest and ns.db.highlightBest ~= false

    -- O `delta` existe porque esta função é compartilhada: ela reaplica a fonte a cada
    -- desenho, e sem ele o placar (corpo 12) teria as células puxadas de volta para o corpo
    -- da janela (13) — nome em 12 e números em 13 na mesma linha.
    ns.ApplyRoleFont(cell, "body", delta or 0)
    cell:SetShadowColor(0, 0, 0, 1)

    if highlight then
        cell:SetTextColor(LeaderColor(row.classFilename))
    else
        cell:SetTextColor(NORMAL[1], NORMAL[2], NORMAL[3])
    end
end

---Escreve o valor de uma célula. Fora de combate formata; dentro, repassa o valor cru ao
---FontString (o motor renderiza secret values que o Lua não pode ler).
---@param halo table|nil cópias de contorno da célula, quando houver
function ns.SetCellText(fontString, value, columnKey)
    local function write(text)
        fontString:SetText(text)
    end

    if value == nil then
        write("|cff4a4a4a-|r")
        return
    end

    if ns.Data.IsPercentColumn(columnKey) then
        write(ns.Data.FormatPercent(value) or "|cff4a4a4a-|r")
        return
    end

    local text = ns.Data.FormatAmount(value)
    if not text then
        -- Valor secret: tenta a estratégia de formatação que funcionou neste cliente.
        local secretText = ns.Data.FormatSecretAmount(value)
        write(secretText ~= nil and secretText or value)
        return
    end

    -- Sem sufixo "/s": o rótulo da coluna (DPS, CPS) já diz que é por segundo, e repetir
    -- em cada linha só rouba espaço da coluna.
    write(text)
end

function Window.Draw()
    if not frame or not frame:IsShown() then return end

    local data, session, total = ns.Data.GetRows(ns.db.sessionType, ns.db.sortBy, ns.db.columns,
        ns.db.rows, not ns.db.sortDesc, scrollOffset)

    totalRows = total or 0

    -- Se gente saiu do grupo (ou a lista encolheu), a rolagem tem que voltar junto.
    local maximum = totalRows - ns.db.rows
    if maximum < 0 then maximum = 0 end
    if scrollOffset > maximum then
        scrollOffset = maximum
        data = ns.Data.GetRows(ns.db.sessionType, ns.db.sortBy, ns.db.columns,
            ns.db.rows, not ns.db.sortDesc, scrollOffset)
    end

    local scope = ns.db.sessionType == 0 and L["Current fight"] or L["Overall"]
    if totalRows > ns.db.rows then
        -- Sem barra de rolagem: a contagem no título é o que avisa que há mais gente.
        scope = format("%s  |cff909090%d-%d/%d|r", scope,
            scrollOffset + 1, math.min(scrollOffset + ns.db.rows, totalRows), totalRows)
    end
    frame.header.segment.text:SetText(scope)

    -- O botão tem largura fixa, mas o texto dele CRESCE quando o indicador de rolagem entra
    -- ("Combate atual" vira "Combate atual  1-5/8"). Como o relógio é ancorado à direita do
    -- BOTÃO e não do texto, o excedente passava por baixo do relógio e os dois se desenhavam
    -- um sobre o outro — o print de 05/09 mostra "1-5" e "02:58" empilhados, ilegíveis.
    -- Acompanhar o texto resolve os dois problemas de uma vez: o relógio sai da frente e a
    -- área clicável passa a cobrir tudo que está escrito.
    local textWidth = frame.header.segment.text:GetStringWidth()
    if textWidth and textWidth > 0 then
        frame.header.segment:SetWidth(math.max(SEGMENT_MIN_WIDTH, textWidth + 6))
    end

    local duration = ns.Data.GetDuration(ns.db.sessionType)
    if duration ~= nil and not issecretvalue(duration) and duration > 0 then
        frame.header.clock:SetText(SecondsToClock(duration))
    elseif InCombatLockdown() then
        frame.header.clock:SetText("|cff909090" .. L["in combat"] .. "|r")
    else
        frame.header.clock:SetText("")
    end

    -- UMA LINHA POR PESSOA, uma barra por coluna.
    --
    -- A lista e UMA so, ordenada pela coluna que o jogador escolheu -- como sempre foi. O que
    -- mudou e a celula: cada coluna virou uma barra escalada pela regua da PROPRIA metrica, com o
    -- numero dentro. E isso responde a pergunta que motivou o desenho -- *"quem esta melhor em
    -- Dano/DPS, Cura/CPS e Interrupts"* -- sem reordenar nada: o lider de cada coluna e a unica
    -- barra CHEIA daquela coluna.
    --
    -- ⚑ E funciona em combate, que e onde quase tudo aqui falha. Descobrir o maior exigiria
    -- comparar, e comparar valor secret levanta erro; escalar pela regua que o jogo entrega
    -- (`session.maxAmount`, uma por metrica) nao exige ler nada. A geometria responde o que o Lua
    -- nao pode calcular.
    -- OS VAOS DESTE DESENHO. `entry.values` e indexado pela lista que o jogador marcou
    -- (`ns.db.columns`), que e o que `Data.GetRows` devolve; `posicaoDe` traduz chave -> posicao,
    -- e e por ele que cada numero e cada barra acham o valor deles.
    --
    -- ⚑ REFAZ, NAO LE O CACHE. A versao anterior disto confiava num contrato -- "quem escreve
    -- `ns.db.columns` chama `Rebuild`" -- e ele quebrou no primeiro chamador que so desenhava: a
    -- tela ficou com os cinco grupos do desenho passado sobre uma lista de tres colunas. Contrato
    -- que depende de todo chamador lembrar nao e garantia; refazer aqui e.
    --
    -- O custo e uma passada pelas colunas por DESENHO (nao por linha), que e o que o cache existe
    -- para evitar -- ele continua servindo os quatro consumidores dentro do mesmo desenho.
    RefreshGroups()

    -- O CABECALHO E PINTADO NO DESENHO, nao so na reconstrucao.
    --
    -- ⚑ DEFEITO ANTERIOR A MESCLA, que so apareceu agora: ele era montado uma vez em `Rebuild`, e
    -- o clique que troca a ordenacao chama `Refresh` -- as linhas se reordenavam e o dourado
    -- ficava na coluna ANTERIOR ate algo reconstruir a janela. O dourado e o unico sinal de qual
    -- coluna ordena (nao ha seta, por decisao de design), entao ele apontando para a coluna errada
    -- e a janela mentindo sobre o que esta mostrando.
    --
    -- A licao e a mesma do cache logo acima: sinal que depende de todo mundo lembrar de repintar
    -- fica errado no primeiro que esquecer. Pintar onde a verdade e LIDA nao tem como divergir.
    BuildColumnHeader()

    local vaosDesenho = GroupSpans()

    local posicaoDe = {}
    for i = 1, #ns.db.columns do posicaoDe[ns.db.columns[i]] = i end

    local escalas = ns.Data.GetColumnScales(ns.db.sessionType, ns.db.columns)

    -- A BARRA MEDE O TOTAL DO GRUPO, e a razao e que **so o total tem regua**.
    --
    -- A regua de cada familia e `session.maxAmount` (`Data.GetColumnScales`), que e o maior
    -- `totalAmount` da sessao. A API nao devolve um maximo de `amountPerSecond` -- e descobrir um
    -- em Lua esbarra na restricao que molda este arquivo inteiro: em combate os valores sao
    -- secret e comparar levanta erro.
    --
    -- Foi tentado encher a barra com a metrica ORDENADA (para a barra cheia cair sempre na
    -- primeira linha quando o jogador ordena por DPS). Nao fecha: sem regua da taxa, o unico
    -- divisor disponivel seria o maximo do TOTAL, e uma taxa dividida por um total da um fiapo em
    -- toda linha. O teste reprovou na hora, com a barra de ninguem cheia.
    --
    -- ⚑ E ISTO CORRIGE UM DEFEITO QUE JA EXISTIA. Quando cada coluna tinha a propria barra, a
    -- do DPS era desenhada com o valor da TAXA sobre a regua do TOTAL -- exatamente o fiapo
    -- descrito acima, em toda linha, desde sempre. Com uma barra por familia o problema deixa de
    -- existir: ha uma barra e ela mede o que tem regua.
    --
    -- O que fica em aberto, e vale dizer em vez de supor: se `amountPerSecond` usar o tempo ATIVO
    -- de cada um (e nao a duracao da sessao), ordenar por DPS pode dar uma lista em que a barra
    -- mais longa nao e a primeira. Nao da para conferir isso daqui -- so uma corrida real
    -- responde -- e a alternativa exigiria uma regua que a API nao oferece.
    local encheCom = {}
    for g = 1, #vaosDesenho do
        encheCom[g] = posicaoDe[vaosDesenho[g].grupo.key]
    end

    local shown = 0
    for i = 1, ns.db.rows do
        local row = BuildRow(i)
        local entry = data and data[i]

        if not entry then
            row:Hide()
        else
            local source = entry.source
            shown = i

            row.bg:SetColorTexture(ns.RowBackdropColor())

            ns.ApplyRowIcon(row.icon, row.iconClass, source)
            ns.DrawName(row, source.name)
            row.classFilename = source.classFilename
            row.source = source

            for g = 1, #vaosDesenho do
                local grupo = vaosDesenho[g].grupo
                local faixa = row.groups[g]

                -- A BARRA, uma so, atravessando o vao do grupo inteiro.
                local at = encheCom[g]
                local escala = at and escalas[at]
                if escala == nil then escala = 1 end
                faixa.bar:SetMinMaxValues(0, escala)
                local valor = at and entry.values[at] or 0
                faixa.bar:SetValue(valor)
                ns.ApplyBarColor(faixa.bar, source.classFilename)

                -- A PISTA SO APARECE QUANDO HA VALOR. Pedido do usuario: *"se tiver zerado fica
                -- sem a pista tingida, somente quando tiver algum valor"*. Ele esta certo: pista
                -- vazia embaixo de um traco anuncia um caminho que ninguem comecou.
                --
                -- ⚑ E DA PARA SABER ISSO EM COMBATE, o que parece impossivel a primeira vista.
                -- Quando o jogador esta AUSENTE de uma metrica, quem escreve o zero e o proprio
                -- addon (`Data.lua`: *"Ausente numa lista que sabemos ler = o jogador nao pontuou
                -- ali. E zero."*) -- numero comum de Lua, legivel sempre. So o valor PRESENTE vem
                -- secret, e esse por definicao nao e o caso de "zerado".
                --
                -- A guarda e escrita ao contrario de proposito: esconde so quando da para PROVAR
                -- que nao ha valor. Com valor opaco a pista FICA -- errar mostrando e melhor que
                -- sumir com a referencia justamente em combate, que e quando ela serve.
                local vazio = valor == nil
                    or (not issecretvalue(valor) and valor == 0)

                ns.ApplyTrackColor(faixa.track, source.classFilename, not vazio)
                ns.ApplySparkColor(faixa.spark, source.classFilename, not vazio)

                -- E UM NUMERO POR COLUNA, cada um formatado pela regra da metrica dele.
                --
                -- Cada texto passa sozinho por `SetCellText`, que sabe de porcentagem, de valor
                -- nulo e da sondagem de valor secret. Foi a versao que juntava os dois numa
                -- string so que precisava de um caminho especial em combate -- separados, cada um
                -- sobrevive a luta por conta propria.
                for i = 1, #grupo.keys do
                    local key = grupo.keys[i]
                    local pos = posicaoDe[key]
                    local fs = faixa.texts[i]

                    ns.SetCellText(fs, pos and entry.values[pos], key)

                -- O NUMERO NAO GANHA COR DE CLASSE, e a razao e do usuario: *"a ideia e que o
                -- tamanho da barra ja vai dizer qual ta na frente, e a linha de baixo que e da
                -- classe"*.
                --
                -- Ele esta certo em dois niveis. O primeiro e redundancia: a barra CHEIA ja marca
                -- o lider daquela coluna, e a faixa do rodape ja marca a classe -- pintar o
                -- numero era um terceiro sinal dizendo o que dois ja diziam.
                --
                -- O segundo e a regra que a skill do workspace registra depois de tres tentativas
                -- falhas: **cor de classe e vocabulario reservado**. Um numero dourado ao lado de
                -- barras coloridas le como "ladino", nao como "este e o melhor". Aqui era pior,
                    -- porque a cor do numero e a cor da barra da MESMA linha competiam entre si.
                    --
                    -- O QUE VARIA E O BRILHO, e so ele: quem ORDENA fica em `Skin.text`, o
                    -- companheiro na mesma barra em `Skin.dim`. E o unico sinal de hierarquia que
                    -- sobrou depois de o corpo sair da lista, e ele nao mexe em metrica nenhuma --
                    -- entao a regua vertical nao danca.
                    --
                    -- Quando a metrica ordenada nao esta neste grupo, o primario e o total: a
                    -- leitura principal da familia, e a mesma escolha que a barra faz.
                    local ordena = 1
                    for k = 1, #grupo.keys do
                        if grupo.keys[k] == ns.db.sortBy then ordena = k end
                    end

                    if i == ordena then
                        fs:SetTextColor(unpack(ns.Skin.text))
                    else
                        fs:SetTextColor(unpack(ns.Skin.dim))
                    end
                end
            end

            row:Show()
        end
    end

    for i = ns.db.rows + 1, #rows do rows[i]:Hide() end

    -- A altura e a de UMA lista com cabecalho de coluna, que e o que esta desenhado.
    local altura = WindowHeight(ns.db.rows)
    if altura ~= alturaDesenhada then
        alturaDesenhada = altura
        frame:SetHeight(altura)
    end

    -- Altura fixa, definida pela alça: as linhas vazias mostram o fundo, como no Details.
    if ns.Breakdown and ns.Breakdown.Refresh then
        ns.Breakdown.Refresh()
    end

end

---O cabecalho de COLUNAS do desenho antigo ainda esta na tela? Tem que ser `false`: ele ocupa o
---lugar do cabecalho da primeira secao, e foi essa sobreposicao que o usuario viu.
function Window.DebugColumnHeaderShown()
    return headerRow ~= nil and headerRow:IsShown() and true or false
end

---A geometria horizontal do que foi desenhado: a largura da janela, a area do nome, e a borda
---ESQUERDA de cada celula medida a partir da borda esquerda da linha.
---
---A borda esquerda e o numero que importa: negativa significa celula desenhando FORA da janela,
---que foi o defeito de 08/09 -- quatro das sete colunas do conjunto padrao caiam para fora e
---pintavam por cima do nome e do cenario, porque `MinWidth` tinha deixado de contar as colunas.
function Window.DebugGeometry()
    local largura = WindowWidth()
    local offsets, columnsWidth = ColumnOffsets()
    local row = rows and rows[1]

    -- A BORDA ESQUERDA DE CADA BARRA, que e o que pode cair fora da janela.
    --
    -- Os numeros saem de `GroupSpans`, a MESMA funcao que ancora a faixa no desenho -- a versao
    -- anterior repetia a aritmetica aqui, e o comentario de `MinWidth` conta o que custou deixar
    -- duas contas do mesmo numero divergirem.
    local bordas = {}
    for c, vao in ipairs(GroupSpans()) do
        local util = largura - PADDING * 2
        bordas[c] = util - vao.offset - CELL_GAP / 2 - (vao.width - CELL_GAP)
    end

    return {
        width = largura,
        minWidth = MinWidth(),
        columnsWidth = columnsWidth,
        nameArea = row and row.nameArea or nil,
        nameFloor = NAME_MIN_WIDTH,
        cellLeft = bordas,
    }
end

---A largura que a janela reserva para um conjunto de colunas, agrupado.
---
---Serve ao teste de que o texto CABE: sem isto ele teria que reimplementar `GroupWidth`, e um
---teste que refaz a conta do codigo so confere que sabe somar.
function Window.DebugGroupWidths(columns)
    local out = {}
    for _, grupo in ipairs(ns.Data.GroupColumns(columns)) do
        out[#out + 1] = { keys = grupo.keys, width = GroupWidth(grupo) }
    end
    return out
end

---O que o CABECALHO escreve, na ordem da tela: rotulo, largura e se esta dourado.
---
---Existe por causa da mescla. "Dano - DPS" e um rotulo montado em tempo de desenho a partir de
---duas colunas, e a unica forma de conferir que ele saiu junto -- e que a largura acompanhou -- e
---perguntar ao widget. Ler `GroupLabel` no teste so provaria que a funcao concatena.
function Window.DebugHeaders()
    local out = {}
    if not (headerRow and headerRow.labels) then return out end

    for c = 1, #ns.db.columns do
        local button = headerRow.labels[c]
        if button and button:IsShown() then
            local r, g, b = button.text:GetTextColor()
            -- ONDE A TINTA DO ROTULO COMECA, medida da borda direita da janela. E o unico jeito
            -- de comparar cabecalho com numero: os dois sao ancorados em frames diferentes, com
            -- margens que ja divergiram uma vez em silencio.
            local onde = ondeFicaCache[ns.db.columns[c]]
            out[c] = {
                inkX = onde
                    and (MargemDireita(headerRow) + onde.offset + onde.largura - TEXT_INSET)
                    or nil,
                text = button.text:GetText(),
                width = button:GetWidth(),
                -- O rotulo encosta na mesma ponta que o numero que ele nomeia.
                align = button.text:GetJustifyH(),
                -- O dourado (1, 0.82, 0) e o unico sinal da coluna ordenada.
                sorted = (r == 1 and g == 0.82 and b == 0),
            }
        end
    end
    return out
end

---Dispara o clique no cabecalho de uma coluna, como o jogador faria.
---
---Existe porque "a ordenacao ainda funciona?" nao se responde lendo o codigo: o clique escreve
---`sortBy`, o desenho le, e entre os dois ha um `Refresh` e uma consulta a API. So um teste que
---clica e olha a lista resultante responde.
function Window.DebugClickColumn(index)
    local button = headerRow and headerRow.labels and headerRow.labels[index]
    if not button then return false end
    local handler = button:GetScript("OnClick")
    if not handler then return false end
    handler(button)
    return true
end

---Os nomes desenhados, na ordem em que estao na tela.
function Window.DebugRowNames()
    local out = {}
    for i = 1, #rows do
        if rows[i]:IsShown() then out[#out + 1] = rows[i].name:GetText() end
    end
    return out
end

---As CELULAS de uma linha, com a regua e o valor que cada barra recebeu.
---
---Sao os dois numeros que decidem o desenho: a regua diz contra o que aquela coluna e medida, e o
---valor diz o quanto da barra se enche. `valor == regua` e a definicao de "esta pessoa lidera
---esta coluna" -- e e por isso que o teste consegue afirmar quem lidera sem comparar nada,
---exatamente como a janela faz.
function Window.DebugCells(index)
    local row = rows and rows[index]
    if not row or not row:IsShown() then return {} end

    -- UMA ENTRADA POR COLUNA, com a barra que ela DIVIDE.
    --
    -- Coluna e barra deixaram de ser a mesma coisa: duas colunas de uma familia partilham uma
    -- barra so. A porta devolve o texto proprio de cada coluna e, junto, o valor/regua/largura da
    -- barra do grupo dela -- e `group` diz quais colunas estao na mesma. Sem esse campo, "as duas
    -- dividem a barra" seria indistinguivel de "as duas tem barras iguais por coincidencia".
    local out, c = {}, 0
    for gi, vao in ipairs(GroupSpans()) do
        local faixa = row.groups[gi]
        if faixa and faixa:IsShown() then
            local _, escala = faixa.bar:GetMinMaxValues()
            for i = 1, #vao.grupo.keys do
                local fs = faixa.texts[i]
                if fs and fs:IsShown() then
                    c = c + 1
                    local r, g, b = fs:GetTextColor()
                    local _, _, _, ancora = fs:GetPoint(1)
                    out[c] = {
                        key = vao.grupo.keys[i],
                        group = gi,
                        text = fs:GetText(),
                        color = { r, g, b },
                        width = fs:GetWidth(),
                        -- A PONTA em que o numero encosta, que e o que a proposta dos cantos
                        -- decide. Medir so a largura nao distinguiria "os dois nas pontas" de
                        -- "os dois na mesma ponta com caixas menores".
                        align = fs:GetJustifyH(),
                        -- Onde a tinta comeca, medida da borda direita da janela: o mesmo
                        -- referencial que `DebugHeaders` usa, para os dois serem comparaveis.
                        -- Sai do caminho do DESENHO; o do cabecalho sai do caminho do cabecalho.
                        -- Duas contas independentes -- que e o que faz a comparacao valer.
                        inkX = (i == 1)
                            and (MargemDireita(row) + vao.offset + vao.width - GROUP_GAP
                                - TEXT_INSET)
                            or nil,
                        -- O CORPO de cada numero: e o que separa o que ORDENA do companheiro.
                        -- Sem ele, "o degrau existe" e indistinguivel de "os dois iguais".
                        size = select(2, fs:GetFont()),
                        anchorX = ancora,
                        -- Da barra do grupo, iguais para as colunas irmas:
                        scale = escala,
                        value = faixa.bar:GetValue(),
                        barWidth = faixa:GetWidth(),
                    }
                end
            end
        end
    end
    return out
end

---A largura reservada a UMA coluna.
---
---Sem ela o teste da barra que atravessa teria que reimplementar `ColumnWidthFor` para dizer
---"a barra mede as duas somadas" -- e um teste que refaz a conta do codigo so confere que sabe
---somar.
function Window.DebugColumnWidth(key)
    return ColumnWidthFor(key)
end

---OS VAOS desenhados: onde cada barra comeca e quanto ela atravessa.
---
---E a porta da ideia do usuario -- *"como se fosse apenas uma barra"*. Sem ela, so daria para
---afirmar que existem duas colunas; que a barra vai de uma ate a outra e coisa que so o vao diz.
function Window.DebugSpans()
    local out = {}
    for gi, vao in ipairs(GroupSpans()) do
        local faixa = rows and rows[1] and rows[1].groups and rows[1].groups[gi]
        -- `anchorX` e lido do WIDGET, nao recalculado: e a diferenca entre afirmar que a
        -- barra esta no lugar e afirmar que a conta que a poe la sabe somar.
        -- Em duas linhas de proposito: `x and x:GetPoint(1)` truncaria os multiplos retornos
        -- para o PRIMEIRO -- `and` devolve um valor so. A ancora saia sempre nil.
        local ancora
        if faixa then local _, _, _, ax = faixa:GetPoint(1) ; ancora = ax end
        out[gi] = {
            keys = vao.grupo.keys,
            offset = vao.offset,
            width = vao.width,
            barWidth = faixa and faixa:GetWidth() or nil,
            anchorX = ancora,
            textos = faixa and faixa.texts and #faixa.texts or 0,
        }
    end
    return out
end

---A primeira linha desenhada. Sem isto, "trocar de variante nao estoura" seria tudo o que daria
---para afirmar -- e uma variante que nao muda nada tambem nao estoura.
---A linha `index` desenhada. `DebugFirstRow()` e o caso 1, que e o mais pedido.
---
---Passou a aceitar indice porque a pista condicional so se testa numa linha que NAO tem valor
---naquela metrica -- e essa nunca e a primeira, que por construcao lidera a coluna ordenada.
function Window.DebugRow(index)
    local row = rows and rows[index or 1]
    if not row or not row:IsShown() then return nil end
    local cor = row.bg.GetColorTexture and row.bg:GetColorTexture()
    return {
        nameArea = row.nameArea or 0,
        bgAlpha = cor and cor[4] or nil,
        rowWidth = row:GetWidth(),
        -- A COR DE CLASSE CONTINUA NA LINHA, e agora num lugar so: as barras das metricas. Sem
        -- esta porta, "removi a faixa" e "removi a cor da classe da linha inteira" seriam
        -- indistinguiveis para o teste.
        -- ⚑ LE `__gradient`, e nao `GetStatusBarColor`. O simulador nao implementa o getter --
        -- ele cai no `__index` generico e devolve uma TABELA, que nunca e nil e nunca e igual a
        -- outra: qualquer comparacao daria "tem cor" e o teste passaria a toa. `__gradient` e
        -- escrito por `ns.ApplyBarColor` no caminho de verdade.
        barColored = (function()
            local faixa = row.groups and row.groups[1]
            return faixa ~= nil and faixa.bar ~= nil and faixa.bar.__gradient == true
        end)(),
        -- A LARGURA DE CADA COLUNA, na ordem da tela: e a caixa do NUMERO, que e o que decide
        -- se ele cabe ou vira reticencias.
        cellWidths = (function()
            local out, c = {}, 0
            for gi, vao in ipairs(GroupSpans()) do
                local faixa = row.groups[gi]
                for i = 1, #vao.grupo.keys do
                    c = c + 1
                    out[c] = faixa and faixa.texts[i] and faixa.texts[i]:GetWidth() or 0
                end
            end
            return out
        end)(),
        -- ⚑ MEDE A TINTA, NAO O NOME DO CAMPO. Ate 08/09 esta porta contava `faixa.track`, um
        -- campo que nunca era criado -- o check passava com qualquer trilho de outro nome, e uma
        -- revisao adversarial o encontrou vazio. Agora que a pista EXISTE (tingida com a cor da
        -- classe, a pedido), o que nao pode voltar e o PRETO.
        cellTracksBlack = (function()
            local n = 0
            for _, faixa in pairs(row.groups) do
                local c = faixa.track and faixa.track.GetColorTexture
                    and faixa.track:GetColorTexture()
                if c and (c[4] or 0) > 0 and c[1] == 0 and c[2] == 0 and c[3] == 0 then
                    n = n + 1
                end
            end
            return n
        end)(),
        -- A pista de cada grupo, na ordem da tela: `nil` quando invisivel.
        cellTracks = (function()
            local out = {}
            for gi, vao in ipairs(GroupSpans()) do
                local faixa = row.groups[gi]
                local c = faixa and faixa.track and faixa.track:GetColorTexture()
                out[gi] = (c and (c[4] or 0) > 0) and { c[1], c[2], c[3], c[4] } or nil
                out[gi] = out[gi] or false
                if vao then end
            end
            return out
        end)(),
        -- A FAISCA ESTA PRESA NO PREENCHIMENTO? E a afirmacao central da proposta: ancorada na
        -- moldura, ela ficaria parada na borda direita e nao diria nada sobre progresso.
        cellSparkOnFill = (function()
            local out = {}
            for gi in ipairs(GroupSpans()) do
                local faixa = row.groups[gi]
                if faixa and faixa.spark then
                    -- ⚑ AS DUAS ANCORAS, e nao so a primeira. E a segunda que impede o brilho de
                    -- ser maior que a barra: com largura fixa e uma barra de 2px, o rastro saia
                    -- pela esquerda e lia como uma seta para tras (print do usuario, 08/09).
                    -- Conferir so a ancora da direita deixaria esse defeito voltar em silencio.
                    local fill = faixa.bar:GetStatusBarTexture()
                    local presas, lados = 0, {}
                    for i = 1, faixa.spark:GetNumPoints() do
                        local ponto, rel = faixa.spark:GetPoint(i)
                        if rel == fill then
                            presas = presas + 1
                            lados[ponto] = true
                        end
                    end
                    out[gi] = presas == 2 and lados.LEFT == true and lados.RIGHT == true
                else
                    out[gi] = false
                end
            end
            return out
        end)(),
        -- OS PONTINHOS do trio, por grupo: quantos estao na tela.
        cellDots = (function()
            local out = {}
            for gi in ipairs(GroupSpans()) do
                local faixa, n = row.groups[gi], 0
                for _, d in ipairs(faixa and faixa.dots or {}) do
                    if d:IsShown() then n = n + 1 end
                end
                out[gi] = n
            end
            return out
        end)(),
        -- E a faisca: visivel ou nao, por grupo.
        cellSparks = (function()
            local out = {}
            for gi in ipairs(GroupSpans()) do
                local faixa = row.groups[gi]
                out[gi] = faixa ~= nil and faixa.spark ~= nil and faixa.spark:IsShown() and true
                    or false
            end
            return out
        end)(),
    }
end

function Window.DebugFirstRow()
    return Window.DebugRow(1)
end

--------------------------------------------------------------------------------
-- Visibilidade
--------------------------------------------------------------------------------
function Window.Show(remember)
    if not frame then Window.Create() end
    frame:Show()
    if remember ~= false then ns.db.shown = true end
    Window.Refresh(true)
end

function Window.Hide(remember)
    if not frame then return end
    frame:Hide()
    if remember ~= false then ns.db.shown = false end
end

function Window.Toggle()
    if not frame then Window.Create() end
    if frame:IsShown() then
        Window.Hide()
    else
        Window.Show()
    end
end

function Window.ApplyVisibility()
    if not frame then return end

    if ns.db.combatOnly and not InCombatLockdown() then
        frame:Hide()
        return
    end

    if ns.db.shown then
        frame:Show()
        Window.Refresh(true)
    else
        frame:Hide()
    end
end

---A visão segue o combate: em combate, a luta atual (0); fora dele, o geral (1).
---
---Devolve `true` quando a visão MUDOU, e quem chama decide se redesenha. Devolver isso em vez de
---redesenhar aqui dentro evita o desenho dobrado no caminho mais quente do addon: o
---`PLAYER_REGEN_DISABLED` já chama `Refresh` logo depois desta função.
---
---⚑ O ESTADO DE COMBATE VEM POR PARÂMETRO nos dois eventos, e não de `InCombatLockdown()`. Não é
---desconfiança da API — é que o valor certo já está na mão de quem chama, e passá-lo torna a
---regra testável fora do jogo: o harness não tem como entrar em combate de verdade.
---Sem argumento (opção ligada na tela, login), aí sim pergunta ao cliente.
function Window.ApplyAutoSession(inCombat)
    if not ns.db.autoSession then return false end

    if inCombat == nil then
        inCombat = InCombatLockdown() and true or false
    end

    local wanted = inCombat and 0 or 1
    if ns.db.sessionType == wanted then return false end

    ns.db.sessionType = wanted
    return true
end

function Window.OnCombatStart()
    Window.ApplyAutoSession(true)

    if ns.db.combatOnly and ns.db.shown then
        Window.Show(false)
    end
end

function Window.OnCombatEnd()
    -- ⚑ O REDESENHO É DAQUI, e não do `Core`. Ele chama `Refresh` ANTES desta função (os valores
    -- deixam de ser secret ao sair do combate), então a troca de visão feita agora só apareceria
    -- no refresh seguinte — que pode demorar uma luta inteira, com a janela parada em "Combate
    -- atual" depois de o combate ter acabado.
    if Window.ApplyAutoSession(false) then
        Window.Refresh(true)
    end

    if ns.db.combatOnly then
        C_Timer.After(ns.db.hideDelay or 5, function()
            if ns.db.combatOnly and not InCombatLockdown() then
                Window.Hide(false)
            end
        end)
    end
end

---Diagnóstico: as linhas estão recebendo clique? Responde sem depender de tentativa e erro.
function Window.RowsAreClickable()
    local row = rows and rows[1]
    if not row then return false end
    return row:IsMouseEnabled() and row:GetScript("OnClick") ~= nil and row.source ~= nil
end

---Aplica o estado travado: ícone do cadeado e visibilidade da alça.
---
---A alça só faz sentido destravada — deixá-la visível travada convida a arrastar algo que não
---vai se mexer. Some junto.


function Window.ApplyLock()
    if not frame then return end

    local locked = ns.db.locked and true or false

    if frame.grip then
        frame.grip:SetShown(not locked)
    end

    local button = frame.lockButton
    if not button then return end

    -- Textura primeiro: `SetAtlas` precisa de uma textura já existente para atuar, e ela também
    -- é a reserva quando o atlas não existe neste cliente.
    button:SetNormalTexture(LOCK_ICON)
    local texture = button:GetNormalTexture()
    if not texture then return end

    -- Destravado ganha a cruz de setas; travado fica com o cadeado. Ver o comentário de
    -- `UNLOCK_ATLAS` no topo: a diferença tem que ser de FORMA, porque cor num glifo de 14px
    -- não se lê. Se o atlas faltar, sobra o comportamento antigo — nunca um botão vazio.
    if not locked and texture.SetAtlas and ns.AtlasExists(UNLOCK_ATLAS) then
        texture:SetAtlas(UNLOCK_ATLAS, false)
    end

    texture:SetDesaturated(true)   -- sem a cor original do ícone, para entrar na família

    -- A cor REFORÇA a forma, não substitui: travado chama atenção, destravado fica no tom dos
    -- outros ícones.
    local tint = locked and { 1, 0.82, 0.30 } or button.baseTint
    button.activeTint = tint
    button:SetTint(tint)

    -- Terceiro canal, e o unico que nao depende de o jogador interpretar um desenho de 14px.
    button.tooltipText = locked and L["Locked — click to unlock and resize"]
        or L["Unlocked — drag to move, corner to resize"]
end

---Define quantas linhas a janela mostra, ajustando a altura.
---
---Ponto único usado pela alça de redimensionar e pelo painel de configuração — sem isto os dois
---caminhos calculariam a altura de formas diferentes.
---Troca o corpo do texto, dentro dos limites.
---
---A altura da linha e a hierarquia (titulo, relogio, cabecalho) acompanham sozinhas, porque as
---tres sao derivadas -- essa foi a razao de elas terem virado deltas na 0.56.1. `Rebuild` e
---necessario porque a altura da linha muda e as linhas ja construidas precisam ser refeitas.
---@return boolean mudou
---Escreve uma chave de um papel e redesenha.
---
---Um caminho so para as tres chaves (corpo, contorno, sombra) e para os tres papeis: elas mudam
---a mesma coisa -- como o texto e desenhado -- e precisam do mesmo trabalho depois. Ter uma
---funcao por combinacao seriam nove, e nove caminhos e onde as telas comecam a divergir.
local function SetRoleField(role, field, value)
    if not ROLE_DEFAULTS[role] then return false end

    ns.db.text = ns.db.text or {}
    local saved = ns.db.text[role]
    if type(saved) ~= "table" then
        saved = CopyTable(ROLE_DEFAULTS[role])
        ns.db.text[role] = saved
    end

    if saved[field] == value then return false end
    saved[field] = value

    ns.RefreshSkin()
    Window.Rebuild()
    if frame then
        frame:SetHeight(CurrentHeight())
        if frame.SetResizeBounds then
            frame:SetResizeBounds(MinWidth(), WindowHeight(MIN_ROWS), 1400, WindowHeight(MAX_ROWS))
        end
    end
    return true
end

function Window.SetRoleSize(role, size)
    if type(size) ~= "number" then return false end
    size = math.floor(size + 0.5)
    if size < ns.Skin.fontSizeMin then size = ns.Skin.fontSizeMin end
    if size > ns.Skin.fontSizeMax then size = ns.Skin.fontSizeMax end
    return SetRoleField(role, "size", size)
end

function Window.SetRoleOutline(role, value)
    for _, choice in ipairs(ns.OUTLINE_CHOICES) do
        if choice.value == value then
            return SetRoleField(role, "outline", value)
        end
    end
    return false
end

function Window.SetRoleShadow(role, on)
    return SetRoleField(role, "shadow", on and true or false)
end

function Window.GetRoleSize(role)
    return ns.RoleSize(role)
end

function Window.GetRoleOutline(role)
    return ns.RoleConfig(role).outline
end

function Window.GetRoleShadow(role)
    return ns.RoleConfig(role).shadow
end

function Window.GetFontSize()
    return ns.RoleSize("body")
end

---Aplica uma escolha de aparencia e redesenha.
---
---Um so caminho para as tres: elas mudam a mesma coisa (como o texto e desenhado) e precisam
---do mesmo trabalho depois -- refazer o Skin, reconstruir as linhas e recalcular a altura,
---porque trocar de fonte muda a largura do que cabe.
local function ApplyAppearance()
    ns.RefreshSkin()
    Window.Rebuild()
    if frame then
        frame:SetHeight(CurrentHeight())
        if frame.SetResizeBounds then
            frame:SetResizeBounds(MinWidth(), WindowHeight(MIN_ROWS), 1400, WindowHeight(MAX_ROWS))
        end
    end
end

function Window.SetFont(path)
    if type(path) ~= "string" or path == "" then return end
    if path == ns.db.font then return end
    ns.db.font = path
    ApplyAppearance()
end

function Window.SetRows(count)
    if type(count) ~= "number" then return end
    if count < MIN_ROWS then count = MIN_ROWS end
    if count > MAX_ROWS then count = MAX_ROWS end
    if count == ns.db.rows then return end

    ns.db.rows = count
    Window.Rebuild()
    if frame and not frame.sizing then
        -- Durante o arraste quem manda na altura é o mouse: cravar a altura aqui brigaria com
        -- o `StartSizing` e a janela pularia embaixo do cursor. O encaixe final é feito ao
        -- soltar, no `OnMouseUp` da alça.
        frame:SetHeight(CurrentHeight())
    end
end

function Window.GetRows()
    return ns.db.rows
end

function Window.ApplyScale()
    if frame then frame:SetScale(ns.db.scale) end
end

--------------------------------------------------------------------------------
-- Colunas
--------------------------------------------------------------------------------
---Liga ou desliga um ITEM -- que pode valer por duas colunas.
---
---Pedido do usuario: *"onde escolhe as colunas na configuracao o dano e dps e cura e cps tem que
---ser um so item"*. A atomicidade mora AQUI, e nao na tela, porque a tela nao e o unico caminho:
---`/rm col 2` chega no mesmo lugar. Regra dividida entre dois caminhos e regra que vale em um so.
function Window.ToggleColumn(key)
    local item = ns.Data.GetItemFor(key)
    local chaves = item and item.keys or { key }

    local presente = {}
    for _, id in ipairs(ns.db.columns) do presente[id] = true end

    local ligado = false
    for _, id in ipairs(chaves) do
        if presente[id] then ligado = true end
    end

    local novo = {}
    if ligado then
        for _, id in ipairs(ns.db.columns) do
            local sai = false
            for _, fora in ipairs(chaves) do
                if id == fora then sai = true end
            end
            if not sai then novo[#novo + 1] = id end
        end

        -- A JANELA NAO PODE FICAR SEM COLUNA. Com item de duas colunas, "sobra uma" deixou de
        -- ser a conta certa: desligar o ultimo item leva as DUAS de uma vez.
        if #novo == 0 then
            ns.Print(L["at least one column must stay."])
            return
        end
    else
        for _, id in ipairs(ns.db.columns) do novo[#novo + 1] = id end
        for _, id in ipairs(chaves) do novo[#novo + 1] = id end
    end

    ns.db.columns = ns.Data.NormalizeColumns(novo)

    -- A ordenacao pode ter ido embora junto com o item.
    local aindaTem = false
    for _, id in ipairs(ns.db.columns) do
        if id == ns.db.sortBy then aindaTem = true end
    end
    if not aindaTem then ns.db.sortBy = ns.db.columns[1] end

    ns.db.width = nil
    Window.Rebuild()
end

---Move um GRUPO de lugar (Shift/Ctrl-clique no cabecalho).
---
---O indice que chega e o do cabecalho, que e o do grupo -- e o total e a taxa andam JUNTOS: o
---jogador arrasta "Dano - DPS", nao "DPS" para longe de "Dano".
---
---A lista de colunas e reescrita a partir da ordem dos grupos. Isso tem um efeito colateral
---desejado: se `ns.db.columns` estava intercalada ({dano, cura, DPS, CPS} -- possivel marcando as
---caixas fora de ordem), ela volta agrupada. O que a tela mostra e o que fica guardado.
function Window.MoveColumn(index, direction)
    -- ⚑ REFAZ OS GRUPOS ANTES DE LER. O cache e do desenho anterior, e `ns.db.columns` pode ter
    -- mudado desde entao sem passar por um desenho -- SavedVariables entram assim. Lendo o cache,
    -- esta funcao reescrevia a lista ATUAL a partir de grupos de uma lista que nao existe mais, e
    -- o resultado era a lista antiga de volta na tela.
    local lista = RefreshGroups()
    local target = index + direction

    -- A ORIGEM TAMBEM E VALIDADA. So o destino era conferido, e um `index` acima do numero de
    -- grupos passava: a troca deixava um BURACO no meio da lista (o slot de origem virava nil),
    -- `#lista` mudava de valor e o achatamento logo abaixo indexava nil. Estouro de Lua, com a
    -- janela morrendo no meio do desenho.
    if index < 1 or index > #lista then return end
    if target < 1 or target > #lista then return end

    lista[index], lista[target] = lista[target], lista[index]

    local novo = {}
    for g = 1, #lista do
        for k = 1, #lista[g].keys do
            novo[#novo + 1] = lista[g].keys[k]
        end
    end
    -- NORMALIZA DE VOLTA. Trocar dois grupos nao pode desfazer a ordem DENTRO deles, e a
    -- normalizacao e barata o bastante para ser a ultima palavra em todo caminho de escrita.
    ns.db.columns = ns.Data.NormalizeColumns(novo)

    Window.Rebuild()
end

function Window.ApplyPreset(name)
    local preset = ns.Data.GetPresets()[name]
    if not preset then return false end
    ns.db.columns = ns.Data.NormalizeColumns(CopyTable(preset.columns))
    ns.db.sortBy = ns.db.columns[1]
    ns.db.width = nil
    Window.Rebuild()
    return true
end
