#include "items.h"

#include <mq/Plugin.h>
#include <sol/sol.hpp>
#include <string>

#include "eqlib/game/Globals.h"

#include "../core/CacheManager.h"
#include "../core/ItemData.h"
#include "../core/Logger.h"
#include "../scanners/BankScanner.h"
#include "../scanners/InventoryScanner.h"
#include "../scanners/SellScanner.h"
#include "../storage/SellCacheWriter.h"

namespace cooptui {
namespace items {

// Convert a CoOptItemData struct into a plain sol::table that Lua scan.lua expects.
// Field names must exactly match buildItemFromMQ() in item_helpers.lua.
static sol::table ItemDataToTable(sol::state_view sv, const core::CoOptItemData& d) {
  sol::table t = sv.create_table();
  t["id"] = d.id;
  t["bag"] = d.bag;
  t["slot"] = d.slot;
  t["source"] = d.source;
  t["name"] = d.name;
  t["type"] = d.type;
  t["value"] = d.value;
  t["totalValue"] = d.totalValue;
  t["stackSize"] = d.stackSize;
  t["weight"] = d.weight;
  t["icon"] = d.icon;
  t["tribute"] = d.tribute;
  t["nodrop"] = d.nodrop;
  t["notrade"] = d.notrade;
  t["lore"] = d.lore;
  t["attuneable"] = d.attuneable;
  t["heirloom"] = d.heirloom;
  t["collectible"] = d.collectible;
  t["quest"] = d.quest;
  t["augSlots"] = d.augSlots;
  t["clicky"] = d.clicky;
  t["wornSlots"] = d.wornSlots;
  t["willSell"] = d.willSell;
  t["sellReason"] = d.sellReason;
  t["willLoot"] = d.willLoot;
  t["lootReason"] = d.lootReason;
  return t;
}

void registerLua(sol::state_view L, sol::table& table) {
  lua_State* rawL = L.lua_state();

  table.set_function("scanInventory", [rawL]() -> sol::table {
    sol::state_view sv(rawL);
    const auto& items = scanners::InventoryScanner::Instance().Scan();
    sol::table result = sv.create_table_with();
    for (const auto& d : items) {
      result.add(ItemDataToTable(sv, d));
    }
    return result;
  });

  table.set_function("scanBank", [rawL]() -> sol::table {
    sol::state_view sv(rawL);
    const auto& items = scanners::BankScanner::Instance().Scan();
    sol::table result = sv.create_table_with();
    for (const auto& d : items) {
      result.add(ItemDataToTable(sv, d));
    }
    return result;
  });

  table.set_function("scanSellItems", [rawL]() -> sol::table {
    sol::state_view sv(rawL);
    const auto& items = scanners::SellScanner::Instance().Scan();
    sol::table result = sv.create_table_with();
    for (const auto& d : items) {
      result.add(ItemDataToTable(sv, d));
    }
    // Write sell cache after scan (mirrors Lua writeSellCache behavior)
    if (!items.empty() && gPathMacros[0] != '\0' &&
        pLocalPlayer && pLocalPlayer->Name[0] != '\0') {
      storage::SellCacheWriter::Write(std::string(gPathMacros),
                                      std::string(pLocalPlayer->Name), items);
    }
    return result;
  });

  table.set_function("getItem", [](int, int, const std::string&) -> sol::optional<sol::table> {
    return sol::nullopt;
  });

  table.set_function("hasInventoryChanged", []() -> bool {
    return scanners::InventoryScanner::Instance().HasChanged();
  });
}

}  // namespace items
}  // namespace cooptui
