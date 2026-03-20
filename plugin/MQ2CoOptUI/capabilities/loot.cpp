#include "loot.h"

#include <mq/Plugin.h>
#include <sol/sol.hpp>
#include <string>

#include "../core/CacheManager.h"
#include "../core/ItemData.h"
#include "../core/ItemDataToTable.h"
#include "../core/Logger.h"
#include "../scanners/LootScanner.h"

namespace cooptui {
namespace loot {

void registerLua(sol::state_view L, sol::table& table) {
  lua_State* rawL = L.lua_state();

  table.set_function("scanLootItems", [rawL]() -> sol::table {
    sol::state_view sv(rawL);
    uint64_t t0 = core::MonotonicUs();
    const auto& items = scanners::LootScanner::Instance().Scan();
    core::CacheManager::Instance().RecordLootScanMs(
        core::ElapsedMsFromUs(t0, core::MonotonicUs()));
    sol::table result = sv.create_table_with();
    for (const auto& d : items) {
      result.add(core::ItemDataToTable(sv, d));
    }
    return result;
  });
}

}  // namespace loot
}  // namespace cooptui
