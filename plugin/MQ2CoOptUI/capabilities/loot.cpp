#include "loot.h"

#include <sol/sol.hpp>
#include <string>

#include "../core/ItemData.h"
#include "../scanners/LootScanner.h"

namespace cooptui {
namespace loot {

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
  t["willLoot"] = d.willLoot;
  t["lootReason"] = d.lootReason;
  t["willSell"] = d.willSell;
  t["sellReason"] = d.sellReason;
  return t;
}

void registerLua(sol::state_view L, sol::table& table) {
  lua_State* rawL = L.lua_state();
  table.set_function("pollEvents", [rawL]() {
    sol::state_view sv(rawL);
    return sv.create_table();
  });

  table.set_function("scanLootItems", [rawL]() -> sol::table {
    sol::state_view sv(rawL);
    const auto& items = scanners::LootScanner::Instance().Scan();
    sol::table result = sv.create_table_with();
    for (const auto& d : items) {
      result.add(ItemDataToTable(sv, d));
    }
    return result;
  });
}

}  // namespace loot
}  // namespace cooptui
