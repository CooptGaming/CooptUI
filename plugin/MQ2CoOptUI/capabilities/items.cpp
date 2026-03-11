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
#include "../core/Logger.h"
#include "../scanners/BankScanner.h"
#include "../scanners/InventoryScanner.h"
#include "../scanners/SellScanner.h"

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

  // Spell effect IDs
  t["proc"] = d.proc;
  t["focus"] = d.focus;
  t["spell"] = d.spell;
  t["worn"] = d.worn;
  t["focus2"] = d.focus2;
  t["familiar"] = d.familiar;
  t["illusion"] = d.illusion;
  t["mount"] = d.mount;

  // Augment
  t["augType"] = d.augType;
  t["augRestrictions"] = d.augRestrictions;

  // Stats (STAT_TLO_MAP keys)
  t["ac"] = d.ac;
  t["hp"] = d.hp;
  t["mana"] = d.mana;
  t["endurance"] = d.endurance;
  t["str"] = d.str;
  t["sta"] = d.sta;
  t["agi"] = d.agi;
  t["dex"] = d.dex;
  t["int"] = d._int;
  t["wis"] = d.wis;
  t["cha"] = d.cha;
  t["attack"] = d.attack;
  t["accuracy"] = d.accuracy;
  t["avoidance"] = d.avoidance;
  t["shielding"] = d.shielding;
  t["haste"] = d.haste;
  t["damage"] = d.damage;
  t["itemDelay"] = d.itemDelay;
  t["dmgBonus"] = d.dmgBonus;
  t["dmgBonusType"] = d.dmgBonusType;
  t["spellDamage"] = d.spellDamage;
  t["strikeThrough"] = d.strikeThrough;
  t["damageShield"] = d.damageShield;
  t["combatEffects"] = d.combatEffects;
  t["dotShielding"] = d.dotShielding;
  t["hpRegen"] = d.hpRegen;
  t["manaRegen"] = d.manaRegen;
  t["enduranceRegen"] = d.enduranceRegen;
  t["spellShield"] = d.spellShield;
  t["damageShieldMitigation"] = d.damageShieldMitigation;
  t["stunResist"] = d.stunResist;
  t["clairvoyance"] = d.clairvoyance;
  t["healAmount"] = d.healAmount;
  t["heroicSTR"] = d.heroicSTR;
  t["heroicSTA"] = d.heroicSTA;
  t["heroicAGI"] = d.heroicAGI;
  t["heroicDEX"] = d.heroicDEX;
  t["heroicINT"] = d.heroicINT;
  t["heroicWIS"] = d.heroicWIS;
  t["heroicCHA"] = d.heroicCHA;
  t["svMagic"] = d.svMagic;
  t["svFire"] = d.svFire;
  t["svCold"] = d.svCold;
  t["svPoison"] = d.svPoison;
  t["svDisease"] = d.svDisease;
  t["svCorruption"] = d.svCorruption;
  t["heroicSvMagic"] = d.heroicSvMagic;
  t["heroicSvFire"] = d.heroicSvFire;
  t["heroicSvCold"] = d.heroicSvCold;
  t["heroicSvDisease"] = d.heroicSvDisease;
  t["heroicSvPoison"] = d.heroicSvPoison;
  t["heroicSvCorruption"] = d.heroicSvCorruption;
  t["charges"] = d.charges;
  t["range"] = d.range;
  t["skillModValue"] = d.skillModValue;
  t["skillModMax"] = d.skillModMax;
  t["baneDMG"] = d.baneDMG;
  t["baneDMGType"] = d.baneDMGType;
  t["luck"] = d.luck;
  t["purity"] = d.purity;

  // Descriptive (DESCRIPTIVE_FIELDS)
  t["size"] = d.size;
  t["sizeCapacity"] = d.sizeCapacity;
  t["container"] = d.container;
  t["stackSizeMax"] = d.stackSizeMax;
  t["norent"] = d.norent;
  t["magic"] = d.magic;
  t["prestige"] = d.prestige;
  t["tradeskills"] = d.tradeskills;
  t["requiredLevel"] = d.requiredLevel;
  t["recommendedLevel"] = d.recommendedLevel;
  t["instrumentType"] = d.instrumentType;
  t["instrumentMod"] = d.instrumentMod;
  t["class"] = d.classStr;
  t["race"] = d.raceStr;
  t["deity"] = d.deityStr;

  // Capture-all
  t["stackable"] = d.stackable;
  t["loreEquipped"] = d.loreEquipped;
  t["noDestroy"] = d.noDestroy;
  t["summoned"] = d.summoned;
  t["expendable"] = d.expendable;
  t["procRate"] = d.procRate;
  t["ornamentationIcon"] = d.ornamentationIcon;
  t["ldoNCost"] = d.ldoNCost;
  t["ldoNTheme"] = d.ldoNTheme;
  t["maxLuck"] = d.maxLuck;
  t["minLuck"] = d.minLuck;
  t["weightReduction"] = d.weightReduction;
  t["contentSize"] = d.contentSize;
  t["slotsUsedByItem"] = d.slotsUsedByItem;
  t["power"] = d.power;
  t["maxPower"] = d.maxPower;
  t["pctPower"] = d.pctPower;
  t["quality"] = d.quality;
  t["delay"] = d.delay;
  t["idFile"] = d.idFile;
  t["idFile2"] = d.idFile2;

  return t;
}

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
      result.add(ItemDataToTable(sv, d));
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
      result.add(ItemDataToTable(sv, d));
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
      result.add(ItemDataToTable(sv, d));
    }
    // Fix 2: Sell cache write is Lua's domain (phase2 + inventory close). Avoid blocking main thread.
    return result;
  });

  table.set_function("getItem", [rawL](int bag, int slot, const std::string& source) -> sol::optional<sol::table> {
    auto opt = GetItemData(bag, slot, source);
    if (!opt) return sol::nullopt;
    sol::state_view sv(rawL);
    return ItemDataToTable(sv, *opt);
  });

  table.set_function("hasInventoryChanged", []() -> bool {
    return scanners::InventoryScanner::Instance().HasChanged();
  });
}

}  // namespace items
}  // namespace cooptui
