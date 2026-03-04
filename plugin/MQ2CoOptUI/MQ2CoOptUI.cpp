// MQ2CoOptUI - CoOpt UI native plugin. Build only inside MacroQuest clone (symlink this
// directory into MQ's plugins/ and use -DMQ_BUILD_CUSTOM_PLUGINS=ON).
// Provides: INI, IPC, window, items, loot capabilities via require("plugin.MQ2CoOptUI").

#include <mq/Plugin.h>
#include <sol/sol.hpp>
#include <Windows.h>
#include <cstdlib>
#include <cstring>
#include <string>

#include "capabilities/cursor.h"
#include "capabilities/ini.h"
#include "capabilities/ipc.h"
#include "capabilities/items.h"
#include "capabilities/loot.h"
#include "capabilities/window.h"
#include "core/CacheManager.h"
#include "core/Config.h"
#include "core/Logger.h"
#include "rules/RulesEngine.h"
#include "scanners/BankScanner.h"
#include "scanners/InventoryScanner.h"
#include "scanners/LootScanner.h"
#include "scanners/SellScanner.h"
#include "storage/SellCacheWriter.h"

PreSetup("MQ2CoOptUI");
PLUGIN_VERSION(1.0);

static constexpr int COOPTUI_API_VERSION = 1;

enum class CoOptUIMembers {
  Version = 1,
  APIVersion,
  MQCommit,
  Debug,
};

class MQ2CoOptUIType : public MQ2Type {
 public:
  MQ2CoOptUIType() : MQ2Type("cooptui") {
    ScopedTypeMember(CoOptUIMembers, Version);
    ScopedTypeMember(CoOptUIMembers, APIVersion);
    ScopedTypeMember(CoOptUIMembers, MQCommit);
    ScopedTypeMember(CoOptUIMembers, Debug);
  }

  bool GetMember(MQVarPtr VarPtr, const char* Member, char* Index, MQTypeVar& Dest) override {
    MQTypeMember* pMember = FindMember(Member);
    if (!pMember) return false;

    switch (static_cast<CoOptUIMembers>(pMember->ID)) {
    case CoOptUIMembers::Version:
      Dest.Type = datatypes::pStringType;
      strcpy_s(DataTypeTemp, "1.0.0");
      Dest.Ptr = &DataTypeTemp[0];
      return true;
    case CoOptUIMembers::APIVersion:
      Dest.Type = datatypes::pIntType;
      Dest.Int = COOPTUI_API_VERSION;
      return true;
    case CoOptUIMembers::MQCommit:
      Dest.Type = datatypes::pStringType;
      strcpy_s(DataTypeTemp, "unknown");
      Dest.Ptr = &DataTypeTemp[0];
      return true;
    case CoOptUIMembers::Debug:
      Dest.Type = datatypes::pBoolType;
      Dest.Set(false);
      return true;
    }
    return false;
  }
};

static MQ2CoOptUIType* pCoOptUIType = nullptr;
// Non-null dummy so macro parser passes VarPtr to GetMember (some paths skip when Ptr is null).
static char s_coOptUIDummy = 0;

bool CoOptUIData(const char* Index, MQTypeVar& Dest) {
  Dest.Type = pCoOptUIType;
  Dest.Ptr = &s_coOptUIDummy;  // type-only TLO; non-null so ${CoOptUI.Version} resolves
  return true;
}

static std::string GetCoOptCoreConfigPath() {
  // gPathConfig is MQ's own config directory (e.g. ...\CoOptUI7\config\).
  // It is populated by MQ before InitializePlugin is called and is the correct
  // place to store plugin configuration. GetModuleFileNameA(nullptr) would return
  // the EverQuest game process path (eqgame.exe), not the MQ install root.
  if (gPathConfig[0] != '\0') {
    std::string path(gPathConfig);
    if (path.back() != '\\' && path.back() != '/') path += '\\';
    return path + "CoOptCore.ini";
  }
  return std::string();
}

static void CmdStatus() {
  const auto& cfg = cooptui::core::Config::Instance().Get();
  cooptui::core::Log(0, "MQ2CoOptUI v1.0.0 — CoOptCore status");
  cooptui::core::Log(0, "  DebugLevel=%d  Config=%s", cfg.debugLevel,
                     cooptui::core::Config::Instance().GetConfigPath().c_str());
  cooptui::core::Log(0, "  Cache: InventoryReserve=%d BankReserve=%d LootReserve=%d ScanThrottleMs=%d",
                     cfg.inventoryReserve, cfg.bankReserve, cfg.lootReserve, cfg.scanThrottleMs);
  cooptui::core::Log(0, "  Rules: AutoReloadOnChange=%s", cfg.autoReloadOnChange ? "true" : "false");

  auto& cache = cooptui::core::CacheManager::Instance();
  cooptui::core::Log(0, "  Cache state: inv=%zu/%zu (dirty=%s v%u) bank=%zu/%zu (dirty=%s v%u) loot=%zu/%zu (dirty=%s v%u) sell=%zu (v%u)",
                     cache.GetInventoryCount(), cache.GetInventoryReserve(),
                     cache.IsInventoryDirty() ? "yes" : "no",
                     cache.GetInventoryVersion(),
                     cache.GetBankCount(), cache.GetBankReserve(),
                     cache.IsBankDirty() ? "yes" : "no",
                     cache.GetBankVersion(),
                     cache.GetLootCount(), cache.GetLootReserve(),
                     cache.IsLootDirty() ? "yes" : "no",
                     cache.GetLootVersion(),
                     cache.GetSellItemsCount(),
                     cache.GetSellVersion());

  auto& re = cooptui::rules::RulesEngine::Instance();
  if (re.IsLoaded()) {
    cooptui::core::Log(0, "  Rules: keep=%zu junk=%zu alwaysLoot=%zu skipLoot=%zu epicSell=%zu",
                       re.GetKeepSetSize(), re.GetJunkSetSize(),
                       re.GetAlwaysLootSize(), re.GetSkipLootSize(), re.GetEpicSellSize());
  } else {
    cooptui::core::Log(0, "  Rules: not loaded");
  }
}

static void CmdReload() {
  cooptui::core::Config::Instance().Reload();
  cooptui::rules::RulesEngine::Instance().Reload();
  cooptui::core::Log(0, "CoOptCore.ini reloaded.");
}

static void CmdDebug(const char* arg) {
  if (!arg) arg = "";
  while (*arg == ' ') ++arg;
  if (*arg == '\0') {
    cooptui::core::Log(0, "Usage: /cooptui debug <0-3>");
    return;
  }
  int level = std::atoi(arg);
  if (level < 0 || level > 3) {
    cooptui::core::Log(0, "Debug level must be 0-3.");
    return;
  }
  cooptui::core::Config::Instance().SetDebugLevel(level);
  cooptui::core::Log(0, "Debug level set to %d.", level);
}

static void CoOptUICommand(PlayerClient* pChar, const char* szLine) {
  (void)pChar;
  if (!szLine) return;
  while (*szLine == ' ') ++szLine;

  if (strncmp(szLine, "ipc send ", 9) == 0) {
    const char* rest = szLine + 9;
    while (*rest == ' ') ++rest;
    const char* space = strchr(rest, ' ');
    if (!space) {
      WriteChatf("\ag[MQ2CoOptUI]\ax Usage: /cooptui ipc send <channel> <message>");
      return;
    }
    std::string channel(rest, space - rest);
    while (*space == ' ') ++space;
    std::string message(space);
    cooptui::ipc::sendFromMacro(channel, message);
    return;
  }

  if (strcmp(szLine, "status") == 0) {
    CmdStatus();
    return;
  }
  if (strcmp(szLine, "reload") == 0) {
    CmdReload();
    return;
  }
  if (strncmp(szLine, "debug ", 6) == 0) {
    CmdDebug(szLine + 6);
    return;
  }
  if (strcmp(szLine, "reloadrules") == 0) {
    uint64_t t0 = GetTickCount64();
    cooptui::rules::RulesEngine::Instance().Reload();
    uint64_t elapsed = GetTickCount64() - t0;
    auto& re = cooptui::rules::RulesEngine::Instance();
    cooptui::core::Log(0, "Rules reloaded in %llu ms: keep=%zu junk=%zu alwaysLoot=%zu skipLoot=%zu epicSell=%zu",
                       elapsed, re.GetKeepSetSize(), re.GetJunkSetSize(),
                       re.GetAlwaysLootSize(), re.GetSkipLootSize(), re.GetEpicSellSize());
    return;
  }
  if (strncmp(szLine, "eval sell ", 10) == 0) {
    const char* itemName = szLine + 10;
    while (*itemName == ' ') ++itemName;
    if (*itemName == '\0') {
      cooptui::core::Log(0, "Usage: /cooptui eval sell <itemname>");
      return;
    }
    cooptui::core::CoOptItemData probe;
    probe.name = itemName;
    // Find a matching item in the inv cache for full field data
    const auto& inv = cooptui::core::CacheManager::Instance().GetInventory();
    for (const auto& it : inv) {
      if (it.name == itemName) { probe = it; break; }
    }
    auto [willSell, reason] = cooptui::rules::RulesEngine::Instance().WillItemBeSold(probe);
    cooptui::core::Log(0, "eval sell '%s': %s (%s)", itemName,
                       willSell ? "WILL SELL" : "keep", reason.c_str());
    return;
  }
  if (strncmp(szLine, "eval loot ", 10) == 0) {
    const char* itemName = szLine + 10;
    while (*itemName == ' ') ++itemName;
    if (*itemName == '\0') {
      cooptui::core::Log(0, "Usage: /cooptui eval loot <itemname>");
      return;
    }
    cooptui::core::CoOptItemData probe;
    probe.name = itemName;
    auto [shouldLoot, reason] = cooptui::rules::RulesEngine::Instance().ShouldItemBeLooted(probe);
    cooptui::core::Log(0, "eval loot '%s': %s (%s)", itemName,
                       shouldLoot ? "LOOT" : "skip", reason.c_str());
    return;
  }
  if (strncmp(szLine, "scan inv", 8) == 0 && (szLine[8] == '\0' || szLine[8] == ' ')) {
    uint64_t t0 = GetTickCount64();
    const auto& items = cooptui::scanners::InventoryScanner::Instance().Scan(/*force=*/true);
    // Attach sell status to the live cache copy
    cooptui::rules::RulesEngine::Instance().AttachSellStatus(
        cooptui::core::CacheManager::Instance().GetInventoryMut());
    uint64_t elapsed = GetTickCount64() - t0;
    // Count items flagged for sell
    int sellCount = 0;
    for (const auto& it : items) { if (it.willSell) ++sellCount; }
    cooptui::core::Log(0, "Inventory scan: %zu items in %llu ms (%d will sell)",
                       items.size(), elapsed, sellCount);
    return;
  }
  if (strncmp(szLine, "scan bank", 9) == 0 && (szLine[9] == '\0' || szLine[9] == ' ')) {
    uint64_t t0 = GetTickCount64();
    const auto& items = cooptui::scanners::BankScanner::Instance().Scan(/*force=*/true);
    uint64_t elapsed = GetTickCount64() - t0;
    bool bankOpen = cooptui::scanners::BankScanner::IsBankWindowOpen();
    cooptui::core::Log(0, "Bank scan: %zu items in %llu ms (bank window %s)",
                       items.size(), elapsed, bankOpen ? "open" : "closed, showing snapshot");
    return;
  }
  if (strncmp(szLine, "scan loot", 9) == 0 && (szLine[9] == '\0' || szLine[9] == ' ')) {
    uint64_t t0 = GetTickCount64();
    const auto& items = cooptui::scanners::LootScanner::Instance().Scan(/*force=*/true);
    uint64_t elapsed = GetTickCount64() - t0;
    bool lootOpen = cooptui::scanners::LootScanner::IsLootWindowOpen();
    int lootCount = 0;
    for (const auto& it : items) { if (it.willLoot) ++lootCount; }
    cooptui::core::Log(0, "Loot scan: %zu items in %llu ms (%d will loot, loot window %s)",
                       items.size(), elapsed, lootCount, lootOpen ? "open" : "closed");
    return;
  }
  if (strncmp(szLine, "scan sell", 9) == 0 && (szLine[9] == '\0' || szLine[9] == ' ')) {
    uint64_t t0 = GetTickCount64();
    const auto& items = cooptui::scanners::SellScanner::Instance().Scan(/*force=*/true);
    uint64_t elapsed = GetTickCount64() - t0;
    size_t sellCount = cooptui::scanners::SellScanner::Instance().GetSellCount();
    cooptui::core::Log(0, "Sell scan: %zu items in %llu ms (%zu will sell)",
                       items.size(), elapsed, sellCount);
    // Write sell cache
    if (!items.empty() && gPathMacros[0] != '\0' &&
        pLocalPlayer && pLocalPlayer->Name[0] != '\0') {
      uint64_t tw = GetTickCount64();
      bool wrote = cooptui::storage::SellCacheWriter::Write(
          std::string(gPathMacros), std::string(pLocalPlayer->Name), items);
      uint64_t elapsedWrite = GetTickCount64() - tw;
      cooptui::core::Log(0, "  sell_cache.ini written=%s in %llu ms (%zu sell items, char=%s)",
                         wrote ? "yes" : "no", elapsedWrite, sellCount, pLocalPlayer->Name);
    } else {
      cooptui::core::Log(0, "  sell_cache.ini not written (no char/macros path)");
    }
    return;
  }

  cooptui::core::Log(0, "Usage: /cooptui status | reload | reloadrules | scan inv | scan bank | scan loot | scan sell | eval sell <name> | eval loot <name> | debug <0-3> | ipc send <channel> <message>");
}

PLUGIN_API void InitializePlugin() {
  // Register TLO and command FIRST so they always work, even if config init fails.
  pCoOptUIType = new MQ2CoOptUIType();
  AddMQ2Data("CoOptUI", CoOptUIData);
  AddCommand("/cooptui", CoOptUICommand);

  std::string configPath = GetCoOptCoreConfigPath();
  if (!configPath.empty()) {
    cooptui::core::Config::Instance().Initialize(configPath);
  } else {
    WriteChatf("\ay[MQ2CoOptUI]\ax Config path not found — CoOptCore.ini will not be used.");
  }
  cooptui::core::CacheManager::Instance().Initialize(cooptui::core::Config::Instance().Get());

  // Initialize rules engine from the MQ macros directory.
  if (gPathMacros[0] != '\0') {
    cooptui::rules::RulesEngine::Instance().Initialize(gPathMacros);
  }

  WriteChatf("\ag[MQ2CoOptUI]\ax v1.0.0 loaded — INI, IPC, cursor, items, loot, window capabilities ready.");
  WriteChatf("\ag[MQ2CoOptUI]\ax TLO: ${CoOptUI.Version}  Lua: require('plugin.MQ2CoOptUI')  /cooptui status");
}

PLUGIN_API void ShutdownPlugin() {
  RemoveCommand("/cooptui");
  RemoveMQ2Data("CoOptUI");
  cooptui::core::CacheManager::Instance().Shutdown();
  delete pCoOptUIType;
  pCoOptUIType = nullptr;
  WriteChatf("\ay[MQ2CoOptUI]\ax Unloaded.");
}

PLUGIN_API void OnPulse() {
  cooptui::cursor::updateFromPulse();
  cooptui::core::CacheManager::Instance().OnPulse();

  // Phase 8: Throttled window-state detection and inventory change tracking.
  // Static state persists across pulses; throttled at 100ms to avoid per-frame cost.
  static uint64_t s_lastEventCheckMs = 0;
  static bool s_wasBankOpen = false;
  static bool s_wasLootOpen = false;
  static uint64_t s_lastInvFingerprint = 0;

  uint64_t now = GetTickCount64();
  if (now - s_lastEventCheckMs < 100) return;
  s_lastEventCheckMs = now;

  // Bank window: auto-scan on open (once per open event)
  bool bankOpen = cooptui::scanners::BankScanner::IsBankWindowOpen();
  if (bankOpen && !s_wasBankOpen) {
    cooptui::scanners::BankScanner::Instance().Scan(/*force=*/true);
    cooptui::core::CacheManager::Instance().IncrementBankVersion();
    cooptui::core::Log(1, "OnPulse: bank opened, auto-scanned %zu items",
                       cooptui::core::CacheManager::Instance().GetBankCount());
  }
  s_wasBankOpen = bankOpen;

  // Loot window: auto-scan on open (once per open event)
  bool lootOpen = cooptui::scanners::LootScanner::IsLootWindowOpen();
  if (lootOpen && !s_wasLootOpen) {
    cooptui::scanners::LootScanner::Instance().Scan(/*force=*/true);
    cooptui::core::CacheManager::Instance().IncrementLootVersion();
    cooptui::core::Log(1, "OnPulse: loot opened, auto-scanned %zu items",
                       cooptui::core::CacheManager::Instance().GetLootCount());
  }
  s_wasLootOpen = lootOpen;

  // Inventory: lightweight fingerprint check — run InventoryScanner (cheap when
  // unchanged due to fingerprint cache) and bump version only when content changes.
  if (pLocalPC) {
    cooptui::scanners::InventoryScanner::Instance().Scan(/*force=*/false);
    if (cooptui::scanners::InventoryScanner::Instance().HasChanged()) {
      cooptui::core::CacheManager::Instance().IncrementInventoryVersion();
      // Also re-attach sell status since inventory changed
      cooptui::rules::RulesEngine::Instance().AttachSellStatus(
          cooptui::core::CacheManager::Instance().GetInventoryMut());
      cooptui::core::CacheManager::Instance().IncrementSellVersion();
      // Bump inventory fingerprint stored in scanner
      s_lastInvFingerprint = cooptui::core::CacheManager::Instance().GetInventoryVersion();
      cooptui::core::Log(1, "OnPulse: inventory changed, version=%u",
                         cooptui::core::CacheManager::Instance().GetInventoryVersion());
    }
  }
}

// Zone transition hooks (Phase 8): invalidate stale caches on zone change.
PLUGIN_API void OnBeginZone() {
  cooptui::core::CacheManager::Instance().InvalidateAll();
  cooptui::scanners::InventoryScanner::Instance().Invalidate();
  cooptui::core::Log(1, "OnBeginZone: all caches invalidated (version bumped)");
}

PLUGIN_API void OnEndZone() {
  // Zone fully loaded — re-invalidate inventory so next scan gets fresh data.
  cooptui::core::CacheManager::Instance().InvalidateInventory();
  cooptui::scanners::InventoryScanner::Instance().Invalidate();
  cooptui::core::Log(1, "OnEndZone: inventory cache invalidated (version bumped)");
}

extern "C" PLUGIN_API bool CreateLuaModule(sol::this_state L, sol::object& outModule) {
  sol::state_view lua(L);
  sol::table mod = lua.create_table();

  sol::table ini_table = lua.create_table();
  cooptui::ini::registerLua(lua, ini_table);
  mod["ini"] = ini_table;

  sol::table ipc_table = lua.create_table();
  cooptui::ipc::registerLua(lua, ipc_table);
  mod["ipc"] = ipc_table;

  sol::table window_table = lua.create_table();
  cooptui::window::registerLua(lua, window_table);
  mod["window"] = window_table;

  sol::table items_table = lua.create_table();
  cooptui::items::registerLua(lua, items_table);
  mod["items"] = items_table;

  sol::table loot_table = lua.create_table();
  cooptui::loot::registerLua(lua, loot_table);
  mod["loot"] = loot_table;

  sol::table cursor_table = lua.create_table();
  cooptui::cursor::registerLua(lua, cursor_table);
  mod["cursor"] = cursor_table;

  // Top-level aliases: scan.lua calls these directly (no sub-table lookup needed)
  mod["scanInventory"] = items_table["scanInventory"];
  mod["scanBank"] = items_table["scanBank"];
  mod["hasInventoryChanged"] = items_table["hasInventoryChanged"];
  mod["scanLootItems"] = loot_table["scanLootItems"];
  mod["scanSellItems"] = items_table["scanSellItems"];

  outModule = sol::object(mod);
  return true;
}
