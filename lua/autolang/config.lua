local M = {}

M.defaults = {
    auto_detect = true,

    lines_to_check = 100,

    interactive = false,

    -- Exemple: { "en", "pt" }
    limit_languages = nil,

    -- Achtung:
    -- Keys must be the name of the trigram file
    -- inside 'lua/autolang/trigrams/' (without .lua extension).
    -- Values are the Vim's 'set spelllang=...'.
    lang_mapping = {
        -- Latin trigram files
        en    = "en",    -- Loads: lua/autolang/trigrams/en.lua
        pt_BR = "pt_br",    -- Loads: lua/autolang/trigrams/pt_BR.lua
        es    = "es",       -- Loads: lua/autolang/trigrams/es.lua
        fr    = "fr",       -- Loads: lua/autolang/trigrams/fr.lua
        de    = "de",       -- Loads: lua/autolang/trigrams/de.lua

        -- Script detection (Unicode)
        -- These are used when script detection (CJK/Cirílico) is enough.
        -- They do not need to be inside the trigrams directory.
        zh    = "cjk",      -- Chinese
        ru    = "ru",       -- Russian
    },
}

return M
