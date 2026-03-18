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
  Inventory,
  Loot,
  Rules,
  Status,
};

// Sub-type for ${CoOptUI.Inventory.Count}
enum class CoOptUIInventoryMembers { Count = 1 };
class MQ2CoOptUIInventoryType : public MQ2Type {
 public:
  MQ2CoOptUIInventoryType() : MQ2Type("cooptui_inventory") {
    ScopedTypeMember(CoOptUIInventoryMembers, Count);
  }
  bool GetMember(MQVarPtr VarPtr, const char* Member, char* Index, MQTypeVar& Dest) override {
    (void)VarPtr;
    (void)Index;
    MQTypeMember* pMember = FindMember(Member);
    if (!pMember) return false;
    if (static_cast<CoOptUIInventoryMembers>(pMember->ID) == CoOptUIInventoryMembers::Count) {
      Dest.Type = datatypes::pIntType;
      Dest.Int = static_cast<int>(cooptui::core::CacheManager::Instance().GetInventoryCount());
      return true;
    }
    return false;
  }
};

// Sub-type for ${CoOptUI.Loot.Count}
enum class CoOptUILootMembers { Count = 1 };
class MQ2CoOptUILootType : public MQ2Type {
 public:
  MQ2CoOptUILootType() : MQ2Type("cooptui_loot") {
    ScopedTypeMember(CoOptUILootMembers, Count);
  }
  bool GetMember(MQVarPtr VarPtr, const char* Member, char* Index, MQTypeVar& Dest) override {
    (void)VarPtr;
    (void)Index;
    MQTypeMember* pMember = FindMember(Member);
    if (!pMember) return false;
    if (static_cast<CoOptUILootMembers>(pMember->ID) == CoOptUILootMembers::Count) {
      Dest.Type = datatypes::pIntType;
      Dest.Int = static_cast<int>(cooptui::core::CacheManager::Instance().GetLootCount());
      return true;
    }
    return false;
  }
};

// Sub-type for ${CoOptUI.Rules.Evaluate[sell,itemname]}
enum class CoOptUIRulesMembers { Evaluate = 1 };
class MQ2CoOptUIRulesType : public MQ2Type {
 public:
  MQ2CoOptUIRulesType() : MQ2Type("cooptui_rules") {
    ScopedTypeMember(CoOptUIRulesMembers, Evaluate);
  }
  bool GetMember(MQVarPtr VarPtr, const char* Member, char* Index, MQTypeVar& Dest) override {
    (void)VarPtr;
    MQTypeMember* pMember = FindMember(Member);
    if (!pMember) return false;
    if (static_cast<CoOptUIRulesMembers>(pMember->ID) != CoOptUIRulesMembers::Evaluate)
      return false;
    // Index format: "sell,itemname" for sell decision
    std::string indexStr(Index ? Index : "");
    std::string result = "keep";
    size_t comma = indexStr.find(',');
    if (comma != std::string::npos) {
      std::string ruleType = indexStr.substr(0, comma);
      std::string itemName = indexStr.substr(comma + 1);
      while (!itemName.empty() && itemName.front() == ' ') itemName.erase(0, 1);
      if (ruleType == "sell" && !itemName.empty()) {
        cooptui::core::CoOptItemData probe;
        probe.name = itemName;
        auto [willSell, reason] = cooptui::rules::RulesEngine::Instance().WillItemBeSold(probe);
        (void)reason;
        result = willSell ? "sell" : "keep";
      }
    }
    strcpy_s(DataTypeTemp, result.c_str());
    Dest.Type = datatypes::pStringType;
    Dest.Ptr = &DataTypeTemp[0];
    return true;
  }
};

static MQ2CoOptUIInventoryType* pCoOptUIInventoryType = nullptr;
static MQ2CoOptUILootType* pCoOptUILootType = nullptr;
static MQ2CoOptUIRulesType* pCoOptUIRulesType = nullptr;
// Non-null dummy so macro parser passes VarPtr to GetMember (some paths skip when Ptr is null).
static char s_coOptUIDummy = 0;

static std::string GetCoOptUIStatusString() {
  auto& cache = cooptui::core::CacheManager::Instance();
  if (!cache.IsInitialized()) return "Loading";
  if (cache.IsInventoryDirty() || cache.IsBankDirty() || cache.IsLootDirty())
    return "Scanning";
  return "Ready";
}

class MQ2CoOptUIType : public MQ2Type {
 public:
  MQ2CoOptUIType() : MQ2Type("cooptui") {
    ScopedTypeMember(CoOptUIMembers, Version);
    ScopedTypeMember(CoOptUIMembers, APIVersion);
    ScopedTypeMember(CoOptUIMembers, MQCommit);
    ScopedTypeMember(CoOptUIMembers, Debug);
    ScopedTypeMember(CoOptUIMembers, Inventory);
    ScopedTypeMember(CoOptUIMembers, Loot);
    ScopedTypeMember(CoOptUIMembers, Rules);
    ScopedTypeMember(CoOptUIMembers, Status);
  }

  bool GetMember(MQVarPtr VarPtr, const char* Member, char* Index, MQTypeVar& Dest) override {
    (void)VarPtr;
    (void)Index;
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
    case CoOptUIMembers::Inventory:
      Dest.Type = pCoOptUIInventoryType;
      Dest.Ptr = &s_coOptUIDummy;
      return true;
    case CoOptUIMembers::Loot:
      Dest.Type = pCoOptUILootType;
      Dest.Ptr = &s_coOptUIDummy;
      return true;
    case CoOptUIMembers::Rules:
      Dest.Type = pCoOptUIRulesType;
      Dest.Ptr = &s_coOptUIDummy;
      return true;
    case CoOptUIMembers::Status: {
      std::string status = GetCoOptUIStatusString();
      strcpy_s(DataTypeTemp, status.c_str());
      Dest.Type = datatypes::pStringType;
      Dest.Ptr = &DataTypeTemp[0];
      return true;
    }
    }
    return false;
  }
};

static MQ2CoOptUIType* pCoOptUIType = nullptr;

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
  cooptui::core::Log(0, "  IPC: ChannelCapacity=%zu", cooptui::ipc::GetMaxChannelSize());
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
  uint64_t t0 = cooptui::core::MonotonicUs();
  cooptui::rules::RulesEngine::Instance().Reload();
  cooptui::core::CacheManager::Instance().RecordRulesLoadMs(
      cooptui::core::ElapsedMsFromUs(t0, cooptui::core::MonotonicUs()));
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
    // Macro command often wraps payload in quotes to preserve spaces/pipes.
    // Strip one level so Lua consumers receive the raw message body.
    if (message.size() >= 2) {
      char q = message.front();
      if ((q == '"' || q == '\'') && message.back() == q) {
        message = message.substr(1, message.size() - 2);
      }
    }
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
    uint64_t t0 = cooptui::core::MonotonicUs();
    cooptui::rules::RulesEngine::Instance().Reload();
    uint64_t elapsed = cooptui::core::ElapsedMsFromUs(t0, cooptui::core::MonotonicUs());
    cooptui::core::CacheManager::Instance().RecordRulesLoadMs(elapsed);
    auto& re = cooptui::rules::RulesEngine::Instance();
    cooptui::core::Log(0, "Rules reloaded in %llu ms: keep=%zu junk=%zu alwaysLoot=%zu skipLoot=%zu epicSell=%zu",
                       elapsed, re.GetKeepSetSize(), re.GetJunkSetSize(),
                       re.GetAlwaysLootSize(), re.GetSkipLootSize(), re.GetEpicSellSize());
    return;
  }
  if (strcmp(szLine, "perf") == 0) {
    auto& cache = cooptui::core::CacheManager::Instance();
    auto pr = [](const char* name, const cooptui::core::CacheManager::PerfStats& s) {
      uint64_t avg = s.count ? (s.totalMs / s.count) : 0;
      cooptui::core::Log(0, "  %s: count=%u avg=%llu ms max=%llu ms", name, s.count, avg, s.maxMs);
    };
    cooptui::core::Log(0, "MQ2CoOptUI perf counters:");
    pr("inv   ", cache.GetInventoryPerf());
    pr("bank  ", cache.GetBankPerf());
    pr("loot  ", cache.GetLootPerf());
    pr("sell  ", cache.GetSellPerf());
    pr("rules ", cache.GetRulesLoadPerf());
    return;
  }
  if (strncmp(szLine, "perf reset", 10) == 0 && (szLine[10] == '\0' || szLine[10] == ' ')) {
    cooptui::core::CacheManager::Instance().ResetPerf();
    cooptui::core::Log(0, "Perf counters reset.");
    return;
  }
  if (strncmp(szLine, "stress loot ", 12) == 0) {
    const char* arg = szLine + 12;
    while (*arg == ' ') ++arg;
    int n = std::atoi(arg);
    if (n <= 0 || n > 10000) {
      cooptui::core::Log(0, "Usage: /cooptui stress loot <count> (1-10000)");
      return;
    }
    uint64_t t0 = cooptui::core::MonotonicUs();
    cooptui::scanners::LootScanner::Instance().RunStressScan(static_cast<size_t>(n));
    uint64_t elapsed = cooptui::core::ElapsedMsFromUs(t0, cooptui::core::MonotonicUs());
    cooptui::core::Log(0, "Stress loot %d items: %llu ms", n, elapsed);
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
    uint64_t t0 = cooptui::core::MonotonicUs();
    const auto& items = cooptui::scanners::InventoryScanner::Instance().Scan(/*force=*/true);
    // Attach sell status to the live cache copy
    cooptui::rules::RulesEngine::Instance().AttachSellStatus(
        cooptui::core::CacheManager::Instance().GetInventoryMut());
    uint64_t elapsed = cooptui::core::ElapsedMsFromUs(t0, cooptui::core::MonotonicUs());
    cooptui::core::CacheManager::Instance().RecordInventoryScanMs(elapsed);
    // Count items flagged for sell
    int sellCount = 0;
    for (const auto& it : items) { if (it.willSell) ++sellCount; }
    cooptui::core::Log(0, "Inventory scan: %zu items in %llu ms (%d will sell)",
                       items.size(), elapsed, sellCount);
    return;
  }
  if (strncmp(szLine, "scan bank", 9) == 0 && (szLine[9] == '\0' || szLine[9] == ' ')) {
    uint64_t t0 = cooptui::core::MonotonicUs();
    const auto& items = cooptui::scanners::BankScanner::Instance().Scan(/*force=*/true);
    uint64_t elapsed = cooptui::core::ElapsedMsFromUs(t0, cooptui::core::MonotonicUs());
    cooptui::core::CacheManager::Instance().RecordBankScanMs(elapsed);
    bool bankOpen = cooptui::scanners::BankScanner::IsBankWindowOpen();
    cooptui::core::Log(0, "Bank scan: %zu items in %llu ms (bank window %s)",
                       items.size(), elapsed, bankOpen ? "open" : "closed, showing snapshot");
    return;
  }
  if (strncmp(szLine, "scan loot", 9) == 0 && (szLine[9] == '\0' || szLine[9] == ' ')) {
    uint64_t t0 = cooptui::core::MonotonicUs();
    const auto& items = cooptui::scanners::LootScanner::Instance().Scan(/*force=*/true);
    uint64_t elapsed = cooptui::core::ElapsedMsFromUs(t0, cooptui::core::MonotonicUs());
    cooptui::core::CacheManager::Instance().RecordLootScanMs(elapsed);
    bool lootOpen = cooptui::scanners::LootScanner::IsLootWindowOpen();
    int lootCount = 0;
    for (const auto& it : items) { if (it.willLoot) ++lootCount; }
    cooptui::core::Log(0, "Loot scan: %zu items in %llu ms (%d will loot, loot window %s)",
                       items.size(), elapsed, lootCount, lootOpen ? "open" : "closed");
    return;
  }
  if (strncmp(szLine, "test getitem ", 13) == 0) {
    const char* rest = szLine + 13;
    while (*rest == ' ') ++rest;
    int bag = 0, slot = 0;
    char srcBuf[32] = {0};
    if (sscanf_s(rest, "%d %d %31s", &bag, &slot, srcBuf, static_cast<unsigned>(sizeof(srcBuf))) < 3) {
      cooptui::core::Log(0, "Usage: /cooptui test getitem <bag> <slot> <source>");
      cooptui::core::Log(0, "  source: inv | bank | equipped | corpse | loot");
      cooptui::core::Log(0, "  inv: bag 1-10, slot 1-based. equipped: slot 0-22 (0-based).");
      return;
    }
    std::string source(srcBuf);
    auto opt = cooptui::items::GetItemData(bag, slot, source);
    if (!opt) {
      cooptui::core::Log(0, "getItem(%d, %d, \"%s\") -> nil (empty or invalid)", bag, slot, source.c_str());
      return;
    }
    const auto& d = *opt;
    cooptui::core::Log(0, "getItem(%d, %d, \"%s\") -> id=%d name=\"%s\" type=%s value=%d stack=%d",
                       bag, slot, source.c_str(), d.id, d.name.c_str(), d.type.c_str(),
                       d.value, d.stackSize);
    cooptui::core::Log(0, "  wornSlots=%s augType=%d augRestrictions=%d ac=%d hp=%d proc=%d focus=%d",
                       d.wornSlots.c_str(), d.augType, d.augRestrictions, d.ac, d.hp, d.proc, d.focus);
    return;
  }
  if (strncmp(szLine, "test cursor", 11) == 0 && (szLine[11] == '\0' || szLine[11] == ' ')) {
    cooptui::cursor::LogCursorState();
    return;
  }
  if (strncmp(szLine, "scan sell", 9) == 0 && (szLine[9] == '\0' || szLine[9] == ' ')) {
    uint64_t t0 = cooptui::core::MonotonicUs();
    const auto& items = cooptui::scanners::SellScanner::Instance().Scan(/*force=*/true);
    uint64_t elapsed = cooptui::core::ElapsedMsFromUs(t0, cooptui::core::MonotonicUs());
    cooptui::core::CacheManager::Instance().RecordSellScanMs(elapsed);
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

  cooptui::core::Log(0, "Usage: /cooptui status | reload | reloadrules | scan inv | scan bank | scan loot | scan sell | test getitem <bag> <slot> <source> | test cursor | perf | perf reset | stress loot <N> | eval sell <name> | eval loot <name> | debug <0-3> | ipc send <channel> <message>");
}

PLUGIN_API void InitializePlugin() {
  // Register TLO and command FIRST so they always work, even if config init fails.
  pCoOptUIInventoryType = new MQ2CoOptUIInventoryType();
  pCoOptUILootType = new MQ2CoOptUILootType();
  pCoOptUIRulesType = new MQ2CoOptUIRulesType();
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
    uint64_t t0 = cooptui::core::MonotonicUs();
    cooptui::rules::RulesEngine::Instance().Initialize(gPathMacros);
    cooptui::core::CacheManager::Instance().RecordRulesLoadMs(
        cooptui::core::ElapsedMsFromUs(t0, cooptui::core::MonotonicUs()));
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
  delete pCoOptUIRulesType;
  pCoOptUIRulesType = nullptr;
  delete pCoOptUILootType;
  pCoOptUILootType = nullptr;
  delete pCoOptUIInventoryType;
  pCoOptUIInventoryType = nullptr;
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
    uint64_t t0 = cooptui::core::MonotonicUs();
    cooptui::scanners::BankScanner::Instance().Scan(/*force=*/true);
    cooptui::core::CacheManager::Instance().RecordBankScanMs(
        cooptui::core::ElapsedMsFromUs(t0, cooptui::core::MonotonicUs()));
    cooptui::core::CacheManager::Instance().IncrementBankVersion();
    cooptui::core::Log(1, "OnPulse: bank opened, auto-scanned %zu items",
                       cooptui::core::CacheManager::Instance().GetBankCount());
  }
  s_wasBankOpen = bankOpen;

  // Loot window: auto-scan on open (once per open event)
  bool lootOpen = cooptui::scanners::LootScanner::IsLootWindowOpen();
  if (lootOpen && !s_wasLootOpen) {
    uint64_t t0 = cooptui::core::MonotonicUs();
    cooptui::scanners::LootScanner::Instance().Scan(/*force=*/true);
    cooptui::core::CacheManager::Instance().RecordLootScanMs(
        cooptui::core::ElapsedMsFromUs(t0, cooptui::core::MonotonicUs()));
    cooptui::core::CacheManager::Instance().IncrementLootVersion();
    cooptui::core::Log(1, "OnPulse: loot opened, auto-scanned %zu items",
                       cooptui::core::CacheManager::Instance().GetLootCount());
  }
  s_wasLootOpen = lootOpen;

  // Inventory: lightweight fingerprint check — run InventoryScanner (cheap when
  // unchanged due to fingerprint cache) and bump version only when content changes.
  if (pLocalPC) {
    uint64_t t0 = cooptui::core::MonotonicUs();
    cooptui::scanners::InventoryScanner::Instance().Scan(/*force=*/false);
    cooptui::core::CacheManager::Instance().RecordInventoryScanMs(
        cooptui::core::ElapsedMsFromUs(t0, cooptui::core::MonotonicUs()));
    if (cooptui::scanners::InventoryScanner::Instance().HasChanged()) {
      cooptui::core::CacheManager::Instance().IncrementInventoryVersion();
      // Fix 2: Sell status is Lua's domain. C++ scan only; Lua attaches status on next scanInventory.
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

  // Version counter aliases: maybeScan* polls these to skip rescans when cache is fresh.
  mod["getInventoryVersion"] = items_table["getInventoryVersion"];
  mod["getBankVersion"] = items_table["getBankVersion"];
  mod["getLootVersion"] = items_table["getLootVersion"];
  mod["getSellVersion"] = items_table["getSellVersion"];

  outModule = sol::object(mod);
  return true;
}
