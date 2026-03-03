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
#include "scanners/InventoryScanner.h"

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
  cooptui::core::Log(0, "  Cache state: inv=%zu/%zu (dirty=%s) bank=%zu/%zu (dirty=%s) loot=%zu/%zu (dirty=%s) sell=%zu",
                     cache.GetInventoryCount(), cache.GetInventoryReserve(),
                     cache.IsInventoryDirty() ? "yes" : "no",
                     cache.GetBankCount(), cache.GetBankReserve(),
                     cache.IsBankDirty() ? "yes" : "no",
                     cache.GetLootCount(), cache.GetLootReserve(),
                     cache.IsLootDirty() ? "yes" : "no",
                     cache.GetSellItemsCount());
}

static void CmdReload() {
  cooptui::core::Config::Instance().Reload();
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
  if (strcmp(szLine, "scan inv") == 0) {
    uint64_t t0 = GetTickCount64();
    const auto& items = cooptui::scanners::InventoryScanner::Instance().Scan(/*force=*/true);
    uint64_t elapsed = GetTickCount64() - t0;
    cooptui::core::Log(0, "Inventory scan: %zu items in %llu ms", items.size(), elapsed);
    return;
  }

  cooptui::core::Log(0, "Usage: /cooptui status | reload | scan inv | debug <0-3> | ipc send <channel> <message>");
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

  // Top-level aliases: scan.lua calls mod.scanInventory() / mod.scanBank() directly
  mod["scanInventory"] = items_table["scanInventory"];
  mod["scanBank"] = items_table["scanBank"];
  mod["hasInventoryChanged"] = items_table["hasInventoryChanged"];

  outModule = sol::object(mod);
  return true;
}
