--[[--
2-customisablesleepscreen-fix.lua
User patch for KOReader.
Automatically integrates the "Ninja Engine" physical page count from statistics.koplugin
into customisablesleepscreen.koplugin without modifying the plugin files.
This patch survives all plugin and KOReader updates.
--]]--

local logger = require("logger")
local userpatch = require("userpatch")

logger.info("[CSS-Fix] Initializing Customisable Sleep Screen Physical Page Patch...")

-- Helper: safely get nested table value
local function safeGet(obj, ...)
    for _, key in ipairs({ ... }) do
        if type(obj) ~= "table" then return nil end
        obj = obj[key]
    end
    return obj
end

-- Helper: Retrieve total physical pages for document
local function getPhysicalDocPages(ui, orig_func)
    -- 1. Check ninja engine global
    if _G.yanllsama_current_physical_pages and type(_G.yanllsama_current_physical_pages) == "number" and _G.yanllsama_current_physical_pages >= 1 then
        return math.floor(_G.yanllsama_current_physical_pages)
    end

    if ui and ui.doc_settings then
        local sync_enabled = nil
        if type(ui.doc_settings.readSetting) == "function" then
            sync_enabled = ui.doc_settings:readSetting("yanllsama_sync_enabled")
        end
        if sync_enabled == nil and ui.doc_settings.data then
            sync_enabled = ui.doc_settings.data.yanllsama_sync_enabled
        end
        if sync_enabled == nil then sync_enabled = true end

        if sync_enabled ~= false then
            local phys = nil
            if type(ui.doc_settings.readSetting) == "function" then
                phys = ui.doc_settings:readSetting("yanllsama_physical_pages")
            end
            if (not phys or type(phys) ~= "number") and ui.doc_settings.data then
                phys = ui.doc_settings.data.yanllsama_physical_pages
            end
            if type(phys) == "string" then phys = tonumber(phys) end
            if type(phys) == "number" and phys >= 1 then
                return math.floor(phys)
            end
        end
    end

    -- 2. Check statistics plugin cached pages
    if ui and ui.statistics and ui.statistics.data and type(ui.statistics.data.pages) == "number" and ui.statistics.data.pages >= 1 then
        local p = nil
        if ui.doc_settings and type(ui.doc_settings.readSetting) == "function" then
            p = ui.doc_settings:readSetting("yanllsama_physical_pages")
        end
        if p and p == ui.statistics.data.pages then
            return math.floor(p)
        end
    end

    if orig_func then
        local ok, res = pcall(orig_func, ui)
        if ok and type(res) == "number" and res >= 1 then return res end
    end
    return 1
end

-- Helper: Retrieve current physical page for document
local function getPhysicalDisplayPage(ui, state, orig_func)
    local cur_page = nil
    if orig_func then
        local ok, res = pcall(orig_func, ui, state)
        if ok and type(res) == "number" and res >= 1 then
            cur_page = res
        end
    end
    if not cur_page or type(cur_page) ~= "number" then
        if ui and ui.document and type(ui.document.getCurrentPage) == "function" then
            local ok, p = pcall(ui.document.getCurrentPage, ui.document)
            if ok and type(p) == "number" and p >= 1 then cur_page = p end
        end
        if not cur_page then
            cur_page = safeGet(state, "page")
                or safeGet(ui, "view", "state", "page")
                or safeGet(ui, "paging", "current_page")
                or 1
        end
    end

    if ui and ui.doc_settings then
        local sync_enabled = nil
        if type(ui.doc_settings.readSetting) == "function" then
            sync_enabled = ui.doc_settings:readSetting("yanllsama_sync_enabled")
        end
        if sync_enabled == nil and ui.doc_settings.data then
            sync_enabled = ui.doc_settings.data.yanllsama_sync_enabled
        end
        if sync_enabled == nil then sync_enabled = true end

        if sync_enabled ~= false then
            local max_phys = nil
            if type(ui.doc_settings.readSetting) == "function" then
                max_phys = ui.doc_settings:readSetting("yanllsama_physical_pages")
            end
            if (not max_phys or type(max_phys) ~= "number") and ui.doc_settings.data then
                max_phys = ui.doc_settings.data.yanllsama_physical_pages
            end
            if type(max_phys) == "string" then max_phys = tonumber(max_phys) end

            if type(max_phys) == "number" and max_phys >= 1 then
                max_phys = math.floor(max_phys)

                -- A. Directly from statistics plugin physical page tracker
                if ui.statistics then
                    if type(ui.statistics._phys_curr) == "number" and ui.statistics._phys_curr >= 1 then
                        return math.min(max_phys, math.floor(ui.statistics._phys_curr))
                    end
                    if type(ui.statistics._phys_next) == "number" and ui.statistics._phys_next >= 1 then
                        return math.min(max_phys, math.floor(ui.statistics._phys_next))
                    end
                end

                -- B. From Pagemap labels
                local pagemap = ui.pagemap or (ui.view and ui.view.pagemap)
                if pagemap and type(pagemap.getCurrentPageLabel) == "function" then
                    local use_labels = pagemap.use_page_labels
                    if use_labels == nil and ui.doc_settings.readSetting then
                        use_labels = ui.doc_settings:readSetting("pagemap_use_page_labels")
                    end
                    if use_labels ~= false then
                        local ok_lbl, lbl = pcall(pagemap.getCurrentPageLabel, pagemap, true)
                        local phys = ok_lbl and lbl and tonumber(lbl)
                        if phys and phys >= 1 then
                            return math.max(1, math.min(max_phys, math.floor(phys)))
                        end
                    end
                end

                -- C. Screen ratio conversion fallback
                local ratio = nil
                if type(ui.doc_settings.readSetting) == "function" then
                    ratio = ui.doc_settings:readSetting("yanllsama_screen_ratio")
                end
                if not ratio and ui.doc_settings.data then
                    ratio = ui.doc_settings.data.yanllsama_screen_ratio
                end
                if ui.doc_settings.readSetting and ui.doc_settings:readSetting("pagemap_chars_per_synthetic_page") then
                    ratio = 1.0
                end
                ratio = tonumber(ratio) or 1.0

                if ratio > 0 then
                    local phys
                    if ratio < 1.0 then
                        phys = math.floor((cur_page - 1) / ratio + 1.5)
                    else
                        phys = math.ceil(cur_page / ratio)
                    end
                    return math.max(1, math.min(max_phys, phys))
                end

                return math.min(max_phys, cur_page)
            end
        end
    end

    return cur_page
end

-- Patch function: apply physical page hooks to css_infobox_bookdata
local function patchBookdata(bookdata_mod)
    if not bookdata_mod or bookdata_mod._css_phys_patched then return end
    bookdata_mod._css_phys_patched = true

    local orig_getDocPages = bookdata_mod.getDocPages
    bookdata_mod.getDocPages = function(ui)
        return getPhysicalDocPages(ui, orig_getDocPages)
    end

    local orig_getDisplayPage = bookdata_mod.getDisplayPage
    bookdata_mod.getDisplayPage = function(ui, state)
        return getPhysicalDisplayPage(ui, state, orig_getDisplayPage)
    end

    -- Patch collectBookData upvalues
    if bookdata_mod.collectBookData then
        local idx = 1
        while true do
            local name, val = debug.getupvalue(bookdata_mod.collectBookData, idx)
            if not name then break end
            if name == "getDocPages" then
                debug.setupvalue(bookdata_mod.collectBookData, idx, bookdata_mod.getDocPages)
            elseif name == "getDisplayPage" then
                debug.setupvalue(bookdata_mod.collectBookData, idx, bookdata_mod.getDisplayPage)
            end
            idx = idx + 1
        end
    end
    logger.info("[CSS-Fix] Successfully patched css_infobox_bookdata")
end

-- Patch function: apply physical page hooks to css_infobox_sections
local function patchSections(sections_mod)
    if not sections_mod or sections_mod._css_phys_patched then return end
    sections_mod._css_phys_patched = true

    if sections_mod.buildBookSection then
        local idx = 1
        while true do
            local name, val = debug.getupvalue(sections_mod.buildBookSection, idx)
            if not name then break end
            if name == "getDocPages" then
                debug.setupvalue(sections_mod.buildBookSection, idx, function(ui)
                    return getPhysicalDocPages(ui, val)
                end)
            elseif name == "getDisplayPage" then
                debug.setupvalue(sections_mod.buildBookSection, idx, function(ui, state)
                    return getPhysicalDisplayPage(ui, state, val)
                end)
            end
            idx = idx + 1
        end
    end
    logger.info("[CSS-Fix] Successfully patched css_infobox_sections")
end

-- Patch function: apply physical page hooks to css_infobox
local function patchInfobox(ib_mod)
    if not ib_mod or ib_mod._css_phys_patched then return end
    ib_mod._css_phys_patched = true

    if ib_mod.collectBookData then
        local orig_collect = ib_mod.collectBookData
        ib_mod.collectBookData = function(ui, state)
            local data = orig_collect(ui, state)
            if data and ui then
                local phys_pages = getPhysicalDocPages(ui)
                if phys_pages and phys_pages > 1 then
                    data.doc_pages = phys_pages
                    data.display_page = getPhysicalDisplayPage(ui, state)
                end
            end
            return data
        end
    end

    if ib_mod.buildInfoBox then
        local orig_build = ib_mod.buildInfoBox
        ib_mod.buildInfoBox = function(ui, state, book_data)
            if book_data and ui then
                local phys_pages = getPhysicalDocPages(ui)
                if phys_pages and phys_pages > 1 then
                    book_data.doc_pages = phys_pages
                    book_data.display_page = getPhysicalDisplayPage(ui, state)
                end
            end
            return orig_build(ui, state, book_data)
        end
    end
    logger.info("[CSS-Fix] Successfully patched css_infobox")
end

-- Check already loaded modules
if package.loaded["css_infobox_bookdata"] then
    patchBookdata(package.loaded["css_infobox_bookdata"])
end
if package.loaded["css_infobox_sections"] then
    patchSections(package.loaded["css_infobox_sections"])
end
if package.loaded["css_infobox"] then
    patchInfobox(package.loaded["css_infobox"])
end

-- Global require interceptor to catch customisablesleepscreen submodules when loaded
local orig_require = require
_G.require = function(modname)
    local res = orig_require(modname)
    if modname == "css_infobox_bookdata" and type(res) == "table" then
        patchBookdata(res)
    elseif modname == "css_infobox_sections" and type(res) == "table" then
        patchSections(res)
    elseif modname == "css_infobox" and type(res) == "table" then
        patchInfobox(res)
    end
    return res
end

-- Register hook for customisablesleepscreen plugin instance creation
userpatch.registerPatchPluginFunc("customisablesleepscreen", function(plugin)
    logger.info("[CSS-Fix] customisablesleepscreen plugin loaded, verifying hooks...")
    if package.loaded["css_infobox_bookdata"] then
        patchBookdata(package.loaded["css_infobox_bookdata"])
    end
    if package.loaded["css_infobox_sections"] then
        patchSections(package.loaded["css_infobox_sections"])
    end
    if package.loaded["css_infobox"] then
        patchInfobox(package.loaded["css_infobox"])
    end
end)

logger.info("[CSS-Fix] Customisable Sleep Screen Physical Page Patch registered successfully.")