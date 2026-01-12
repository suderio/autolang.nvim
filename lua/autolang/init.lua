local config = require("autolang.config")
local data = require("autolang.data")

local M = {}
M.opts = {}

-- Função interna para contar ocorrências
local function count_matches(text, patterns, is_cjk)
    local count = 0
    for _, pattern in ipairs(patterns) do
        if is_cjk then
            -- Para CJK, busca o padrão literal
            local _, n = text:gsub(pattern, "")
            count = count + n
        else
            -- Para latinas, busca a string exata (já normalizada com espaços)
            local _, n = text:gsub(pattern, "")
            count = count + n
        end
    end
    return count
end

function M.detect_and_set()
    local buf = vim.api.nvim_get_current_buf()

    -- Ignora buffers que não são arquivos normais ou se spell estiver desativado globalmente
    if vim.bo[buf].buftype ~= "" then return end

    -- Ler linhas (limitado pela config)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, M.opts.lines_to_check, false)
    if #lines == 0 then return end

    -- Normalização: lowercase e padding com espaços para facilitar regex simples
    local text = " " .. table.concat(lines, " "):lower() .. " "

    local scores = {}
    local highest_score = 0
    local detected_lang = nil

    -- Determinar quais línguas verificar
    local langs_to_check = M.opts.limit_languages or vim.tbl_keys(data.languages)

    for _, lang_code in ipairs(langs_to_check) do
        local patterns = data.languages[lang_code]
        if patterns then
            local is_cjk = (lang_code == "zh")
            local score = count_matches(text, patterns, is_cjk)

            if score > highest_score then
                highest_score = score
                detected_lang = lang_code
            end
        end
    end

    -- Se não detectou nada relevante, aborta
    if not detected_lang or highest_score == 0 then return end

    local target_spelllang = M.opts.lang_mapping[detected_lang]
    if not target_spelllang then return end

    -- Verificar se já está na língua correta
    local current_spell = vim.bo[buf].spelllang
    if current_spell == target_spelllang then return end

    -- Aplicação da mudança
    local function apply()
        vim.bo[buf].spelllang = target_spelllang
        vim.notify("Autolang: Spelllang alterado para " .. target_spelllang, vim.log.levels.INFO)
    end

    if M.opts.interactive then
        vim.ui.select({ "Sim", "Não" }, {
            prompt = "Autolang detectou [" .. target_spelllang .. "]. Alterar spelllang?",
        }, function(choice)
            if choice == "Sim" then apply() end
        end)
    else
        apply()
    end
end

function M.setup(user_opts)
    M.opts = vim.tbl_deep_extend("force", config.defaults, user_opts or {})

    if M.opts.auto_detect then
        vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
            group = vim.api.nvim_create_augroup("AutolangGroup", { clear = true }),
            callback = function()
                -- Adia ligeiramente para não bloquear a renderização inicial
                vim.defer_fn(M.detect_and_set, 10)
            end,
        })
    end

    -- Comando manual
    vim.api.nvim_create_user_command("AutolangDetect", M.detect_and_set, {})
end

return M
