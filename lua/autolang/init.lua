local config = require("autolang.config")

local M = {}
M.opts = {}

local profiles_cache = {}
local MAX_PENALTY = 300
--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------
local function is_valid_buffer(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return false
    end
    if vim.bo[buf].buftype ~= "" then
        return false
    end

    -- Ignore binary
    if vim.bo[buf].binary then
        return false
    end

    -- Ignore big files (> 1MB) to avoid freezing UI
    local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
    if ok and stats and stats.size > 1024 * 1024 then
        return false
    end

    return true
end

local function utf8_codes(str)
    local i = 1
    return function()
        if i > #str then
            return nil
        end
        local byte = string.byte(str, i)
        local code, width = 0, 0

        -- UTF-8 manual decoding
        if byte < 128 then
            code, width = byte, 1
        elseif byte < 224 then
            -- 2 bytes
            local b2 = string.byte(str, i + 1) or 0
            code, width = ((byte - 192) * 64) + (b2 - 128), 2
        elseif byte < 240 then
            -- 3 bytes (CJK)
            local b2 = string.byte(str, i + 1) or 0
            local b3 = string.byte(str, i + 2) or 0
            code, width = ((byte - 224) * 4096) + ((b2 - 128) * 64) + (b3 - 128), 3
        else
            -- 4 bytes (Emojis, etc) - Ignore
            width = 4
        end

        i = i + width
        return code
    end
end
--------------------------------------------------------------------------------
-- Tree-sitter
--------------------------------------------------------------------------------

local ts_queries = {
    -- === Markup & Prose ===

    typst = [[ (text) @content ]],

    markdown = [[
        (paragraph) @content
        (inline) @content
    ]],

    org = [[ (paragraph) @content ]],

    html = [[ (text) @content ]],

    latex = [[ (text) @content ]],

    gitcommit = [[ (message) @content ]],

    -- === Web ===

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

    css = [[ (comment) @content ]],

    scss = [[ (comment) @content ]],

    -- === Programming ===

    lua = [[
        (comment) @content
        (string_content) @content
    ]],

    python = [[
        (comment) @content
        (string_content) @content
    ]],

    rust = [[
        (line_comment) @content
        (block_comment) @content
        (string_literal) @content
    ]],

    go = [[
        (comment) @content
        (interpreted_string_literal) @content
        (raw_string_literal) @content
    ]],

    c = [[
        (comment) @content
        (string_literal) @content
    ]],

    cpp = [[
        (comment) @content
        (string_literal) @content
        (raw_string_literal) @content
    ]],

    java = [[
        (line_comment) @content
        (block_comment) @content
        (string_literal) @content
    ]],

    bash = [[
        (comment) @content
        (string) @content
    ]],

    cs = [[
        (comment) @content
        (string_literal) @content
        (interpolated_string_expression) @content
    ]],

    kotlin = [[
        (comment) @content
        (line_comment) @content
        (multiline_comment) @content
        (string_literal) @content
    ]],

    swift = [[
        (line_comment) @content
        (block_comment) @content
        (line_string_literal) @content
        (multiline_string_literal) @content
    ]],

    scala = [[
        (comment) @content
        (string_literal) @content
        (interpolated_string_expression) @content
    ]],

    php = [[
        (comment) @content
        (string) @content
        (encapsed_string) @content
        (heredoc) @content
    ]],

    ruby = [[
        (comment) @content
        (string) @content
        (heredoc_body) @content
    ]],

    ps1 = [[
        (comment) @content
        (string_literal) @content
        (expandable_string_literal) @content
    ]],

    perl = [[
        (comment) @content
        (string_literal) @content
    ]],

    sql = [[
        (comment) @content
        (string_literal) @content
    ]],

    r = [[
        (comment) @content
        (string) @content
    ]],

    julia = [[
        (line_comment) @content
        (block_comment) @content
        (string_literal) @content
        (triple_string_literal) @content
    ]],

    matlab = [[
        (comment) @content
        (string_literal) @content
        (char_literal) @content
    ]],

    elixir = [[
        (comment) @content
        (string) @content
        (sigil) @content
        (heredoc) @content
    ]],

    erlang = [[
        (comment) @content
        (string) @content
    ]],

    haskell = [[
        (comment) @content
        (string) @content
    ]],

    clojure = [[
        (comment) @content
        (string_literal) @content
        (regex_literal) @content
    ]],

    lisp = [[
        (comment) @content
        (string_literal) @content
    ]],

    ocaml = [[
        (comment) @content
        (string_literal) @content
        (quoted_string) @content
    ]],

    fsharp = [[
        (line_comment) @content
        (block_comment) @content
        (string) @content
        (triple_quoted_string) @content
    ]],

    zig = [[
        (line_comment) @content
        (doc_comment) @content
        (string_literal) @content
        (multiline_string_literal) @content
    ]],

    fortran = [[
        (comment) @content
        (string_literal) @content
    ]],

    cobol = [[
        (comment_line) @content
        (alphanumeric_literal) @content
    ]],

    -- === Data ===

    yaml = [[
        (comment) @content
        (string_scalar) @content
    ]],

    json = [[ (string) @content ]],

    toml = [[
        (comment) @content
        (string) @content
    ]],

    xml = [[ (text) @content ]],
}

local function get_text_with_treesitter(buf)
    local ft = vim.bo[buf].filetype
    local query_string = ts_queries[ft]

    if not query_string then
        return nil
    end

    local ok, parser = pcall(vim.treesitter.get_parser, buf, ft)
    if not ok or not parser then
        return nil
    end

    local tree = parser:parse()[1]
    if not tree then
        return nil
    end

    local root = tree:root()
    local ok_query, query = pcall(vim.treesitter.query.parse, ft, query_string)
    if not ok_query then
        return nil
    end

    local text_parts = {}
    local char_count = 0
    local LIMIT_CHARS = 2000

    -- ORG-MODE:
    -- Define 'stop_row' (ex: line 100).
    -- Tree-sitter ignores everything below.
    local stop_row = 100

    for _, node, _ in query:iter_captures(root, buf, 0, stop_row) do
        local node_text = vim.treesitter.get_node_text(node, buf)

        table.insert(text_parts, node_text)

        char_count = char_count + #node_text
        if char_count > LIMIT_CHARS then
            break
        end
    end

    return table.concat(text_parts, " ")
end

local function get_sample_text(buf, lines_limit)
    local MAX_CHARS = 2000

    -- Tree-sitter
    local ts_text = get_text_with_treesitter(buf)
    if ts_text and #ts_text > 50 then
        -- Trunc to avoid needless processing
        return string.sub(ts_text, 1, MAX_CHARS):lower()
    end

    -- Fallback
    local lines = vim.api.nvim_buf_get_lines(buf, 0, lines_limit, false)
    local full_text = table.concat(lines, " ")

    return string.sub(full_text, 1, MAX_CHARS):lower()
end

--------------------------------------------------------------------------------
-- Text & Trigrams
--------------------------------------------------------------------------------

local function clean_text(text)
    if not text then
        return ""
    end
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
                local tri = padded:sub(i, i + 2)
                counts[tri] = (counts[tri] or 0) + 1
            end
        end
    end

    local sorted_trigrams = {}
    for tri, count in pairs(counts) do
        table.insert(sorted_trigrams, { tri = tri, count = count })
    end

    table.sort(sorted_trigrams, function(a, b)
        return a.count > b.count
    end)

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
    if profiles_cache[lang_code] then
        return profiles_cache[lang_code]
    end

    local status, trigram_list = pcall(require, "autolang.trigrams." .. lang_code)
    if not status or type(trigram_list) ~= "table" then
        return nil
    end

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
    -- Just the first 1000 characters
    local limit = math.min(#text_sample, 1000)
    local sample = text_sample:sub(1, limit)

    for code in utf8_codes(sample) do
        -- CJK Unified Ideographs: U+4E00 (20992) to U+9FFF (40959)
        if code >= 0x4E00 and code <= 0x9FFF then
            return "zh"
        end

        -- Cirílic: U+0400 (1024) to U+04FF (1279)
        if code >= 0x0400 and code <= 0x04FF then
            return "ru"
        end
    end

    return "latin"
end

--------------------------------------------------------------------------------
-- Função de Desempate (PT vs ES)
--------------------------------------------------------------------------------

local function disambiguate_pt_es(text, detected_lang)
    -- Se não for nem PT nem ES, não faz nada
    if detected_lang ~= "es" and detected_lang ~= "pt_BR" and detected_lang ~= "pt_PT" and detected_lang ~= "pt" then
        return detected_lang
    end

    -- Marcadores fortes de Português
    -- ã, õ, ç, ê, ô, à (o til e a cedilha são os mais fortes)
    if vim.fn.match(text, "[ãõçêôà]") > -1 then
        -- Se detectou ES mas tem 'ç', vira PT-BR (ou PT-PT se preferir lógica mais complexa)
        if detected_lang == "es" then
            return "pt_BR"
        end
        return detected_lang
    end

    -- Marcadores fortes de Espanhol
    -- ñ, ¿, ¡, ó (ó existe em PT, mas a frequência em final de palavra difere. Vamos focar no ñ)
    if vim.fn.match(text, "[ñ¿¡]") > -1 then
        if detected_lang == "pt_BR" or detected_lang == "pt_PT" or detected_lang == "pt" then
            return "es"
        end
    end

    -- Fallback: Se não tem caracteres especiais, confia nos trigramas
    return detected_lang
end

--------------------------------------------------------------------------------
-- Main logic
--------------------------------------------------------------------------------

function M.detect_and_set()
    if not M.opts.auto_detect then
        return
    end

    local buf = vim.api.nvim_get_current_buf()

    if not is_valid_buffer(buf) then
        return
    end

    if vim.bo[buf].buftype ~= "" or not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    local raw_text = get_sample_text(buf, M.opts.lines_to_check)

    -- Without enough text, abort
    if not raw_text or #raw_text < 30 then
        return
    end

    local script_lang = detect_script(raw_text)

    if script_lang ~= "latin" then
        local target = M.opts.lang_mapping[script_lang]
        if target then
            vim.bo[buf].spelllang = target
        end
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
        detected_lang = disambiguate_pt_es(text, detected_lang)
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
                    if choice == "Yes" then
                        apply()
                    end
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
        -- Force execution even if auto_detect false, but only on valid buffer
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
