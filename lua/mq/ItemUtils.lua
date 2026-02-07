--[[
    MQ ItemUtils - Shared item formatting helpers for ItemUI, SellUI, BankUI, etc.
    MacroQuest2 best practice: Use local/require for shared code to avoid duplication.
--]]

local ItemUtils = {}

-- Cache for formatValue (reduces allocations when same values formatted repeatedly, e.g. in tables)
local FORMAT_VALUE_CACHE_SIZE = 64
local formatValueCache = {}
local formatValueCacheKeys = {}

local function formatValueImpl(copperValue)
    if not copperValue or copperValue == 0 then return "0c" end
    local plat = math.floor(copperValue / 1000)
    local gold = math.floor((copperValue % 1000) / 100)
    local silver = math.floor((copperValue % 100) / 10)
    local copper = copperValue % 10
    if plat > 0 then return string.format("%dp %dg", plat, gold) end
    if gold > 0 then return string.format("%dg %ds", gold, silver) end
    if silver > 0 then return string.format("%ds %dc", silver, copper) end
    return string.format("%dc", copper)
end

--- Format copper value to plat/gold/silver/copper string
--- @param copperValue number Copper value (1000 = 1 plat)
--- @return string Formatted value string
function ItemUtils.formatValue(copperValue)
    if not copperValue or copperValue == 0 then return "0c" end
    local cv = math.floor(copperValue)
    local cached = formatValueCache[cv]
    if cached then return cached end
    local result = formatValueImpl(cv)
    if #formatValueCacheKeys >= FORMAT_VALUE_CACHE_SIZE then
        local evict = table.remove(formatValueCacheKeys, 1)
        formatValueCache[evict] = nil
    end
    formatValueCache[cv] = result
    formatValueCacheKeys[#formatValueCacheKeys + 1] = cv
    return result
end

-- formatWeight cache (weight values often repeat in tables)
local formatWeightCache = {}
local formatWeightCacheKeys = {}
local FORMAT_WEIGHT_CACHE_SIZE = 32

--- Format weight (EQ uses tenths - 10 = 1.0)
--- @param weight number Weight in tenths
--- @return string Formatted weight string
function ItemUtils.formatWeight(weight)
    if not weight or weight == 0 then return "0.0" end
    local w = math.floor(weight)
    local cached = formatWeightCache[w]
    if cached then return cached end
    local result = string.format("%.1f", w / 10.0)
    if #formatWeightCacheKeys >= FORMAT_WEIGHT_CACHE_SIZE then
        formatWeightCache[table.remove(formatWeightCacheKeys, 1)] = nil
    end
    formatWeightCache[w] = result
    formatWeightCacheKeys[#formatWeightCacheKeys + 1] = w
    return result
end

return ItemUtils
