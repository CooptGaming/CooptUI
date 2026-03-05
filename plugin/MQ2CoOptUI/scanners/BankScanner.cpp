#include "BankScanner.h"

#include <mq/Plugin.h>
#include "eqlib/game/Constants.h"
#include "eqlib/game/Globals.h"
#include "eqlib/game/Items.h"
#include "eqlib/game/PcClient.h"
#include "eqlib/game/UI.h"

#include "../core/CacheManager.h"
#include "../core/Config.h"
#include "../core/ItemDataPopulate.h"
#include "../core/Logger.h"

namespace cooptui {
namespace scanners {

BankScanner& BankScanner::Instance() {
  static BankScanner instance;
  return instance;
}

bool BankScanner::IsBankWindowOpen() {
  return pBankWnd && pBankWnd->IsVisible();
}

std::string BankScanner::ItemTypeString(uint8_t itemClass) const {
  if (itemClass < MAX_ITEMCLASSES && szItemClasses[itemClass] != nullptr)
    return szItemClasses[itemClass];
  return "";
}

void BankScanner::DoScan() {
  if (!pLocalPC) return;

  const int debugLevel = core::Config::Instance().GetDebugLevel();
  std::vector<core::CoOptItemData> fresh;

  try {
    auto& bankItems = pLocalPC->BankItems;
    int bankSize = bankItems.GetSize();  // typically NUM_BANK_SLOTS = 24

    for (int bagIdx = 0; bagIdx < bankSize; ++bagIdx) {
      ItemPtr bagItem = bankItems.GetItem(bagIdx);
      if (!bagItem) continue;

      ItemDefinition* bagDef = bagItem->GetItemDefinition();
      if (!bagDef) continue;

      // Lua bag numbering: (ItemSlot 0-based) + 1 = bagIdx + 1
      int luaBag = bagIdx + 1;

      if (bagItem->IsContainer()) {
        // Container bag: walk sub-slots
        auto& contents = bagItem->GetHeldItems();
        int sz = contents.GetSize();
        for (int s = 0; s < sz; ++s) {
          ItemPtr item = contents.GetItem(s);
          if (!item) continue;

          ItemDefinition* def = item->GetItemDefinition();
          if (!def) continue;

          int id = item->GetID();
          if (id <= 0) continue;

          core::CoOptItemData d;
          d.id = id;
          d.bag = luaBag;
          d.slot = s + 1;  // Lua: (ItemSlot2 0-based) + 1
          d.source = "bank";
          d.name = def->Name;
          d.type = ItemTypeString(def->ItemClass);
          d.value = def->Cost;
          d.stackSize = item->GetItemCount();
          if (d.stackSize < 1) d.stackSize = 1;
          d.totalValue = d.value * d.stackSize;
          d.weight = def->Weight;
          d.icon = def->IconNumber;
          d.tribute = def->Favor;
          d.nodrop = !def->IsDroppable;
          d.notrade = !def->IsDroppable;
          d.lore = (def->Lore != 0);
          d.attuneable = def->Attuneable;
          d.heirloom = def->Heirloom;
          d.collectible = def->Collectible;
          d.quest = def->QuestItem;

          d.augSlots = 0;
          for (int a = 0; a < MAX_AUG_SOCKETS; ++a) {
            if (def->AugData.IsSocketValid(a)) ++d.augSlots;
          }

          d.clicky = 0;
          {
            int sid = def->SpellData.GetSpellId(ItemSpellType_Clicky);
            eItemEffectType eff = def->SpellData.GetSpellEffectType(ItemSpellType_Clicky);
            if (sid > 0 && (eff == ItemEffectClicky || eff == ItemEffectClickyWorn ||
                            eff == ItemEffectClickyRestricted)) {
              d.clicky = sid;
            }
          }

          core::PopulateItemDataFromDefinition(d, def, item);
          fresh.push_back(std::move(d));
        }
      } else {
        // Single item directly in a bank slot (not a container bag)
        int id = bagItem->GetID();
        if (id <= 0) continue;

        core::CoOptItemData d;
        d.id = id;
        d.bag = luaBag;
        d.slot = 1;  // Lua: (ItemSlot2 == 0) + 1 = 1
        d.source = "bank";
        d.name = bagDef->Name;
        d.type = ItemTypeString(bagDef->ItemClass);
        d.value = bagDef->Cost;
        d.stackSize = bagItem->GetItemCount();
        if (d.stackSize < 1) d.stackSize = 1;
        d.totalValue = d.value * d.stackSize;
        d.weight = bagDef->Weight;
        d.icon = bagDef->IconNumber;
        d.tribute = bagDef->Favor;
        d.nodrop = !bagDef->IsDroppable;
        d.notrade = !bagDef->IsDroppable;
        d.lore = (bagDef->Lore != 0);
        d.attuneable = bagDef->Attuneable;
        d.heirloom = bagDef->Heirloom;
        d.collectible = bagDef->Collectible;
        d.quest = bagDef->QuestItem;

        d.augSlots = 0;
        for (int a = 0; a < MAX_AUG_SOCKETS; ++a) {
          if (bagDef->AugData.IsSocketValid(a)) ++d.augSlots;
        }

        d.clicky = 0;
        {
          int sid = bagDef->SpellData.GetSpellId(ItemSpellType_Clicky);
          eItemEffectType eff = bagDef->SpellData.GetSpellEffectType(ItemSpellType_Clicky);
          if (sid > 0 && (eff == ItemEffectClicky || eff == ItemEffectClickyWorn ||
                          eff == ItemEffectClickyRestricted)) {
            d.clicky = sid;
          }
        }

        core::PopulateItemDataFromDefinition(d, bagDef, bagItem);
        fresh.push_back(std::move(d));
      }
    }
  } catch (...) {
    if (debugLevel >= 1) {
      core::Log(1, "BankScanner::DoScan caught exception — partial results");
    }
  }

  changed_ = (fresh.size() != snapshot_.size());
  if (!changed_) {
    // Quick content check: compare first/last item IDs
    if (!fresh.empty() && fresh.front().id != snapshot_.front().id)
      changed_ = true;
  }

  snapshot_ = std::move(fresh);
  lastScanTimeMs_ = GetTickCount64();

  // Publish to CacheManager
  auto& cache = core::CacheManager::Instance();
  cache.GetBankMut() = snapshot_;
  cache.SetBankDirty(false);

  if (debugLevel >= 2) {
    core::Log(2, "BankScanner: scanned %zu bank items (changed=%s)",
              snapshot_.size(), changed_ ? "yes" : "no");
  }
}

const std::vector<core::CoOptItemData>& BankScanner::Scan(bool force) {
  bool bankOpen = IsBankWindowOpen();

  if (force || bankOpen) {
    DoScan();
  } else {
    changed_ = false;
  }

  return snapshot_;
}

}  // namespace scanners
}  // namespace cooptui
