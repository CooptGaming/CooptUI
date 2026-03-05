#include "items.h"

#include <mq/Plugin.h>
#include <sol/sol.hpp>
#include <string>

#include "eqlib/game/Globals.h"

#include "../core/CacheManager.h"
#include "../core/Logger.h"
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
