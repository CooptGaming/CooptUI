#include "RulesEngine.h"

#include <Windows.h>
#include <algorithm>
#include <cctype>
#include <cstring>

#include "../core/Config.h"
#include "../core/Logger.h"

namespace cooptui {
namespace rules {

// ---------------------------------------------------------------------------
// Singleton
// ---------------------------------------------------------------------------
RulesEngine& RulesEngine::Instance() {
  static RulesEngine instance;
  return instance;
}

// ---------------------------------------------------------------------------
// Path builders
// ---------------------------------------------------------------------------

// Ensure the macros path ends with a backslash.
static std::string EnsureTrailingSlash(const std::string& p) {
  if (p.empty()) return p;
  char last = p.back();
  if (last != '\\' && last != '/') return p + '\\';
  return p;
}

std::string RulesEngine::SellPath(const char* file) const {
  return EnsureTrailingSlash(macrosPath_) + "sell_config\\" + file;
}

std::string RulesEngine::SharedPath(const char* file) const {
  return EnsureTrailingSlash(macrosPath_) + "shared_config\\" + file;
}

std::string RulesEngine::LootPath(const char* file) const {
  return EnsureTrailingSlash(macrosPath_) + "loot_config\\" + file;
}

// ---------------------------------------------------------------------------
// INI helpers (Win32 — same as capabilities/ini.cpp pattern)
// ---------------------------------------------------------------------------

std::string RulesEngine::ReadIni(const std::string& path, const char* section,
                                  const char* key,
                                  const char* defaultVal) const {
  if (path.empty()) return defaultVal ? defaultVal : "";
  char buf[4096] = {};
  DWORD len = GetPrivateProfileStringA(section, key, defaultVal ? defaultVal : "",
                                       buf, static_cast<DWORD>(sizeof(buf)),
                                       path.c_str());
  return std::string(buf, len);
}

// Read chunked list: key, key2, key3... up to 20 chunks, join with '/'.
std::string RulesEngine::ReadChunkedList(const std::string& path,
                                          const char* section,
                                          const char* key) const {
  if (path.empty()) return "";
  std::string result;
  char buf[4096] = {};
  char keyBuf[64] = {};

  for (int i = 1; i <= 20; ++i) {
    if (i == 1) {
      snprintf(keyBuf, sizeof(keyBuf), "%s", key);
    } else {
      snprintf(keyBuf, sizeof(keyBuf), "%s%d", key, i);
    }
    DWORD len = GetPrivateProfileStringA(section, keyBuf, "",
                                         buf, static_cast<DWORD>(sizeof(buf)),
                                         path.c_str());
    if (len == 0) break;
    if (!result.empty()) result += '/';
    result.append(buf, len);
  }
  return result;
}

// ---------------------------------------------------------------------------
// String helpers
// ---------------------------------------------------------------------------

std::string RulesEngine::TrimStr(const std::string& s) {
  size_t a = s.find_first_not_of(" \t\r\n");
  if (a == std::string::npos) return "";
  size_t b = s.find_last_not_of(" \t\r\n");
  return s.substr(a, b - a + 1);
}

bool RulesEngine::IsValidEntry(const std::string& s) {
  if (s.empty()) return false;
  std::string lo = s;
  std::transform(lo.begin(), lo.end(), lo.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return lo != "null" && lo != "nil";
}

// Normalize item name for epic list lookup: trim + collapse multiple spaces.
std::string RulesEngine::NormalizeName(const std::string& s) {
  std::string t = TrimStr(s);
  std::string out;
  out.reserve(t.size());
  bool lastSpace = false;
  for (char c : t) {
    if (c == ' ' || c == '\t') {
      if (!lastSpace && !out.empty()) { out += ' '; lastSpace = true; }
    } else {
      out += c;
      lastSpace = false;
    }
  }
  return out;
}

void RulesEngine::ParseSlashList(const std::string& raw,
                                  std::unordered_set<std::string>& outSet) {
  if (raw.empty()) return;
  size_t start = 0;
  while (start <= raw.size()) {
    size_t end = raw.find('/', start);
    if (end == std::string::npos) end = raw.size();
    std::string item = TrimStr(raw.substr(start, end - start));
    if (IsValidEntry(item)) outSet.insert(item);
    start = end + 1;
  }
}

void RulesEngine::ParseSlashList(const std::string& raw,
                                  std::vector<std::string>& outVec) {
  if (raw.empty()) return;
  size_t start = 0;
  while (start <= raw.size()) {
    size_t end = raw.find('/', start);
    if (end == std::string::npos) end = raw.size();
    std::string item = TrimStr(raw.substr(start, end - start));
    if (IsValidEntry(item)) outVec.push_back(item);
    start = end + 1;
  }
}

// ---------------------------------------------------------------------------
// Epic item set loader — mirrors Lua loadEpicItemSetByClass()
// ---------------------------------------------------------------------------
static const char* kEpicClasses[] = {
    "bard", "beastlord", "berserker", "cleric", "druid", "enchanter",
    "magician", "monk", "necromancer", "paladin", "ranger", "rogue",
    "shadow_knight", "shaman", "warrior", "wizard"};

std::unordered_set<std::string> RulesEngine::LoadEpicItemSet() const {
  std::unordered_set<std::string> set;
  std::string classesIni = SharedPath("epic_classes.ini");
  bool anySelected = false;

  for (const char* cls : kEpicClasses) {
    std::string val = ReadIni(classesIni, "Classes", cls, "FALSE");
    if (val == "TRUE") {
      anySelected = true;
      std::string classIni = SharedPath((std::string("epic_items_") + cls + ".ini").c_str());
      std::string raw = ReadChunkedList(classIni, "Items", "exact");
      // Parse normalized names
      size_t start = 0;
      while (start <= raw.size()) {
        size_t end = raw.find('/', start);
        if (end == std::string::npos) end = raw.size();
        std::string item = NormalizeName(raw.substr(start, end - start));
        if (IsValidEntry(item)) set.insert(item);
        start = end + 1;
      }
    }
  }

  if (!anySelected) return set;

  // Fallback: if classes selected but all per-class files empty, use full list
  if (set.empty()) {
    std::string fallbackIni = SharedPath("epic_items_exact.ini");
    std::string raw = ReadChunkedList(fallbackIni, "Items", "exact");
    size_t start = 0;
    while (start <= raw.size()) {
      size_t end = raw.find('/', start);
      if (end == std::string::npos) end = raw.size();
      std::string item = NormalizeName(raw.substr(start, end - start));
      if (IsValidEntry(item)) set.insert(item);
      start = end + 1;
    }
  }

  return set;
}

// ---------------------------------------------------------------------------
// Sell config loader
// ---------------------------------------------------------------------------
void RulesEngine::LoadSellConfig() {
  sell_ = SellConfig{};  // reset to defaults

  // --- Flags ---
  auto flagIni = SellPath("sell_flags.ini");
  sell_.protectNoDrop      = ReadIni(flagIni, "Settings", "protectNoDrop",      "TRUE") == "TRUE";
  sell_.protectNoTrade     = ReadIni(flagIni, "Settings", "protectNoTrade",     "TRUE") == "TRUE";
  sell_.protectLore        = ReadIni(flagIni, "Settings", "protectLore",        "TRUE") == "TRUE";
  sell_.protectQuest       = ReadIni(flagIni, "Settings", "protectQuest",       "TRUE") == "TRUE";
  sell_.protectCollectible = ReadIni(flagIni, "Settings", "protectCollectible", "TRUE") == "TRUE";
  sell_.protectHeirloom    = ReadIni(flagIni, "Settings", "protectHeirloom",    "TRUE") == "TRUE";
  sell_.protectEpic        = ReadIni(flagIni, "Settings", "protectEpic",        "TRUE") == "TRUE";
  sell_.protectAttuneable  = ReadIni(flagIni, "Settings", "protectAttuneable",  "FALSE") == "TRUE";
  sell_.protectAugSlots    = ReadIni(flagIni, "Settings", "protectAugSlots",    "FALSE") == "TRUE";

  // --- Values ---
  auto valIni = SellPath("sell_value.ini");
  sell_.minSell  = std::stoi(ReadIni(valIni, "Settings", "minSellValue",          "50"));
  sell_.minStack = std::stoi(ReadIni(valIni, "Settings", "minSellValueStack",     "10"));
  sell_.maxKeep  = std::stoi(ReadIni(valIni, "Settings", "maxKeepValue",          "10000"));
  sell_.tributeKeepOverride = std::stoi(ReadIni(valIni, "Settings", "tributeKeepOverride", "1000"));

  // --- Keep sets ---
  ParseSlashList(ReadChunkedList(SharedPath("valuable_exact.ini"),    "Items", "exact"),   sell_.keepSet);
  ParseSlashList(ReadIni(SellPath("sell_keep_exact.ini"),             "Items", "exact", ""), sell_.keepSet);

  // --- Junk sets ---
  ParseSlashList(ReadChunkedList(SellPath("sell_always_sell_exact.ini"), "Items", "exact"), sell_.junkSet);
  ParseSlashList(ReadChunkedList(SellPath("sell_always_sell_contains.ini"), "Items", "contains"), sell_.junkContainsList);

  // --- Augment overrides ---
  ParseSlashList(ReadIni(SellPath("sell_augment_always_sell_exact.ini"), "Items", "exact", ""), sell_.augmentAlwaysSellSet);

  // --- NeverLoot sell sets (loot_skip -> sell them when in inventory) ---
  ParseSlashList(ReadChunkedList(LootPath("loot_skip_exact.ini"),          "Items", "exact"), sell_.neverLootSellSet);
  ParseSlashList(ReadChunkedList(LootPath("loot_augment_skip_exact.ini"),  "Items", "exact"), sell_.augmentNeverLootSellSet);

  // --- Protected types ---
  ParseSlashList(ReadChunkedList(SellPath("sell_protected_types.ini"), "Items", "types"), sell_.protectedTypeSet);

  // --- Keep contains (shared + sell) ---
  ParseSlashList(ReadChunkedList(SharedPath("valuable_contains.ini"), "Items", "contains"), sell_.keepContainsList);
  ParseSlashList(ReadIni(SellPath("sell_keep_contains.ini"),          "Items", "contains", ""), sell_.keepContainsList);

  // --- Keep types (shared + sell_keep + protected) ---
  ParseSlashList(ReadChunkedList(SharedPath("valuable_types.ini"),        "Items", "types"), sell_.keepTypeSet);
  ParseSlashList(ReadIni(SellPath("sell_keep_types.ini"),                 "Items", "types", ""), sell_.keepTypeSet);
  // protected types also go into keepTypeSet (same as Lua)
  for (const auto& t : sell_.protectedTypeSet) sell_.keepTypeSet.insert(t);

  // --- Epic items ---
  if (sell_.protectEpic) {
    sell_.epicItemSet = LoadEpicItemSet();
  }
}

// ---------------------------------------------------------------------------
// Loot config loader
// ---------------------------------------------------------------------------
void RulesEngine::LoadLootConfig() {
  loot_ = LootConfig{};  // reset to defaults

  // --- Values ---
  auto valIni = LootPath("loot_value.ini");
  loot_.minLootValue      = std::stoi(ReadIni(valIni, "Settings", "minLootValue",      "999"));
  loot_.minLootValueStack = std::stoi(ReadIni(valIni, "Settings", "minLootValueStack", "200"));
  loot_.tributeOverride   = std::stoi(ReadIni(valIni, "Settings", "tributeOverride",   "0"));

  // --- Flags ---
  auto flagIni = LootPath("loot_flags.ini");
  loot_.lootClickies     = ReadIni(flagIni, "Settings", "lootClickies",     "FALSE") == "TRUE";
  loot_.lootQuest        = ReadIni(flagIni, "Settings", "lootQuest",        "FALSE") == "TRUE";
  loot_.lootCollectible  = ReadIni(flagIni, "Settings", "lootCollectible",  "FALSE") == "TRUE";
  loot_.lootHeirloom     = ReadIni(flagIni, "Settings", "lootHeirloom",     "FALSE") == "TRUE";
  loot_.lootAttuneable   = ReadIni(flagIni, "Settings", "lootAttuneable",   "FALSE") == "TRUE";
  loot_.lootAugSlots     = ReadIni(flagIni, "Settings", "lootAugSlots",     "FALSE") == "TRUE";
  loot_.alwaysLootEpic   = ReadIni(flagIni, "Settings", "alwaysLootEpic",   "TRUE")  == "TRUE";

  // --- Skip lists ---
  ParseSlashList(ReadChunkedList(LootPath("loot_skip_exact.ini"),         "Items", "exact"),    loot_.skipExactSet);
  ParseSlashList(ReadChunkedList(LootPath("loot_augment_skip_exact.ini"), "Items", "exact"),    loot_.augmentSkipExactSet);
  ParseSlashList(ReadChunkedList(LootPath("loot_skip_contains.ini"),      "Items", "contains"), loot_.skipContainsList);
  ParseSlashList(ReadChunkedList(LootPath("loot_skip_types.ini"),         "Items", "types"),    loot_.skipTypeSet);

  // --- Always loot (shared + loot-specific, merged) ---
  ParseSlashList(ReadChunkedList(SharedPath("valuable_exact.ini"),        "Items", "exact"),    loot_.alwaysLootExactSet);
  ParseSlashList(ReadChunkedList(LootPath("loot_always_exact.ini"),       "Items", "exact"),    loot_.alwaysLootExactSet);
  ParseSlashList(ReadChunkedList(SharedPath("valuable_contains.ini"),     "Items", "contains"), loot_.alwaysLootContainsList);
  ParseSlashList(ReadChunkedList(LootPath("loot_always_contains.ini"),    "Items", "contains"), loot_.alwaysLootContainsList);
  ParseSlashList(ReadChunkedList(SharedPath("valuable_types.ini"),        "Items", "types"),    loot_.alwaysLootTypeSet);
  ParseSlashList(ReadChunkedList(LootPath("loot_always_types.ini"),       "Items", "types"),    loot_.alwaysLootTypeSet);

  // --- Epic items ---
  if (loot_.alwaysLootEpic) {
    loot_.epicItemSet = LoadEpicItemSet();
  }
}

// ---------------------------------------------------------------------------
// Initialize / Reload
// ---------------------------------------------------------------------------
void RulesEngine::Initialize(const std::string& macrosPath) {
  macrosPath_ = macrosPath;
  Reload();
}

void RulesEngine::Reload() {
  if (macrosPath_.empty()) return;
  try {
    LoadSellConfig();
    LoadLootConfig();
    loaded_ = true;
    int dbg = core::Config::Instance().GetDebugLevel();
    if (dbg >= 1) {
      core::Log(1, "RulesEngine: reloaded. keep=%zu junk=%zu alwaysLoot=%zu skipLoot=%zu epic(sell)=%zu",
                sell_.keepSet.size(), sell_.junkSet.size(),
                loot_.alwaysLootExactSet.size(), loot_.skipExactSet.size(),
                sell_.epicItemSet.size());
    }
  } catch (const std::exception& ex) {
    core::Log(0, "RulesEngine::Reload error: %s", ex.what());
  }
}

// ---------------------------------------------------------------------------
// Sell evaluation — exact mirror of Lua willItemBeSold() steps 0a-19
// ---------------------------------------------------------------------------
std::pair<bool, std::string> RulesEngine::WillItemBeSold(
    const core::CoOptItemData& item) const {
  const auto& c = sell_;

  // Augment-only overrides (step 0a)
  std::string itemType = TrimStr(item.type);
  if (itemType == "Augmentation") {
    if (c.augmentAlwaysSellSet.count(item.name))     return {true,  "AugmentAlwaysSell"};
    if (c.augmentNeverLootSellSet.count(item.name))  return {true,  "AugmentNeverLoot"};
  }
  if (c.neverLootSellSet.count(item.name))           return {true,  "NeverLoot"};

  // Step 1: NoDrop
  if (c.protectNoDrop   && item.nodrop)              return {false, "NoDrop"};
  // Step 2: NoTrade
  if (c.protectNoTrade  && item.notrade)             return {false, "NoTrade"};
  // Step 3: Epic
  if (!c.epicItemSet.empty()) {
    std::string epicKey = NormalizeName(item.name);
    if (c.epicItemSet.count(epicKey))                return {false, "Epic"};
  }
  // Step 4: Keep exact
  if (c.keepSet.count(item.name))                    return {false, "Keep"};
  // Step 5: Junk exact
  if (c.junkSet.count(item.name))                    return {true,  "Junk"};
  // Step 6: Keep contains
  for (const auto& kw : c.keepContainsList) {
    if (item.name.find(kw) != std::string::npos)     return {false, "KeepKeyword"};
  }
  // Step 7: Junk contains
  for (const auto& kw : c.junkContainsList) {
    if (item.name.find(kw) != std::string::npos)     return {true,  "JunkKeyword"};
  }
  // Step 8: Keep type
  if (c.keepTypeSet.count(itemType))                 return {false, "KeepType"};
  // Step 9: Protected type
  if (c.protectedTypeSet.count(itemType))            return {false, "ProtectedType"};
  // Step 10: Lore
  if (c.protectLore        && item.lore)             return {false, "Lore"};
  // Step 11: Quest
  if (c.protectQuest       && item.quest)            return {false, "Quest"};
  // Step 12: Collectible
  if (c.protectCollectible && item.collectible)      return {false, "Collectible"};
  // Step 13: Heirloom
  if (c.protectHeirloom    && item.heirloom)         return {false, "Heirloom"};
  // Step 14: Attuneable
  if (c.protectAttuneable  && item.attuneable)       return {false, "Attuneable"};
  // Step 15: AugSlots
  if (c.protectAugSlots    && item.augSlots > 0)     return {false, "AugSlots"};
  // Step 16: maxKeepValue
  if (c.maxKeep > 0 && item.totalValue >= c.maxKeep) return {false, "HighValue"};
  // Step 17: tributeKeepOverride
  if (c.tributeKeepOverride > 0 && item.tribute >= c.tributeKeepOverride)
                                                     return {false, "Tribute"};
  // Step 18: minSellValue
  bool isStack = item.stackSize > 1;
  int  minVal  = isStack ? c.minStack : c.minSell;
  if (item.value < minVal)                           return {false, "BelowSell"};
  // Step 19: default sell
  return {true, "Sell"};
}

// ---------------------------------------------------------------------------
// Loot evaluation — exact mirror of Lua shouldItemBeLooted()
// ---------------------------------------------------------------------------
std::pair<bool, std::string> RulesEngine::ShouldItemBeLooted(
    const core::CoOptItemData& item) const {
  if (!loaded_) return {false, "NoConfig"};
  const auto& c = loot_;

  std::string itemType = TrimStr(item.type);
  std::string epicKey  = NormalizeName(item.name);

  // Augment-only skip (highest priority)
  if (itemType == "Augmentation" && c.augmentSkipExactSet.count(item.name))
    return {false, "AugmentNeverLoot"};

  // Epic always loot (before skip lists)
  if (c.alwaysLootEpic && !c.epicItemSet.empty() && !epicKey.empty() &&
      c.epicItemSet.count(epicKey))
    return {true, "Epic"};

  // Skip lists
  if (c.skipExactSet.count(item.name))               return {false, "SkipExact"};
  for (const auto& kw : c.skipContainsList) {
    if (item.name.find(kw) != std::string::npos)     return {false, "SkipContains"};
  }
  if (c.skipTypeSet.count(itemType))                 return {false, "SkipType"};

  // Tribute override
  if (c.tributeOverride > 0 && item.tribute >= c.tributeOverride)
    return {true, "TributeOverride"};

  // Always loot exact
  if (c.alwaysLootExactSet.count(item.name))         return {true,  "AlwaysExact"};

  // Always loot contains
  for (const auto& kw : c.alwaysLootContainsList) {
    if (item.name.find(kw) != std::string::npos)     return {true, "AlwaysContains"};
  }

  // Always loot type
  if (c.alwaysLootTypeSet.count(itemType))           return {true, "AlwaysType"};

  // Value check
  bool isStack = item.stackSize > 1;
  int  minVal  = isStack ? c.minLootValueStack : c.minLootValue;
  if (item.value >= minVal)                          return {true, "Value"};

  // Flag checks
  if (c.lootClickies && item.clicky > 0 && !item.wornSlots.empty())
    return {true, "Clicky"};
  if (c.lootQuest       && item.quest)               return {true, "Quest"};
  if (c.lootCollectible && item.collectible)         return {true, "Collectible"};
  if (c.lootHeirloom    && item.heirloom)            return {true, "Heirloom"};
  if (c.lootAttuneable  && item.attuneable)          return {true, "Attuneable"};
  if (c.lootAugSlots    && item.augSlots > 0)        return {true, "AugSlots"};

  return {false, "NoMatch"};
}

// ---------------------------------------------------------------------------
// Batch: attach sell status to all items in a vector
// ---------------------------------------------------------------------------
void RulesEngine::AttachSellStatus(std::vector<core::CoOptItemData>& items) const {
  if (!loaded_) return;
  for (auto& item : items) {
    auto [willSell, reason] = WillItemBeSold(item);
    item.willSell  = willSell;
    item.sellReason = reason;
  }
}

}  // namespace rules
}  // namespace cooptui
