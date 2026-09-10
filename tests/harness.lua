-- RocketMeter | tests/harness.lua
-- Simulador mínimo da API do WoW para rodar o addon fora do jogo.
--
--   luajit tests/harness.lua        (da pasta do addon)
--
-- Não substitui o teste in-game: não desenha nada e os dados são falsos. Serve para pegar o
-- que quebra no carregamento — nil indexado, função que não existe, evento que estoura.
-- Este arquivo NÃO entra no .toc.

local ADDON = "RocketMeter"

--------------------------------------------------------------------------------
-- Objeto genérico: qualquer método vira no-op que devolve outro objeto genérico.
--------------------------------------------------------------------------------
local function widget(kind)
    local self = { __kind = kind, __scripts = {}, __events = {} }

    function self.SetScript(_, name, fn) self.__scripts[name] = fn end
    function self.GetScript(_, name) return self.__scripts[name] end
    function self.RegisterEvent(_, event) self.__events[event] = true end
    function self.RegisterUnitEvent(_, event) self.__events[event] = true end
    -- FontString sem template nao tem fonte, e o jogo responde "Font not set" no SetText.
    -- O simulador reproduz isso: sem template e sem SetFont previo, SetText estoura.
    function self.CreateFontString(_, _, template)
        local fs = widget("FontString")
        fs.__hasFont = template ~= nil
        -- O PAI DE VERDADE, e nao o generico do `__index`: o addon pergunta o pai para criar as
        -- copias do contorno desenhado nele. Com o generico, cada copia nasceria num frame
        -- diferente do original e o teste de espelhamento passaria sem provar nada.
        function fs.GetParent() return self end
        fs.__alpha = 1
        function fs.SetAlpha(_, a) fs.__alpha = a end
        function fs.GetAlpha() return fs.__alpha end
        -- Guarda e devolve, como no jogo: `GetFont` e o unico jeito de o addon saber se o
        -- `SetFont` pegou, e e nele que a guarda de fonte invalida se apoia.
        function fs.SetFont(_, path, size, flags)
            fs.__hasFont = true
            fs.__font, fs.__size, fs.__flags = path, size, flags
            return true
        end
        function fs.GetFont() return fs.__font, fs.__size, fs.__flags end
        -- GUARDA O QUE ESCREVEU. Antes ele so devolvia os argumentos, entao nada que dependesse
        -- do texto era conferivel -- e o contorno desenhado depende: as copias tem que receber a
        -- mesma string do original, sem os escapes de cor.
        function fs.SetText(_, text)
            if not fs.__hasFont then
                error("FontString:SetText(): Font not set", 2)
            end
            fs.__text = text
            return text
        end
        function fs.GetText() return fs.__text end
        return fs
    end
    function self.CreateTexture() return widget("Texture") end
    function self.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function self.GetName() return kind .. "Stub" end
    -- Show/Hide MUDAM o estado, e `IsShown` responde de acordo. Antes ele devolvia `true` para
    -- tudo, entao qualquer teste sobre "esta visivel?" passava sem olhar nada -- foi assim que
    -- as tres abas do configurador apareceram todas ao mesmo tempo e o teste nao viu.
    self.__shown = true
    function self.Show() self.__shown = true end
    function self.Hide() self.__shown = false end
    function self.SetShown(_, v) self.__shown = v and true or false end

    -- A REGUA E O VALOR DA BARRA, guardados. Sem isto o `__index` generico respondia
    -- `SetMinMaxValues` com um no-op, e a regua de cada secao -- que e o que impede a barra de
    -- cura de ser medida contra o maior dano -- ficava invisivel ao teste: sabotar `top = 1` nao
    -- reprovava nada.
    -- A COR DO TEXTO, guardada: o usuario mandou tirar a cor de classe do numero, e "tirei" so se
    -- prova perguntando ao widget que cor ele ficou.
    function self.SetTextColor(_, r, g, b, a) self.__textColor = { r, g, b, a } end
    function self.GetTextColor() 
        local c = self.__textColor
        if not c then return 1, 1, 1, 1 end
        return c[1], c[2], c[3], c[4]
    end

    -- A COR CHAPADA, guardada pelo mesmo motivo: o fundo tingido da linha e o que da chao ao
    -- numero encostado a direita, e sem registrar isso sabotar o tingimento nao reprovava nada.
    function self.SetColorTexture(_, r, g, b, a) self.__color = { r, g, b, a } end
    function self.GetColorTexture() return self.__color end

    function self.SetMinMaxValues(_, lo, hi) self.__min, self.__max = lo, hi end
    function self.GetMinMaxValues() return self.__min, self.__max end
    function self.SetValue(_, v) self.__value = v end
    function self.GetValue() return self.__value end
    function self.IsShown() return self.__shown end
    function self.IsVisible() return self.__shown end
    function self.IsMouseEnabled() return true end
    function self.IsForbidden() return false end
    -- ⚑ A MESMA TEXTURA EM TODA CHAMADA, como no jogo. Devolver uma NOVA a cada chamada
    -- destruiria a unica coisa que a faisca depende: a IDENTIDADE do objeto. Ela e ancorada a
    -- textura de preenchimento e acompanha a ponta porque o motor redimensiona aquele objeto --
    -- se cada consulta devolvesse outro, nenhum teste conseguiria afirmar que a ancora e a certa,
    -- e o defeito "ancorei na moldura em vez de no preenchimento" passaria batido.
    --
    -- E o mesmo cuidado que `GetNormalTexture` ja tinha aqui, pelo mesmo motivo.
    function self.GetStatusBarTexture()
        if not self.__barTexture then self.__barTexture = widget("Texture") end
        return self.__barTexture
    end
    function self.GetEffectiveScale() return 1 end
    function self.GetCenter() return 400, 300 end
    function self.GetID() return 1 end
    -- Getters numericos: sem isso o codigo que faz conta com GetWidth quebra so no simulador.
    --
    -- E `SetWidth`/`SetHeight` MUDAM o que os getters devolvem, como no jogo. Antes eram
    -- constantes, entao qualquer teste sobre "a janela mudou de tamanho?" respondia sempre que
    -- nao -- foi assim que a altura por aba passou despercebida.
    self.__width, self.__height = 400, 200
    function self.SetWidth(_, v) if type(v) == "number" then self.__width = v end end
    function self.SetHeight(_, v) if type(v) == "number" then self.__height = v end end
    function self.SetSize(_, w, h)
        if type(w) == "number" then self.__width = w end
        if type(h) == "number" then self.__height = h end
    end
    -- Quem foi ancorado com `SetAllPoints` mede o que o pai mede.
    function self.GetWidth()
        if self.__anchoredTo then return self.__anchoredTo:GetWidth() end
        return self.__width
    end
    function self.GetHeight()
        if self.__anchoredTo then return self.__anchoredTo:GetHeight() end
        return self.__height
    end

    -- ⚑ ANCORAS SAO GUARDADAS, como no jogo. Ate 08/09 o simulador ENGOLIA `SetPoint` (caia no
    -- `__index` generico, que devolve funcao vazia), e a consequencia era exata: geometria so se
    -- afirmava pela aritmetica REPETIDA dentro de `DebugGeometry`. Sabotar a ancora do widget nao
    -- reprovava nada, porque nenhum teste olhava a ancora -- olhava a conta paralela.
    --
    -- E a licao que este projeto ja pagou duas vezes: o stub concordar com o codigo nao e
    -- evidencia. Ele precisa representar a API antes de servir de juiz.
    -- ⚑ `SetAllPoints` NAO EXISTIA NO SIMULADOR, e isso escondia a afirmacao central do
    -- desenho novo. A barra que atravessa o par e `faixa.bar:SetAllPoints()`; sem a implementacao
    -- ela caia no `__index` generico e virava no-op, entao TODA verificacao de largura media o
    -- Frame conteiner -- nunca a barra. "A barra cobre as duas colunas" era uma afirmacao sobre
    -- outra coisa.
    --
    -- Aqui ela amarra o filho ao pai: as medidas passam a acompanhar, como no jogo.
    function self.SetAllPoints(_, rel)
        self.__anchoredTo = rel or self.__parent
        self.__points = { { point = "ALL", relative = self.__anchoredTo, x = 0, y = 0 } }
    end

    -- ⚑ A JUSTIFICACAO E GUARDADA, como no jogo. Ela e a afirmacao central do desenho em
    -- PONTAS: "o dano encosta na esquerda, o DPS na direita, e quem esta sozinho fica no meio".
    -- Sem isto, `GetJustifyH` caia no `__index` generico e devolvia uma TABELA -- que nunca e
    -- igual a "LEFT" nem a nil, entao qualquer verificacao sobre posicao passaria a esmo.
    self.__justifyH = "LEFT"
    function self.SetJustifyH(_, v) self.__justifyH = v end
    function self.GetJustifyH() return self.__justifyH end

    self.__points = {}
    function self.SetPoint(_, point, rel, relPoint, x, y)
        -- Forma curta do WoW: SetPoint("RIGHT", x, y) -- o segundo argumento vem numero.
        if type(rel) == "number" then
            rel, relPoint, x, y = nil, nil, rel, relPoint
        elseif type(relPoint) == "number" then
            -- SetPoint("RIGHT", frame, x, y)
            x, y, relPoint = relPoint, x, nil
        end
        self.__points[#self.__points + 1] = {
            point = point, relative = rel, relativePoint = relPoint,
            x = tonumber(x) or 0, y = tonumber(y) or 0,
        }
    end
    function self.ClearAllPoints() self.__points = {} end
    function self.GetNumPoints() return #self.__points end
    function self.GetPoint(_, i)
        local p = self.__points[i or 1]
        if not p then return nil end
        return p.point, p.relative, p.relativePoint, p.x, p.y
    end
    -- ⚑ A LARGURA DO TEXTO DEPENDE DO TEXTO E DO CORPO, como no jogo. Ate 08/09 isto devolvia
    -- 40 fixo, e a consequencia so apareceu quando a largura da coluna passou a MEDIR o texto:
    -- com uma regua que responde sempre a mesma coisa, "a coluna acompanha a fonte" seria uma
    -- afirmacao sobre nada -- todas as colunas mediriam igual, em qualquer fonte, em qualquer
    -- corpo.
    --
    -- O fator 0,5 e o avanco de um digito em Arial Narrow (medido neste projeto: "Kaelvorn", 8
    -- letras, 51px no corpo 16). Nao e a fonte do jogador, e nao precisa ser: o que o teste
    -- afirma e que a largura SEGUE o texto e o corpo, nao qual e o numero exato.
    function self.GetStringWidth()
        local texto = self.__text
        if type(texto) ~= "string" then return 40 end
        local corpo = self.__size or 16
        return #texto * corpo * 0.5
    end
    function self.GetFrameLevel() return 1 end
    -- A MESMA textura em toda chamada, como no jogo. Devolver uma nova a cada
    -- `GetNormalTexture()` fazia todo teste sobre estado de icone olhar um objeto recem criado
    -- em vez do que o addon acabou de configurar -- o defeito passaria despercebido.
    function self.GetNormalTexture()
        if not self.__normalTexture then
            self.__normalTexture = widget("Texture")
        end
        return self.__normalTexture
    end
    function self.SetNormalTexture(_, path)
        local t = self:GetNormalTexture()
        -- Trocar a textura DESFAZ o atlas, como no jogo: sem isso o atlas anterior ficava
        -- grudado e um teste de "o icone mudou?" respondia sempre que nao.
        t.__texture, t.__atlas = path, nil
        return t
    end
    function self.SetHighlightTexture() end
    -- `SetAtlas` e `SetTexture` REGISTRAM o que receberam: e o unico jeito de um teste
    -- distinguir "trocou o icone" de "nao trocou", ja que o WoW nao devolve isso.
    function self.SetAtlas(_, name) self.__atlas = name; self.__texture = nil end
    function self.SetTexture(_, path) self.__texture = path; self.__atlas = nil end
    function self.GetAtlas() return self.__atlas end
    function self.GetTexture() return self.__texture or "texture" end
    function self.SetDesaturated() end

    return setmetatable(self, {
        -- Metodo do WoW e PascalCase; campo que o addon guarda no frame e minusculo.
        -- Sem essa distincao, `row.arrows` devolveria uma funcao e o codigo que testa
        -- "ja existe?" nunca veria nil — falso alarme que nao acontece no jogo.
        __index = function(_, key)
            if type(key) == "string" and key:match("^%u") then
                return function() return widget(key) end
            end
            return nil
        end,
    })
end

local frames = {}

-- FILHOS QUE O TEMPLATE JA TRAZ.
--
-- Sem isto, `check.Text` cai no `__index` generico e volta uma FUNCAO -- que e verdadeira, e
-- portanto passa por `if check.Text then` -- e o `SetText` seguinte estoura so no jogo. E a
-- mesma armadilha do `frame.Inset` no RocketSwap: stub que diverge do template testa a si
-- mesmo. `UICheckButtonTemplate` traz um `Text` posicionado a direita da caixa
-- (`UIPanelTemplates.xml`), e `DefaultPanelTemplate`/`ButtonFrameTemplate` trazem o `Inset`.
local TEMPLATE_PARTS = {
    UICheckButtonTemplate = { "Text" },
    DefaultPanelTemplate = { "Inset" },
    ButtonFrameTemplate = { "Inset" },
    PortraitFrameTemplate = { "Inset" },
}

function CreateFrame(frameType, name, parent, template)
    local f = widget(frameType or "Frame")
    f.__name = name
    f.__template = template
    -- O PAI E GUARDADO: `SetAllPoints()` sem argumento amarra ao pai, e sem isto ela nao teria
    -- em que se amarrar.
    f.__parent = parent
    function f.GetParent() return parent end

    for _, part in ipairs(TEMPLATE_PARTS[template] or {}) do
        -- Com template: a fonte ja vem definida, como no jogo.
        f[part] = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end

    frames[#frames + 1] = f
    return f
end

--------------------------------------------------------------------------------
-- Globais que o addon usa
--------------------------------------------------------------------------------
UIParent = widget("Frame")
-- Altura de tela plausivel: o placar limita as linhas pelo que cabe, e o stub generico de
-- 200px faria todo teste cair no piso, escondendo o calculo.
UIParent.GetHeight = function() return 1080 end
Minimap = widget("Frame")
GameTooltip = widget("GameTooltip")
UISpecialFrames = {}
RAID_CLASS_COLORS = { MAGE = { r = 0.4, g = 0.8, b = 0.9 },
                      PRIEST = { r = 1, g = 1, b = 1 },
                      ROGUE = { r = 1, g = 0.96, b = 0.41 } }
CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.49, 0, 0.25 },
                       PRIEST = { 0.49, 0.73, 0.25, 0.5 },
                       ROGUE = { 0, 0.24, 0.25, 0.5 } }
unpack = unpack or table.unpack

function GameTooltip_Hide() end

-- Templates do configurador em abas. Todos conferidos na fonte do 12.1.0 antes de entrar no
-- addon; aqui sao no-ops com a MESMA forma de retorno, para o teste exercitar o caminho real.
function PanelTemplates_TabResize() end
function PanelTemplates_SelectTab() end
function PanelTemplates_DeselectTab() end
function CreateMinimalSliderFormatter() return function() end end
MinimalSliderWithSteppersMixin = {
    Label = { Right = 1, Left = 2, Top = 3, Bottom = 4 },
    Event = { OnValueChanged = "OnValueChanged" },
}
MenuUtil = {
    CreateRadioMenu = function() end,
}
function InCombatLockdown() return false end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function GetCursorPosition() return 400, 300 end
function GetNumGroupMembers() return 5 end
-- Grupo de 5, para o placar descobrir a funcao de cada um sem inspecionar.
local PARTY = {
    player = { name = "Bolva",      role = "TANK" },
    party1 = { name = "Drakaris",   role = "HEALER" },
    party2 = { name = "Kaelvorn",   role = "DAMAGER" },
    party3 = { name = "Sargath",    role = "DAMAGER" },
    party4 = { name = "Lilianvoss", role = "DAMAGER" },
}
function UnitName(unit) return PARTY[unit] and PARTY[unit].name end
function UnitGroupRolesAssigned(unit) return PARTY[unit] and PARTY[unit].role or "NONE" end
function IsInRaid() return false end
function GetLocale() return "ptBR" end
-- Nome cross-realm: o jogo devolve "Nome-Reino" e Ambiguate tira o reino.
function Ambiguate(name, context)
    if context == "short" then return (tostring(name):gsub("%-.*$", "")) end
    return name
end
function date(fmt) return "12:00:00" end
local fakeClock = 1000
function GetTime() return fakeClock end
function time() return 1789000000 end
UNKNOWN = "Desconhecido"
function GetDifficultyInfo(id)
    local map = {
        [14] = { "Normal",  false, false },
        [15] = { "Heroico", true,  false },
        [16] = { "Mitico",  false, true  },
    }
    local d = map[id] or { "Normal", false, false }
    -- name, groupType, isHeroic, isChallengeMode, displayHeroic, displayMythic
    return d[1], "raid", d[2], false, d[2], d[3]
end
function AdvanceClock(seconds) fakeClock = fakeClock + seconds end
function SecondsToClock(s) return string.format("%02d:%02d", s / 60, s % 60) end
function AbbreviateNumbers(v) return tostring(math.floor(v)) end
function CopyTable(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and CopyTable(v) or v end
    return out
end
---O gancho do jogo, com a semantica que importa aqui: o original roda PRIMEIRO e o gancho
---depois, com os mesmos argumentos, e o retorno e o do original. Um stub que so trocasse a
---funcao testaria o gancho e nao o par -- e o defeito real seria o original deixar de rodar.
function hooksecurefunc(tbl, name, hook)
    local original = tbl[name]
    tbl[name] = function(...)
        local a, b, c = original(...)
        hook(...)
        return a, b, c
    end
end

function issecretvalue() return false end
function securecallfunction(fn, ...) return fn(...) end
function BreakUpLargeNumbers(v) return tostring(v) end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end end
format = string.format

C_Spell = {
    GetSpellInfo = function(id) return { name = "Magia " .. tostring(id), iconID = 134400 } end,
    RequestLoadSpellData = function() end,
}
function UnitGUID() return "Player-Thalyra" end

-- Le o .toc de verdade em vez de devolver um numero fixo: com constante aqui, um teste
-- sobre versao passaria a confirmar o stub em vez do addon.
C_AddOns = {
    GetAddOnMetadata = function(_, field)
        for line in io.lines(ADDON .. ".toc") do
            local value = line:match("^## " .. field .. ":%s*(.-)%s*$")
            if value then return (value:gsub("%c", "")) end
        end
    end,
}
C_Texture = {
    GetAtlasInfo = function()
        return { file = "atlas.blp", leftTexCoord = 0, rightTexCoord = 1,
                 topTexCoord = 0, bottomTexCoord = 1, width = 64, height = 64 }
    end,
}
C_Timer = { After = function(_, fn) fn() end }
C_ChallengeMode = {
    GetActiveChallengeMapID = function() return mundo.challengeMapID end,
    -- Formato do 12.1.0: UMA TABELA. Os campos abaixo sao os que o placar le.
    GetChallengeCompletionInfo = function()
        return {
            mapChallengeModeID = 2, level = 12, time = 1500000, onTime = true,
            keystoneUpgradeLevels = 1, practiceRun = false,
            oldOverallDungeonScore = 2800, newOverallDungeonScore = 2871,
            isEligibleForScore = true,
        }
    end,
    -- name, id, timeLimit, texture, backgroundTexture
    GetMapUIInfo = function() return "Masmorra de Teste", 2, 1800, 1, 2 end,
    GetDeathCount = function() return 3, 45 end,
    GetActiveKeystoneInfo = function() return 12, { 10, 152 } end,
    GetAffixInfo = function(id) return "Afixo " .. tostring(id), "descricao", 100 end,
}
C_PlayerInfo = {
    GetPlayerMythicPlusRatingSummary = function(name)
        if name == nil then return nil end
        return { currentSeasonScore = 2500 + #tostring(name), runs = {} }
    end,
}
C_MythicPlus = {
    GetCurrentAffixes = function() return { { id = 10 }, { id = 152 }, { id = 148 } } end,
    RequestMapInfo = function() end,
}

Enum = {
    DamageMeterSessionType = { Current = 0, Overall = 1, Expired = 2 },
    DamageMeterType = {
        DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4,
        Interrupts = 5, Dispels = 6, DamageTaken = 7, AvoidableDamageTaken = 8,
        Deaths = 9, EnemyDamageTaken = 10,
    },
    -- O enum que separa aliado de inimigo. Faltava, e o stub por isso nao sabia representar
    -- ALIADO NPC -- que e exatamente o caso do relato da masmorra de seguidores.
    DamageMeterSourceDisplayType = { None = 0, Ally = 1, Enemy = 2 },
}

--------------------------------------------------------------------------------
-- A CHAVE EM ANDAMENTO E O CRONOMETRO DO MUNDO
--------------------------------------------------------------------------------
-- Sem estes dois, o caminho da RETOMADA -- o `/reload` no meio da corrida, que e rotina para
-- quem mexe em addon -- nao existia para o teste. E foi dele que saiu o defeito relatado com
-- print em 07/09 20:22: "Fora de combate: 26:13" numa chave de 26:13.
--
-- `mundo` sao os botoes que o teste gira; o resto do harness nao tinha uma tabela de estado, e
-- uma so para isto e melhor que duas globais soltas.
mundo = { challengeMapID = nil, worldElapsed = nil }

Enum.WorldElapsedTimerTypes = { ChallengeMode = 1 }

function GetWorldElapsedTimers()
    if not mundo.worldElapsed then return {} end
    return { 1 }
end

function GetWorldElapsedTime()
    -- TRES retornos, e o primeiro nao interessa. Conferido no proprio cliente, que le assim em
    -- cinco lugares: `local _, elapsedTime, type = GetWorldElapsedTime(timerID)`
    -- (`WorldStateFrame.lua:50`, `Blizzard_ScenarioObjectiveTracker.lua:680`).
    --
    -- Eu tinha escrito QUATRO aqui, e o efeito foi o stub acusar de errado um addon que estava
    -- certo: `Run.ElapsedFromWorldTimer` lia nil, marcava a corrida como parcial, e o teste
    -- apontava para o codigo do addon. Stub que representa a API errado nao testa nada -- ele
    -- inventa um defeito.
    return nil, mundo.worldElapsed, Enum.WorldElapsedTimerTypes.ChallengeMode
end


-- Dados falsos, no formato lido do Details!
-- Classe e spec DISTINTAS por ator. Nao e enfeite: `classFilename` e `specIconID` sao
-- `NeverSecret` e por isso viraram a chave de casamento entre metricas quando o GUID esta
-- secret. Com os tres atores como "MAGE/1" o casamento por identidade ficava sempre ambiguo
-- e o caminho novo nunca era exercitado.
local FAKE_IDENTITY = {
    Thalyra = { class = "MAGE",   spec = 101 },
    Brumm   = { class = "PRIEST", spec = 102 },
    Sarien  = { class = "ROGUE",  spec = 103 },
    Kaz     = { class = "SHAMAN", spec = 104 },
    -- ALIADO NPC: e o caso do relato -- masmorra de SEGUIDORES, onde o healer nao e jogador.
    -- A API preve isso: `sourceDisplayType` vale `Ally`, `sourceCreatureID` existe e a classe vem
    -- VAZIA (`DamageMeterDocumentation.lua:199-212`). O medidor nativo desenha esse caso com cor
    -- de aliado em vez de cor de classe (`DamageMeterEntry.lua:365-369`).
    Elowen  = { class = "", spec = 0, creature = 210001, ally = true },
}

local function fakeSource(name, total, extra)
    local id = FAKE_IDENTITY[name] or { class = "MAGE", spec = 199 }
    local src = {
        name = name, sourceGUID = "Player-" .. name,
        sourceCreatureID = id.creature or 0,
        totalAmount = total, amountPerSecond = total / 120,
        classFilename = id.class, specIconID = id.spec, deathRecapID = 0,
        deathTimeSeconds = 0,
        classification = id.ally and "elite" or "player",
        sourceDisplayType = Enum.DamageMeterSourceDisplayType
            and Enum.DamageMeterSourceDisplayType.Ally or 1,
        isLocalPlayer = name == "Thalyra",
    }
    for k, v in pairs(extra or {}) do src[k] = v end
    return src
end

-- Os valores que `GetCombatSessionFromType` aceita neste "cliente". Fixo de proposito: ver a
-- nota dentro do stub.
local SESSION_TYPES_ACEITOS = { [0] = true, [1] = true, [2] = true }

--------------------------------------------------------------------------------
-- Tratamento de erro do cliente
--------------------------------------------------------------------------------
-- O SIMULADOR PRECISA DOS TRES MUNDOS, porque o addon escolhe caminho diferente em cada um:
--
--   1. sem !BugGrabber          -> encadeia no handler que estiver valendo
--   2. com !BugGrabber          -> assina o callback dele (e o `seterrorhandler` e um no-op)
--   3. `seterrorhandler` mudo, sem BugGrabber -> nao da para capturar, e tem que ADMITIR isso
--
-- O mundo 3 e o que justifica a conferencia `geterrorhandler() == meu` no addon: sem ela a
-- captura se declara ligada estando desligada, e "o arquivo nao tem erro" viraria mentira.
mundoErro = {
    handler = nil,
    mudo = false,        -- o !BugGrabber faz `function seterrorhandler() end`
}

function seterrorhandler(fn)
    if mundoErro.mudo then return end
    mundoErro.handler = fn
end

function geterrorhandler()
    return mundoErro.handler
end

function debugstack()
    return mundoErro.pilha or ""
end

C_DamageMeter = {
    IsDamageMeterAvailable = function() return true end,
    GetSessionDurationSeconds = function() return 134 end,
    ResetAllCombatSessions = function() end,
    GetAvailableCombatSessions = function() return { { sessionID = 1 } } end,
    GetCombatSessionFromType = function(sessionType, attribute)
        -- ⚑ VALOR FORA DO ENUM LEVANTA, como no cliente de verdade -- ela NAO devolve `nil`.
        --
        -- O stub aceitava qualquer numero, e por isso o harness ficou verde enquanto o log de
        -- diagnostico varria `0, 3` num enum de tres valores: uma linha vermelha por combate, 1628
        -- delas no BugGrabber ate 09/09/2026, e nenhum teste daqui podia ter pego. Simulador que
        -- e mais permissivo que o jogo transforma erro em silencio.
        -- O CONJUNTO ACEITO E FIXO AQUI, e nao lido de `Enum.DamageMeterSessionType`. A funcao do
        -- cliente e C: ela tem a lista dela, que nao muda porque alguem mexeu na tabela Lua do
        -- enum. Ler o enum aqui tornaria impossivel simular o caso que interessa -- um valor
        -- existir no enum e a funcao ainda nao atende-lo.
        if not SESSION_TYPES_ACEITOS[sessionType] then
            error("bad argument #1 to 'GetCombatSessionFromType' (Usage: local session = "
                .. "C_DamageMeter.GetCombatSessionFromType(sessionType, type))", 2)
        end

        -- Cada metrica tem seus proprios valores: e o que torna os testes de cruzamento
        -- significativos. Antes tudo devolvia a sessao de dano e o teste passava por acidente.
        -- MORTES TEM FORMA PROPRIA: cada entrada da lista e UM OBITO, nao um jogador com
        -- contagem em `totalAmount`. Quem nao morreu simplesmente NAO APARECE. Confirmado na
        -- documentacao da API (`DamageMeterCombatSource` traz `deathRecapID` e
        -- `deathTimeSeconds`), no consumidor da Blizzard (`DamageMeterEntry.lua:562-604`,
        -- onde `GetValueText` devolve o HORARIO e `GetStatusValue` devolve 1 fixo) e no
        -- retrato da primeira corrida real, onde os dois que morreram vieram com 0.
        --
        -- Brumm morreu 2x, Sarien 1x, Thalyra nenhuma.
        if attribute == Enum.DamageMeterType.Deaths then
            return {
                combatSources = {
                    fakeSource("Brumm",  0, { deathRecapID = 11, deathTimeSeconds = 42 }),
                    fakeSource("Sarien", 0, { deathRecapID = 12, deathTimeSeconds = 88 }),
                    fakeSource("Brumm",  0, { deathRecapID = 13, deathTimeSeconds = 130 }),
                    -- ENTRADAS COM `deathRecapID = 0`. E a forma do relato de 06/09: um cacador
                    -- apareceu com 19 mortes numa mitica+ sem ter morrido, depois de usar
                    -- "Fingir-se de Morto" muitas vezes.
                    --
                    -- O stub nao sabia produzir esta forma -- todas as entradas dele tinham recap
                    -- valido -- entao a diferenca entre "esta na lista" e "e uma morte" nao
                    -- existia aqui dentro, e o addon podia contar tudo sem nada acusar.
                    --
                    -- Que o jogo NAO conta essas entradas como morte esta na fonte dele: o
                    -- medidor nativo pergunta `deathRecapID ~= 0` em quatro lugares antes de
                    -- desenhar (`DamageMeterEntry.lua:563,572,580,594`).
                    fakeSource("Kaz", 0, { deathRecapID = 0, deathTimeSeconds = 0 }),
                    fakeSource("Kaz", 0, { deathRecapID = 0, deathTimeSeconds = 0 }),
                    fakeSource("Kaz", 0, { deathRecapID = 0, deathTimeSeconds = 0 }),
                },
                combatSourcesCount = 6, totalAmount = 0, maxAmount = 0, durationSeconds = 134,
            }
        end

        -- CADA METRICA TEM SEU PROPRIO ELENCO, e nao so seus proprios numeros.
        --
        -- Antes as tres metricas tinham sempre os MESMOS tres atores, e isso escondia o defeito
        -- que o usuario relatou: "o healer pode dar 0 dano e curar muito, ele tem que aparecer" e
        -- "pode ter alguem que nao cura e nem da dano, so da interrupt, tem que aparecer". Com
        -- elenco identico em toda metrica, montar as linhas a partir de UMA metrica dava o mesmo
        -- resultado que montar a partir da uniao -- e o teste concordava com o defeito.
        --
        -- `Elowen` e o caso do relato: masmorra de seguidores, cura muito e nao da dano nenhum.
        -- `Kaz` e o segundo caso: so interrompe.
        local perAttribute = {
            [Enum.DamageMeterType.HealingDone] = {
                Thalyra = 120000, Brumm = 900000, Sarien = 50000, Elowen = 2400000,
            },
            [Enum.DamageMeterType.Interrupts] = { Thalyra = 1, Sarien = 5, Kaz = 7 },
            [Enum.DamageMeterType.Dispels] = { Sarien = 3 },
            [Enum.DamageMeterType.Absorbs] = {},
        }
        local values = perAttribute[attribute]
        if values then
            -- ATOR COM ZERO NAO APARECE. E assim na API -- foi o que o retrato da corrida real
            -- mostrou: o Delzoka nao tinha a chave `avoidable` porque o dele era 0, e o
            -- Details escrevia 0 na mesma celula.
            local names = { "Thalyra", "Brumm", "Sarien", "Elowen", "Kaz" }
            local sources, total, maximum = {}, 0, 0
            for i = 1, #names do
                local v = values[names[i]]
                if v and v > 0 then
                    sources[#sources + 1] = fakeSource(names[i], v)
                    total = total + v
                    if v > maximum then maximum = v end
                end
            end
            -- ⚑ A LISTA VEM ORDENADA PELA METRICA PEDIDA, e sem isto o simulador escondia a
            -- unica propriedade de que o desenho inteiro depende.
            --
            -- Ele montava a lista na ordem fixa dos nomes. A API real devolve ordenada -- e isso
            -- foi CONFERIDO no medidor da propria Blizzard, que nao ordena nada em Lua: percorre
            -- `combatSources` na ordem e usa `index = i` como posicao
            -- (`DamageMeterSessionWindow.lua:621-641`). E tem que ser assim, porque em combate os
            -- valores sao secret e ordenar em Lua levantaria erro.
            --
            -- Com o stub em ordem de nome, clicar num cabecalho de coluna nao mudava nada na
            -- lista, e o teste que perguntava "a ordenacao ainda funciona?" respondia NAO para um
            -- addon que estava certo. Quinta vez nesta sessao que o stub acusa ou absolve por nao
            -- saber representar a API.
            table.sort(sources, function(a, b) return a.totalAmount > b.totalAmount end)

            return {
                combatSources = sources, totalAmount = total,
                maxAmount = maximum, durationSeconds = 134,
            }
        end
        return {
            combatSources = { fakeSource("Thalyra", 1200000), fakeSource("Brumm", 980000),
                              fakeSource("Sarien", 740000) },
            totalAmount = 2920000, maxAmount = 1200000, durationSeconds = 134,
        }
    end,
    GetCombatSessionSourceFromType = function(sessionType, attribute, guid)
        -- Valores distintos por metrica E por ator: assim o teste de lider por coluna
        -- verifica que o healer (Brumm) lidera a cura mesmo estando em segundo no dano.
        local perActor = {
            ["Player-Thalyra"] = { heal = 120000, interrupts = 1, deaths = 0 },
            ["Player-Brumm"] = { heal = 900000, interrupts = 0, deaths = 2 },
            ["Player-Sarien"] = { heal = 50000, interrupts = 5, deaths = 1 },
        }
        local actor = perActor[guid] or { heal = 0, interrupts = 0, deaths = 0 }
        local byAttribute = {
            [Enum.DamageMeterType.HealingDone] = { totalAmount = actor.heal, amountPerSecond = actor.heal / 120 },
            [Enum.DamageMeterType.Interrupts] = { totalAmount = actor.interrupts, amountPerSecond = 0 },
            [Enum.DamageMeterType.Deaths] = { totalAmount = actor.deaths, amountPerSecond = 0 },
        }
        local entry = byAttribute[attribute] or { totalAmount = 42000, amountPerSecond = 350 }
        return {
            combatSpells = {
                { spellID = 1001, totalAmount = 500000, amountPerSecond = 4000 },
                { spellID = 1002, totalAmount = 300000, amountPerSecond = 2500 },
                { spellID = 1003, totalAmount = 120000, amountPerSecond = 1000 },
            },
            maxAmount = entry.totalAmount,
            totalAmount = entry.totalAmount, amountPerSecond = entry.amountPerSecond,
        }
    end,
    GetCombatSessionFromID = function() return nil end,
}

-- Settings API
local settingsStore = {}
Settings = {
    RegisterVerticalLayoutCategory = function(name)
        return { name = name, GetID = function() return 1 end }, { AddInitializer = function() end }
    end,
    RegisterAddOnCategory = function() end,
    RegisterAddOnSetting = function(_, variable, key, tbl, kind, label, default)
        settingsStore[variable] = { key = key, tbl = tbl, default = default }
        -- exercita o proxy: lê e escreve como o painel faria
        local _ = tbl[key]
        return { variable = variable, GetValue = function() return tbl[key] end }
    end,
    SetOnValueChangedCallback = function() end,
    CreateCheckbox = function() end,
    CreateSlider = function() end,
    CreateDropdown = function() end,
    CreateSliderOptions = function() return {} end,
    CreateControlTextContainer = function()
        return { Add = function() end, GetData = function() return {} end }
    end,
    OpenToCategory = function() end,
}
function CreateSettingsListSectionHeaderInitializer() return {} end

StaticPopupDialogs = {}
YES, NO = "Sim", "Nao"
local popupShown
function StaticPopup_Show(which)
    popupShown = which
    -- executa o OnAccept para exercitar o caminho de verdade
    local dialog = StaticPopupDialogs[which]
    if dialog and dialog.OnAccept then dialog.OnAccept() end
end

SlashCmdList = {}

--------------------------------------------------------------------------------
-- Carrega o addon na ordem do .toc
--------------------------------------------------------------------------------
local ns = {}
local files = {}
for line in io.lines(ADDON .. ".toc") do
    line = line:gsub("\r", "")
    if line:match("%.lua$") and not line:match("^#") then
        files[#files + 1] = line:gsub("\\", "/")
    end
end

print("== carregando " .. #files .. " arquivos ==")
for _, file in ipairs(files) do
    local chunk, err = loadfile(file)
    if not chunk then
        print("  FALHA AO COMPILAR " .. file .. ": " .. err)
        os.exit(1)
    end
    local ok, runErr = pcall(chunk, ADDON, ns)
    print(ok and ("  ok    " .. file) or ("  ERRO  " .. file .. ": " .. tostring(runErr)))
    if not ok then os.exit(1) end
end

--------------------------------------------------------------------------------
-- Dispara os eventos do ciclo de vida
--------------------------------------------------------------------------------
local function fire(event, ...)
    for _, f in ipairs(frames) do
        if f.__events[event] and f.__scripts.OnEvent then
            local ok, err = pcall(f.__scripts.OnEvent, f, event, ...)
            if not ok then
                print("  ERRO em " .. event .. ": " .. tostring(err))
                os.exit(1)
            end
        end
    end
    print("  ok    " .. event)
end

print("== ciclo de vida ==")
fire("ADDON_LOADED", ADDON)
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
fire("DAMAGE_METER_CURRENT_SESSION_UPDATED")
fire("DAMAGE_METER_COMBAT_SESSION_UPDATED")
fire("CHALLENGE_MODE_START")
fire("PLAYER_REGEN_DISABLED")
fire("ENCOUNTER_END", 1234, "Chefe de Teste", 16, 20, 1)
fire("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
fire("PLAYER_REGEN_ENABLED")
fire("CHALLENGE_MODE_COMPLETED")

print("== funcionalidades ==")
local function try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    print(ok and ("  ok    " .. label) or ("  ERRO  " .. label .. ": " .. tostring(err)))
    if not ok then os.exit(1) end
end

try("Window.ApplyVisibility", ns.Window.ApplyVisibility)
try("Window.ApplyLock (travado)", function()
    ns.db.locked = true
    ns.Window.ApplyLock()
end)
try("Window.ApplyLock (destravado)", function()
    ns.db.locked = false
    ns.Window.ApplyLock()
end)
try("Window.Show", ns.Window.Show)
try("Window.Hide", ns.Window.Hide)
try("Window.OnCombatStart", ns.Window.OnCombatStart)
try("Window.OnCombatEnd", ns.Window.OnCombatEnd)
try("Window.Draw", ns.Window.Draw)
try("Window.Rebuild", ns.Window.Rebuild)
try("ApplyRowIcon (spec)", function()
    ns.db.rowIcon = "spec"
    ns.Window.Rebuild()
end)
try("ApplyRowIcon (class)", function()
    ns.db.rowIcon = "class"
    ns.Window.Rebuild()
    ns.db.rowIcon = "spec"
end)
try("Window.ToggleColumn", ns.Window.ToggleColumn, "absorb")
try("Window.MoveColumn", ns.Window.MoveColumn, 2, -1)
try("Window.ApplyPreset(raid)", ns.Window.ApplyPreset, "raid")
try("Minimap.ApplyVisibility", ns.Minimap.ApplyVisibility)
try("Profile.SetPerCharacter(true)", ns.Profile.SetPerCharacter, true)
try("Profile.SetPerCharacter(false)", ns.Profile.SetPerCharacter, false)
try("Profile.Reset", ns.Profile.Reset)
try("Data.RequestReset (com confirmacao)", ns.Data.RequestReset)
try("Data.RequestReset (direto)", ns.Data.RequestReset, true)
try("Log.Snapshot", ns.Log.Snapshot, "teste")
try("Log.OnCombatStart", ns.Log.OnCombatStart)
try("Log.OnCombatEnd", ns.Log.OnCombatEnd)
try("Log.Clear", ns.Log.Clear)
try("Scoreboard.Show", ns.Scoreboard.Show)
try("Breakdown.Show", function()
    local session = C_DamageMeter.GetCombatSessionFromType(0, Enum.DamageMeterType.DamageDone)
    ns.Breakdown.Show(session.combatSources[1], 0)
end)
try("Breakdown.Refresh", ns.Breakdown.Refresh)
try("Breakdown.Hide", ns.Breakdown.Hide)
try("Data.GetRows", ns.Data.GetRows, 0, "damage", { "damage", "dps", "hps" }, 5, false)


print("== valores ==")
-- Regressao da 0.8.0: a coluna de DPS mostrava o total, porque usava o atributo Enum.Dps
-- em vez do campo amountPerSecond. Aqui isso quebra o teste.
local function check(label, got, want)
    local ok = got == want
    print(ok and ("  ok    " .. label .. " = " .. tostring(got))
        or ("  ERRO  " .. label .. ": esperado " .. tostring(want) .. ", veio " .. tostring(got)))
    if not ok then os.exit(1) end
end

local cols = { "damage", "dps", "healing", "hps", "interrupts", "damagepct" }
local rows = ns.Data.GetRows(0, "damage", cols, 5, false)
if not rows or not rows[1] then
    print("  ERRO  GetRows nao devolveu linhas")
    os.exit(1)
end

local first = rows[1].values
check("dano total", first[1], 1200000)
check("dps (amountPerSecond, nao o total)", first[2], 1200000 / 120)
check("cura total (metrica cruzada)", first[3], 120000)
-- Regressao: CPS ficava em branco porque o conteiner de magias nao tem amountPerSecond.
check("cps (metrica cruzada, nao pode ser nil)", first[4], 120000 / 120)
check("interrupcoes (metrica cruzada)", first[5], 1)

-- A LISTA E A UNIAO DOS ATORES DE TODAS AS METRICAS EXIBIDAS, e nao so da que ordena.
--
-- Pedido literal do usuario, em duas frases do mesmo dia: "o healer pode dar 0 dano e curar
-- muito, ele tem que aparecer no medidor" e "pode ter alguem que nao cura e nem da dano, so da
-- interrupt, tem que aparecer". Antes a lista saia da metrica ordenada, entao quem nao pontuava
-- nela nao tinha linha -- nem para mostrar zero.
--
-- `Elowen` cura 2,4M e nao da dano nenhum (o healer NPC da masmorra de seguidores). `Kaz` so
-- interrompe. Ordenando por DANO, os dois tem que aparecer assim mesmo.
-- E NINGUEM APARECE DUAS VEZES. E o risco que a uniao traz: o mesmo ator existe em varias
-- metricas, e sem deduplicacao ele ganharia uma linha por metrica -- com os numeros dele
-- contados varias vezes na frente do jogador, que e pior que faltar uma linha.
do
    local todos = ns.Data.GetRows(0, "damage", cols, 99, false)
    local vistos, repetido = {}, nil
    for i = 1, #todos do
        local g = todos[i].source and todos[i].source.sourceGUID
        if g then
            if vistos[g] then repetido = g end
            vistos[g] = true
        end
    end
    check("nenhum ator aparece duas vezes", repetido or false, false)
end

local nomes = {}
for i = 1, #rows do nomes[rows[i].source and rows[i].source.name or "?"] = i end
check("o healer que nao da dano tem linha", nomes["Elowen"] ~= nil, true)
check("e quem so interrompe tambem", nomes["Kaz"] ~= nil, true)

-- E COM ZERO NA COLUNA ORDENADA, que e o numero certo: ele nao pontuou ali, e nao "nao sei".
check("o dano do healer e zero, nao vazio", rows[nomes["Elowen"]].values[1], 0)

-- E COM O NUMERO DELE NA COLUNA DELE. Este e o erro silencioso que a uniao quase introduziu: o
-- laco semeia o cache com a metrica ORDENADA, e para quem entrou pela cura isso poria a CURA na
-- coluna de DANO. O ator lembra de qual metrica veio.
check("e a cura dele esta na coluna de cura", rows[nomes["Elowen"]].values[3], 2400000)
check("e as interrupcoes do Kaz na coluna de interrupcoes", rows[nomes["Kaz"]].values[5], 7)

-- Lider por coluna: Thalyra lidera o dano (linha 1), e agora quem cura mais e o Elowen e quem
-- mais interrompe e o Kaz -- os dois que so existem por causa da uniao. Cada coluna tem seu
-- proprio realce, e ele considera o GRUPO todo.
check("lider do dano e a linha 1", rows[1].best and rows[1].best[1] or false, true)
check("lider da cura e o healer sem dano",
    rows[nomes["Elowen"]].best and rows[nomes["Elowen"]].best[3] or false, true)
check("lider das interrupcoes e quem so interrompe",
    rows[nomes["Kaz"]].best and rows[nomes["Kaz"]].best[5] or false, true)
check("linha 1 nao lidera a cura", rows[1].best and rows[1].best[3] or false, false)
-- (o lider das interrupcoes ja foi conferido acima: e o Kaz, que so interrompe)
check("e a linha 3 NAO lidera as interrupcoes", rows[3].best and rows[3].best[5] or false, false)
check("percentual do dano", math.floor(first[6] + 0.5), math.floor(1200000 / 2920000 * 100 + 0.5))

-- ordem invertida: a ultima linha vira a primeira, sem comparar nada
--
-- A ASSERCAO MUDOU DE CAMPO na 0.64.0, e a razao vale registrar: ela lia
-- `source.totalAmount`, que e o total DA METRICA DE ONDE O ATOR VEIO. Enquanto todos vinham da
-- metrica ordenada isso era o dano; com a uniao, para quem entrou pela cura ou pelas
-- interrupcoes, `totalAmount` e a cura ou a contagem de interrupcoes. Ler o valor da COLUNA e o
-- que mede o que a asserção diz medir.
local asc = ns.Data.GetRows(0, "damage", cols, 5, true)
check("ordem crescente comeca pelo menor dano", asc[1].values[1], 0)
check("e o maior dano vai para o fim", asc[#asc].values[1], 1200000)

-- migracao das colunas salvas no formato antigo (ids de Enum)
--
-- A migracao agora TAMBEM normaliza: agrupa por familia, completa o par total+taxa e ordena
-- total antes da taxa. Uma lista salva de {dano, CPS} sai como {dano, DPS, cura, CPS} -- o dano
-- ganha a taxa dele e a cura ganha o total, porque item que o jogador ve como um so tem que
-- estar inteiro na tela.
local migrated = ns.Data.MigrateColumns({ Enum.DamageMeterType.DamageDone, Enum.DamageMeterType.Hps })
check("migracao converte id em chave", migrated[1], "damage")
check("  e completa o par do dano", migrated[2], "dps")
check("  a familia da cura vem depois", migrated[3], "healing")
check("  com o CPS que estava salvo", migrated[4], "hps")

print("== mortes sao CONTADAS, nao somadas ==")
-- Primeira corrida real (05/09/2026) trouxe o defeito inteiro num retrato: os tres que NAO
-- morreram vieram sem a chave `deaths`, e os DOIS que morreram vieram com `deaths = 0`.
-- A causa nao era o placar: e que a metrica de mortes lista UM OBITO POR ENTRADA, e
-- `totalAmount` ali nao significa nada. Quem le `totalAmount` acerta zero e erra o resto.
do
    local cols = { "damage", "deaths" }
    local r = ns.Data.GetRows(0, "damage", cols, 5, false)

    -- ordem por dano: Thalyra (1.2M), Brumm (980K), Sarien (740K)
    check("quem nao morreu tem 0, nao vazio", r[1].values[2], 0)
    check("duas mortes do mesmo jogador contam 2", r[2].values[2], 2)
    check("uma morte conta 1", r[3].values[2], 1)

    -- ESTAR NA LISTA NAO E TER MORRIDO. Relato de 06/09: um cacador apareceu com 19 mortes numa
    -- mitica+ sem ter morrido, depois de usar "Fingir-se de Morto" muitas vezes.
    --
    -- Quem decide e o `deathRecapID`: o medidor da propria Blizzard trata a entrada como obito so
    -- quando ele e diferente de zero, e faz essa pergunta em QUATRO lugares antes de desenhar
    -- (`DamageMeterEntry.lua:563,572,580,594`). Nos contavamos toda entrada da lista.
    --
    -- O `Kaz` tem TRES entradas com recap zero e nenhuma morte de verdade.
    local todos = ns.Data.GetRows(0, "damage", cols, 99, false)
    local porNome = {}
    for i = 1, #todos do porNome[todos[i].source and todos[i].source.name or "?"] = todos[i] end

    check("entrada sem recap NAO conta como morte", porNome["Kaz"].values[2], 0)

    -- E as mortes de verdade continuam contando: o filtro nao pode zerar a coluna inteira, que
    -- seria trocar um numero errado por outro.
    check("e as mortes de verdade seguem contando", porNome["Brumm"].values[2], 2)
end

print("== ausente numa metrica e ZERO, nao desconhecido ==")
-- O Details escreve `0`. Nos escreviamos "." porque `SourceFor` devolvia nil e o valor virava
-- nil. Quem nao aparece na lista de uma metrica nao pontuou nela -- desde que a lista tenha
-- sido lida, que e o caso fora de combate.
do
    local semDispel = ns.Data.GetRows(0, "damage", { "damage", "dispels" }, 5, false)
    check("sem dissipacoes = 0", semDispel[1].values[2], 0)
end

print("== cruzamento por classe+spec quando o GUID esta secret ==")
-- Durante a chave inteira o GUID e secret (restricao de ChallengeMode) e
-- `GetCombatSessionSourceFromType` recusa receber o valor opaco de volta
-- (`SecretArguments = "AllowedWhenUntainted"` e addon e codigo tainted). Resultado no jogo:
-- so o proprio jogador tinha Cura/CPS e o HEALER aparecia zerado -- reclamacao do usuario.
--
-- `classFilename` e `specIconID` sao `NeverSecret`: dao para casar o ator entre metricas.
do
    local marker = setmetatable({}, { __tostring = function() return "SECRET" end })
    local realIsSecret = issecretvalue
    issecretvalue = function(v) return v == marker end

    local plain = C_DamageMeter.GetCombatSessionFromType
    C_DamageMeter.GetCombatSessionFromType = function(sessionType, attribute)
        local session = plain(sessionType, attribute)
        for i, src in ipairs(session.combatSources) do
            src.sourceGUID = marker
            src.isLocalPlayer = i == 1
        end
        return session
    end

    local r = ns.Data.GetRows(0, "damage", { "damage", "healing" }, 5, false)
    -- Brumm e o healer e esta em SEGUNDO no dano: sem o casamento por identidade a celula
    -- dele fica vazia, que foi o "healer sem informacoes de healer" do print.
    check("healer tem cura mesmo com GUID secret", r[2].values[2], 900000)
    check("terceiro tambem, nao so o jogador local", r[3].values[2], 50000)

    -- E a contagem de mortes tem que sobreviver ao mesmo cenario.
    local d = ns.Data.GetRows(0, "damage", { "damage", "deaths" }, 5, false)
    check("mortes contadas com GUID secret", d[2].values[2], 2)

    C_DamageMeter.GetCombatSessionFromType = plain
    issecretvalue = realIsSecret
end

print("== identidade ambigua nao inventa numero ==")
-- Dois jogadores da mesma classe E spec colidem na chave. Nesse caso o addon tem que devolver
-- vazio, nao o numero do outro: trocar os valores de dois jogadores e pior que nao mostrar.
do
    local marker = setmetatable({}, { __tostring = function() return "SECRET" end })
    local realIsSecret = issecretvalue
    issecretvalue = function(v) return v == marker end

    local plain = C_DamageMeter.GetCombatSessionFromType
    C_DamageMeter.GetCombatSessionFromType = function(sessionType, attribute)
        local session = plain(sessionType, attribute)
        for i, src in ipairs(session.combatSources) do
            src.sourceGUID = marker
            src.isLocalPlayer = false          -- ninguem e o jogador local: so resta a identidade
            src.classFilename = "MAGE"         -- todos iguais de proposito
            src.specIconID = 101
        end
        return session
    end

    local r = ns.Data.GetRows(0, "damage", { "damage", "healing" }, 5, false)
    check("empate de classe+spec deixa vazio", r[2].values[2], nil)

    C_DamageMeter.GetCombatSessionFromType = plain
    issecretvalue = realIsSecret
end

print("== combate: guid secret ==")
-- SIMULA_SECRET: reproduz o bug real relatado no log do usuario. Em combate o GUID e secret,
-- e devolver esse valor para a API responde "Secret values are only allowed during untainted".
-- Antes da correcao, o erro derrubava o desenho e a janela ficava vazia a luta inteira.
local secretMarker = setmetatable({}, { __tostring = function() return "SECRET" end })
local realIsSecret = issecretvalue
issecretvalue = function(v) return v == secretMarker end

local plainFromType = C_DamageMeter.GetCombatSessionFromType
C_DamageMeter.GetCombatSessionFromType = function(sessionType, attribute)
    local session = plainFromType(sessionType, attribute)
    for i, src in ipairs(session.combatSources) do
        src.sourceGUID = secretMarker           -- em combate o GUID e opaco
        src.isLocalPlayer = i == 1              -- so a propria linha da para casar
    end
    return session
end
C_DamageMeter.GetCombatSessionSourceFromType = function(_, _, guid)
    if guid == secretMarker then
        error("Secret values are only allowed during untainted execution")
    end
    return { totalAmount = 1, amountPerSecond = 1 }
end

local combatRows = ns.Data.GetRows(0, "damage", { "damage", "healing" }, 5, false)
if not combatRows or not combatRows[1] then
    print("  ERRO  nenhuma linha em combate — a janela ficaria vazia")
    os.exit(1)
end
print("  ok    " .. #combatRows .. " linha(s) mesmo com guid secret")
if combatRows[1].values[1] == nil then
    print("  ERRO  a coluna ordenada precisa de valor mesmo em combate")
    os.exit(1)
end
print("  ok    coluna ordenada preenchida em combate")

issecretvalue = realIsSecret
C_DamageMeter.GetCombatSessionFromType = plainFromType
C_DamageMeter.GetCombatSessionSourceFromType = function(sessionType, attribute, guid)
    local byAttribute = {
        [Enum.DamageMeterType.HealingDone] = { totalAmount = 600000, amountPerSecond = 5000 },
    }
    return byAttribute[attribute] or { totalAmount = 42000, amountPerSecond = 350 }
end

print("== sessao vazia por tipo (cenario do reset) ==")
-- SIMULA_RESET: depois de zerar, a sessao "atual" volta vazia enquanto a luta acontece.
-- Os dados so aparecem pela sessao por id — sem o fallback, a janela fica em branco.
local originalFromType = C_DamageMeter.GetCombatSessionFromType
C_DamageMeter.GetCombatSessionFromType = function()
    return { combatSources = {}, totalAmount = 0, maxAmount = 0, durationSeconds = 0 }
end
C_DamageMeter.GetCombatSessionFromID = function(id, attribute)
    return originalFromType(0, attribute)
end

local fallbackRows = ns.Data.GetRows(0, "damage", { "damage", "dps" }, 5, false)
if fallbackRows and fallbackRows[1] then
    print("  ok    fallback por id devolveu " .. #fallbackRows .. " linha(s)")
else
    print("  ERRO  fallback por id nao devolveu linhas — janela ficaria vazia em combate")
    os.exit(1)
end

C_DamageMeter.GetCombatSessionFromType = originalFromType
C_DamageMeter.GetCombatSessionFromID = function() return nil end

print("== formato dos numeros ==")
-- Regressao: AbbreviateNumbers do cliente devolvia texto longo e a coluna virava reticencias.
check("milhoes", ns.Data.FormatAmount(2900000), "2.9M")
check("centenas de milhar", ns.Data.FormatAmount(786000), "786K")
check("milhares com decimal", ns.Data.FormatAmount(9600), "9.6K")
check("valor pequeno inteiro", ns.Data.FormatAmount(847), "847")

-- TETO DE LARGURA. A celula tem 50px; texto maior nao e cortado, vira reticencias -- foi a
-- reclamacao "esses pontos me incomoda" depois de uma corrida de 28 minutos. As duas faixas
-- abaixo nao existiam: 339 milhoes davam "339.1M" (6) e 1,2 bilhao dava "1234.6M" (7).
check("centenas de milhao sem decimal", ns.Data.FormatAmount(339123456), "339M")
check("bilhoes tem faixa propria", ns.Data.FormatAmount(1234567890), "1.2B")
check("negativo grande tambem", ns.Data.FormatAmount(-339123456), "-339M")

do
    -- Inclui os pontos de ARREDONDAMENTO, nao so os limiares redondos: e ali que a mantissa
    -- ganha um digito e o texto estoura (99.999.999 dava "100.0M").
    local piores = { 0, 1, 999, 1000, 9994, 9995, 9999, 10000, 999999, 1000000,
                     99949999, 99950000, 99999999, 100000000, 999499999, 999500000,
                     999999999, 1000000000, 9999999999 }
    local maior, culpado = 0, nil
    for _, v in ipairs(piores) do
        local t = ns.Data.FormatAmount(v)
        if #t > maior then maior, culpado = #t, t end
    end
    check("nenhum valor passa do teto (" .. tostring(culpado) .. ")",
        maior <= ns.Data.MAX_CELL_CHARS, true)
end

print("== linhas ==")
ns.Window.SetRows(5)
check("altura padrao mostra 5 jogadores", ns.Window.GetRows(), 5)
ns.Window.SetRows(12)
check("stepper muda a quantidade", ns.Window.GetRows(), 12)
ns.Window.SetRows(0)
check("minimo respeitado", ns.Window.GetRows(), 1)
ns.Window.SetRows(99)
check("maximo respeitado", ns.Window.GetRows(), 20)
ns.Window.SetRows(5)

print("== rolagem ==")
-- Com 3 atores e janela de 2 linhas, rolar uma posicao mostra o 2o e o 3o.
local scrolled, _, totalActors = ns.Data.GetRows(0, "damage", { "damage" }, 2, false, 1)
check("total de atores", totalActors, 3)
check("rolagem pula o primeiro", scrolled[1].source.name, "Brumm")
check("janela mostra 2 linhas", #scrolled, 2)

local clamped = ns.Data.GetRows(0, "damage", { "damage" }, 2, false, 99)
check("rolagem excessiva nao estoura", clamped ~= nil and #clamped > 0, true)

print("== lider e o melhor de TODOS, nao da pagina ==")
-- Reclamacao do usuario (05/09): "eu rolo e ele vai trocando". O realce era calculado sobre a
-- fatia visivel, entao dizia "o melhor entre os que voce esta vendo" — que nao significa nada.
-- O harness tem 3 atores; com janela de 2, a segunda pagina nao contem o lider de dano e
-- portanto nao pode ter NINGUEM marcado.
local pagina1 = ns.Data.GetRows(0, "damage", { "damage" }, 2, false, 0)
local pagina2 = ns.Data.GetRows(0, "damage", { "damage" }, 2, false, 1)

check("o primeiro colocado e o lider", pagina1[1].best ~= nil and pagina1[1].best[1] == true, true)
check("o segundo da primeira pagina nao e lider",
    pagina1[2].best ~= nil and pagina1[2].best[1] == true, false)
check("rolar nao promove ninguem",
    pagina2[1].best ~= nil and pagina2[1].best[1] == true, false)
check("nem na ultima linha",
    pagina2[2] ~= nil and pagina2[2].best ~= nil and pagina2[2].best[1] == true, false)

-- Trocar a coluna de ordenacao tambem nao pode mexer em quem lidera cada coluna.
local porDano = ns.Data.GetRows(0, "damage", { "damage", "healing" }, 3, false, 0)
local porCura = ns.Data.GetRows(0, "healing", { "damage", "healing" }, 3, false, 0)
local function lider(lista, coluna)
    for i = 1, #lista do
        if lista[i].best and lista[i].best[coluna] then return lista[i].source.name end
    end
end
check("o lider de dano nao muda com a ordenacao",
    lider(porDano, 1), lider(porCura, 1))

print("== degrade da faixa ==")
-- Regressao da 0.50.0: a faixa era pintada chapada com a cor cheia da classe
-- (`SetStatusBarColor(ns.ClassColor(...))`), e por isso saia visivelmente mais clara que a do
-- medidor nativo, que vai de ~52% a ~84% da cor ao longo do comprimento. Se alguem voltar a
-- chapar, estes checks caem.
local pintado = { gradiente = nil, chapado = nil }
local faixa = {
    GetStatusBarTexture = function()
        return {
            SetGradient = function(_, orientacao, minCor, maxCor)
                pintado.gradiente = { orientacao = orientacao, min = minCor, max = maxCor }
            end,
        }
    end,
    SetStatusBarColor = function(_, r, g, b)
        pintado.chapado = { r, g, b }
    end,
}

ns.ApplyBarColor(faixa, "MAGE")
check("degrade aplicado", pintado.gradiente ~= nil, true)
check("degrade na horizontal", pintado.gradiente.orientacao, "HORIZONTAL")
-- Mage e 0.4/0.8/0.9 no simulador; as pontas sao 52% e 84% disso.
check("ponta esquerda escurecida", string.format("%.3f", pintado.gradiente.min.r), "0.208")
check("ponta direita mais clara", string.format("%.3f", pintado.gradiente.max.r), "0.336")
check("cor de vertice neutra antes do degrade", pintado.chapado[1], 1)
check("faixa nunca recebe a cor cheia", pintado.gradiente.max.b < 0.9, true)

print("== placar: retrato ==")
-- O placar NAO le mais a sessao viva: le sempre um retrato solto. Tres produtores (corrida
-- que acabou, corrida guardada em disco, simulacao) e um caminho de desenho so. O contrato do
-- retrato e `values` indexado pela CHAVE da coluna — nao pela posicao, que nao sobrevive a uma
-- mudanca na lista de colunas entre o dia da gravacao e o dia da leitura.
local run = ns.Demo.Run()

check("corrida marcada como simulacao", run.demo, true)
check("simulacao e do tipo mplus", run.kind, "mplus")
check("cinco jogadores", #run.rows, 5)
check("valores indexados por chave", run.rows[1].values.dps, 103000)
check("nao ha valores por posicao", run.rows[1].values[1], nil)
check("a linha carrega a classe", run.rows[1].classFilename, "DEATHKNIGHT")
check("a linha carrega a funcao", run.rows[1].role, "TANK")

-- Os totais sao reconstruidos por taxa * tempo em combate: se alguem mexer num sem mexer no
-- outro, as colunas param de fechar entre si e o placar mostra numeros que se contradizem.
check("dano reconstruido do dps",
    run.rows[1].values.damage, run.rows[1].values.dps * run.combatSeconds)
check("tempo em combate menor que a corrida", run.combatSeconds < run.durationSeconds, true)

print("== placar: corridas guardadas ==")
-- "Ver o ultimo placar" so funciona se a corrida tiver sido copiada para fora da sessao no
-- momento certo: a sessao do C_DamageMeter e zerada pela proxima luta.
-- O CHALLENGE_MODE_COMPLETED do ciclo de vida (bem la em cima) ja deve ter capturado e
-- gravado: e esse o caminho que faz o botao "Ultimo Mitico+" ter o que mostrar.
check("o fim da corrida gravou sozinho", ns.Scoreboard.HasRun("mplus"), true)
-- O ENCOUNTER_END tambem disparou, mas IsInRaid() e falso no simulador: em masmorra quem
-- manda e o CHALLENGE_MODE_COMPLETED, e o caminho de raide tem que sair cedo.
check("encounter fora de raide nao grava placar de raide", ns.Scoreboard.HasRun("raid"), false)

local guardada = ns.Scoreboard.Snapshot({ kind = "mplus", title = "Teste", level = 12,
    durationSeconds = 1500, sessionType = 1 })
check("o retrato tem linhas", #guardada.rows > 0, true)
check("o retrato carimba a hora", type(guardada.recordedAt), "number")
check("o retrato guarda por chave", type(guardada.rows[1].values.dps), "number")
check("o retrato guarda TODAS as metricas, nao so as visiveis",
    guardada.rows[1].values.taken ~= nil and guardada.rows[1].values.dispels ~= nil, true)

ns.Scoreboard.SaveRun("mplus", guardada)
check("agora ha corrida de mplus", ns.Scoreboard.HasRun("mplus"), true)
check("raide continua vazia", ns.Scoreboard.HasRun("raid"), false)
check("gravou no SavedVariable proprio, fora da configuracao",
    RocketMeterRunsDB ~= nil and RocketMeterRunsDB.mplus == guardada, true)

-- Profile.Reset apaga a CONFIGURACAO. Nao pode levar as corridas junto.
ns.Profile.Reset()
check("restaurar o padrao nao apaga as corridas", ns.Scoreboard.HasRun("mplus"), true)

-- Nada no retrato pode ser secret: SavedVariables nao serializa valor opaco.
local function temSecret(t, profundidade)
    if profundidade > 6 then return false end
    for k, v in pairs(t) do
        if issecretvalue(k) or issecretvalue(v) then return true end
        if type(v) == "table" and temSecret(v, profundidade + 1) then return true end
    end
    return false
end
check("retrato nao carrega secret value", temSecret(guardada, 0), false)

print("== corpos de fonte ==")
-- A descida foi 16 -> 14 -> 13 -> 12, cada degrau pedido depois de teste in-game. O que este
-- bloco tranca nao e o numero em si, e sim que a LINHA tem corpo unico e que as telas com
-- corpo proprio (titulo, cabecalho de coluna, painel de detalhamento) NAO seguem a linha —
-- eles sao valores absolutos, e ja se perderam rodadas por alguem tratar um deles como delta.
local function spyFontString()
    local fs = {}
    function fs.SetFont(_, path, size, flags)
        fs.path, fs.size, fs.flags = path, size, flags
        return true
    end
    -- `GetFont` existe porque a guarda de fonte invalida do addon pergunta por ela: sem isso o
    -- espiao divergiria da API justamente no caminho que ele deveria testar.
    function fs.GetFont() return fs.path, fs.size, fs.flags end
    function fs.SetShadowOffset() end
    function fs.SetShadowColor() end
    function fs.SetAlpha() end
    function fs.GetWidth() return 40 end
    function fs.SetWidth() end
    function fs.SetText() end
    function fs.SetTextColor(_, r, g, b) fs.color = { r, g, b } end
    function fs.SetJustifyH() end
    function fs.GetJustifyH() return "LEFT" end
    return fs
end

local fs = spyFontString()
ns.ApplyFont(fs, 0)
-- A REFERENCIA E A JANELA DE CHAT DO USUARIO, e os numeros sao os que ELE configurou -- lidos
-- de `SavedVariables/Chattynator.lua`, nao inferidos de print:
--     message_font = "default"  -> Chattynator: fonts.default = "ChatFontNormal" -> ARIALN
--     message_font_size = 17
--     message_font_outline = "thin" -> "OUTLINE"
--     show_font_shadow = true
-- UM numero cravado, e so um: `ns.Skin.fontSize` e a fonte unica da verdade, e todo o resto e
-- conferido POR RELACAO a ela. Assim mudar o corpo e uma linha aqui, e nao seis.
check("corpo da linha e o que foi decidido", ns.Skin.fontSize, 16)
check("ApplyFont usa o corpo do Skin", fs.size, ns.Skin.fontSize)
check("linha usa a fonte do chat (Arial Narrow)", fs.path, ns.Skin.font)
check("a fonte e mesmo Arial Narrow", ns.Skin.font:find("ARIALN", 1, true) ~= nil, true)

-- UM CONTORNO SO PARA TUDO. A mistura anterior (celula sem contorno, nome com halo desenhado)
-- foi o que o usuario leu como "umas colunas parece ta com mais borda a fonte, outras nao".
check("linha com contorno", fs.flags, "OUTLINE")
do
    local celula = spyFontString()
    celula.classFilename = nil
    local linha = { cells = { celula }, classFilename = "MAGE" }
    ns.StyleCell(linha, 1, false, 0)
    check("celula usa o MESMO contorno da linha", celula.flags, fs.flags)
end

-- O placar NAO segue a janela: ele foi visto e aprovado em 12, e a janela subiu para 13
-- depois, a pedido. Herdar desfaria uma aprovacao que ja existe.
-- HIERARQUIA DA JANELA. Titulo, relogio e cabecalho de coluna eram tres numeros ABSOLUTOS,
-- herdados de quando a linha era 13. Cada vez que o corpo da linha mudava -- e mudou seis
-- vezes -- a relacao se desfazia sozinha: chegou ao ponto de o titulo EMPATAR com a linha,
-- quando no medidor nativo ele e menor, e e o menor que da a hierarquia.
--
-- Agora sao deltas. Estes checks travam a relacao, que e o que precisa sobreviver a proxima
-- mudanca de corpo -- nao os numeros.
check("titulo e menor que a linha", ns.Skin.titleFontSize < ns.Skin.fontSize, true)
check("relogio e menor que o titulo", ns.Skin.clockFontSize < ns.Skin.titleFontSize, true)
check("cabecalho e o menor de todos", ns.Skin.colheadFontSize < ns.Skin.clockFontSize, true)
-- E nenhum pode despencar: hierarquia nao e sumir.
check("cabecalho nao fica ilegivel", ns.Skin.colheadFontSize >= ns.Skin.fontSize - 5, true)

-- O CONTORNO E O MESMO EM TODA A JANELA. Era isto que faltava quando o usuario disse "umas
-- colunas parece ta com mais borda a fonte, outras nao": as celulas iam sem contorno, o nome
-- ia com halo desenhado, e titulo/relogio/cabecalho iam sem nada.
do
    local titulo, relogio, cabecalho = spyFontString(), spyFontString(), spyFontString()
    ns.ApplyFont(titulo,   ns.Skin.titleFontSize   - ns.Skin.fontSize, ns.Skin.fontOutline)
    ns.ApplyFont(relogio,  ns.Skin.clockFontSize   - ns.Skin.fontSize, ns.Skin.fontOutline)
    ns.ApplyFont(cabecalho, ns.Skin.colheadFontSize - ns.Skin.fontSize, ns.Skin.fontOutline)

    check("titulo com o contorno da janela", titulo.flags, fs.flags)
    check("relogio com o contorno da janela", relogio.flags, fs.flags)
    check("cabecalho com o contorno da janela", cabecalho.flags, fs.flags)
    check("e os tres na mesma familia", titulo.path, ns.Skin.font)
end

-- E O DESENHO DE VERDADE TEM QUE DIZER O PAPEL. Sem este check, os tres poderiam continuar
-- desenhando com o corpo da linha e todos os checks de relacao acima passariam do mesmo jeito --
-- eles conferem a INTENCAO, nao o desenho.
do
    local arquivo = io.open("Window.lua")
    local texto = arquivo:read("*a")
    arquivo:close()

    local papeis = {}
    -- `(.-)%)` para no primeiro `)`, que e o fim da chamada: nenhuma delas tem parenteses
    -- aninhados antes disso.
    for chamada in texto:gmatch("ns%.ApplyRoleFont%((.-)%)") do
        for _, papel in ipairs({ "body", "title", "header" }) do
            if chamada:find('"' .. papel .. '"', 1, true) then papeis[papel] = true end
        end
    end
    check("as linhas desenham com o papel 'body'", papeis.body or false, true)
    check("o titulo desenha com o papel 'title'", papeis.title or false, true)
    check("o cabecalho desenha com o papel 'header'", papeis.header or false, true)

    -- E nenhum deles pode ter voltado a usar o corpo unico.
    check("ninguem desenha titulo ou cabecalho pelo corpo da linha",
        texto:find("ApplyFont(frame.header", 1, true) == nil
        and texto:find("ApplyFont(button.text", 1, true) == nil, true)
end

ns.ApplyScoreboardFont(fs, 0)
check("corpo do placar e proprio", fs.size, 12)
check("ns.Skin expoe o corpo do placar", ns.Skin.scoreboardFontSize, 12)

ns.ApplyPanelFont(fs, 0)
check("painel de detalhamento tem corpo proprio", fs.size, 13)

ns.ApplyFont(fs, -30)
check("piso de 6pt respeitado", fs.size, 6)

print("== ponta da faixa de titulo ==")
-- O atlas ui-damagemeters-header-bar tem 17px transparentes e depois uma rampa de alfa ate
-- ~x=70 (de 560): e o afunilamento que faz a faixa parecer uma fita, e e o que o rastreador
-- de missoes do jogo mostra. O recorte antigo comecava em 0.045 (x=25), no MEIO da rampa, e o
-- resultado era uma parede vertical de alfa 40. Se alguem voltar a recortar, isto cai.
check("faixa comeca no inicio do atlas", ns.Skin.headerCrop[1], 0)
check("faixa termina no fim do atlas", ns.Skin.headerCrop[2], 1)
check("sem recorte vertical (as bordas douradas moram nele)",
    ns.Skin.headerCrop[3] .. "," .. ns.Skin.headerCrop[4], "0,1")

print("== nome cross-realm ==")
-- Print de 05/09: as tres linhas mostravam "Magicpanda-Tic...", "Huntwave-Stor...",
-- "Szarazard-Ticho..." — nome e reino brigando pela mesma largura, reticencias comendo os dois.
-- A correcao NAO e apagar o reino (primeira tentativa, reprovada pelo usuario): e hierarquia,
-- com o reino um ponto abaixo do nome.
local nome, reino = ns.SplitName("Magicpanda-Tichondrius")
check("separa o nome", nome, "Magicpanda")
check("separa o reino, sem o hifen", reino, "Tichondrius")

nome, reino = ns.SplitName("Bolva")
check("nome sem reino volta inteiro", nome, "Bolva")
check("sem reino devolve nil", reino, nil)

-- Reino com espaco existe ("Nemesis", "Azralon", mas tambem "Ragnaros" vs "Nome-Reino Composto")
nome, reino = ns.SplitName("Thrall-Ragnaros Prime")
check("reino com espaco nao quebra", reino, "Ragnaros Prime")

check("nil nao estoura", (ns.SplitName(nil)), nil)
check("nao-string passa cru", (ns.SplitName(42)), 42)
check("delta do reino e -1", ns.REALM_FONT_DELTA, -1)

-- O reino e um ponto abaixo do nome — se o corpo da linha mudar, a diferenca acompanha.
local fsNome, fsReino = spyFontString(), spyFontString()
ns.ApplyFont(fsNome, 0)
ns.ApplyFont(fsReino, ns.REALM_FONT_DELTA)
-- O que precisa ficar travado e a RELACAO, nao o numero: o corpo da linha ja mudou quatro vezes
-- (16 -> 14 -> 13 -> 12 -> 13 -> 17) e um teste com valor cravado so obriga a reescrever o
-- teste junto. O reino e sempre um ponto abaixo do nome.
check("reino e exatamente um ponto abaixo do nome", fsNome.size - fsReino.size, 1)
check("nome usa o corpo da linha", fsNome.size, ns.Skin.fontSize)

print("== uma secao por metrica: tres classificacoes numa janela ==")
-- Pedido: *"qual seria a melhor forma de em uma janela ver uma ordenacao onde eu consiga ver quem
-- esta sendo o melhor em Dano/DPS, Cura/CPS e Interrupts"*.
--
-- A resposta e POSICAO, nao realce. Em combate os valores sao secret e o addon NAO consegue
-- descobrir quem e o maior -- comparar levanta erro. Mas a API devolve a lista ja ordenada pela
-- metrica pedida (o medidor da Blizzard nao ordena nada em Lua, so percorre e usa `index = i`),
-- entao uma consulta por metrica da uma classificacao pronta. O lider e a primeira linha.
do
    local secoes = ns.Data.GetSections(0, { "damage", "dps", "healing", "hps", "interrupts" }, 5)

    -- "Dano total" e "Dano por segundo" sao a MESMA metrica: dao UMA secao com dois numeros, nao
    -- duas secoes. E o que faz a tela de configuracao continuar valendo sem redesenho.
    check("tres metricas viram tres secoes", #secoes, 3)
    check("a primeira e Dano", secoes[1].key, "damage")
    check("  com as duas colunas dela", #secoes[1].columns, 2)
    check("a segunda e Cura", secoes[2].key, "healing")
    check("  tambem com duas", #secoes[2].columns, 2)
    check("a terceira e Interrupcoes", secoes[3].key, "interrupts")
    check("  com uma so", #secoes[3].columns, 1)

    -- O CABECALHO NOMEIA A FAMILIA, nao a coluna: "Dano", nao "Dano total".
    check("o cabecalho da secao e o nome da familia", secoes[1].label, ns.L["Damage"])

    -- CADA SECAO TEM A SUA PROPRIA REGUA. Sem isso a barra de cura seria medida contra o maior
    -- dano e ficaria sempre num fiapo.
    check("cada secao traz a propria sessao", secoes[1].session ~= secoes[2].session, true)
    check("e a propria regua", secoes[1].session.maxAmount ~= nil, true)

    -- E A ORDEM VEM DA API. O teste nao ordena nada: ele afirma que a lista que chegou ja esta
    -- ordenada, que e a propriedade da qual todo o desenho depende.
    local primeiro = secoes[1].rows[1].values[1]
    local segundo = secoes[1].rows[2] and secoes[1].rows[2].values[1]
    check("a secao ja vem ordenada pela API",
        segundo == nil or primeiro >= segundo, true)
end

do
    -- SECAO SEM NINGUEM NAO APARECE. Ninguem dissipou nada nesta sessao de teste.
    local secoes = ns.Data.GetSections(0, { "damage", "dispels" }, 5)
    for _, secao in ipairs(secoes) do
        check("secao vazia nao entrou (" .. secao.key .. ")", #secao.rows > 0, true)
    end
end

print("== cada FAMILIA e uma barra com escala propria ==")
-- O DESENHO ESCOLHIDO PELO USUARIO (opcao B): uma linha por pessoa, o numero dentro da barra.
--
-- A propriedade que o faz funcionar -- e que o faz funcionar EM COMBATE, onde comparar valor
-- secret levanta erro -- e que cada barra e escalada pela regua da PROPRIA familia. Assim o lider
-- daquela familia e a unica barra CHEIA dela: a geometria responde quem e o maior sem o Lua
-- precisar descobrir.
--
-- ⚑ "POR FAMILIA", nao "por coluna": dano e DPS dividem UMA barra (o bloco "o total e a taxa
-- dividem UMA barra" cobre isso). Este bloco usa tres familias de uma coluna cada, onde os dois
-- recortes coincidem -- e o que ele afirma e que familias diferentes nao compartilham regua.
do
    ns.db.columns = { "damage", "healing", "interrupts" }
    ns.db.rows = 5
    ns.Window.Show(false)
    ns.Window.Draw()

    -- O CABECALHO DE COLUNAS TEM QUE ESTAR NA TELA: este desenho TEM colunas, e sem o rotulo as
    -- barras sao tres retangulos coloridos sem assunto.
    check("o cabecalho de colunas esta na tela", ns.Window.DebugColumnHeaderShown(), true)

    local celulas = ns.Window.DebugCells(1)
    check("a primeira linha tem um numero por coluna", #celulas, 3)
    check("  e aqui cada um tem a barra dele", celulas[1].group ~= celulas[2].group, true)

    -- CADA COLUNA COM A SUA REGUA. Sem isso a barra de cura seria medida contra o maior dano e
    -- ficaria num fiapo em toda luta -- e a coluna deixaria de responder quem cura mais.
    local reguas = {}
    for _, c in ipairs(celulas) do reguas[c.scale] = true end
    local distintas = 0
    for _ in pairs(reguas) do distintas = distintas + 1 end
    check("familias diferentes nao compartilham regua", distintas > 1, true)
    check("e nenhuma caiu no 1 de fallback", reguas[1], nil)

    -- E O LIDER E A BARRA CHEIA. Em cada grupo, alguem tem valor igual a regua.
    --
    -- A regua e lida pela coluna que ORDENA o grupo (o total), porque e o valor dela que a barra
    -- desenha: as duas metricas de um grupo dariam a mesma proporcao, mas ler pelo total deixa
    -- explicito qual dos dois numeros a geometria esta contando.
    local grupos = ns.Data.GroupColumns(ns.db.columns)
    local porColuna = ns.Data.GetColumnScales(0, ns.db.columns)
    local posicaoDe = {}
    for i = 1, #ns.db.columns do posicaoDe[ns.db.columns[i]] = i end

    for c = 1, #grupos do
        local regua = porColuna[posicaoDe[grupos[c].keys[1]]]
        local cheia
        for linha = 1, ns.db.rows do
            local cell = ns.Window.DebugCells(linha)[c]
            if cell and cell.value == regua then cheia = linha end
        end
        check("o grupo " .. grupos[c].key .. " tem uma barra cheia", cheia ~= nil, true)
    end

    -- O NUMERO NAO GANHA COR DE CLASSE, nem o do lider. Pedido do usuario: *"nao precisa colocar
    -- cor do texto da cor da classe, por que a ideia e que o tamanho da barra ja vai dizer qual
    -- ta na frente e a linha de baixo que e da classe"*.
    --
    -- Ele esta certo em dois niveis: era um terceiro sinal dizendo o que a barra cheia e a faixa
    -- de classe ja diziam, e cor de classe e vocabulario reservado -- numero colorido le como
    -- "ladino", nao como "melhor".
    --
    -- O teste compara as cores de TODAS as linhas: se alguma diferir, alguem foi pintado.
    local cores = {}
    for linha = 1, ns.db.rows do
        for _, cel in ipairs(ns.Window.DebugCells(linha)) do
            cores[table.concat(cel.color, ",")] = true
        end
    end
    local tons = 0
    for _ in pairs(cores) do tons = tons + 1 end
    check("todo numero tem a mesma cor, inclusive o do lider", tons, 1)

    -- A LARGURA DA COLUNA SEGUE O QUE ELA ESCREVE. Pedido: *"precisa aumentar um pouco a largura
    -- das colunas, principalmente nas colunas onde o resultado e maior, Dano e Cura por exemplo"*.
    --
    -- Uma largura so para todas dava o mesmo espaco para "339M" e para "8": a primeira apertada,
    -- a segunda com metade vazia.
    do
        ns.db.columns = { "damage", "interrupts" }
        ns.Window.Rebuild()
        ns.Window.Draw()

        local larguras = ns.Window.DebugFirstRow().cellWidths
        check("dano (total) e mais largo que interrupcoes (contagem)",
            larguras[1] > larguras[2], true)
        -- A caixa do numero, nao a da coluna: e ela que decide se o texto vira reticencias.
        check("e a caixa do numero do dano passa dos 58 de antes", larguras[1] > 58, true)

        ns.db.columns = { "damage", "healing", "interrupts" }
        ns.Window.Rebuild()
        ns.Window.Draw()
        local iguais = ns.Window.DebugFirstRow().cellWidths
        check("dano e cura tem a mesma largura (mesmo formato)", iguais[1], iguais[2])
    end

    -- A COR DE CLASSE TEM UM LUGAR SO NA LINHA: a faixa do rodape cobre apenas a coluna do nome.
    --
    -- A FAIXA DE COR DE CLASSE SAIU (0.72.0). Ela era uma linha fina no rodape, limitada a coluna
    -- do nome, com o comprimento proporcional a metrica ordenada. Pedido do usuario:
    -- *"remove a linha da cor da classe da coluna do nome"*.
    --
    -- ⚑ E ISSO APAGOU DUAS VERIFICACOES QUE ERAM A REDE DE OUTRA COISA. Elas mediam a largura da
    -- faixa contra a janela, e a sabotagem de `MinWidth` era pega por ali: quando `MinWidth`
    -- deixava de somar as colunas, a area do nome ficava NEGATIVA e a faixa (que a acompanhava)
    -- denunciava. Sem a faixa, a invariante continua valendo e precisa de medida propria -- senao
    -- some junto o unico teste que pegava o defeito de 08/09.
    local primeira = ns.Window.DebugFirstRow()
    local geo = ns.Window.DebugGeometry()

    -- A AREA DO NOME NUNCA E NEGATIVA. Era isto que a largura da faixa denunciava de carona:
    -- quando `MinWidth` deixava de somar as colunas, `nameArea` ia a -111 e so o clamp de 40px
    -- segurava. Medir direto e mais honesto que medir pela sombra de outra coisa.
    check("a area do nome nunca e negativa", primeira.nameArea > 0, true)
    check("e as colunas cabem na janela", geo.columnsWidth < geo.width, true)

    -- A COR DE CLASSE NAO SUMIU DA LINHA: ela mora nas barras das metricas, que continuam
    -- pintadas por `ns.ApplyBarColor`. O que saiu foi o SEGUNDO lugar onde ela aparecia.
    check("a barra da primeira coluna tem cor", primeira.barColored, true)

    -- E O FUNDO PRETO NAO VOLTA. O usuario reprovou o preto DUAS vezes -- *"tira o fundo preto
    -- com algum percentual de opacidade"* e *"o fundo preto e feio"* -- e depois pediu uma pista
    -- TINGIDA, que e outra coisa: mesma familia de cor da barra, nao um bloco escuro.
    --
    -- ⚑ ESTE CHECK ERA VAZIO ate 08/09: ele contava o CAMPO `faixa.track`, que nunca era criado.
    -- Passava com qualquer trilho de outro nome. Agora mede a TINTA.
    check("nenhuma pista e preta", primeira.cellTracksBlack, 0)

    -- O NOME NAO PODE FICAR ESPREMIDO. Com tres colunas de 58 numa janela de 340, sobra espaco de
    -- verdade; foi com SETE colunas que ele caiu para 57px e o nome virou reticencias.
    check("o nome tem largura de verdade", ns.Window.DebugFirstRow().nameArea > 60, true)
end

print("== a pista e a faisca: so onde ha caminho ==")
-- PEDIDO DO USUARIO, 08/09: *"eu quero Faisca na ponta e Pista tingida. Sem fundo preto, mas com
-- a condicao que se tiver zerado fica sem a pista tingida, somente quando tiver algum valor"*.
--
-- ⚑ E ISSO PARECE IMPOSSIVEL EM COMBATE, mas nao e. Quando o jogador esta AUSENTE de uma metrica,
-- quem escreve o zero e o proprio addon (Data.lua: "Ausente numa lista que sabemos ler = o jogador
-- nao pontuou ali. E zero.") -- numero comum, legivel sempre. So o valor PRESENTE vem secret, e
-- esse por definicao nao e o caso de "zerado".
do
    ns.db.columns = { "damage", "healing" }
    ns.db.sortBy = "damage"
    ns.db.rows = 5
    ns.Window.Show(false)
    ns.Window.Rebuild()
    ns.Window.Draw()

    -- A primeira linha e de quem lidera o dano. Ela tem dano; pode nao ter cura.
    local linhas = ns.Data.GetRows(0, "damage", ns.db.columns, ns.db.rows)
    local primeira = ns.Window.DebugFirstRow()

    check("quem tem dano tem pista no dano", primeira.cellTracks[1] ~= false, true)
    check("  e a pista e da cor da classe, nao preta",
        primeira.cellTracks[1][1] ~= 0 or primeira.cellTracks[1][2] ~= 0, true)
    check("  com o alfa apagado da referencia", primeira.cellTracks[1][4], 0.15)
    check("e a faisca aparece junto", primeira.cellSparks[1], true)

    -- ⚑ E ELA ESTA PRESA NA TEXTURA DE PREENCHIMENTO, nao na moldura. E a afirmacao central:
    -- ancorada ali, ela acompanha a ponta porque quem redimensiona aquele objeto e o MOTOR --
    -- o Lua nunca le o valor, que em combate e opaco. Presa na moldura, ficaria parada na borda
    -- direita e nao diria nada sobre progresso, sem que nada estourasse.
    --
    -- A fonte do 12.1.0 faz assim em seis lugares (linha do tempo de encontro, gerenciador de
    -- recargas, barra de honra, barras de widget), um deles movido por valor secret.
    -- E PELAS DUAS PONTAS. Presa so pela direita com largura fixa, ela fica MAIOR que a barra
    -- quando a barra e pequena, e o excedente sai pela esquerda -- lendo como uma seta para tras.
    -- Foi o defeito de 08/09, com print: "o brilho quando a barra ta quase num tamanho minimo, ta
    -- ficando parecendo que vai andar pra tras".
    --
    -- Nao da para consertar medindo: `GetWidth()` na textura de preenchimento e SECRET, porque ela
    -- e ancorada por valor opaco. Prender as duas pontas resolve por CONSTRUCAO -- a largura do
    -- brilho passa a ser a do preenchimento sem ninguem precisar saber qual e.
    check("a faisca esta presa no preenchimento pelas duas pontas",
        primeira.cellSparkOnFill[1], true)
    check("  em todos os grupos", primeira.cellSparkOnFill[2], true)

    -- Uma terceira verificacao seria redundante e o simulador nao a sustentaria: com as duas
    -- pontas ancoradas, qualquer `SetWidth` e ignorado pelo motor -- e aqui todo widget nasce com
    -- largura 400, entao "largura propria" e indistinguivel de "largura nunca definida".

    -- E ONDE NAO HA VALOR, NADA. "Sem valor" sao DOIS casos, e os dois tem que esconder a pista:
    --
    --   `0`   -- o addon SABE que o jogador nao pontuou ali (ele mesmo escreveu o zero);
    --   `nil` -- o addon nao conseguiu cruzar a identidade e nao sabe.
    --
    -- Pista embaixo de um traco anuncia um caminho que ninguem comecou; pista embaixo de "nao
    -- sei" e pior, porque inventa um caminho. Os dois somem.
    -- O caso e o do curandeiro que nao causou dano -- e o zero dele foi escrito pelo ADDON, nao
    -- pela API. E o que torna a regra possivel em combate.
    local semDano
    for i = 1, #linhas do
        local v = linhas[i].values[1]
        if v == nil or v == 0 then semDano = i break end
    end
    check("ha alguem sem dano nenhum na lista", semDano ~= nil, true)
    check("  e o valor dele e zero, nao desconhecido", linhas[semDano].values[1], 0)

    local zerada = ns.Window.DebugRow(semDano)
    check("quem nao causou dano nao ganha pista de dano", zerada.cellTracks[1], false)
    check("  nem faisca", zerada.cellSparks[1], false)
    check("  mas continua com a pista da cura, que ele tem", zerada.cellTracks[2] ~= false, true)
    check("  e com a faisca dela", zerada.cellSparks[2], true)
end

print("== o total e a taxa dividem UMA barra ==")
-- IDEIA DO USUARIO, 08/09: *"a barra que progride conforme quem ta melhor, ela vai desde a coluna
-- de dano ate o DPS, e mesma coisa pra Cura e CPS, como se fosse apenas uma barra"*.
--
-- Uma versao anterior tinha juntado os DOIS NUMEROS numa string so ("1.2M - 10K"); ele mandou
-- voltar. O que fica junto e a BARRA, nao o texto: duas colunas, dois numeros, uma barra
-- atravessando as duas. E a leitura que ele descreveu -- o comprimento diz quem esta na frente na
-- familia, e cada coluna responde a pergunta dela.
do
    ns.db.columns = { "damage", "dps", "healing", "hps", "interrupts" }
    ns.db.sortBy = "damage"
    ns.db.sortDesc = true
    ns.db.rows = 5
    ns.Window.Show(false)
    ns.Window.Rebuild()
    ns.Window.Draw()

    -- CINCO COLUNAS, CINCO NUMEROS. O texto voltou a ser um por coluna.
    local celulas = ns.Window.DebugCells(1)
    check("cinco colunas marcadas, cinco numeros", #celulas, 5)

    local linhas = ns.Data.GetRows(0, "damage", ns.db.columns, ns.db.rows)
    check("o primeiro numero e o total do dano",
        celulas[1].text, ns.Data.FormatAmount(linhas[1].values[1]))
    check("o segundo e a taxa, sozinha", celulas[2].text,
        ns.Data.FormatAmount(linhas[1].values[2]))
    check("e nenhum deles junta os dois", celulas[1].text:find(" - "), nil)

    -- MAS SAO TRES BARRAS, NAO CINCO: dano+DPS dividem uma, cura+CPS dividem outra.
    local vaos = ns.Window.DebugSpans()
    check("cinco colunas viram tres barras", #vaos, 3)
    check("o dano e o DPS estao na mesma", celulas[1].group, celulas[2].group)
    check("a cura e o CPS tambem", celulas[3].group, celulas[4].group)
    check("e interrupcoes tem a sua", celulas[5].group ~= celulas[4].group, true)

    -- E A BARRA ATRAVESSA AS DUAS COLUNAS. E a afirmacao central do pedido: a largura dela e a
    -- das duas somadas, nao a de uma.
    local larguraDano = ns.Window.DebugColumnWidth("damage")
    local larguraDps = ns.Window.DebugColumnWidth("dps")
    check("a barra do dano cobre as duas colunas",
        vaos[1].width, larguraDano + larguraDps)
    -- ⚑ O VAO VEM DE `GetGroupGap()`, e nao de `ns.Skin.groupGap`. O do Skin e o PADRAO, uma
    -- constante; o desenho usa o que o jogador configurou (09/09/2026). Comparar com o padrao
    -- passava so enquanto ninguem tivesse mexido no deslizador -- teste que so vale na
    -- configuracao de fabrica nao protege o addon de ninguem.
    check("  e o widget tem essa largura mesmo",
        vaos[1].barWidth, larguraDano + larguraDps - ns.Window.GetGroupGap())
    check("a de interrupcoes cobre uma so",
        vaos[3].width, ns.Window.DebugColumnWidth("interrupts"))

    -- ⚑ CADA NUMERO NUMA PONTA DA BARRA. Pedido do usuario, 08/09: *"se cada um ficasse alinhado
    -- em cada canto, ou seja, dano a esquerda, dps a direita"*.
    --
    -- O que mudou foi o PRINCIPIO que une os dois. Antes eles eram alinhados a direita, cada um
    -- na caixa da coluna dele, e o vao entre eles era o RESIDUO da largura da taxa: media 35,8px
    -- e variava 11px por linha, enquanto o vao entre familias DIFERENTES era 33 -- dois numeros
    -- da mesma familia mais longe entre si que dois de familias diferentes. Agora eles vao para
    -- as pontas e quem os une e a REGIAO COMUM: as duas extremidades de um recipiente pertencem
    -- ao recipiente. So funciona porque a barra ganhou pista tingida na 0.73.0.
    check("o dano encosta na ponta esquerda", celulas[1].align, "LEFT")
    check("e o DPS na direita", celulas[2].align, "RIGHT")

    -- E A CAIXA DE CADA UM NAO PASSA DA METADE. Com dois textos ancorados em pontas opostas,
    -- caixas generosas demais se sobrepoem no meio -- e sobreposicao de texto nao levanta erro,
    -- so fica ilegivel.
    local larguraFaixa = larguraDano + larguraDps - ns.Skin.groupGap
    check("nenhum dos dois passa da metade da barra",
        celulas[1].width + celulas[2].width <= larguraFaixa, true)

    -- ⚑ O ROTULO COMECA NO MESMO X QUE O NUMERO. Relatado com print em 09/09: *"o alinhamento
    -- do titulo do header com o comeco no inicio da barra, nao ta bem alinhado"*.
    --
    -- Eram 7px, de duas divergencias somadas: o cabecalho ainda dividia a folga entre familias
    -- em dois (`GROUP_GAP / 2`) enquanto a barra ja a tirava inteira da esquerda, e `headerRow`
    -- recuava `PADDING + 2` contra o `PADDING` da linha.
    --
    -- Nenhum teste olhava isso, e por um motivo que vale registrar: enquanto os dois eram
    -- alinhados a DIREITA, 7px de diferenca na esquerda nao apareciam. A mudanca para as pontas
    -- (0.76.0) tornou visivel um desencontro que ja existia.
    --
    -- Os dois lados vem de caminhos INDEPENDENTES -- o do cabecalho e o do desenho da linha --,
    -- que e o que faz a comparacao valer alguma coisa.
    local cabAlinha = ns.Window.DebugHeaders()
    check("o rotulo comeca no mesmo x que o numero", cabAlinha[1].inkX, celulas[1].inkX)
    check("  e o da cura tambem", cabAlinha[3].inkX, celulas[3].inkX)

    -- ⚑ CORPO UNICO NA LINHA INTEIRA. O CORPO DA FONTE NAO E UM SINAL.
    --
    -- Decisao do usuario de 05/09/2026, ja escrita em `ns.StyleCell` -- *"o corpo de fonte saiu da
    -- lista de sinais... o +1pt dava presenca ao lider, mas ao custo de os numeros de uma mesma
    -- coluna mudarem de tamanho de linha para linha: a regua vertical dancava"*.
    --
    -- ⚑ ELA NAO TINHA TESTE, e em 09/09 eu a desrespeitei: pus o companheiro do par tres pontos
    -- menor. Ele viu no jogo e mandou desfazer -- *"o texto cada um parece em uma escala ou
    -- tamanho de fonte diferente, ficou bizarro, esse tipo de erro nao pode mais acontecer"*.
    --
    -- E havia um agravante que so a tela mostrou: o degrau CRUZAVA o limiar do contorno (corpo 13,
    -- `OUTLINE_MIN_SIZE` 13), entao o companheiro perdia o contorno JUNTO com o tamanho. Duas
    -- mudancas de uma vez, e e por isso que leu como "escalas diferentes" e nao como hierarquia.
    --
    -- Este check e o que a decisao nunca teve. Vale para a linha INTEIRA, em qualquer ordenacao.
    do
        local corpos = {}
        for _, cel in ipairs(celulas) do corpos[cel.size or 0] = true end
        local quantos = 0
        for _ in pairs(corpos) do quantos = quantos + 1 end
        check("todo numero da linha tem o MESMO corpo", quantos, 1)
    end

    -- E CONTINUA VALENDO COM OUTRA COLUNA ORDENANDO: era exatamente ai que o degrau agia.
    ns.db.sortBy = "dps"
    ns.Window.Draw()
    do
        local porTaxa2 = ns.Window.DebugCells(1)
        local corpos = {}
        for _, cel in ipairs(porTaxa2) do corpos[cel.size or 0] = true end
        local quantos = 0
        for _ in pairs(corpos) do quantos = quantos + 1 end
        check("  inclusive ordenando pela taxa", quantos, 1)

        -- A HIERARQUIA QUE SOBROU E A COR, e ela nao mexe em metrica nenhuma: quem ordena fica
        -- claro, o companheiro apaga.
        local claro = table.concat(porTaxa2[2].color, ",")
        local apagado = table.concat(porTaxa2[1].color, ",")
        check("quem ordena fica mais claro que o companheiro", claro ~= apagado, true)
        check("  e o claro e o `Skin.text`", claro, table.concat(ns.Skin.text, ","))
        check("  e o apagado, o `Skin.dim`", apagado, table.concat(ns.Skin.dim, ","))
    end

    ns.db.sortBy = "damage"
    ns.Window.Draw()

    -- ⚑ E O CABECALHO VAI JUNTO. O rotulo tem que ficar em cima do numero que ele nomeia -- e o
    -- botao em cima da fatia que ele ordena. Sem isso, "Dano" apareceria colado em "DPS" enquanto
    -- os numeros ficam nas pontas, e clicar no lugar errado ordenaria pela metrica errada.
    local cab = ns.Window.DebugHeaders()
    check("o rotulo do dano encosta na mesma ponta", cab[1].align, "LEFT")
    check("e o do DPS na dele", cab[2].align, "RIGHT")

    -- E A BARRA COMECA ONDE A COLUNA DELA COMECA, medido no widget pelo mesmo motivo.
    -- ⚑ A FOLGA SAI DA ESQUERDA DO GRUPO, entao a borda DIREITA da faixa continua colada na
    -- borda direita da coluna -- e e isso que mantem o cabecalho em cima do numero que ele nomeia.
    -- Tirando dos dois lados, os dois se afastariam e a coluna deixaria de ter uma borda so.
    check("a barra da cura e ancorada no vao dela", vaos[2].anchorX, -vaos[2].offset)
    check("  e a do dano no vao dela", vaos[1].anchorX, -vaos[1].offset)
    check("  que sao vaos diferentes", vaos[1].offset ~= vaos[2].offset, true)

    -- ⚑ E QUEM ESTA SOZINHO FICA NO CENTRO. Pedido do usuario, na mesma mensagem: *"quando a
    -- coluna tiver apenas um valor, fica centralizado"*.
    --
    -- E o que impede a janela de ficar com DUAS gramaticas -- uma para quem tem par e outra para
    -- quem nao tem. Interrupcoes, mortes e absorvido nao tem companheiro, e encostar o numero
    -- numa ponta arbitraria seria escolher um canto sem razao. Centrado, a regra e a mesma dos
    -- pares: o recipiente posiciona o que ele contem.
    check("interrupcoes, sozinha, fica centralizada", celulas[5].align, "CENTER")
    check("  e o rotulo dela tambem", ns.Window.DebugHeaders()[5].align, "CENTER")

    -- A BARRA MEDE O TOTAL, e a razao e que **so o total tem regua**.
    --
    -- `Data.GetColumnScales` devolve `session.maxAmount`, que e o maior `totalAmount` da sessao.
    -- Nao ha um maximo de `amountPerSecond` na API, e descobrir um em Lua esbarra no valor secret.
    -- Encher a barra com a taxa dividida pela regua do total daria um fiapo em toda linha.
    check("a barra mede o total do grupo", celulas[1].value, linhas[1].values[1])
    check("  medido pela regua do total", celulas[1].scale,
        ns.Data.GetColumnScales(0, ns.db.columns)[1])

    -- E A COLUNA DA TAXA COMPARTILHA ESSA BARRA, em vez de ter uma medida contra a regua errada.
    --
    -- ⚑ DEFEITO QUE ISTO CORRIGE, e ele e anterior a este pedido: quando cada coluna tinha a
    -- propria barra, a do DPS desenhava a TAXA sobre a regua do TOTAL -- um fiapo em toda linha,
    -- desde sempre. Ninguem tinha reparado porque o olho le a coluna do dano ao lado.
    check("a coluna da taxa nao tem barra propria", celulas[2].value, celulas[1].value)
    check("  nem regua propria", celulas[2].scale, celulas[1].scale)

    -- E ORDENAR PELA TAXA NAO MUDA A BARRA: a lista se reordena, a regua e a mesma.
    ns.db.sortBy = "dps"
    ns.Window.Draw()
    local porTaxa = ns.Window.DebugCells(1)
    check("ordenado por DPS, a barra segue medindo o total",
        porTaxa[1].value, porTaxa[2].value)

    -- E O LIDER E A BARRA CHEIA, em cada grupo: alguem tem valor igual a regua.
    for g = 1, #vaos do
        local cheia
        for linha = 1, ns.db.rows do
            for _, cel in ipairs(ns.Window.DebugCells(linha)) do
                if cel.group == g and cel.value == cel.scale then cheia = linha end
            end
        end
        check("a barra " .. g .. " tem um dono cheio", cheia ~= nil, true)
    end

    ns.db.sortBy = "damage"
    ns.db.columns = { "damage", "healing", "interrupts" }
    ns.Window.Rebuild()
end

print("== os pontinhos separam o trio, e so o trio ==")
-- PEDIDO DO USUARIO: *"quando tiver 3, pode usar aquele micropontinhos, os bem pequenos pra
-- separar de alguma forma"*.
--
-- ⚑ E SO COM TRES, de proposito. Com DOIS os numeros estao nas duas pontas da barra, longe um do
-- outro: um ponto solto no meio nao separaria nada -- pareceria sujeira. Com tres, os vizinhos se
-- aproximam e a marca passa a ter trabalho.
do
    ns.db.columns = { "damage", "dps", "interrupts" }
    ns.db.sortBy = "damage"
    ns.db.rows = 5
    ns.Window.Show(false)
    ns.Window.Rebuild()
    ns.Window.Draw()

    local doisMembros = ns.Window.DebugFirstRow()
    check("com dois numeros, nenhum pontinho", doisMembros.cellDots[1], 0)
    check("  e com um numero, tambem nao", doisMembros.cellDots[2], 0)

    -- O TRIO NAO E HIPOTETICO: dano + DPS + dano% vem de fabrica em duas das tres predefinicoes.
    ns.db.columns = { "damage", "dps", "damagepct", "interrupts" }
    ns.db.sortBy = "damage"
    ns.Window.Rebuild()
    ns.Window.Draw()

    local trio = ns.Window.DebugFirstRow()
    check("com tres numeros, dois pontinhos", trio.cellDots[1], 2)
    check("  e a coluna sozinha continua sem nenhum", trio.cellDots[2], 0)

    -- E OS TRES SE ESPALHAM: esquerda, centro, direita.
    local celulasTrio = ns.Window.DebugCells(1)
    check("o primeiro do trio na esquerda", celulasTrio[1].align, "LEFT")
    check("  o do meio, centrado", celulasTrio[2].align, "CENTER")
    check("  e o ultimo na direita", celulasTrio[3].align, "RIGHT")

    ns.db.columns = { "damage", "healing", "interrupts" }
    ns.db.sortBy = "damage"
    ns.Window.Rebuild()
end

print("== a ordem de dano e DPS e travada ==")
-- PEDIDO DO USUARIO: *"vamos bloquear para que a coluna de Dano sempre venha primeiro que a DPS e
-- assim com a cura sempre na frente do CPS"*.
--
-- Nao e arrumacao: e o que torna a barra unica possivel. Um grupo so pode virar UMA faixa
-- continua se as colunas dele forem vizinhas -- com {dano, cura, DPS} a barra do dano teria que
-- atravessar por baixo de um numero de cura.
do
    local ordenada = ns.Data.NormalizeColumns({ "dps", "damage" })
    check("a taxa marcada primeiro vai para tras", table.concat(ordenada, ","), "damage,dps")

    local intercalada = ns.Data.NormalizeColumns({ "damage", "healing", "dps", "hps" })
    check("lista intercalada volta agrupada",
        table.concat(intercalada, ","), "damage,dps,healing,hps")

    -- E A FAMILIA QUE APARECEU PRIMEIRO CONTINUA NA FRENTE: travar a ordem DENTRO do grupo nao
    -- pode reordenar os grupos entre si -- isso e escolha do jogador.
    local curaNaFrente = ns.Data.NormalizeColumns({ "healing", "damage" })
    check("quem pos cura na frente continua com ela na frente",
        table.concat(curaNaFrente, ","), "healing,hps,damage,dps")

    -- COMPLETA O PAR: item que o jogador ve como um so tem que estar inteiro na tela.
    local so_total = ns.Data.NormalizeColumns({ "damage", "interrupts" })
    check("total sem a taxa ganha a taxa",
        table.concat(so_total, ","), "damage,dps,interrupts")

    -- A porcentagem NAO entra no par -- e outra pergunta ("quanto do total do grupo"), e o
    -- usuario nao pediu para ela vir junto. Mas quando marcada, entra na familia, depois da taxa.
    local com_pct = ns.Data.NormalizeColumns({ "damagepct", "damage" })
    check("a porcentagem fica depois da taxa",
        table.concat(com_pct, ","), "damage,dps,damagepct")

    check("normalizar de novo nao muda mais nada",
        table.concat(ns.Data.NormalizeColumns(com_pct), ","), "damage,dps,damagepct")

    local _, mudou = ns.Data.NormalizeColumns({ "damage", "dps" })
    check("e ela avisa quando NAO mexeu", mudou, false)

    -- Chave repetida na lista salva entra uma vez so.
    check("chave repetida nao duplica a coluna",
        table.concat(ns.Data.NormalizeColumns({ "damage", "damage" }), ","), "damage,dps")
end

print("== dano e DPS sao UM item na configuracao ==")
-- PEDIDO DO USUARIO: *"onde escolhe as colunas na configuracao o dano e dps e cura e cps tem que
-- ser um so item"*. Total e taxa sao a mesma medida em duas unidades -- oferecer as duas como
-- escolhas separadas pedia uma decisao que ele nao tem por que tomar.
do
    local items = ns.Data.GetColumnItems()
    local todas = ns.Data.GetColumns()

    check("o catalogo tem 14 colunas", #todas, 14)
    check("mas a tela oferece 11 itens", #items, 11)

    local porChave = {}
    for _, item in ipairs(items) do porChave[item.key] = item end

    check("dano e um item de duas colunas", #porChave["damage"].keys, 2)
    check("  e a segunda e o DPS", porChave["damage"].keys[2], "dps")
    check("cura tambem", table.concat(porChave["healing"].keys, ","), "healing,hps")

    -- A REGRA E POR FORMA, nao por uma lista de nomes: dano recebido tem total e taxa igual, e
    -- trata-lo de outro jeito seria arbitrario.
    check("dano recebido segue a mesma regra",
        table.concat(porChave["taken"].keys, ","), "taken,takenps")

    check("interrupcoes continua sozinha", #porChave["interrupts"].keys, 1)
    check("e a porcentagem tem item proprio", #porChave["damagepct"].keys, 1)

    -- O DPS NAO APARECE DUAS VEZES: ele e a segunda metade do item do dano, nao um item.
    check("a taxa nao vira item sozinha", porChave["dps"], nil)

    -- O ROTULO NOMEIA OS DOIS.
    check("o rotulo do item traz as duas metades",
        porChave["damage"].label,
        ns.Data.GetColumn("damage").label .. " / " .. ns.Data.GetColumn("dps").short)

    -- E QUALQUER UMA DAS CHAVES ACHA O ITEM: e por isso que ligar pelo DPS liga o par.
    check("o DPS aponta para o item do dano", ns.Data.GetItemFor("dps").key, "damage")

    -- LIGAR E DESLIGAR LEVA AS DUAS COLUNAS.
    ns.db.columns = { "interrupts" }
    ns.db.sortBy = "interrupts"
    ns.Window.ToggleColumn("dps")
    check("ligar pelo DPS traz o dano junto",
        table.concat(ns.db.columns, ","), "interrupts,damage,dps")

    ns.Window.ToggleColumn("damage")
    check("e desligar pelo dano leva o DPS junto",
        table.concat(ns.db.columns, ","), "interrupts")

    -- E LIGAR NORMALIZA A LISTA, nao so acrescenta no fim. O caso que separa os dois: a
    -- porcentagem do dano ja marcada, e o par do dano entrando depois -- sem normalizar, a lista
    -- fica {dano%, dano, DPS} e a barra do dano teria que atravessar por baixo da porcentagem.
    ns.db.columns = { "damagepct" }
    ns.db.sortBy = "damagepct"
    ns.Window.ToggleColumn("damage")
    check("ligar o par reordena a familia inteira",
        table.concat(ns.db.columns, ","), "damage,dps,damagepct")

    -- E A JANELA NAO FICA SEM COLUNA. Com item de duas, "sobra uma" deixou de ser a conta.
    ns.db.columns = { "damage", "dps" }
    ns.db.sortBy = "damage"
    ns.Window.ToggleColumn("damage")
    check("desligar o ultimo item nao esvazia a janela", #ns.db.columns, 2)

    ns.db.columns = { "damage", "healing", "interrupts" }
    ns.db.sortBy = "damage"
    ns.Window.Rebuild()
end

print("== em combate cada numero se vira sozinho ==")
-- ⚑ O RISCO QUE SOBROU DA VERSAO MESCLADA, e ele so existe EM COMBATE.
--
-- A versao que juntava os dois numeros precisava de um caminho especial: para concatenar era
-- preciso LER, e valor secret nao se le -- na pratica ela mostrava "- - -" e o numero sumia. Com
-- os textos separados esse risco acabou: cada um passa sozinho por `SetCellText`, que ja tem a
-- sondagem de valor secret.
--
-- O que NASCEU no lugar e a barra unica: ela recebe `SetMinMaxValues` e `SetValue` com valores
-- que em combate sao opacos. Repassar para widget e permitido; ler nao. Este bloco afirma as
-- duas coisas -- que o desenho nao levanta erro, e que o numero continua aparecendo.
do
    ns.db.columns = { "damage", "dps", "interrupts" }
    ns.db.sortBy = "damage"
    ns.db.rows = 5
    ns.Window.Show(false)
    ns.Window.Rebuild()
    ns.Window.Draw()

    local opaco = setmetatable({}, {
        __concat = function() error("attempt to concatenate a secret value", 2) end,
        __lt = function() error("attempt to compare a secret value", 2) end,
        __add = function() error("attempt to perform arithmetic on a secret value", 2) end,
        __tostring = function() return "SECRET" end,
    })
    local realIsSecret = issecretvalue
    issecretvalue = function(v) return v == opaco end

    -- A FAMILIA DO DANO FICA OPACA, lida do catalogo: cravar o numero do enum aqui faria o teste
    -- passar a mentir no dia em que ele mudasse.
    local attrDano = ns.Data.GetColumn("damage").attr

    local realGetSession = ns.Data.GetSession
    ns.Data.GetSession = function(sessionType, attr)
        local session = realGetSession(sessionType, attr)
        if session and attr == attrDano then
            -- SO O TOTAL FICA OPACO; a taxa continua legivel.
            --
            -- E de proposito, e e o que torna este teste capaz de provar alguma coisa: com os
            -- dois opacos, os dois textos sairiam iguais e "cada um se vira sozinho" seria
            -- indistinguivel de "os dois vieram do mesmo caminho". Com um opaco e o outro nao, a
            -- celula da taxa TEM que mostrar um numero formatado -- e era exatamente isso que a
            -- versao mesclada nao conseguia fazer.
            --
            -- `maxAmount` tambem vem opaco em combate, e e ele que vira a regua da barra.
            local copia = { maxAmount = opaco, totalAmount = session.totalAmount,
                durationSeconds = session.durationSeconds, combatSources = {} }
            for i, src in ipairs(session.combatSources) do
                local clone = {}
                for k, v in pairs(src) do clone[k] = v end
                clone.totalAmount = opaco
                copia.combatSources[i] = clone
            end
            return copia
        end
        return session
    end

    ns.Window.SafeDraw()
    check("o desenho nao levantou erro de Lua", ns.Window.GetLastError(), nil)

    -- E OS DOIS NUMEROS CONTINUAM NA TELA, cada um por conta propria. Com a mescla, o segundo
    -- desaparecia; sem ela, os dois chegam ao widget.
    local durante = ns.Window.DebugCells(1)
    check("as tres colunas continuam desenhadas", #durante, 3)

    -- O TOTAL PASSOU PELO CAMINHO DE VALOR SECRET e chegou ao widget de alguma forma -- qual
    -- forma e da sondagem de `SetCellText`, nao deste teste. O que nao pode acontecer e virar o
    -- traco de "sem dado".
    check("o total nao virou traco de vazio", durante[1].text ~= "|cff4a4a4a-|r", true)
    check("  e nao ficou vazio", durante[1].text ~= nil and durante[1].text ~= "", true)

    -- E A TAXA, QUE ESTA LEGIVEL, SAIU FORMATADA. Esta e a afirmacao que a mescla nao conseguia
    -- sustentar: la, um valor secret no grupo levava o outro numero junto.
    local taxa = ns.Data.GetSession(0, ns.Data.GetColumn("dps").attr)
    check("a taxa continua sendo um numero de verdade",
        durante[2].text, ns.Data.FormatAmount(taxa.combatSources[1].amountPerSecond))

    -- E A METRICA QUE NAO ESTA OPACA SEGUE LEGIVEL: uma familia secret nao apaga as outras.
    check("interrupcoes continua sendo texto", type(durante[3].text), "string")

    ns.Data.GetSession = realGetSession
    issecretvalue = realIsSecret

    ns.db.columns = { "damage", "healing", "interrupts" }
    ns.Window.Rebuild()
end

print("== o cabecalho volta a ser um por coluna ==")
-- "Volta como estava": dois cabecalhos, "Dano" e "DPS", cada um ordenando pela metrica dele. O
-- que os une e a barra por baixo, nao o rotulo.
do
    ns.db.columns = { "damage", "dps", "healing", "hps", "interrupts" }
    ns.db.sortBy = "damage"
    ns.db.sortDesc = true
    ns.db.rows = 5
    ns.Window.Show(false)
    ns.Window.Rebuild()
    ns.Window.Draw()

    local cabecalhos = ns.Window.DebugHeaders()
    check("um cabecalho por coluna", #cabecalhos, 5)
    check("o primeiro e o do dano", cabecalhos[1].text, ns.Data.GetShortLabel("damage"))
    check("o segundo e o do DPS, separado", cabecalhos[2].text, ns.Data.GetShortLabel("dps"))
    -- A LARGURA DO BOTAO E A FATIA DELE DENTRO DA BARRA, e nao mais a largura declarada da
    -- coluna: os 10px de folga entre familias saem da faixa, entao as fatias somam a largura da
    -- BARRA. O que a largura declarada continua governando e a PROPORCAO entre elas -- o total,
    -- que pede mais espaco, tambem fica com o alvo de clique maior.
    local fatias = cabecalhos[1].width + cabecalhos[2].width
    -- Idem: o vao vem de `GetGroupGap()`, que e o configurado, e nao do padrao do Skin.
    check("as duas fatias somam a barra do par",
        fatias, ns.Window.DebugColumnWidth("damage") + ns.Window.DebugColumnWidth("dps")
            - ns.Window.GetGroupGap())
    check("  e a do total e a maior das duas",
        cabecalhos[1].width > cabecalhos[2].width, true)

    -- CLICAR EM "DPS" ORDENA POR DPS. Na versao mesclada os dois rotulos eram um cabecalho so e
    -- clicar ali ordenava sempre pelo total; com dois cabecalhos, cada um responde por si.
    check("clicar no DPS responde", ns.Window.DebugClickColumn(2), true)
    check("e ordena pela taxa", ns.db.sortBy, "dps")

    local depois = ns.Window.DebugHeaders()
    check("o dourado esta no DPS", depois[2].sorted, true)
    check("  e nao no dano", depois[1].sorted, false)

    -- CLICAR DE NOVO INVERTE, em vez de trocar de coluna.
    ns.Window.DebugClickColumn(2)
    check("clicar de novo inverte a ordem", ns.db.sortDesc, false)

    -- MOVER MOVE O GRUPO INTEIRO: o total e a taxa andam juntos, sempre -- e e o que mantem a
    -- barra unica desenhavel.
    ns.db.columns = { "damage", "dps", "healing", "hps", "interrupts" }
    ns.db.sortBy = "damage"
    ns.db.sortDesc = true
    ns.Window.Rebuild()
    ns.Window.MoveColumn(1, 1)
    check("mover trocou os dois primeiros grupos",
        table.concat(ns.db.columns, ","), "healing,hps,damage,dps,interrupts")

    local antes = table.concat(ns.db.columns, ",")
    ns.Window.MoveColumn(1, -1)
    check("mover para fora da lista nao faz nada", table.concat(ns.db.columns, ","), antes)

    -- E MOVER NORMALIZA DE VOLTA. Uma lista guardada pode chegar aqui fora de ordem -- ela vem de
    -- SavedVariables, e so a migracao normaliza. Mover nao pode devolver a bagunca para a tela.
    -- A TAXA NA FRENTE DO TOTAL e o caso que separa: intercalada, o proprio achatamento por
    -- grupo ja arruma; com a familia invertida por dentro, so a normalizacao arruma.
    ns.db.columns = { "dps", "damage", "healing", "hps" }
    ns.db.sortBy = "damage"
    ns.Window.MoveColumn(1, 1)
    check("mover devolve a lista agrupada mesmo se ela chegou intercalada",
        table.concat(ns.db.columns, ","), "healing,hps,damage,dps")

    -- E MARCAR UMA COLUNA MUDA A TELA NA HORA: os grupos ficam em cache, e cache que nao se
    -- invalida mostra o desenho anterior.
    ns.db.columns = { "damage", "dps", "interrupts" }
    ns.db.sortBy = "damage"
    ns.Window.Rebuild()
    check("tres colunas, tres cabecalhos", #ns.Window.DebugHeaders(), 3)
    check("  e duas barras", #ns.Window.DebugSpans(), 2)

    ns.Window.ToggleColumn("healing")
    check("marcar cura acrescenta DUAS colunas", #ns.Window.DebugHeaders(), 5)
    check("  e uma barra", #ns.Window.DebugSpans(), 3)

    ns.db.columns = { "damage", "healing", "interrupts" }
    ns.db.sortBy = "damage"
    ns.db.sortDesc = true
    ns.Window.Rebuild()
end

print("== Shift/Ctrl-clique no cabecalho move a familia da coluna clicada ==")
-- ⚑ DEFEITO ALTO ACHADO NA REVISAO DE 08/09, por tres lentes independentes, e reproduzido.
--
-- `button.columnIndex` e posicao em `ns.db.columns`; `Window.MoveColumn` indexa a lista de
-- GRUPOS. Enquanto o cabecalho foi por grupo os dois coincidiam. Ele voltou a ser por coluna e o
-- clique continuou entregando o indice da coluna -- e com um par total+taxa ligado as duas listas
-- NUNCA tem o mesmo tamanho.
--
-- O que isso produzia com {dano, DPS, cura, CPS, interr} (5 colunas, 3 grupos): dos dez cliques
-- possiveis, um acertava, um ESTOURAVA a janela e oito moviam a familia errada ou nao faziam nada.
-- Nenhum teste pegava porque todos chamavam `MoveColumn` direto, nunca pelo botao.
do
    local realShift, realCtrl = IsShiftKeyDown, IsControlKeyDown
    local shift, ctrl = false, false
    IsShiftKeyDown = function() return shift end
    IsControlKeyDown = function() return ctrl end

    local function comColunas()
        ns.db.columns = { "damage", "dps", "healing", "hps", "interrupts" }
        ns.db.sortBy = "damage"
        ns.db.sortDesc = true
        ns.db.rows = 5
        ns.Window.Show(false)
        ns.Window.Rebuild()
    end

    -- CLICAR NO 3o CABECALHO e clicar em "Cura" -- a coluna 3. O grupo dela e o 2.
    comColunas()
    shift = true
    check("Shift no cabecalho da cura responde", ns.Window.DebugClickColumn(3), true)
    shift = false
    check("e move a familia da CURA para a esquerda",
        table.concat(ns.db.columns, ","), "healing,hps,damage,dps,interrupts")

    -- CLICAR NO 4o e clicar em "CPS" -- a segunda metade do mesmo par. Move o mesmo grupo, e
    -- **nao estoura**: era o indice 4 numa lista de 3 grupos que abria o buraco.
    comColunas()
    shift = true
    check("Shift no cabecalho do CPS responde", ns.Window.DebugClickColumn(4), true)
    shift = false
    check("  e move a familia da cura, nao outra",
        table.concat(ns.db.columns, ","), "healing,hps,damage,dps,interrupts")

    -- E O ULTIMO CABECALHO NAO TEM PARA ONDE IR A DIREITA: nao faz nada, sem estourar.
    comColunas()
    local antes = table.concat(ns.db.columns, ",")
    ctrl = true
    ns.Window.DebugClickColumn(5)
    ctrl = false
    check("Ctrl no ultimo grupo nao faz nada", table.concat(ns.db.columns, ","), antes)

    -- E CLICAR SEM MODIFICADOR CONTINUA ORDENANDO, que e o caminho comum.
    comColunas()
    ns.Window.DebugClickColumn(4)
    check("clique sem modificador ainda ordena", ns.db.sortBy, "hps")

    IsShiftKeyDown, IsControlKeyDown = realShift, realCtrl

    -- E MOVER COM INDICE FORA DA LISTA NAO ESCREVE BURACO NENHUM. So o destino era conferido; a
    -- origem entrava sem guarda e a troca deixava um nil no meio da lista de grupos.
    ns.db.columns = { "damage", "dps", "interrupts" }
    ns.db.sortBy = "damage"
    ns.Window.Rebuild()
    local intactas = table.concat(ns.db.columns, ",")
    ns.Window.MoveColumn(9, -1)
    check("mover a partir de um indice inexistente nao muda nada",
        table.concat(ns.db.columns, ","), intactas)
    ns.Window.MoveColumn(0, 1)
    check("  nem a partir do zero", table.concat(ns.db.columns, ","), intactas)

    ns.db.columns = { "damage", "healing", "interrupts" }
    ns.db.sortBy = "damage"
    ns.Window.Rebuild()
end

print("== o login nao joga fora a ordenacao escolhida ==")
-- ⚑ DEFEITO ACHADO NA MESMA REVISAO. `MigrateColumns` passou a devolver "mudou" tambem para
-- reordenacao, e o perfil usa esse valor para APAGAR `sortBy` e anunciar "colunas migradas" no
-- chat. Resultado: todo login jogava fora a coluna que o jogador escolheu para ordenar e mentia
-- sobre o motivo.
--
-- Sao duas coisas diferentes: a lista normalizada e adotada SEMPRE; so a migracao de FORMATO
-- (ids de Enum, cujas chaves mudam de identidade) invalida a ordenacao salva.
do
    -- Lista ja em chaves, so fora de ordem: reagrupa, e NAO e migracao.
    local lista, formato = ns.Data.MigrateColumns({ "healing", "damage" })
    check("reagrupar devolve a lista arrumada", table.concat(lista, ","),
        "healing,hps,damage,dps")
    check("  mas nao conta como migracao de formato", formato, false)

    -- Lista em ids de Enum: e migracao de verdade.
    local _, migrou = ns.Data.MigrateColumns({ Enum.DamageMeterType.DamageDone })
    check("id numerico salvo conta como migracao", migrou, true)
end

print("== a tela de configuracao e o chat falam dos mesmos itens ==")
-- A LISTA DE COLUNAS DEIXOU DE SER O CATALOGO. Ela lista ITENS, e o `/rm col` tem que numerar os
-- mesmos -- dois "numero 4" diferentes para a mesma pessoa e pior que nao ter numero.
do
    ns.db.columns = { "damage", "dps", "healing", "hps", "interrupts" }
    ns.db.sortBy = "damage"
    ns.Picker.Toggle()

    local itens = ns.Picker.__items()
    check("a tela de colunas lista os itens", #itens, #ns.Data.GetColumnItems())
    check("  e a primeira linha e o par do dano",
        itens[1].label, ns.Data.GetColumnItems()[1].label)
    check("  com o DPS dentro dela, nao numa linha propria",
        itens[2].key ~= "dps", true)

    -- AS SETAS FALAM EM GRUPO. Com 5 colunas em 3 grupos, a linha da cura e o grupo 2 -- a versao
    -- anterior devolvia 3 (a posicao de "healing" em `ns.db.columns`) e movia a familia errada.
    check("a seta move a familia da linha clicada", ns.Picker.__arrowTarget("healing"), 2)
    check("  e a de interrupcoes e a terceira", ns.Picker.__arrowTarget("interrupts"), 3)

    -- E O CHAT NUMERA IGUAL: `/rm col N` liga o item N da mesma lista.
    ns.db.columns = { "interrupts" }
    ns.db.sortBy = "interrupts"
    local numero
    for i, item in ipairs(ns.Data.GetColumnItems()) do
        if item.key == "damage" then numero = i end
    end
    SlashCmdList["ROCKETMETER"]("col " .. numero)
    check("/rm col numera pelos mesmos itens da tela",
        table.concat(ns.db.columns, ","), "interrupts,damage,dps")

    ns.Picker.Toggle()
    ns.db.columns = { "damage", "healing", "interrupts" }
    ns.db.sortBy = "damage"
    ns.Window.Rebuild()
end

print("== a janela cabe o que ela desenha, em qualquer conjunto de colunas ==")
-- DEFEITO DE 08/09, achado por tres lentes independentes de um estudo de aparencia.
--
-- `MinWidth` deixou de somar as colunas quando o desenho em SECOES as tirou da tela -- e eu
-- escrevi no comentario que "as colunas nao sao mais desenhadas". Depois as colunas voltaram e a
-- soma nao voltou junto: a premissa venceu e o comentario ficou afirmando um fato morto.
--
-- Com o conjunto padrao de Mitico+ (7 colunas x 58 = 406) numa janela de 340, a area do nome dava
-- **-111**; o clamp a punha em 40px e a primeira celula era ancorada em x = -70 -- INTEIRA fora da
-- janela, desenhando por cima do icone, do nome e do cenario. Nada recorta.
--
-- ⚑ O TESTE TRAVA A INVARIANTE, NAO OS NUMEROS. Foi um numero solto (o `10` da calha, digitado em
-- dois lugares) que permitiu as duas contas divergirem; travar "largura = 537" so amarraria o
-- proximo valor errado. O que nao pode quebrar e: **a janela cabe o que ela desenha**.
do
    ns.db.rows = 5
    for _, conjunto in ipairs({
        { "damage" },
        { "damage", "healing", "interrupts" },
        { "damage", "dps", "healing", "hps", "interrupts", "dispels", "deaths" },
    }) do
        ns.db.columns = conjunto
        ns.db.width = nil                 -- como numa instalacao limpa
        ns.Window.Show(false)
        ns.Window.Rebuild()
        ns.Window.Draw()

        local g = ns.Window.DebugGeometry()

        -- O QUE A JANELA DESENHA SAO GRUPOS, nao colunas marcadas: as sete do conjunto de
        -- Mitico+ viram cinco (dano+DPS e cura+CPS se fundem). Contar `#conjunto` aqui pediria
        -- pela borda de duas celulas que nao existem -- e foi exatamente o `nil` que apareceu.
        local quantas = #ns.Data.GroupColumns(conjunto)

        check("com " .. #conjunto .. " coluna(s) em " .. quantas .. " grupo(s), o nome tem o piso",
            g.nameArea ~= nil and g.nameArea >= g.nameFloor, true)

        local foraDaJanela
        for c = 1, quantas do
            if g.cellLeft[c] < 0 then foraDaJanela = c end
        end
        check("  e nenhuma coluna desenha fora da janela", foraDaJanela, nil)

        check("  e a largura padrao tem folga sobre o minimo", g.width > g.minWidth, true)
    end

    -- E NO MINIMO A CONTA AINDA FECHA: arrastar ate o piso nao pode espremer o nome abaixo dele.
    ns.db.columns = { "damage", "dps", "healing", "hps", "interrupts", "dispels", "deaths" }
    ns.db.width = ns.Window.DebugGeometry().minWidth
    ns.Window.Rebuild()
    ns.Window.Draw()
    local g = ns.Window.DebugGeometry()
    check("no minimo, o nome ainda tem o piso exato", g.nameArea, g.nameFloor)

    ns.db.width = nil
    ns.db.columns = { "damage", "healing", "interrupts" }
end

print("== a ordenacao pelas colunas continua funcionando ==")
-- Pergunta do usuario depois da mudanca de layout: *"a ordenacao pelas colunas ainda funciona?"*.
--
-- Ler o codigo nao responde: o clique escreve `ns.db.sortBy`, o desenho le, e entre os dois ha um
-- `Refresh` e uma consulta a API. So clicando e olhando a lista resultante da para afirmar.
do
    ns.db.columns = { "damage", "healing", "interrupts" }
    ns.db.rows = 5
    ns.db.sortBy = "damage"
    ns.db.sortDesc = true
    ns.Window.Show(false)
    ns.Window.Draw()

    local porDano = ns.Window.DebugRowNames()
    check("ha gente na lista", #porDano > 1, true)

    -- CLICA NA COLUNA DE CURA (a segunda).
    check("o cabecalho responde ao clique", ns.Window.DebugClickColumn(2), true)
    check("e a coluna ordenada mudou", ns.db.sortBy, "healing")

    local porCura = ns.Window.DebugRowNames()
    check("a lista foi reordenada de verdade",
        table.concat(porCura, "|") ~= table.concat(porDano, "|"), true)

    -- CLICAR DE NOVO NA MESMA INVERTE a ordem, em vez de trocar de coluna.
    check("clicar de novo responde", ns.Window.DebugClickColumn(2), true)
    check("a coluna continua a mesma", ns.db.sortBy, "healing")
    check("e a ordem inverteu", ns.db.sortDesc, false)

    local invertida = ns.Window.DebugRowNames()
    check("e a lista virou de fato",
        table.concat(invertida, "|") ~= table.concat(porCura, "|"), true)

    -- E AS REGUAS DAS COLUNAS NAO SEGUEM A ORDENACAO. Cada coluna continua medida contra a
    -- propria metrica: ordenar por cura nao pode fazer a barra de dano encolher.
    local celulas = ns.Window.DebugCells(1)
    local reguas = {}
    for _, c in ipairs(celulas) do reguas[c.scale] = true end
    local distintas = 0
    for _ in pairs(reguas) do distintas = distintas + 1 end
    check("cada coluna segue com a sua regua depois de reordenar", distintas > 1, true)

    ns.db.sortBy = "damage"
    ns.db.sortDesc = true
end

print("== placar: a copia do Details! Mythic+ Scoreboard ==")
-- Pedido do usuario: *"pode copiar e deixa exatamente igual ao do Details! mythic scoreboard?
-- E para copiar tudo mesmo, deixar literalmente tudo igual"*.
--
-- ENTAO A TABELA ABAIXO E UM CONTRATO, nao um retrato do que o codigo faz hoje. Cada numero foi
-- lido em `Interface/AddOns/Details_MythicPlus/`, com o arquivo e a linha ao lado. Quem mexer
-- num deles reprova aqui -- e a mensagem diz de onde o numero veio, que e a unica forma de a
-- proxima pessoa saber se esta corrigindo um erro ou desfazendo a copia.
do
    local m = ns.Scoreboard.DebugLayout()

    -- Geometria do quadro (scoreboard.lua:119-136)
    check("altura da linha",            m.rowHeight,     46)   -- `lineHeight`            :130
    check("vao entre linhas",           m.rowSpacing,     1)   -- `(lineHeight+1)`        :821
    check("recuo das linhas",           m.lineInset,      2)   -- `lineOffset`            :129
    check("margem lateral do painel",   m.side,           5)   -- `mainFramePadding...`   :119
    check("onde comeca o cabecalho",    m.headerHeight,  65)   -- `headerY = -65`         :125
    check("altura do cabecalho",        m.colheadHeight, 20)   -- `header_height`  DF/header:747
    check("respiro entre colunas",      m.colPadding,     2)   -- `padding`        DF/header:733
    check("titulo",                     m.titleY,       -12)   -- `dungeonNameY`          :123
    check("corpo do titulo",            m.titleSize,     20)   -- (:355)
    check("corpo do tempo",             m.clockSize,     16)   -- (:361)

    -- A CONTA FECHA NOS 452 DELE (`mainFrameHeight`, :117). E o unico check aqui que nao copia
    -- um numero: ele deriva a altura de cinco linhas dos outros seis e compara com o total.
    -- Se um dos seis for mexido sem que o rodape acompanhe, e aqui que aparece.
    check("altura do painel com cinco linhas", m.panelHeight, 452)

    -- As colunas: ordem e largura, uma linha `ScoreboardColumn:Create` cada
    -- (`scoreboard_layout.lua:291,361,378,515,650,674,701,717,780,844,904,964,1037`).
    local ESPERADO = {
        { "portrait",   60 },
        { "spec",       25 },
        { "name",      110 },
        { "keystone",   60 },
        { "score",      90 },
        { "loot",       80 },
        { "deaths",     80 },
        { "avoidable",  80 },
        { "taken",     100 },
        { "dps",       100 },
        { "hps",       100 },
        { "interrupts",100 },
        { "dispels",    80 },
    }

    check("quantas colunas", #m.order, #ESPERADO)
    for i, esperado in ipairs(ESPERADO) do
        check("coluna " .. i .. " e " .. esperado[1], m.order[i], esperado[1])
        check("  e mede " .. esperado[2], m.widths[esperado[1]], esperado[2])
    end

    -- A largura do painel e consequencia das colunas, nao um numero solto.
    local soma = 0
    for _, esperado in ipairs(ESPERADO) do soma = soma + esperado[2] + m.colPadding end
    check("largura do painel = colunas + margens", m.panelWidth, soma + m.side * 2)

    -- AS DUAS COLUNAS QUE FICARAM DE FORA, e o teste diz por que. Sem esta trava, a proxima
    -- leitura da tabela do Details acha que faltou copiar e acrescenta duas colunas que so
    -- sabem mostrar zero: `player-likes` e `player-like-button` sao a rede social DELE -- o
    -- "gg" viaja pelo canal de addon entre quem roda o plugin, e ninguem fora dele responde.
    for _, ausente in ipairs({ "likes", "like-button" }) do
        check("nao copiamos a coluna de " .. ausente, m.widths[ausente], nil)
    end
end

print("== placar: toda coluna sabe se desenhar ==")
-- O DEFEITO DO PRINT DE 07/09 20:22, e ele e do tipo mais enganoso que existe: a coluna de
-- pontuacao declarava `render = "score"`, tinha `CellPainters.score` e NAO tinha
-- `CellBuilders.score`. `BuildRow` faz `CellBuilders[kind](cell)`, entao na primeira linha
-- chamava nil e o desenho abortava -- com o cabecalho e os rotulos de coluna JA na tela, porque
-- eles sao desenhados antes. O painel abriu bonito e vazio: nao parece erro de Lua, parece
-- "nao tem dado".
--
-- E O HARNESS NAO PEGOU. O unico `Scoreboard.Show` daqui era sem chave, e sem chave as tres
-- colunas de Mitico+ (pedra, pontuacao, saque) nem entram em `columns`. Testar so o caminho
-- facil e nao testar.
do
    local m = ns.Scoreboard.DebugLayout()
    check("ha tipos de celula para conferir", #m.renders > 0, true)
    for _, kind in ipairs(m.renders) do
        check("a celula `" .. kind .. "` tem construtor", m.builders[kind] == true, true)
        check("  e tem pintor", m.painters[kind] == true, true)
    end
end

print("== placar: a corrida de chave desenha INTEIRA ==")
-- O teste de ponta a ponta que faltava. A simulacao e uma chave de Mitico+, entao ela e o unico
-- caminho em que as treze colunas existem ao mesmo tempo.
--
-- `Scoreboard.Refresh` engole o erro de proposito -- para um erro no laco nao derrubar o painel
-- inteiro --, entao quem responde se deu certo NAO e "nao estourou": e `lastError`.
do
    ns.Scoreboard.lastError = nil
    ns.Scoreboard.ShowDemo()
    check("desenhou sem erro de Lua", ns.Scoreboard.lastError, nil)

    local celulas = ns.Scoreboard.DebugRow(1)
    check("a primeira linha existe", celulas ~= nil, true)
    check("com as treze colunas", #celulas, 13)

    -- E cada celula e do tipo que a coluna pediu -- senao um retrato poderia ter sido
    -- construido onde deveria haver numero, sem erro nenhum e completamente errado.
    local m = ns.Scoreboard.DebugLayout()
    for i, key in ipairs(m.order) do
        local esperado = "value"
        for _, col in ipairs({ "portrait", "spec", "name", "keystone", "score", "loot" }) do
            if key == col then esperado = col end
        end
        check("celula " .. i .. " (" .. key .. ") e do tipo certo", celulas[i].kind, esperado)
    end
end

print("== corrida retomada nao afirma sobre o que nao viu ==")
-- O SEGUNDO defeito do print de 07/09 20:22: o painel anunciava "Fora de combate: 26:13" numa
-- chave de 26:13, ou seja a corrida INTEIRA.
--
-- A causa e o `/reload` no meio da chave, que e rotina para quem mexe em addon: `Run.Resume`
-- recupera a duracao do cronometro do mundo, mas o registro de combate recomeca vazio. Somar "o
-- que nao esta marcado como combate" sobre um registro que so cobre o fim da a corrida toda.
do
    ns.Run.Start()
    check("corrida acompanhada do inicio conhece tudo", ns.Run.GetKnownFrom(), 0)

    -- Uma retomada: o addon carrega com a chave ja em andamento.
    ns.Run.Stop()
    mundo.challengeMapID = 500
    mundo.worldElapsed = 900          -- 15 minutos ja passaram
    ns.Run.Resume()

    local desde = ns.Run.GetKnownFrom()
    check("retomada sabe que so viu do minuto 15 em diante", desde, 900)
    check("e a semente do eixo comeca la, nao no zero",
        ns.Run.GetCombatTimeline()[1][1], 900)

    -- E o painel NAO mostra o numero de fora-de-combate nesse caso.
    ns.Scoreboard.lastError = nil
    ns.Scoreboard.Show({
        kind = "mplus", title = "Retomada", level = 11,
        durationSeconds = 1573, timeLimit = 1800, onTime = true,
        knownFrom = 900,
        combatTimeline = { { 900, false } },
        rows = ns.Demo.Run().rows,
        rowCount = 5,
    })
    check("desenhou sem erro", ns.Scoreboard.lastError, nil)
    check("o tempo fora de combate some quando o registro e parcial",
        ns.Scoreboard.DebugHeader().idleShown, false)

    -- E aparece de novo quando a corrida foi acompanhada do inicio.
    ns.Scoreboard.Show({
        kind = "mplus", title = "Inteira", level = 11,
        durationSeconds = 1000, timeLimit = 1800, onTime = true,
        knownFrom = 0,
        combatTimeline = { { 0, false }, { 100, true }, { 400, false } },
        rows = ns.Demo.Run().rows,
        rowCount = 5,
    })
    check("com registro inteiro, o numero volta",
        ns.Scoreboard.DebugHeader().idleShown, true)
    -- 0..100 e 400..1000 fora de combate = 700
    -- 0..100 e 400..1000 fora de combate = 700 s = 11:40. O rotulo vem junto porque o teste
    -- pergunta o que esta ESCRITO na tela, nao o que a funcao calculou.
    check("e ele conta so os trechos fora de combate",
        ns.Scoreboard.DebugHeader().idleText:find("11:40") ~= nil, true)

    ns.Run.Stop()
    mundo.challengeMapID = nil
end

print("== placar: nomes de atlas ==")
-- SetAtlas com nome errado falha em SILENCIO. Dois nomes aqui sao armadilha conhecida:
-- a Blizzard escreve "Fillagree" com dois L, e "Filigree" (a grafia correta do ingles) some
-- sem avisar. Este teste existe para ninguem "corrigir" a grafia.
local sawFillagree = 0
for _, name in ipairs(ns.SCOREBOARD_ATLASES) do
    if name:match("Filigree") then
        print("  ERRO  grafia errada no atlas: " .. name .. " (a Blizzard usa Fillagree)")
        os.exit(1)
    end
    if name:match("Fillagree") then sawFillagree = sawFillagree + 1 end
end
check("as tres filigranas do BossBanner na lista", sawFillagree, 3)
check("estrela do nivel na lista",
    (function()
        for _, n in ipairs(ns.SCOREBOARD_ATLASES) do
            if n == "ChallengeMode-SpikeyStar" then return true end
        end
        return false
    end)(), true)

print("== linha do tempo da corrida ==")
-- Sem combat log no Midnight, a linha do tempo so existe se for gravada durante a corrida.
ns.Run.Start()
check("comeca com a semente de fora de combate", #ns.Run.GetCombatTimeline(), 1)

AdvanceClock(30) ; ns.Run.OnCombatStart()
AdvanceClock(60) ; ns.Run.OnCombatEnd()
check("dois toggles gravados", #ns.Run.GetCombatTimeline(), 3)
check("entrada de combate aos 30s", ns.Run.GetCombatTimeline()[2][1], 30)
check("saida de combate aos 90s", ns.Run.GetCombatTimeline()[3][1], 90)

AdvanceClock(10) ; ns.Run.OnEncounterEnd("Chefe de Teste", 1)
check("boss gravado", #ns.Run.GetBosses(), 1)
check("boss no instante certo", ns.Run.GetBosses()[1][1], 100)
ns.Run.OnEncounterEnd("Wipe", 0)
check("wipe nao vira marcador de boss", #ns.Run.GetBosses(), 1)

-- O stub de GetDeathCount devolve 3: tres mortes acumuladas viram tres marcadores.
AdvanceClock(5) ; ns.Run.OnDeathCountUpdated()
check("mortes gravadas pela diferenca do contador", #ns.Run.GetDeaths(), 3)
ns.Run.OnDeathCountUpdated()
check("contador que nao subiu grava uma so", #ns.Run.GetDeaths(), 4)

-- Fora de corrida o modulo e inerte: sem isso ele gravaria em toda luta do jogo.
local before = #ns.Run.GetCombatTimeline()
ns.Run.Stop()
ns.Run.OnCombatStart()
ns.Run.OnEncounterEnd("Chefe fora da corrida", 1)
check("fora de corrida nao grava", #ns.Run.GetCombatTimeline(), before)
check("boss fora da corrida nao entra", #ns.Run.GetBosses(), 1)

print("== localizacao: rotulos que vem do jogo ==")
-- `FROM_GAME` troca nossos rotulos pelas palavras que o CLIENTE ja traduziu, o que vale para os
-- ~12 idiomas de uma vez. O modo de falha e silencioso e grave: global que nao existe e `nil`,
-- e `nil` no lugar de um rotulo faz o texto SUMIR da tela.
--
-- Roda em namespace proprio, carregando so o enUS.lua. Motivo: num cliente pt-BR o ptBR.lua
-- sobrescreve TODAS as 25 chaves, entao pelo `L` de verdade este caminho e invisivel — e teste
-- que nao consegue ver o que testa nao testa nada.
do
    local saved, touched = {}, {}
    local function setglobal(name, value)
        if not touched[name] then
            saved[name], touched[name] = _G[name], true
        end
        _G[name] = value
    end

    -- Os quatro casos que as guardas precisam separar:
    setglobal("DAMAGE_METER_TYPE_DEATHS", "Todesfaelle")   -- 1. global limpa
    setglobal("DAMAGE_METER_TYPE_DISPELS", nil)            -- 2. nao existe neste cliente
    setglobal("DAMAGE_METER_CATEGORY_DAMAGE", "%d. %s")    -- 3. e modelo de frase, nao rotulo
    setglobal("DAMAGE_METER_CATEGORY_HEALING", "")         -- 4. existe mas esta vazia
    -- Esta e limpa DE PROPOSITO: e a isca do teste de "conferir nao escreve" la embaixo.
    -- Sem uma global valida ali, a sabotagem nao teria o que sobrescrever e o teste
    -- passaria em cima do bug.
    setglobal("DAMAGE_METER_TYPE_ABSORBS", "Absorption-DE")

    local probe = {}
    assert(loadfile("Locales/enUS.lua"))(ADDON, probe)
    local PL = probe.L

    check("global limpa vira o rotulo", PL["Player deaths"], "Todesfaelle")
    check("global ausente cai no ingles, nao em nil", PL["Dispels"], "Dispels")
    check("global com marcador de formato e recusada", PL["Damage"], "Damage")
    check("global vazia e recusada", PL["Healing"], "Healing")

    -- O relatorio do `/rm i18n` precisa dizer exatamente qual global nao serviu e por que: e
    -- ele que transforma "o rotulo esta estranho" em dado, sem rodada de teste in-game.
    local why = {}
    for _, row in ipairs(probe.CheckGameStrings()) do
        why[row.tag] = row.why or false
    end
    check("ausente entra no relatorio", why["DAMAGE_METER_TYPE_DISPELS"], "ausente")
    check("com formato entra no relatorio", why["DAMAGE_METER_CATEGORY_DAMAGE"], "modelo de frase")
    check("vazia entra no relatorio", why["DAMAGE_METER_CATEGORY_HEALING"], "vazia")
    check("limpa NAO entra no relatorio", why["DAMAGE_METER_TYPE_DEATHS"], false)

    -- O relatorio nao pode ESCREVER. `/rm i18n` roda muito depois da carga, e reaplicar ali
    -- apagaria o que o arquivo de idioma sobrescreveu: num cliente pt-BR "Absorcoes" viraria
    -- "Absorve" ate o proximo /reload. Aqui: o ptBR ja rodou sobre o L de verdade, entao
    -- chamar o relatorio nao pode mexer nele.
    local antes = ns.L["Absorbs"]
    ns.CheckGameStrings()
    check("conferir NAO reaplica por cima da traducao", ns.L["Absorbs"], antes)

    -- Chave de FROM_GAME que o codigo nao usa e peso morto que ninguem descobre sozinho.
    local usedKeys = {}
    for _, file in ipairs(files) do
        local fh = io.open(file)
        for key in fh:read("*a"):gmatch('L%[%s*"([^"]*)"%s*%]') do
            usedKeys[key] = true
        end
        fh:close()
    end
    local orphan = false
    for key in pairs(probe.FROM_GAME) do
        if not usedKeys[key] then
            orphan = key
        end
    end
    check("nenhuma chave de FROM_GAME esta morta", orphan, false)

    -- REGRESSAO 0.53.0: `DAMAGE_METER_TYPE_DPS` e `_HPS` chegaram a entrar em FROM_GAME porque
    -- em enUS e ptBR sao a sigla "DPS"/"CPS" e pareciam perfeitas para o cabecalho de coluna.
    -- Nos outros nove idiomas nao sao sigla: deDE da "Schadensklassen" (15 caracteres, e quer
    -- dizer *classes de dano* -- o tradutor leu DPS como FUNCAO), ruRU da "Бойцы"
    -- (*combatentes*), esMX da "Sanacion por segundo" (20). O cabecalho tem 58px.
    check("DPS nao volta para FROM_GAME", probe.FROM_GAME["DPS"] or false, false)
    check("HPS nao volta para FROM_GAME", probe.FROM_GAME["HPS"] or false, false)

    for name in pairs(touched) do
        _G[name] = saved[name]
    end
end

print("== cadeado: a forma muda, nao so a cor ==")
-- Ate a 0.54.0 os dois estados usavam a MESMA textura e so trocavam o tom. Num glifo de 14px
-- isso nao se le -- o usuario disse que nao conseguia perceber. E a licao ja estava registrada
-- na saga do realce de lider: cor sozinha ficou fraca.
do
    local btn = ns.Window.__frame and ns.Window.__frame.lockButton
    check("o botao de cadeado existe", btn ~= nil, true)

    if btn then
        ns.db.locked = false
        ns.Window.ApplyLock()
        local destravado = btn:GetNormalTexture().__atlas

        ns.db.locked = true
        ns.Window.ApplyLock()
        local travado = btn:GetNormalTexture().__atlas

        check("os dois estados nao usam a mesma arte", destravado ~= travado, true)
        check("destravado usa o glifo de mover", destravado, "common-icon-move")
        check("travado nao usa o glifo de mover", travado ~= "common-icon-move", true)
    end
end

print("== cadeado: atlas ausente nao deixa o botao vazio ==")
-- `SetAtlas` com nome invalido falha em SILENCIO. Se o cliente nao tiver o atlas, o botao tem
-- que continuar mostrando o cadeado de sempre -- nunca sumir.
do
    local btn = ns.Window.__frame and ns.Window.__frame.lockButton
    local real = C_Texture.GetAtlasInfo
    C_Texture.GetAtlasInfo = function() return nil end

    ns.db.locked = false
    ns.Window.ApplyLock()
    check("sem o atlas, sobra a textura do cadeado",
        btn:GetNormalTexture().__texture, "Interface\\PetBattles\\PetBattle-LockIcon")

    C_Texture.GetAtlasInfo = real
    ns.db.locked = false
    ns.Window.ApplyLock()
end

print("== redimensionar nao pode cortar a linha de um jogador ==")
-- Pedido do usuario: "criar um minimo aceitavel para caber as informacoes de acordo com as
-- colunas e as linhas, para nao cortar a linha de um jogador".
-- ⚑ E O PAR TEM QUE SER O DO DESENHO ATUAL. Ate a 0.67.2 este teste comparava
-- `__WindowHeight` (a formula do layout de COLUNAS) com `__RowsThatFit`, e ficou verde enquanto a
-- janela desenhava secoes -- ele validava um par de formulas que ninguem mais usava. A auditoria
-- de 08/09 chamou isso pelo nome: *"passa verde para sempre"*.
--
-- Agora o par e `HeightForSections(n, linhas)` x `RowsThatFit(altura, n)`, que sao as duas contas
-- que a janela realmente faz -- e sao inversas uma da outra por construcao.
do
    local altura = ns.Window.__WindowHeight
    local cabem = ns.Window.__RowsThatFit
    check("os dois auxiliares estao expostos", altura ~= nil and cabem ~= nil, true)

    if altura and cabem then
        -- A INVERSA TEM QUE FECHAR. A alca chama `RowsThatFit`, o desenho chama `WindowHeight`,
        -- e se as duas discordarem o arraste nao converge: a janela cresce, o desenho cresce
        -- mais, e a alca pede mais ainda. Foi o que aconteceu enquanto uma media secoes e a outra
        -- media colunas.
        local falhou
        for n = 1, 12 do
            if cabem(altura(n)) ~= n then falhou = n end
        end
        check("a inversa fecha de 1 a 12 linhas", falhou, nil)

        -- MEIA LINHA A MAIS NAO PROMOVE: "para nao cortar a linha de um jogador".
        falhou = nil
        for n = 1, 12 do
            local sobrando = altura(n) + math.floor(ns.Window.__RowStep() / 2)
            if cabem(sobrando) ~= n then falhou = n end
        end
        check("meia linha sobrando nao vira uma linha", falhou, nil)

        check("faltando 1px, a ultima linha nao entra", cabem(altura(6) - 1), 5)
        check("altura absurda nao vai a zero linhas", cabem(10), 1)
    end
end

print("== realce do lider: clarear NAO pode dessaturar ==")
-- Relato: "a cor que da o realce dos melhores precisa ta mais escuro, a do DK parece ate rosa".
-- Estava certo, e a causa era a formula: misturar com branco (`r + (1-r)*k`) clareia mas
-- DESSATURA, e vermelho escuro dessaturado e literalmente rosa.
--
-- Medido nas cores de classe do 12.x:
--   Cavaleiro da Morte  RGB(196,31,59)  satur 0.84
--   com a mistura       RGB(216,105,124) satur 0.51   <- o rosa
--   multiplicando       RGB(255,39,76)   satur 0.84   <- vermelho vivo, e MAIS ESCURO
do
    local salvo = RAID_CLASS_COLORS
    RAID_CLASS_COLORS = {
        DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },   -- escuro: passa pela correcao
        ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },   -- claro: tem que sair intacto
    }

    local function satur(r, g, b)
        local hi = math.max(r, g, b)
        local lo = math.min(r, g, b)
        if hi <= 0 then return 0 end
        return (hi - lo) / hi
    end

    local r, g, b = ns.LeaderColor("DEATHKNIGHT")
    local sOriginal = satur(0.77, 0.12, 0.23)
    local sRealce = satur(r, g, b)

    -- O teste central: a saturacao nao pode cair. Com a formula antiga ela caia de 0.84 p/ 0.51.
    check("realce nao dessatura (o que fazia virar rosa)", sRealce >= sOriginal - 0.02, true)

    -- E o verde/azul nao podem subir muito: e neles que o rosa aparece.
    check("canal verde nao explode", g < 0.30, true)
    check("canal azul nao explode", b < 0.40, true)

    -- "precisa ta mais escuro": a formula antiga levava a luma para 0.55.
    local luma = 0.299 * r + 0.587 * g + 0.114 * b
    check("mais escuro que o piso antigo de 0.55", luma < 0.55, true)
    check("ainda assim legivel (nao ficou no original 0.33)", luma > 0.36, true)

    -- Classe que ja passa do piso sai INTACTA: clarear quem nao precisa e ruido.
    local rr, gg, bb = ns.LeaderColor("ROGUE")
    check("classe clara sai intacta (r)", rr, 1.00)
    check("classe clara sai intacta (g)", gg, 0.96)
    check("classe clara sai intacta (b)", bb, 0.41)

    -- Nenhum canal pode passar de 1: o jogo satura e a cor viraria outra.
    check("canais dentro de 0..1", r <= 1 and g <= 1 and b <= 1, true)

    RAID_CLASS_COLORS = salvo
end

print("== tres textos independentes, com limites ==")
-- A regra do projeto e que aparencia nao se configura (0.20.0). A tipografia e a excecao, e ela
-- e deliberada: o corpo foi ajustado a pedido seis vezes. Depois disso o usuario reprovou o
-- corpo UNICO com a razao certa -- "mudo um e ele faz pra tudo e fica ruim" -- e agora sao tres
-- textos com corpo, contorno e sombra proprios.
do
    local L = ns.Skin

    check("os limites estao expostos", L.fontSizeMin ~= nil and L.fontSizeMax ~= nil, true)

    -- TETO derivado da largura da celula, nao escolhido no olho. Em Arial Narrow um digito
    -- avanca ~0,5 do corpo, e o texto mais longo que `FormatAmount` produz tem 5 caracteres.
    local maiorTexto = 0
    for _, v in ipairs({ 0, 999, 9995, 999999, 1000000, 99950000, 999500000, 1000000000 }) do
        local t = ns.Data.FormatAmount(v)
        if #t > maiorTexto then maiorTexto = #t end
    end
    check("o teto e o que cabe na celula",
        L.fontSizeMax <= math.floor((L.columnWidth - 8) / (maiorTexto * 0.5)), true)

    -- E O TETO TEM QUE VALER EM TODO CORPO DE FONTE, nao so no padrao.
    --
    -- O que garante isso e a largura da coluna ACOMPANHAR o corpo (`ColumnWidthFor` multiplica
    -- pela escala do corpo). Se ela virasse constante, aumentar o texto passaria a estourar a
    -- caixa -- e o teste roda nos DOIS extremos por isso.
    --
    -- A coluna da TAXA e a apertada do par: ela e mais estreita que a do total e escreve quase o
    -- mesmo ("299K" contra "339M"). Medir a folgada nao provaria nada sobre ela.
    do
        local medida = {}
        for _, corpo in ipairs({ L.fontSizeMin, L.fontSizeMax }) do
            ns.Window.SetRoleSize("body", corpo)

            local caixa = ns.Window.DebugColumnWidth("dps")
            medida[corpo] = caixa
            check("com corpo " .. corpo .. ", o texto cabe na caixa dele",
                maiorTexto * corpo * 0.5 <= caixa - 8, true)
        end

        -- E A CAIXA CRESCE COM O CORPO, quando o texto pede. So "cabe" nao basta: uma largura
        -- CONSTANTE tambem cabe no corpo padrao, e so estoura quando o jogador aumenta a fonte --
        -- que e quando ninguem esta olhando um teste.
        check("e a caixa cresce junto com o corpo",
            medida[L.fontSizeMax] > medida[L.fontSizeMin], true)

        -- ⚑ MAS A RESOLUCAO DA BARRA NAO ENCOLHE COM ELA. Esta e a metade que faltava, e e a
        -- queixa do usuario: *"trocar tamanho de fonte e a fonte bagunca muito a largura das
        -- colunas, as vezes ate desproporcional"*.
        --
        -- A largura antiga era `base * corpo / 16`: diminuir a fonte encolhia a barra junto, e
        -- aumentar inflava a janela inteira. Mas a largura da coluna do TOTAL existe para dar
        -- RESOLUCAO A BARRA -- 92 contra 56 e distinguir 78% de 84% --, e resolucao de barra nao
        -- tem nada a ver com o tamanho da letra. Sao duas exigencias independentes, e a largura e
        -- a MAIOR das duas.
        ns.Window.SetRoleSize("body", L.fontSizeMin)
        local comFontePequena = ns.Window.DebugColumnWidth("damage")
        ns.Window.SetRoleSize("body", 16)
        local comFonteNormal = ns.Window.DebugColumnWidth("damage")
        check("a coluna do dano nao encolhe com a fonte pequena",
            comFontePequena, comFonteNormal)

        ns.Window.SetRoleSize("body", 16)
    end

    -- OS TRES SAO INDEPENDENTES. E o pedido literal: mexer num nao pode mexer nos outros.
    ns.Window.SetRoleSize("body", 18)
    ns.Window.SetRoleSize("title", 12)
    ns.Window.SetRoleSize("header", 11)
    check("corpo das linhas guardou o proprio", ns.Window.GetRoleSize("body"), 18)
    check("titulo guardou o proprio", ns.Window.GetRoleSize("title"), 12)
    check("cabecalho guardou o proprio", ns.Window.GetRoleSize("header"), 11)

    ns.Window.SetRoleSize("body", 14)
    check("mexer no corpo NAO mexe no titulo", ns.Window.GetRoleSize("title"), 12)
    check("mexer no corpo NAO mexe no cabecalho", ns.Window.GetRoleSize("header"), 11)

    -- CONTORNO tambem e por papel.
    ns.Window.SetRoleOutline("body", "thick")
    ns.Window.SetRoleOutline("title", "none")
    check("contorno do corpo", ns.OutlineFor("body"), "THICKOUTLINE")
    check("contorno do titulo", ns.OutlineFor("title"), "")
    check("mexer num contorno NAO mexe no outro",
        ns.Window.GetRoleOutline("body"), "thick")

    -- SOMBRA tambem.
    ns.Window.SetRoleShadow("body", false)
    ns.Window.SetRoleShadow("title", true)
    check("sombra do corpo desligada", ns.ShadowAlphaFor("body"), 0)
    check("sombra do titulo ligada", ns.ShadowAlphaFor("title") > 0, true)

    -- LIMITES valem para todo papel, nao so para o corpo.
    ns.Window.SetRoleSize("header", 99)
    check("teto respeitado em qualquer papel", ns.Window.GetRoleSize("header"), L.fontSizeMax)
    ns.Window.SetRoleSize("header", 1)
    check("piso respeitado em qualquer papel", ns.Window.GetRoleSize("header"), L.fontSizeMin)
    ns.Window.SetRoleSize("header", "dez")
    check("valor invalido nao muda nada", ns.Window.GetRoleSize("header"), L.fontSizeMin)

    -- O CONTORNO DESCE UM DEGRAU no corpo pequeno, por papel: e o cabecalho, o menor dos tres,
    -- que fecharia as letras primeiro.
    ns.Window.SetRoleOutline("header", "thin")
    ns.Window.SetRoleSize("header", 10)
    check("contorno some no papel pequeno", ns.OutlineFor("header"), "")
    ns.Window.SetRoleSize("header", 16)
    check("e volta quando o papel cresce", ns.OutlineFor("header"), "OUTLINE")

    -- A ALTURA DA LINHA segue o CORPO DAS LINHAS, nao os outros dois.
    ns.Window.SetRoleSize("body", 20)
    check("altura da linha cresce com o corpo das linhas", ns.Skin.rowHeight > 25, true)
    ns.Window.SetRoleSize("title", 20)
    local antes = ns.Skin.rowHeight
    ns.Window.SetRoleSize("title", 10)
    check("e nao muda quando o titulo muda", ns.Skin.rowHeight, antes)

    -- E O PLACAR nao pode ser arrastado junto: tem corpo proprio, ja aprovado.
    do
        local fsPlacar = spyFontString()
        ns.Window.SetRoleSize("body", 20)
        ns.ApplyScoreboardFont(fsPlacar, 0)
        local grande = fsPlacar.size
        ns.Window.SetRoleSize("body", 10)
        ns.ApplyScoreboardFont(fsPlacar, 0)
        check("o placar nao segue o corpo da janela", fsPlacar.size, grande)
        check("e continua no corpo dele", fsPlacar.size, ns.Skin.scoreboardFontSize)
    end

    -- volta ao padrao
    for _, role in ipairs(ns.ROLES) do
        local d = ns.ROLE_DEFAULTS[role]
        ns.Window.SetRoleSize(role, d.size)
        ns.Window.SetRoleOutline(role, d.outline)
        ns.Window.SetRoleShadow(role, d.shadow)
    end
end

print("== migracao: um texto vira tres ==")
-- As chaves antigas eram unicas para a janela inteira. Herda-las nos tres papeis mantem a tela
-- como o jogador deixou -- so que agora separavel. O TAMANHO e a excecao: herdar o corpo unico
-- nos tres achataria a hierarquia que o medidor nativo tem (titulo e cabecalho menores).
do
    local salvo = ns.db.text
    ns.db.text = nil
    ns.db.fontSize, ns.db.fontOutline, ns.db.fontShadow = 18, "thick", false

    ns.Profile.EnsureRuntimeDefaults()

    check("o corpo salvo foi para as linhas", ns.db.text.body.size, 18)
    check("o titulo manteve a distancia que tinha", ns.db.text.title.size, 16)
    check("o cabecalho tambem", ns.db.text.header.size, 14)
    check("o contorno foi herdado nos tres",
        ns.db.text.body.outline == "thick" and ns.db.text.title.outline == "thick"
        and ns.db.text.header.outline == "thick", true)
    check("a sombra tambem",
        ns.db.text.body.shadow == false and ns.db.text.header.shadow == false, true)
    check("as chaves antigas sairam", ns.db.fontSize == nil and ns.db.fontOutline == nil, true)

    ns.db.text = salvo
    ns.RefreshSkin()
end

print("== o instrumento de fontes IMPRIME ==")
-- Instrumento que nao imprime nada e pior que instrumento nenhum: ele passa a impressao de que a
-- lista esta vazia quando o que esta vazio e o comando. Ja aconteceu aqui -- o `/rm fontes` nasceu
-- chamando `Data.Available()`, que nao existe, e o unico sinal foi o silencio.
do
    local saida = {}
    local realPrint = print
    print = function(...)
        local partes = {}
        for i = 1, select("#", ...) do partes[i] = tostring((select(i, ...))) end
        saida[#saida + 1] = table.concat(partes, " ")
        return realPrint(...)
    end
    SlashCmdList["ROCKETMETER"]("fontes")
    print = realPrint

    local texto = table.concat(saida, " | ")
    -- Contar linhas nao bastaria: qualquer aviso conta como linha. O que prova que o instrumento
    -- FUNCIONOU e ele ter listado ator com o campo que a duvida pede -- o tipo de fonte, que e o
    -- que separa aliado NPC de jogador.
    check("o /rm fontes lista as metricas", texto:find("damage", 1, true) ~= nil, true)
    check("e lista ator com o tipo de fonte", texto:find("tipo=", 1, true) ~= nil, true)
end

print("== grade do configurador: nada vaza da coluna ==")
-- ESTE E O TESTE QUE FALTAVA. Duas rodadas seguidas de teste in-game caíram em geometria: as
-- abas se sobrepondo, e depois o checkbox nascendo no meio da janela com o rotulo saindo pela
-- borda direita. Os dois eram conferiveis sem desenhar nada.
--
-- A regra agora e uma so: todo controle vive DENTRO de uma coluna, e a coluna diz onde ele
-- comeca e termina. Nada e posicionado em relacao a janela inteira.
do
    ns.Picker.Create()
    local L = ns.Picker.__layout
    local controles = ns.Picker.__probe()

    check("ha controles para conferir", #controles > 0, true)

    -- NENHUM CONTROLE PODE COMECAR FORA DA COLUNA nem passar do fim dela.
    local foraEsquerda, foraDireita = nil, nil
    for _, c in ipairs(controles) do
        if c.x < 0 then foraEsquerda = c.name end
        if c.x + c.width > L.columnWidth then foraDireita = c.name end
    end
    check("nenhum controle comeca antes da coluna", foraEsquerda or false, false)
    check("nenhum controle passa do fim da coluna", foraDireita or false, false)

    -- E O DEFEITO EXATO DO RELATO: o checkbox comecava a 40% da largura da JANELA. Com duas
    -- colunas de 288 numa janela de 634, 40% da janela sao ~253 -- dentro da coluna por
    -- acidente, mas o rotulo (que vem depois da caixa) estourava. Aqui o inicio tem que ser a
    -- margem da coluna, nao uma fracao da janela.
    local checkForaDaMargem
    for _, c in ipairs(controles) do
        if c.x ~= 0 then checkForaDaMargem = c.name end
    end
    check("todo controle comeca na margem da coluna", checkForaDaMargem or false, false)

    -- O ROTULO DO CHECKBOX tem que caber no que sobra da coluna depois da caixa. Era a largura
    -- que faltava: sem ela a FontString cresce ate onde o texto pedir e atravessa a borda.
    local sobra = L.columnWidth - L.checkSize - 6
    check("sobra largura util para o rotulo do checkbox", sobra > 200, true)

    -- AS COLUNAS CABEM NA JANELA, com as margens.
    check("as colunas cabem na largura",
        L.margin * 2 + L.columnWidth * L.columns + L.gutter * (L.columns - 1) <= L.width, true)

    -- O RITMO VERTICAL. O que se trava e a RAZAO e a VIZINHANCA, nao os numeros crus.
    --
    -- A causa de "ta tudo muito junto e grudado, e feio, confuso" foi medida: o espaco DENTRO de
    -- um campo (rotulo -> seu controle) era 4 e o espaco ENTRE campos era 6 -- 1,5x. Com 1,5x o
    -- olho nao decide se o rotulo pertence ao controle de baixo ou a linha de cima. E a lei de
    -- proximidade da Gestalt.
    --
    -- O piso e 2x, e ele nao e escolhido: e o que a propria Blizzard pratica na transicao de
    -- secao (25 de branco acima do titulo contra 9 entre linhas -- `Blizzard_SettingsList.lua:46`
    -- e `Blizzard_SettingControls.xml:14,19`). Abaixo disso a borda de grupo deixa de ser vista.
    check("o espaco entre campos e MUITO maior que o de dentro do campo",
        L.gapField >= L.gapLabel * 2, true)
    check("e o espaco entre secoes e maior ainda que o entre campos",
        L.gapSection >= L.gapField * 2, true)

    -- NAO HA GRADE DE 4 AQUI, e o teste registra por que: nenhum dos numeros da Blizzard e
    -- multiplo de 4. Travar a grade obrigaria a arredondar 9 para 8 e 25 para 24, perdendo a
    -- coincidencia exata com o nativo -- que e o objetivo declarado da tela.
    check("o respiro entre campos e o do formulario empilhado nativo", L.gapField, 10)
    check("o branco de secao e o que a Blizzard abre acima de um titulo", L.gapSection, 25)

    -- A linha de controle tem a altura que a Blizzard usa nos NOVE templates de opcao dela
    -- (`Blizzard_SettingControls.xml:108-164`, todos 280x26).
    check("altura de controle e a do painel de opcoes do jogo", L.control, 26)

    -- VIZINHANCA VERTICAL. ESTE E O TESTE QUE FALTAVA DE VERDADE: o `Probe` guardava so `x` e
    -- `width`, e as TRES reprovacoes in-game por geometria foram colisao VERTICAL -- abas
    -- sobrepostas, campo encavalado no seguinte. Nao havia o que conferir.
    do
        local porColuna = {}
        for _, c in ipairs(controles) do
            if c.column then
                porColuna[c.column] = porColuna[c.column] or {}
                local t = porColuna[c.column]
                t[#t + 1] = c
            end
        end
        check("os controles sabem em que coluna estao", next(porColuna) ~= nil, true)

        -- O vao e medido entre TINTAS, e por isso e o branco que o jogador enxerga de verdade.
        local menorVao, menorNome = math.huge, nil
        local menorSecao, secaoNome = math.huge, nil
        for _, lista in pairs(porColuna) do
            table.sort(lista, function(a, b) return a.y < b.y end)
            for i = 2, #lista do
                local ant, cur = lista[i - 1], lista[i]
                local vao = cur.y - (ant.y + ant.height)
                if cur.isSection then
                    if vao < menorSecao then menorSecao, secaoNome = vao, cur.name end
                elseif vao < menorVao then
                    menorVao, menorNome = vao, ant.name .. " -> " .. cur.name
                end
            end
        end

        -- PISO ABSOLUTO: os 9 de respiro de linha do painel de Opcoes
        -- (`Blizzard_SettingsList.lua:46`). Nunca zero, que era o estado anterior desta tela.
        check("o menor vao entre campos vizinhos (" .. tostring(menorNome) .. ")",
            menorVao >= 9, true)

        -- E A TROCA DE ASSUNTO TEM QUE SER VISIVELMENTE MAIOR: 25, o branco que a Blizzard abre
        -- acima de um titulo de secao (9 de respiro + 16 de recuo do titulo no bloco de 45).
        check("o menor vao antes de uma secao (" .. tostring(secaoNome) .. ")",
            menorSecao >= 25, true)

        -- E a RAZAO entre os dois, que e o defeito original: 1,5x nao separa nada.
        check("a troca de secao e ao menos o dobro do vao entre campos",
            menorSecao >= menorVao * 2, true)
    end

    -- ALVO DE CLIQUE. WCAG 2.2 SC 2.5.8 (AA): 24x24, OU 24 de distancia CENTRO A CENTRO ate o
    -- vizinho -- a excecao se mede entre centros, nao entre bordas. As setas de reordenar sao
    -- 18x18; com o vao de 2 que havia dava 20 e reprovava.
    check("as setas passam no criterio de alvo adjacente",
        L.arrow + L.arrowGap >= 24, true)

    -- A CAIXA DE OPCAO e o rotulo dela andam em par. O template original e 32x32 com o texto em
    -- -2 (margem transparente da arte); a 28x28 a Blizzard reancora em +2
    -- (`SharedUIPanelTemplates.xml:1322,1337`). Copiar so o 28 deixa o texto comecando ANTES do
    -- fim da caixa, que foi o estado anterior.
    check("caixa de 28 vem com o rotulo reancorado em +2", L.checkSize == 28 and L.checkTextOffset == 2, true)

    -- E A CAIXA NAO PODE ENCOSTAR NA PROXIMA: foi o que subir a caixa de 24 para 28 causou. A
    -- vaga da linha de caixa e 26+10, e a caixa e 28 -- ou seja, ela transborda 2 da linha de
    -- controle, como a da Blizzard (30x29 numa linha de 26, `SettingControls.xml:81`). O que
    -- precisa sobrar e o respiro, e ele nao pode virar negativo.
    check("caixa de opcao tem folga ate a proxima", L.check - L.checkSize >= 8, true)
end

print("== o contorno medio saiu, e nao pode voltar ==")
-- PEDIDO DO USUARIO, 08/09: *"tira o contorno medio das opcoes, claramente tu nao conseguiu
-- fazer ele funcionar, sempre fica igual ao fino"*.
--
-- Ele foi criado na 0.61.0 para preencher o degrau que o motor nao tem: `OUTLINE` e
-- `THICKOUTLINE` e mais nada, e o salto entre os dois e grande. A ideia era desenhar o meio --
-- uma copia preta em THICKOUTLINE atras do texto em OUTLINE, com o alfa da copia fazendo as vezes
-- de espessura continua. No papel fecha; na tela, nunca deu diferenca.
--
-- ⚑ E O HANDOFF JA DIZIA POR QUE, tres versoes antes: *"o unico numero sem medicao por tras e o
-- `HALO_ALPHA` = 0.5"*. Espessura aparente e RENDERIZACAO, e renderizacao so o jogo responde --
-- nenhum teste daqui podia ter pego isso. O que da para travar e o que sobrou depois.
do
    local valores = {}
    for _, c in ipairs(ns.OUTLINE_CHOICES) do valores[#valores + 1] = c.value end
    check("sobraram os tres niveis que o motor tem", table.concat(valores, ","),
        "none,thin,thick")

    -- E NENHUM DELES PEDE COPIA. `halo` era a marca que ligava a maquinaria; se ela voltar sem a
    -- maquinaria, o contorno some em silencio no lugar de engrossar.
    local pedindoCopia = 0
    for _, c in ipairs(ns.OUTLINE_CHOICES) do
        if c.halo then pedindoCopia = pedindoCopia + 1 end
    end
    check("e nenhum pede contorno desenhado", pedindoCopia, 0)

    -- A MAQUINARIA FOI EMBORA JUNTO. Codigo que sobrevive ao unico consumidor vira armadilha: o
    -- proximo a mexer aqui acharia que ha um sistema de contorno desenhado funcionando.
    for _, nome in ipairs({ "CreateHalo", "SyncHaloFont", "SetHaloText", "ApplyRoleHalo",
                            "HaloAlphaFor", "HALO_OFFSETS", "HALO_FLAGS" }) do
        check("  e `ns." .. nome .. "` nao existe mais", ns[nome], nil)
    end

    ns.Window.SetRoleOutline("body", "thin")
    check("o fino continua sendo OUTLINE", ns.OutlineFor("body"), "OUTLINE")
    ns.Window.SetRoleOutline("body", "thick")
    check("e o grosso, THICKOUTLINE", ns.OutlineFor("body"), "THICKOUTLINE")
    ns.Window.SetRoleOutline("body", "thin")

    -- ⚑ QUEM TINHA "medium" SALVO NAO PERDE O CONTORNO. Sem migracao, `OutlineFor` nao acha a
    -- escolha na lista e devolve "" -- o contorno some sozinho no proximo login, num papel so.
    --
    -- O caso e do SavedVariables do proprio usuario, lido em 08/09: `text.header.outline` estava
    -- em "medium" enquanto corpo e titulo estavam em "thin". A primeira versao da migracao ficava
    -- dentro do bloco que so roda no formato de fonte UNICA -- e quem escolheu "medium" ja tinha
    -- passado daquele formato por definicao. Ela teria passado ao largo de quem devia atender.
    ns.db.text.header.outline = "medium"
    ns.db.text.body.outline = "medium"
    ns.Profile.EnsureRuntimeDefaults()
    check("o medio salvo vira fino", ns.db.text.header.outline, "thin")
    check("  em todo papel que o tinha", ns.db.text.body.outline, "thin")

    -- E O CONTORNO VOLTA A EXISTIR. Conferido no CORPO, e nao no cabecalho: o cabecalho sai
    -- quatro pontos menor que a linha e cai abaixo do limiar, onde `OutlineFor` zera o contorno
    -- de proposito -- num corpo pequeno o traco fecha os vazados do "a", do "e" e do "8". Medir
    -- ali confundiria "a migracao funcionou" com "o limiar agiu".
    -- ⚑ GUARDA E DEVOLVE O CORPO. Cravar 13 na volta deixava o corpo alterado para todo teste
    -- seguinte -- e a largura das colunas ESCALA com ele, entao a janela inteira media outra
    -- coisa dali para a frente. Estado global que um teste muda e nao devolve e defeito de teste.
    local corpoAntes = ns.RoleSizeSafe("body")
    ns.Window.SetRoleSize("body", 16)
    check("  e o contorno volta a existir", ns.OutlineFor("body"), "OUTLINE")
    ns.Window.SetRoleSize("body", corpoAntes)
end

print("== fonte, contorno e sombra configuraveis ==")
do
    local fonte = ns.db.font

    -- FONTE. So caminhos que aparecem nas declaracoes da Blizzard entram na lista: caminho de
    -- fonte inventado nao da erro, da texto que some.
    check("ha mais de uma fonte para escolher", #ns.FONT_CHOICES >= 2, true)
    check("a primeira e a padrao da janela", ns.FONT_CHOICES[1].path, ns.Skin.font)

    ns.Window.SetFont(ns.FONT_CHOICES[2].path)
    check("trocar a fonte muda o que o Skin expoe", ns.Skin.font, ns.FONT_CHOICES[2].path)
    do
        local fs = spyFontString()
        ns.ApplyFont(fs, 0)
        check("e a janela desenha com ela", fs.path, ns.FONT_CHOICES[2].path)
    end

    -- FONTE QUEBRADA cai na padrao em vez de sumir. E o caso real: uma fonte vinda de outro
    -- addon some quando aquele addon e desinstalado, e o caminho gravado continua aqui.
    do
        local fs = spyFontString()
        local quebrada = "Interface\\AddOns\\Sumiu\\fonte.ttf"
        -- O cliente recusa o arquivo: `SetFont` nao pega e `GetFont` continua sem nada. E o
        -- que acontece de verdade quando o addon que trazia a fonte e desinstalado.
        function fs.SetFont(_, path, size, flags)
            if path == quebrada then return false end
            fs.path, fs.size, fs.flags = path, size, flags
            return true
        end
        function fs.GetFont() return fs.path, fs.size, fs.flags end

        ns.db.font = quebrada
        local ok = pcall(ns.ApplyFont, fs, 0)
        check("fonte invalida nao derruba o desenho", ok, true)
        -- O QUE IMPORTA: ela tem que CAIR NA PADRAO, nao ficar sem fonte. Sem isso o texto
        -- simplesmente nao desenha, e nada avisa.
        check("e cai na fonte padrao", fs.path, ns.FONT_CHOICES[1].path)
    end

    -- Contorno e sombra por papel tem bloco proprio ("tres textos independentes"): aqui so
    -- interessa a FONTE, que continua sendo uma so para o addon inteiro.
    ns.db.font = nil
    ns.RefreshSkin()
    check("voltar ao padrao restaura a fonte", ns.Skin.font, ns.FONT_CHOICES[1].path)

    ns.db.font = fonte
    ns.RefreshSkin()
end


print("== migracao do contorno salvo ==")
-- `fontOutline` guardava a FLAG do WoW ("OUTLINE"); agora guarda a escolha do jogador
-- ("thin"). Sem converter, o valor salvo nao casa com nenhuma opcao e o combo aparece VAZIO --
-- foi exatamente o que apareceu no primeiro teste da tela.
do
    local salvo = ns.db.fontOutline

    for antigo, novo in pairs({ OUTLINE = "thin", THICKOUTLINE = "thick", [""] = "none" }) do
        ns.db.fontOutline = antigo
        ns.Profile.EnsureRuntimeDefaults()
        check("'" .. antigo .. "' vira '" .. novo .. "'", ns.db.fontOutline, novo)
    end

    -- Valor ja novo nao pode ser mexido.
    ns.db.fontOutline = "thick"
    ns.Profile.EnsureRuntimeDefaults()
    check("valor ja convertido fica como esta", ns.db.fontOutline, "thick")

    -- E o combo tem que achar o valor: se nao achar, ele desenha em branco.
    local achou = false
    for _, escolha in ipairs(ns.OUTLINE_CHOICES) do
        if escolha.value == ns.db.fontOutline then achou = true end
    end
    check("o valor salvo casa com uma opcao do combo", achou, true)

    ns.db.fontOutline = salvo
end

print("== as duas distancias da linha, configuraveis ==")
-- PEDIDO DE 09/09/2026, com print e retangulos apontando DUAS distancias: *"sao das distancia
-- entre colunas e entre valores nas colunas mescladas"*, e depois *"coloca estas distancias
-- configuraveis no addon, padrao de valor entre colunas de 8px e entre valores de 60px ou se for
-- medir pelo tamanho total das colunas duplas (mescladas) 84px"*.
--
-- O print saiu 1:1 com o jogo, e as duas foram MEDIDAS nele: vao entre familias = 10 px (que era
-- exatamente o `GROUP_GAP` do codigo, e e o que prova a escala 1:1), e vao entre os dois numeros
-- de um par = 65 px, com a coluna de total em 92.
do
    local gapAntes, totalAntes = ns.db.groupGap, ns.db.totalWidth

    check("o vao entre colunas nasce em 8", ns.defaults.groupGap, 8)
    check("e a coluna de total nasce em 84", ns.defaults.totalWidth, 84)

    -- ⚑ O SEGUNDO NUMERO E O QUE MANDA NO PRIMEIRO SENTIDO DO PEDIDO. Nao existe "espaco entre
    -- valores" para ajustar: o par e UMA barra com um numero ancorado em cada ponta, entao o vao
    -- entre eles e a largura do par menos a tinta dos dois. Encurtar a coluna de total e o unico
    -- jeito de aproxima-los -- e por isso o deslizador ajusta uma coisa e mostra outra.
    ns.db.groupGap, ns.db.totalWidth = 8, 84
    local vaoEm84 = ns.Window.PairValueGap()
    ns.Window.SetTotalWidth(120)
    check("alargar a coluna de total AFASTA os dois valores",
        ns.Window.PairValueGap() > vaoEm84, true)
    ns.Window.SetTotalWidth(56)
    check("  e estreitar aproxima", ns.Window.PairValueGap() < vaoEm84, true)

    -- ⚑ E O DESLIZADOR TEM QUE TER EFEITO NA TELA. `ColumnWidthFor` guarda a largura num cache
    -- com chave propria; se a chave nao souber do valor configurado, arrastar o controle nao muda
    -- NADA ate a proxima troca de fonte -- o jogador conclui que a opcao nao funciona, e nenhum
    -- erro aparece. E o mesmo defeito calado de um `SetAtlas` que falha em silencio.
    ns.Window.SetTotalWidth(120)
    local largo = ns.Window.DebugColumnWidth("damage")
    ns.Window.SetTotalWidth(56)
    local estreito = ns.Window.DebugColumnWidth("damage")
    check("mudar a largura atravessa o cache", largo > estreito, true)

    -- ⚑ E PELO CAMINHO QUE NAO PASSA PELO SETTER. Trocar de perfil, ligar a configuracao por
    -- personagem ou zerar tudo escrevem em `ns.db` DIRETO e chamam `Rebuild` -- nenhum deles limpa
    -- o cache. Se a chave do cache nao souber da largura configurada, o jogador troca de perfil e
    -- a janela continua desenhada com a largura do perfil anterior, sem nada acusar.
    ns.db.totalWidth = 120
    local porPerfilLargo = ns.Window.DebugColumnWidth("damage")
    ns.db.totalWidth = 56
    local porPerfilEstreito = ns.Window.DebugColumnWidth("damage")
    check("  e tambem quando o perfil muda o valor por fora",
        porPerfilLargo > porPerfilEstreito, true)

    -- LIMITES. O piso de 56 nao e estetico: `ColumnWidthFor` devolve `max(resolucao, texto)`, e
    -- abaixo do que "999.9M" pede o texto passa a mandar e o deslizador emudece.
    check("valor abaixo do piso e preso no piso",
        ns.Window.SetTotalWidth(10), ns.Skin.totalWidthMin)
    check("  e acima do teto, no teto",
        ns.Window.SetTotalWidth(999), ns.Skin.totalWidthMax)
    check("o vao entre colunas tambem tem piso",
        ns.Window.SetGroupGap(0), ns.Skin.groupGapMin)
    check("  e teto", ns.Window.SetGroupGap(999), ns.Skin.groupGapMax)

    -- ⚑ A RAZAO, no PADRAO. O que faz o vao ser lido como "muda de assunto" e ele ser multiplo do
    -- vao de dentro da familia (`CELL_GAP`), e o piso praticado e 2x -- foi a razao de 1,5x que
    -- produziu o *"ta tudo muito junto e grudado"* na tela de configuracao, e e a mesma lei de
    -- proximidade numa linha de dados. O jogador pode descer abaixo disso; o PADRAO nao pode.
    ns.db.groupGap = ns.defaults.groupGap
    local grupo, celula = ns.Window.DebugGaps()
    check("no padrao, o vao de fora e ao menos o DOBRO do de dentro", grupo >= celula * 2, true)

    -- E os dois controles existem na tela, dentro da coluna.
    ns.Picker.Create()
    local achados = 0
    for _, c in ipairs(ns.Picker.__probe()) do
        if c.name == ns.L["Space between columns"] or c.name == ns.L["Width of the total column"] then
            achados = achados + 1
            check("  '" .. c.name .. "' cabe na coluna",
                c.x >= 0 and c.x + c.width <= ns.Picker.__layout.columnWidth, true)
        end
    end
    check("os dois deslizadores estao na tela", achados, 2)

    ns.db.groupGap, ns.db.totalWidth = gapAntes, totalAntes
    ns.Window.Rebuild()
end

print("== o diagnostico nao pode derrubar o addon ==")
-- ⚑ ERRO REAL, achado no BugGrabber em 09/09/2026: 1628 ocorrencias de
-- "bad argument #1 to '?' (Usage: local session = C_DamageMeter.GetCombatSessionFromType(...))",
-- com a pilha em `Log.lua:71`, dentro de `Snapshot`, chamado por `Log.OnCombatStart`.
--
-- A causa era o laco da varredura: `for candidate = 0, 3`, num enum que tem TRES valores. O `3`
-- nao existe, e a API LEVANTA em valor invalido em vez de devolver `nil` -- entao o instrumento
-- que existe para explicar o addon dava uma linha vermelha por combate.
--
-- O simulador tambem tinha culpa: ele aceitava qualquer numero, mais permissivo que o jogo, e por
-- isso o harness ficava verde. A guarda esta agora no stub, e este bloco trava o resto.
do
    local antes = ns.Log.Count and ns.Log.Count() or 0
    local ok = pcall(ns.Log.Snapshot, "teste da varredura")
    check("a foto de diagnostico nao levanta", ok, true)
    check("  e gravou a linha", (ns.Log.Count and ns.Log.Count() or 0) > antes, true)

    -- E A VARREDURA COBRE O ENUM INTEIRO, com o NOME de cada valor. "tipo0" nao diz nada, e a
    -- ordem muda de cliente para cliente: neste `Current` e 1, nao 0.
    local foto
    for _, entrada in ipairs(RocketMeterLogDB.entries or {}) do
        if entrada.data and entrada.data.sweep then foto = entrada.data.sweep end
    end
    check("a varredura existe na foto", foto ~= nil, true)

    local quantos = 0
    for _ in pairs(foto or {}) do quantos = quantos + 1 end
    local doEnum = 0
    for _ in pairs(Enum.DamageMeterSessionType) do doEnum = doEnum + 1 end
    check("  e tem uma entrada por valor do enum", quantos, doEnum)
    check("  nomeada pelo valor, nao pelo numero cru",
        foto and foto["Overall(1)"] ~= nil, true)

    -- ⚑ E O CLIENTE QUE GANHA UM VALOR DE ENUM QUE A API AINDA NAO ATENDE. E o mesmo defeito um
    -- degrau acima do laco fixo: percorrer o enum deixa de bastar no dia em que a Blizzard
    -- acrescentar um valor antes de a funcao aceita-lo. Sem o `pcall` da sonda, a foto inteira
    -- morre por causa de UM valor -- e o instrumento some justamente na versao em que ele seria
    -- mais necessario. O stub recusa o que nao esta na tabela, entao basta pos um valor a mais.
    Enum.DamageMeterSessionType.Futuro = 9
    local okFuturo = pcall(ns.Log.Snapshot, "enum com valor novo")
    Enum.DamageMeterSessionType.Futuro = nil
    check("valor de enum que a API recusa nao derruba a foto", okFuturo, true)
end

print("== a visao segue o combate ==")
-- PEDIDO DE 09/09: *"assim que sair de combate a visao do painel muda para geral (overall) e
-- durante combate, a luta atual"*, ligado por padrao.
--
-- ⚑ ESTE TESTE EXISTE PORQUE O ESTADO DE COMBATE NAO E TESTAVEL AQUI. `InCombatLockdown()` e um
-- stub que devolve `false` sempre, e o harness nao tem como entrar em combate de verdade -- foi
-- por isso que `ApplyAutoSession` recebe o estado por PARAMETRO em vez de perguntar ao cliente.
-- Sem o parametro, a metade "entrou em combate" da regra ficaria sem cobertura nenhuma.
do
    local salvo, ligado = ns.db.sessionType, ns.db.autoSession

    check("a opcao nasce ligada", ns.defaults.autoSession, true)

    ns.db.autoSession = true

    -- OS DOIS SENTIDOS, e nao so o que o pedido cita primeiro.
    ns.db.sessionType = 1
    ns.Window.OnCombatStart()
    check("entrar em combate mostra a luta atual", ns.db.sessionType, 0)

    ns.Window.OnCombatEnd()
    check("sair do combate volta para o geral", ns.db.sessionType, 1)

    -- E A TROCA TEM QUE SER ANUNCIADA A QUEM CHAMA. `false` aqui nao e detalhe: e o que impede o
    -- desenho dobrado no caminho mais quente do addon (o `Core` ja chama `Refresh` nos dois
    -- eventos). Se isto passar a devolver `true` sempre, a janela redesenha duas vezes por pull.
    check("estando na visao certa, nada muda", ns.Window.ApplyAutoSession(false), false)
    check("  e mudar de verdade avisa quem chamou", ns.Window.ApplyAutoSession(true), true)

    -- DESLIGADA, A OPCAO NAO ENCOSTA NA ESCOLHA DO JOGADOR. Quem desliga quer trocar na mao pelo
    -- cabecalho ou pelo `/rm overall`, e a regra passando por cima seria pior que nao existir.
    ns.db.autoSession = false
    ns.db.sessionType = 0
    ns.Window.OnCombatEnd()
    check("desligada, sair do combate nao mexe na visao", ns.db.sessionType, 0)
    ns.db.sessionType = 1
    ns.Window.OnCombatStart()
    check("  nem entrar nele", ns.db.sessionType, 1)

    -- A CAIXA EXISTE NA TELA, na coluna da janela, e dentro dela. O comportamento pode estar
    -- certo e a opcao inalcancavel -- ja aconteceu nesta tela, com o rotulo saindo pela borda.
    ns.Picker.Create()
    local caixa
    for _, c in ipairs(ns.Picker.__probe()) do
        if c.name == ns.L["Follow the combat"] then caixa = c end
    end
    check("a caixa esta na tela de configuracao", caixa ~= nil, true)
    check("  na coluna da janela", caixa and caixa.column, 2)
    check("  e dentro da coluna",
        caixa and caixa.x >= 0 and caixa.x + caixa.width <= ns.Picker.__layout.columnWidth, true)

    ns.db.autoSession, ns.db.sessionType = ligado, salvo
end

print("== o diario captura os erros DESTE addon ==")
-- ⚑ PEDIDO DO USUARIO, 09/09/2026: *"tu esta armazenando logs de ambos addons? fazendo aqueles
-- logs de tudo que faz e etc para capturar qualquer erro inesperado?"*. A resposta era NAO: o
-- diario so sabia o que a gente mandou anotar, e erro de Lua ficava fora dele. No mesmo dia isso
-- custou 1628 ocorrencias do mesmo erro passando despercebidas no arquivo de um addon de terceiro.
do
    local ADDON_PATH = "Interface/AddOns/" .. "RocketMeter"

    ns.Log.ClearErrors()

    -- MUNDO 1: sem !BugGrabber. Encadeia no handler que estiver valendo.
    local chamouAnterior = false
    mundoErro.mudo = false
    mundoErro.handler = function() chamouAnterior = true end
    ns.Log.__resetCapture()
    check("sem BugGrabber, encadeia no handler", ns.Log.CaptureErrors(), "handler")

    mundoErro.pilha = ADDON_PATH .. "/Data.lua:10: in function 'X'\n"
        .. "Interface/AddOns/Outro/Coisa.lua:3: in function <Coisa>"
    geterrorhandler()(ADDON_PATH .. "/Data.lua:10: deu ruim")

    local distintos, total = ns.Log.ErrorCount()
    check("o erro nosso entra no diario", distintos, 1)

    -- ⚑ NAO ROUBAR O ERRO DE QUEM JA TRATAVA. Substituir sem chamar o anterior apagaria o erro
    -- do BugSack/ElvUI do jogador -- estragar a ferramenta dos outros para ter a nossa.
    check("  e o handler anterior continua sendo chamado", chamouAnterior, true)

    local guardado = RocketMeterLogDB.erros[1]
    check("  com a pilha filtrada nos nossos quadros",
        guardado.pilha ~= nil and guardado.pilha:find("Outro/Coisa", 1, true) == nil, true)

    -- REPETICAO VIRA CONTAGEM. Sem isto, o caso real (1628 vezes o mesmo erro) varreria o anel
    -- inteiro e apagaria justamente o contexto que explica o defeito.
    geterrorhandler()(ADDON_PATH .. "/Data.lua:10: deu ruim")
    geterrorhandler()(ADDON_PATH .. "/Data.lua:10: deu ruim")
    distintos, total = ns.Log.ErrorCount()
    check("repeticao vira contagem, nao linha nova", distintos, 1)
    check("  e a contagem sobe", total, 3)

    -- ERRO DE OUTRO ADDON NAO E NOSSO. Guardar o alheio enche o arquivo do que nao vamos
    -- consertar, e -- pior -- faz parecer que o defeito e nosso.
    mundoErro.pilha = "Interface/AddOns/Outro/Coisa.lua:3: in function <Coisa>"
    geterrorhandler()("Interface/AddOns/Outro/Coisa.lua:3: erro alheio")
    distintos = ns.Log.ErrorCount()
    check("erro de outro addon nao entra", distintos, 1)

    -- MUNDO 2: com !BugGrabber. Ele NEUTRALIZA o seterrorhandler
    -- (`!BugGrabber/BugGrabber.lua:573-574`), entao o caminho tem que ser o callback dele.
    ns.Log.ClearErrors()
    local assinantes = {}
    EventRegistry = {
        RegisterCallback = function(_, evento, fn) assinantes[evento] = fn end,
    }
    BugGrabber = {
        erros = {},
        GetErrorByID = function(self, id) return self.erros[id] end,
    }
    mundoErro.mudo = true
    ns.Log.__resetCapture()
    check("com BugGrabber, assina o callback dele", ns.Log.CaptureErrors(), "buggrabber")

    BugGrabber.erros["x1"] = {
        message = ADDON_PATH .. "/Window.lua:882: bad argument",
        stack = ADDON_PATH .. "/Window.lua:882: in function 'Y'",
    }
    assinantes["BugGrabber.BugGrabbed"](nil, "x1")
    check("  e copia o erro que e nosso", ns.Log.ErrorCount(), 1)

    BugGrabber.erros["x2"] = {
        message = "Interface/AddOns/Outro/Coisa.lua:3: alheio",
        stack = "Interface/AddOns/Outro/Coisa.lua:3: in function <Coisa>",
    }
    assinantes["BugGrabber.BugGrabbed"](nil, "x2")
    check("  e so o que e nosso", ns.Log.ErrorCount(), 1)

    -- ⚑ MUNDO 3: `seterrorhandler` mudo e SEM BugGrabber. E o mundo que a conferencia existe para
    -- pegar. Declarar "handler" aqui seria a pior falha possivel num instrumento: ele afirmaria
    -- estar ligado, o arquivo sairia limpo, e a conclusao "nao houve erro" seria falsa.
    BugGrabber, EventRegistry = nil, nil
    mundoErro.mudo = true
    ns.Log.__resetCapture()
    check("seterrorhandler mudo e sem BugGrabber: admite que nao captura",
        ns.Log.CaptureErrors(), "nenhuma")

    mundoErro.mudo = false
    mundoErro.handler = nil
    ns.Log.ClearErrors()
end

print("== comandos ==")
for _, cmd in ipairs({ "", "show", "hide", "help", "col", "columns", "preset raid", "preset",
                       "overall", "profile", "profile char", "profile account",
                       "move 2 right", "score", "score demo", "score mplus", "score raid",
                       "atlas", "atlas ChallengeMode-SpikeyStar", "i18n", "config", "fontes",
                       "reset" }) do
    local ok, err = pcall(SlashCmdList.ROCKETMETER, cmd)
    print(ok and ("  ok    /rm " .. cmd) or ("  ERRO  /rm " .. cmd .. ": " .. tostring(err)))
    if not ok then os.exit(1) end
end

print("\nTudo carregou e rodou sem erro de Lua.")
