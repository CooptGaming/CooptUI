#include "items.h"

#include <mq/Plugin.h>
#include <sol/sol.hpp>
#include <string>

#include "eqlib/game/Constants.h"
#include "eqlib/game/Globals.h"
#include "eqlib/game/Items.h"
#include "eqlib/game/PcClient.h"
#include "eqlib/game/UI.h"

#include "../core/CacheManager.h"
#include "../core/ItemData.h"
#include "../core/ItemDataPopulate.h"
#include "../core/ItemDataToTable.h"
#include "../core/Logger.h"
#include "../scanners/BankScanner.h"
#include "../scanners/InventoryScanner.h"
#include "../scanners/SellScanner.h"

namespace cooptui {
namespace items {

std::optional<core::CoOptItemData> GetItemData(int bag, int slot, const std::string& source) {
  if (!pLocalPC) return std::nullopt;

  using namespace eqlib;

  ItemPtr item = nullptr;
  ItemDefinition* def = nullptr;
  int outBag = bag;
  int outSlot = slot;

  if (source == "inv") {
    // inv: pack bag 1-based, slot 1-based
    auto& inv = pLocalPC->GetCurrentPcProfile()->GetInventory();
    int bagIdx = InvSlot_FirstBagSlot + bag - 1;
    if (bagIdx < InvSlot_FirstBagSlot || bagIdx > InvSlot_LastBagSlot) return std::nullopt;
    ItemPtr bagItem = inv.GetItem(bagIdx);
    if (!bagItem || !bagItem->IsContainer()) return std::nullopt;
    item = bagItem->GetHeldItems().GetItem(slot - 1);
    if (!item) return std::nullopt;
    def = item->GetItemDefinition();
  } else if (source == "bank") {
    if (scanners::BankScanner::IsBankWindowOpen()) {
      // Live: BankItems when window open
      item = pLocalPC->BankItems.GetItem(bag - 1);
      if (!item) return std::nullopt;
      if (item->IsContainer() && slot > 0) {
        item = item->GetHeldItems().GetItem(slot - 1);
      } else if (slot > 1) {
        return std::nullopt;  // Non-container, slot must be 1
      }
      def = item ? item->GetItemDefinition() : nullptr;
    } else {
      // Bank closed: use cached snapshot from last scan
      const auto& bankItems = core::CacheManager::Instance().GetBank();
      for (const auto& d : bankItems) {
        if (d.bag == bag && d.slot == slot) {
          return d;
        }
      }
      return std::nullopt;
    }
  } else if (source == "equipped") {
    // equipped: slot 0-based equipment index (0-22)
    if (slot < 0 || slot > InvSlot_LastWornItem) return std::nullopt;
    auto& inv = pLocalPC->GetCurrentPcProfile()->GetInventory();
    item = inv.GetItem(slot);
    def = item ? item->GetItemDefinition() : nullptr;
    outBag = 0;
    outSlot = slot;
  } else if (source == "corpse" || source == "loot") {
    // corpse/loot: slot 1-based corpse loot slot; requires loot window open
    if (!pLootWnd || !pLootWnd->IsVisible()) return std::nullopt;
    if (slot < 1) return std::nullopt;
    auto& lootItems = pLootWnd->GetLootItems();
    if (slot > lootItems.GetSize()) return std::nullopt;
    item = lootItems.GetItem(slot - 1);
    def = item ? item->GetItemDefinition() : nullptr;
    outBag = 0;
    outSlot = slot;
  } else {
    return std::nullopt;
  }

  if (!item || !def) return std::nullopt;
  if (item->GetID() <= 0) return std::nullopt;

  core::CoOptItemData d;
  core::PopulateItemData(d, item, def, outBag, outSlot, source);
  return d;
}

void registerLua(sol::state_view L, sol::table& table) {
  lua_State* rawL = L.lua_state();

  table.set_function("scanInventory", [rawL]() -> sol::table {
    sol::state_view sv(rawL);
    uint64_t t0 = core::MonotonicUs();
    const auto& items = scanners::InventoryScanner::Instance().Scan();
    core::CacheManager::Instance().RecordInventoryScanMs(
        core::ElapsedMsFromUs(t0, core::MonotonicUs()));
    sol::table result = sv.create_table_with();
    for (const auto& d : items) {
      result.add(core::ItemDataToTable(sv, d));
    }
    return result;
  });

  table.set_function("scanBank", [rawL]() -> sol::table {
    sol::state_view sv(rawL);
    uint64_t t0 = core::MonotonicUs();
    const auto& items = scanners::BankScanner::Instance().Scan();
    core::CacheManager::Instance().RecordBankScanMs(
        core::ElapsedMsFromUs(t0, core::MonotonicUs()));
    sol::table result = sv.create_table_with();
    for (const auto& d : items) {
      result.add(core::ItemDataToTable(sv, d));
    }
    return result;
  });

  table.set_function("scanSellItems", [rawL]() -> sol::table {
    sol::state_view sv(rawL);
    uint64_t t0 = core::MonotonicUs();
    const auto& items = scanners::SellScanner::Instance().Scan();
    core::CacheManager::Instance().RecordSellScanMs(
        core::ElapsedMsFromUs(t0, core::MonotonicUs()));
    sol::table result = sv.create_table_with();
    for (const auto& d : items) {
      result.add(core::ItemDataToTable(sv, d));
    }
    // Fix 2: Sell cache write is Lua's domain (phase2 + inventory close). Avoid blocking main thread.
    return result;
  });

  table.set_function("getItem", [rawL](int bag, int slot, const std::string& source) -> sol::optional<sol::table> {
    auto opt = GetItemData(bag, slot, source);
    if (!opt) return sol::nullopt;
    sol::state_view sv(rawL);
    return core::ItemDataToTable(sv, *opt);
  });

  table.set_function("hasInventoryChanged", []() -> bool {
    return scanners::InventoryScanner::Instance().HasChanged();
  });

  // Version counters: Lua polls these to detect cache staleness without re-scanning.
  // Incremented by C++ event hooks (OnPulse item changes, zone transitions, etc.).
  table.set_function("getInventoryVersion", []() -> uint32_t {
    return core::CacheManager::Instance().GetInventoryVersion();
  });

  table.set_function("getBankVersion", []() -> uint32_t {
    return core::CacheManager::Instance().GetBankVersion();
  });

  table.set_function("getLootVersion", []() -> uint32_t {
    return core::CacheManager::Instance().GetLootVersion();
  });

  table.set_function("getSellVersion", []() -> uint32_t {
    return core::CacheManager::Instance().GetSellVersion();
  });
}

}  // namespace items
}  // namespace cooptui
