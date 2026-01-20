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
    local limit = math.min(#text_sample, 1000)
    local sample = text_sample:sub(1, limit)

    for code in utf8_codes(sample) do
        -- CJK Unified Ideographs
        if code >= 0x4E00 and code <= 0x9FFF then
            return "zh"
        end

        -- Hiragana & Katakana
        -- Hiragana: 3040-309F, Katakana: 30A0-30FF
        if code >= 0x3040 and code <= 0x30FF then
            return "jp"
        end

        -- Hangul
        if code >= 0xAC00 and code <= 0xD7A3 then
            return "ko"
        end

        -- Cirilic
        if code >= 0x0400 and code <= 0x04FF then
            return "ru"
        end

        -- Greek
        if code >= 0x0370 and code <= 0x03FF then
            return "el"
        end

        -- Hebraic
        if code >= 0x0590 and code <= 0x05FF then
            return "he"
        end

        -- Arabic
        if code >= 0x0600 and code <= 0x06FF then
            return "ar"
        end

        -- Tai
        if code >= 0x0E00 and code <= 0x0E7F then
            return "th"
        end
    end

    return "latin"
end

--------------------------------------------------------------------------------
-- Added Heuristic
--------------------------------------------------------------------------------

local function apply_heuristics(text, detected_lang)
    local t = text:lower()

    if vim.fn.match(t, "\\v\\W(the|and|is|with|for|to|of)\\W") > -1 then
        return "en"
    end

    if vim.fn.match(t, "\\v\\W(n[ãa]o|s[ãa]o|est[áa]|voc[êe]|com|uma)\\W") > -1 then
        return "pt_BR" -- TODO check if pt or pt_PT
    end
    if vim.fn.match(t, "[ãõçêô]") > -1 then
        return "pt_BR"
    end

    -- PT vs ES vs CA
    if
        detected_lang == "pt_BR"
        or detected_lang == "pt"
        or detected_lang == "pt_PT"
        or detected_lang == "es"
        or detected_lang == "ca"
    then
        -- Spanish: ñ, ¿, ¡, ' y ', ' con '
        if vim.fn.match(t, "[ñ¿¡]") > -1 or vim.fn.match(t, "\\v\\W(y|con|los|las|una)\\W") > -1 then
            return "es"
        end

        -- Catalan: 'i' (e), 'amb' (com), 'els' (os)
        if detected_lang == "ca" then
            if vim.fn.match(t, "\\v\\W(i|amb|els)\\W") == -1 then
                return "pt_BR"
            end
        end
    end

    return detected_lang
end

--------------------------------------------------------------------------------
-- Main logic
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Main logic
--------------------------------------------------------------------------------

local function merge_spelllangs(new_langs, current_langs, keep)
    local final = {}
    local seen = {}

    -- Add new detected languages
    for _, lang in ipairs(new_langs) do
        if not seen[lang] then
            table.insert(final, lang)
            seen[lang] = true
        end
    end

    -- Add current languages if keep is true
    if keep then
        local parts = vim.split(current_langs, ",")
        for _, lang in ipairs(parts) do
            lang = vim.trim(lang)
            if lang ~= "" and not seen[lang] then
                table.insert(final, lang)
                seen[lang] = true
            end
        end
    end

    return table.concat(final, ",")
end

function M.detect_and_set()
    if not M.opts.auto_detect then
        return
    end

    local buf = vim.api.nvim_get_current_buf()

    if not is_valid_buffer(buf) then
        return
    end

    local raw_text = get_sample_text(buf, M.opts.lines_to_check)

    -- Without enough text, abort
    if not raw_text or #raw_text < 30 then
        return
    end

    local current_spelllang = vim.bo[buf].spelllang
    local script_lang = detect_script(raw_text)

    -- 1. Script Detection (Fail Fast)
    if script_lang ~= "latin" then
        local target = M.opts.lang_mapping[script_lang]
        if target then
            local final_spelllang = merge_spelllangs({ target }, current_spelllang, M.opts.keep_default_spelllang)
            if vim.bo[buf].spelllang ~= final_spelllang then
                vim.bo[buf].spelllang = final_spelllang
                vim.notify("Autolang: " .. final_spelllang, vim.log.levels.INFO)
            end
        end
        return
    end

    -- 2. Trigram Detection
    local text = clean_text(raw_text)
    local doc_profile = get_document_profile(text)

    local candidates = {}
    local langs_to_check = M.opts.limit_languages or vim.tbl_keys(M.opts.lang_mapping)

    for _, lang_code in ipairs(langs_to_check) do
        -- Skip non-latin profiles that are handled by script detection
        if not vim.tbl_contains({ "zh", "ru", "jp", "ko", "el", "he", "ar", "th" }, lang_code) then
            local lang_profile = load_lang_profile(lang_code)
            if lang_profile then
                local dist = calculate_distance(doc_profile, lang_profile)
                table.insert(candidates, { lang = lang_code, dist = dist })
            end
        end
    end

    -- Sort by distance (lower is better)
    table.sort(candidates, function(a, b)
        return a.dist < b.dist
    end)

    if #candidates == 0 then
        return
    end

    -- 3. Select Top N Languages
    local top_n = M.opts.number_of_spelllangs or 1
    local selected_langs = {}

    -- Apply heuristics to the WINNER only
    -- If heuristics change the winner (e.g. pt -> pt_BR), we replace the winner
    local winner = candidates[1].lang
    local heuristic_winner = apply_heuristics(text, winner)
    
    table.insert(selected_langs, M.opts.lang_mapping[heuristic_winner] or heuristic_winner)

    -- Add runners-up (only if we need more than 1)
    if top_n > 1 then
        for i = 2, math.min(#candidates, top_n) do
            local code = candidates[i].lang
            table.insert(selected_langs, M.opts.lang_mapping[code] or code)
        end
    end

    -- 4. Apply Changes
    local final_spelllang = merge_spelllangs(selected_langs, current_spelllang, M.opts.keep_default_spelllang)

    if vim.bo[buf].spelllang ~= final_spelllang then
        local function apply()
            vim.bo[buf].spelllang = final_spelllang
            vim.notify("Autolang: " .. final_spelllang, vim.log.levels.INFO)
        end

        if M.opts.interactive then
            vim.ui.select({ "Yes", "No" }, {
                prompt = "Change language to " .. final_spelllang .. "?",
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
