local config = require("autolang.config")

local M = {}
M.opts = {}

-- Cache para armazenar os perfis de linguagem carregados na memória.
-- Formato: { ["en"] = { ["the"] = 0, ["and"] = 1, ... }, ["pt_BR"] = ... }
local profiles_cache = {}

-- Constante de Penalidade Máxima (Baseada no tamanho padrão de 300 trigramas)
local MAX_PENALTY = 300

--------------------------------------------------------------------------------
-- 1. Utilitários de Texto e Trigramas
--------------------------------------------------------------------------------

-- Limpa o texto mantendo apenas caracteres alfabéticos e converte para minúsculas
local function clean_text(text)
    -- Substitui tudo que não é letra por espaço e reduz espaços múltiplos
    -- O padrão %a em Lua considera acentos dependendo do locale, mas para segurança
    -- e consistência em trigramas, muitas vezes foca-se no ASCII ou UTF8 base.
    -- Aqui, vamos assumir que o texto cru já é suficiente.
    return text:lower()
end

-- Gera o perfil de trigramas do documento atual (Input Profile)
-- Retorna uma lista ordenada dos 300 trigramas mais frequentes.
local function get_document_profile(text)
    local counts = {}

    -- Itera sobre palavras. Adiciona '_' como padding de início/fim.
    -- Ex: "casa" -> "_ca", "cas", "asa", "sa_"
    for word in text:gmatch("%a+") do
        if #word > 1 then -- Ignora letras isoladas
            local padded = "_" .. word .. "_"
            for i = 1, #padded - 2 do
                local tri = padded:sub(i, i+2)
                counts[tri] = (counts[tri] or 0) + 1
            end
        end
    end

    -- Converte o mapa de contagem em uma lista para ordenação
    local sorted_trigrams = {}
    for tri, count in pairs(counts) do
        table.insert(sorted_trigrams, { tri = tri, count = count })
    end

    -- Ordena por frequência (descendente)
    table.sort(sorted_trigrams, function(a, b)
        return a.count > b.count
    end)

    -- Retorna apenas os top 300 trigramas (apenas as strings)
    local profile = {}
    for i = 1, math.min(#sorted_trigrams, 300) do
        table.insert(profile, sorted_trigrams[i].tri)
    end

    return profile
end

--------------------------------------------------------------------------------
-- 2. Gerenciamento de Perfis de Linguagem
--------------------------------------------------------------------------------

-- Carrega um perfil do disco e o converte para tabela de lookup (Rank Map)
local function load_lang_profile(lang_code)
    if profiles_cache[lang_code] then
        return profiles_cache[lang_code]
    end

    -- Tenta carregar o arquivo lua/autolang/trigrams/<code.lua>
    local status, trigram_list = pcall(require, "autolang.trigrams." .. lang_code)

    if not status or type(trigram_list) ~= "table" then
        -- Se falhar, retorna nil mas não crasha (pode ser um code mapeado que não tem arquivo)
        return nil
    end

    -- Otimização: Inverter a lista para mapa de Rank
    -- De: { "the", "and" }  (onde o índice é o rank)
    -- Para: { ["the"] = 0, ["and"] = 1 } (acesso O(1))
    local rank_map = {}
    for i, tri in ipairs(trigram_list) do
        rank_map[tri] = i - 1 -- Base 0 para o cálculo de distância
    end

    profiles_cache[lang_code] = rank_map
    return rank_map
end

--------------------------------------------------------------------------------
-- 3. Algoritmo de Distância (Out-Of-Place Measure)
--------------------------------------------------------------------------------

local function calculate_distance(doc_profile, lang_rank_map)
    local total_dist = 0

    for i, tri in ipairs(doc_profile) do
        local doc_rank = i - 1
        local lang_rank = lang_rank_map[tri]

        if lang_rank then
            -- Match: calcula a distância absoluta entre os ranks
            total_dist = total_dist + math.abs(doc_rank - lang_rank)
        else
            -- Miss: trigrama não existe na língua -> Penalidade Máxima
            total_dist = total_dist + MAX_PENALTY
        end
    end

    return total_dist
end

--------------------------------------------------------------------------------
-- 4. Detecção de Script (Fail Fast)
--------------------------------------------------------------------------------

local function detect_script(lines)
    -- Junta as linhas para uma verificação rápida de regex
    local sample = table.concat(lines, "")

    -- Verifica CJK (Chinês, Japonês, Coreano)
    -- Regex vim para intervalo CJK Unified Ideographs
    if vim.fn.match(sample, "[\\u4e00-\\u9fff]") > -1 then
        return "zh" -- Retorna código genérico para chinês/cjk
    end

    -- Verifica Cirílico (Russo, Ucraniano, etc)
    if vim.fn.match(sample, "[\\u0400-\\u04ff]") > -1 then
        return "ru"
    end

    -- Se não cair nos scripts específicos, assume-se Latino/Comum
    return "latin"
end

--------------------------------------------------------------------------------
-- 5. Lógica Principal
--------------------------------------------------------------------------------

function M.detect_and_set()
    local buf = vim.api.nvim_get_current_buf()

    -- Validações básicas de buffer
    if vim.bo[buf].buftype ~= "" or not vim.api.nvim_buf_is_valid(buf) then return end

    -- Coleta amostra do texto
    local lines = vim.api.nvim_buf_get_lines(buf, 0, M.opts.lines_to_check, false)
    if #lines == 0 then return end

    -- PASSO 1: Detecção de Script (Pré-filtro)
    local script_lang = detect_script(lines)

    -- Se detectou um script não-latino forte (ex: Chinês), aplica direto e sai.
    if script_lang ~= "latin" then
        local target = M.opts.lang_mapping[script_lang]
        if target then
            vim.bo[buf].spelllang = target
        end
        return
    end

    -- PASSO 2: Detecção de Trigramas (Para script Latino)
    local text = clean_text(table.concat(lines, " "))
    -- Se o texto for muito curto, trigramas falham. Mínimo razoável de caracteres.
    if #text < 30 then return end

    local doc_profile = get_document_profile(text)

    local lowest_distance = math.huge
    local detected_lang = nil

    -- Define quais línguas testar (config ou todas disponíveis nos arquivos)
    -- Nota: Aqui iteramos sobre o MAPPING da config para saber quais arquivos buscar
    local langs_to_check = {}
    if M.opts.limit_languages then
        langs_to_check = M.opts.limit_languages
    else
        -- Se não limitado, tenta inferir das chaves do mapping que não sejam especiais
        langs_to_check = vim.tbl_keys(M.opts.lang_mapping)
    end

    for _, lang_code in ipairs(langs_to_check) do
        -- Ignora mapeamentos especiais como CJK se estivermos na fase latina
        if lang_code ~= "zh" and lang_code ~= "ru" then
            local lang_profile = load_lang_profile(lang_code)

            if lang_profile then
                local dist = calculate_distance(doc_profile, lang_profile)

                -- Debug (descomente para ver os scores)
                -- print("Lang:", lang_code, "Dist:", dist)

                if dist < lowest_distance then
                    lowest_distance = dist
                    detected_lang = lang_code
                end
            end
        end
    end

    -- Aplicação do resultado
    if detected_lang then
        local target_spelllang = M.opts.lang_mapping[detected_lang]
        if target_spelllang and vim.bo[buf].spelllang ~= target_spelllang then

            local function apply()
                vim.bo[buf].spelllang = target_spelllang
                vim.notify("Autolang: " .. detected_lang .. " (" .. target_spelllang .. ")", vim.log.levels.INFO)
            end

            if M.opts.interactive then
                vim.ui.select({ "Sim", "Não" }, {
                    prompt = "Mudar linguagem para " .. target_spelllang .. "?",
                }, function(choice)
                    if choice == "Sim" then apply() end
                end)
            else
                apply()
            end
        end
    end
end

function M.setup(user_opts)
    M.opts = vim.tbl_deep_extend("force", config.defaults, user_opts or {})

    if M.opts.auto_detect then
        vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
            group = vim.api.nvim_create_augroup("AutolangGroup", { clear = true }),
            callback = function()
                vim.defer_fn(M.detect_and_set, 10)
            end,
        })
    end

    vim.api.nvim_create_user_command("AutolangDetect", M.detect_and_set, {})
end

return M
