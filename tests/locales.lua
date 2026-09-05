-- tests/locales.lua — conferência das traduções, fora do jogo.
--
--     luajit tests/locales.lua        (de dentro da pasta do addon)
--
-- Sai com código 1 em quatro casos, e os quatro são **silenciosos in-game**:
--
--   (a) chave usada no código que um idioma não traduz  → o jogador vê inglês cru
--   (b) chave traduzida que ninguém usa                 → tradução morta, custa revisão
--   (c) `%d`/`%s` em número OU ORDEM diferente           → `format()` estoura em produção
--   (d) chave de `FROM_GAME` que o código não usa        → peso morto
--
-- O (c) é o pior: Lua 5.1 **não tem argumento posicional** (`%1$s` é erro de sintaxe do
-- `format`), então o tradutor não pode reordenar os marcadores. Trocar `%s` e `%d` de lugar
-- levanta erro só no idioma errado, na máquina de outra pessoa.
--
-- Este arquivo é o MESMO nos dois addons do workspace; só o `.toc` que ele lê muda.
--
-- Limite conhecido: `L[variavel]` não dá para conferir estaticamente. A convenção do projeto
-- é escrever sempre `L["literal"]`.

local ADDON do
    local f = io.popen('dir /b *.toc 2>nul') or io.popen('ls *.toc 2>/dev/null')
    local list = f and f:read("*a") or ""
    if f then f:close() end
    ADDON = list:match("([^\r\n]+)%.toc")
    assert(ADDON, "rode de dentro da pasta do addon: luajit tests/locales.lua")
end

--------------------------------------------------------------------------------
-- 1. O .toc diz o que é código e o que é locale
--------------------------------------------------------------------------------
local sources, locales = {}, {}
for line in io.lines(ADDON .. ".toc") do
    line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line:match("%.lua$") and not line:match("^#") then
        local path = line:gsub("\\", "/")
        if path:match("^Locales/") then
            locales[#locales + 1] = path
        else
            sources[#sources + 1] = path
        end
    end
end
assert(#locales > 0, "nenhum arquivo em Locales/ listado no .toc")

--------------------------------------------------------------------------------
-- 2. Chaves usadas no código
--------------------------------------------------------------------------------
-- A fronteira `%f[%w_]` exige que o caractere antes do `L` NÃO seja de palavra. Sem ela,
-- `NORMAL["a"]` casa (termina em `L[`) e a chave "a" passa a contar como usada.
local KEY = '%f[%w_]L%[%s*"([^"]*)"%s*%]'

local used, usedIn = {}, {}
for _, file in ipairs(sources) do
    local fh = assert(io.open(file), "arquivo do .toc não existe: " .. file)
    local text = fh:read("*a")
    fh:close()
    for key in text:gmatch(KEY) do
        used[key] = true
        usedIn[key] = usedIn[key] or file
    end
end

--------------------------------------------------------------------------------
-- 3. Carrega cada idioma pelo MESMO caminho do jogo
--------------------------------------------------------------------------------
-- Executar os arquivos, em vez de raspar com regex, faz string multilinha, escape e
-- concatenação funcionarem — e faz o `if GetLocale() ~= "xx" then return end` entrar no teste.
local languages = {}
for _, path in ipairs(locales) do
    local code = path:match("([^/]+)%.lua$")
    if code ~= "enUS" then languages[#languages + 1] = code end
end

local function loadLanguage(code)
    local ns = {}
    local realGetLocale = GetLocale
    GetLocale = function() return code end
    for _, path in ipairs(locales) do
        assert(loadfile(path), "erro de sintaxe em " .. path)(ADDON, ns)
    end
    GetLocale = realGetLocale
    return ns
end

--------------------------------------------------------------------------------
-- 4. As conferências
--------------------------------------------------------------------------------
local problems = 0
local function fail(fmt, ...)
    problems = problems + 1
    print("  ERRO  " .. string.format(fmt, ...))
end

-- A sequência de marcadores, não só a contagem: `"%d de %s"` e `"%s de %d"` têm a mesma
-- contagem e a segunda estoura.
local function markers(text)
    local out = {}
    for m in text:gmatch("%%[%d%.%-]*([dsfxq%%])") do out[#out + 1] = m end
    return table.concat(out, ",")
end

print("== " .. ADDON .. ": " .. #sources .. " arquivos de código, "
    .. #locales .. " de locale ==")

local usedCount = 0
for _ in pairs(used) do usedCount = usedCount + 1 end
print("   " .. usedCount .. " chaves usadas no código")

for _, code in ipairs(languages) do
    local ns = loadLanguage(code)
    local L = ns.L
    assert(L, code .. ": o arquivo de locale não criou ns.L")

    -- (a) e (c) — `rawget`, porque `__index` devolve a própria chave e `L[k]` nunca é nil.
    local missing, translated = 0, {}
    for key in pairs(used) do
        local value = rawget(L, key)
        if value == nil then
            missing = missing + 1
            fail('%s não traduz "%s" (usada em %s)', code, key, usedIn[key])
        else
            translated[key] = true
            local a, b = markers(key), markers(value)
            if a ~= b then
                fail('%s: "%s" tem os marcadores [%s], a tradução tem [%s]'
                    .. ' -> format() estoura', code, key, a, b)
            end
        end
    end

    -- (b) — o que está na tabela e o código não pede. Só conta o que o ARQUIVO DE IDIOMA
    -- escreveu: o enUS.lua também preenche L a partir das globais do jogo, e isso não é
    -- tradução morta.
    local fromGame = {}
    for key in pairs(ns.FROM_GAME or {}) do fromGame[key] = true end

    local dead = 0
    for key in pairs(L) do
        if not used[key] and not fromGame[key] then
            dead = dead + 1
            fail('%s traduz "%s", que nenhum arquivo usa', code, key)
        end
    end

    print(string.format("   %s: %d traduzidas, %d faltando, %d mortas",
        code, usedCount - missing, missing, dead))
end

-- (d) — chave de FROM_GAME que o código não usa.
do
    local ns = loadLanguage("enUS")
    for key in pairs(ns.FROM_GAME or {}) do
        if not used[key] then
            fail('FROM_GAME mapeia "%s", que nenhum arquivo usa', key)
        end
    end
end

--------------------------------------------------------------------------------
print()
if problems > 0 then
    print(problems .. " problema(s).")
    os.exit(1)
end
print("0 problemas.")
print("Não confere se as globais de FROM_GAME existem no cliente — isso só o jogo responde:")
print("  /rm i18n   (ou /rs i18n)")
