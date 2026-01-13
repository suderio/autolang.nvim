local config = require("autolang.config")

local M = {}
M.opts = {}

local profiles_cache = {}
local MAX_PENALTY = 300
--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------
local function is_valid_buffer(buf)
    if not vim.api.nvim_buf_is_valid(buf) then return false end
    if vim.bo[buf].buftype ~= "" then return false end

    -- Ignora binários
    if vim.bo[buf].binary then return false end

    -- Ignora arquivos gigantes (> 1MB) para evitar travar a UI
    local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
    if ok and stats and stats.size > 1024 * 1024 then return false end

    return true
end
--------------------------------------------------------------------------------
-- Tree-sitter
--------------------------------------------------------------------------------

local ts_queries = {
    -- === Markup & Prosa ===

    -- Typst: O nó 'text' captura o conteúdo principal
    typst = [[ (text) @content ]],

    -- Markdown: Parágrafos e texto inline (dentro de bold, italic, etc)
    markdown = [[
        (paragraph) @content
        (inline) @content
    ]],

    -- Org Mode: Foca nos parágrafos para evitar pegar properties e tags
    org = [[ (paragraph) @content ]],

    -- HTML / XML: O nó 'text' é o conteúdo entre tags <div>Texto</div>
    html = [[ (text) @content ]],
    xml = [[ (text) @content ]],

    -- LaTeX: Texto genérico fora de comandos
    latex = [[ (text) @content ]],

    -- Git Commit: A mensagem do commit
    gitcommit = [[ (message) @content ]],

    -- === Desenvolvimento Web ===

    -- Javascript / Typescript: Comentários, strings e template strings (backticks)
    javascript = [[
        (comment) @content
        (string) @content
        (template_string) @content
    ]],
    typescript = [[
        (comment) @content
        (string) @content
        (template_string) @content
    ]],

    -- TSX / JSX: Além do JS normal, precisa pegar o texto dentro das tags JSX
    tsx = [[
        (comment) @content
        (string) @content
        (template_string) @content
        (jsx_text) @content
    ]],
    javascriptreact = [[
        (comment) @content
        (string) @content
        (template_string) @content
        (jsx_text) @content
    ]],

    -- CSS / SCSS: Principalmente comentários (strings em CSS geralmente são URLs ou seletores)
    css = [[ (comment) @content ]],
    scss = [[ (comment) @content ]],

    -- === Linguagens de Backend / Sistemas ===

    -- Lua
    lua = [[
        (comment) @content
        (string_content) @content
    ]],

    -- Python: Docstrings são strings normais no AST do Python
    python = [[
        (comment) @content
        (string_content) @content
    ]],

    -- Rust: Comentários de linha, bloco e strings
    rust = [[
        (line_comment) @content
        (block_comment) @content
        (string_literal) @content
    ]],

    -- Go: Strings interpretadas ("") e raw (``)
    go = [[
        (comment) @content
        (interpreted_string_literal) @content
        (raw_string_literal) @content
    ]],

    -- C / C++
    c = [[
        (comment) @content
        (string_literal) @content
    ]],
    cpp = [[
        (comment) @content
        (string_literal) @content
        (raw_string_literal) @content
    ]],

    -- Java
    java = [[
        (line_comment) @content
        (block_comment) @content
        (string_literal) @content
    ]],

    -- Bash / Shell
    bash = [[
        (comment) @content
        (string) @content
    ]],

    -- === Dados / Configuração ===

    -- YAML: Comentários e valores escalares (texto)
    yaml = [[
        (comment) @content
        (string_scalar) @content
    ]],

    -- JSON: Apenas strings (valores)
    json = [[ (string) @content ]],

    -- TOML: Comentários e strings
    toml = [[
        (comment) @content
        (string) @content
    ]],
}
local function get_text_with_treesitter(buf)
    local ft = vim.bo[buf].filetype
    local query_string = ts_queries[ft]

    if not query_string then return nil end

    local ok, parser = pcall(vim.treesitter.get_parser, buf, ft)
    if not ok or not parser then return nil end

    local tree = parser:parse()[1]
    if not tree then return nil end

    local root = tree:root()
    local ok_query, query = pcall(vim.treesitter.query.parse, ft, query_string)
    if not ok_query then return nil end

    local text_parts = {}
    local char_count = 0
    local LIMIT = 2000

    for _, node, _ in query:iter_captures(root, buf, 0, -1) do
        local node_text = vim.treesitter.get_node_text(node, buf)
        -- Add spaces to avoid wrong concatenation
        table.insert(text_parts, node_text)

        char_count = char_count + #node_text
        if char_count > LIMIT then break end
    end

    return table.concat(text_parts, " ")
end


local function get_sample_text(buf, lines_limit)
    local ts_text = get_text_with_treesitter(buf)

    -- Tree-sitter
    if ts_text and #ts_text > 50 then
        return ts_text
    end

    -- Fallback
    local lines = vim.api.nvim_buf_get_lines(buf, 0, lines_limit, false)
    return table.concat(lines, " ")
end

--------------------------------------------------------------------------------
-- Text & Trigrams
--------------------------------------------------------------------------------

local function clean_text(text)
    if not text then return "" end
    local clean = text:lower()
    -- Optional: Change any symbol to space
    -- Although gmatch("%a+") ignores symbols, this can help
    -- clean = clean:gsub("[^%a]", " ")
    return clean
end

local function get_document_profile(text)
    local counts = {}

    for word in text:gmatch("%a+") do
        if #word > 1 then
            local padded = "_" .. word .. "_"
            for i = 1, #padded - 2 do
                local tri = padded:sub(i, i+2)
                counts[tri] = (counts[tri] or 0) + 1
            end
        end
    end

    local sorted_trigrams = {}
    for tri, count in pairs(counts) do
        table.insert(sorted_trigrams, { tri = tri, count = count })
    end

    table.sort(sorted_trigrams, function(a, b) return a.count > b.count end)

    local profile = {}
    for i = 1, math.min(#sorted_trigrams, 300) do
        table.insert(profile, sorted_trigrams[i].tri)
    end

    return profile
end

--------------------------------------------------------------------------------
-- Lang Profiles
--------------------------------------------------------------------------------

local function load_lang_profile(lang_code)
    if profiles_cache[lang_code] then return profiles_cache[lang_code] end

    local status, trigram_list = pcall(require, "autolang.trigrams." .. lang_code)
    if not status or type(trigram_list) ~= "table" then return nil end

    local rank_map = {}
    for i, tri in ipairs(trigram_list) do
        rank_map[tri] = i - 1
    end

    profiles_cache[lang_code] = rank_map
    return rank_map
end

local function calculate_distance(doc_profile, lang_rank_map)
    local total_dist = 0
    for i, tri in ipairs(doc_profile) do
        local doc_rank = i - 1
        local lang_rank = lang_rank_map[tri]
        if lang_rank then
            total_dist = total_dist + math.abs(doc_rank - lang_rank)
        else
            total_dist = total_dist + MAX_PENALTY
        end
    end
    return total_dist
end

--------------------------------------------------------------------------------
-- Script detection
--------------------------------------------------------------------------------

local function detect_script(text_sample)
    if vim.fn.match(text_sample, "[\\u4e00-\\u9fff]") > -1 then
        return "zh"
    end
    if vim.fn.match(text_sample, "[\\u0400-\\u04ff]") > -1 then
        return "ru"
    end
    return "latin"
end

--------------------------------------------------------------------------------
-- Main logic
--------------------------------------------------------------------------------

function M.detect_and_set()
    if not M.opts.auto_detect then return end

    local buf = vim.api.nvim_get_current_buf()

    if not is_valid_buffer(buf) then return end

    if vim.bo[buf].buftype ~= "" or not vim.api.nvim_buf_is_valid(buf) then return end

    local raw_text = get_sample_text(buf, M.opts.lines_to_check)

    -- Without enough text, abort
    if not raw_text or #raw_text < 30 then return end

    local script_lang = detect_script(raw_text)

    if script_lang ~= "latin" then
        local target = M.opts.lang_mapping[script_lang]
        if target then vim.bo[buf].spelllang = target end
        return
    end

    local text = clean_text(raw_text)
    local doc_profile = get_document_profile(text)

    local lowest_distance = math.huge
    local detected_lang = nil

    local langs_to_check = M.opts.limit_languages or vim.tbl_keys(M.opts.lang_mapping)

    for _, lang_code in ipairs(langs_to_check) do
        if lang_code ~= "zh" and lang_code ~= "ru" then
            local lang_profile = load_lang_profile(lang_code)
            if lang_profile then
                local dist = calculate_distance(doc_profile, lang_profile)
                if dist < lowest_distance then
                    lowest_distance = dist
                    detected_lang = lang_code
                end
            end
        end
    end

    if detected_lang then
        local target_spelllang = M.opts.lang_mapping[detected_lang]
        if target_spelllang and vim.bo[buf].spelllang ~= target_spelllang then
            local function apply()
                vim.bo[buf].spelllang = target_spelllang
                vim.notify("Autolang: " .. detected_lang, vim.log.levels.INFO)
            end

            if M.opts.interactive then
                vim.ui.select({ "Yes", "No" }, {
                    prompt = "Change language to " .. target_spelllang .. "?",
                }, function(choice)
                    if choice == "Yes" then apply() end
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
                vim.defer_fn(M.detect_and_set, 100)
            end,
        })
    end

    -- Detection
    vim.api.nvim_create_user_command("AutolangDetect", function()
        -- Força a execução mesmo se auto_detect for false, mas respeita valid buffer
        local old_val = M.opts.auto_detect
        M.opts.auto_detect = true
        M.detect_and_set()
        M.opts.auto_detect = old_val
    end, {})

    -- Toggle Commands
    vim.api.nvim_create_user_command("AutolangEnable", function()
        M.opts.auto_detect = true
        vim.notify("Autolang enabled", vim.log.levels.INFO)
    end, {})

    vim.api.nvim_create_user_command("AutolangDisable", function()
        M.opts.auto_detect = false
        vim.notify("Autolang disabled", vim.log.levels.INFO)
    end, {})
end

-- Register health check
M.health = require("autolang.health")

return M
