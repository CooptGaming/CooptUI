#include "LootScanner.h"

#include <mq/Plugin.h>
#include <Windows.h>
#include "eqlib/game/Constants.h"
#include "eqlib/game/Globals.h"
#include "eqlib/game/Items.h"
#include "eqlib/game/PcClient.h"
#include "eqlib/game/UI.h"

#include "../core/CacheManager.h"
#include "../core/Config.h"
#include "../core/Logger.h"
#include "../rules/RulesEngine.h"

namespace cooptui {
namespace scanners {

static constexpr size_t kDefaultLootReserve = 512;

LootScanner& LootScanner::Instance() {
  static LootScanner instance;
  return instance;
}

LootScanner::LootScanner() {
  items_.reserve(kDefaultLootReserve);
}

bool LootScanner::IsLootWindowOpen() {
  return pLootWnd && pLootWnd->IsVisible();
}

std::string LootScanner::ItemTypeString(uint8_t itemClass) const {
  if (itemClass < MAX_ITEMCLASSES && szItemClasses[itemClass] != nullptr)
    return szItemClasses[itemClass];
  return "";
}

// Native lore duplicate check: search PC inventory + bank for an item with
// the same name. Uses FindItemByNamePred for O(n) scan — no TLO calls.
bool LootScanner::HasLoreDuplicate(const std::string& itemName) const {
  if (!pLocalPC || itemName.empty()) return false;

  auto& inv = pLocalPC->GetCurrentPcProfile()->GetInventory();
  ItemIndex idx = inv.FindItem(FindItemByNamePred(itemName, true));
  return idx.IsValid();
}

void LootScanner::DoScan() {
  if (!pLootWnd || !pLocalPC) return;

  const int debugLevel = core::Config::Instance().GetDebugLevel();
  items_.clear();

  try {
    auto& lootItems = pLootWnd->GetLootItems();
    int numSlots = lootItems.GetSize();

    if (numSlots <= 0) return;

    // Auto-resize warning if corpse has more items than reserved
    if (static_cast<size_t>(numSlots) > items_.capacity()) {
      core::Log(1, "LootScanner: %d items exceeds reserve %zu, auto-resizing",
                numSlots, items_.capacity());
      items_.reserve(static_cast<size_t>(numSlots) + 64);
    }

    const auto& rulesEngine = rules::RulesEngine::Instance();

    for (int i = 0; i < numSlots; ++i) {
      ItemPtr item = lootItems.GetItem(i);
      if (!item) continue;

      ItemDefinition* def = item->GetItemDefinition();
      if (!def) continue;

      int id = item->GetID();
      if (id <= 0) continue;

      core::CoOptItemData d;
      d.id = id;
      d.bag = 0;
      d.slot = i + 1;  // Lua uses 1-based loot slot index
      d.source = "loot";
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

      d.wornSlots = "";

      // Pre-evaluate loot rules
      auto [shouldLoot, reason] = rulesEngine.ShouldItemBeLooted(d);

      // Lore duplicate check overrides rule result
      if (d.lore && HasLoreDuplicate(d.name)) {
        shouldLoot = false;
        reason = "LoreDup";
      }

      d.willLoot = shouldLoot;
      d.lootReason = reason;

      items_.push_back(std::move(d));
    }
  } catch (...) {
    if (debugLevel >= 1) {
      core::Log(1, "LootScanner::DoScan caught exception - partial results");
    }
  }

  lastScanTimeMs_ = GetTickCount64();

  // Publish to CacheManager
  auto& cache = core::CacheManager::Instance();
  cache.GetLootMut() = items_;
  cache.SetLootDirty(false);

  if (debugLevel >= 2) {
    core::Log(2, "LootScanner: scanned %zu loot items", items_.size());
  }
}

const std::vector<core::CoOptItemData>& LootScanner::Scan(bool force) {
  if (!IsLootWindowOpen()) {
    items_.clear();
    return items_;
  }

  if (force || items_.empty()) {
    DoScan();
  }

  return items_;
}

uint64_t LootScanner::RunStressScan(size_t numItems) {
  uint64_t t0 = static_cast<uint64_t>(GetTickCount64());
  const auto& rulesEngine = rules::RulesEngine::Instance();
  for (size_t i = 0; i < numItems; ++i) {
    core::CoOptItemData d;
    d.name = "StressItem";
    d.type = "Misc";
    d.value = 0;
    d.stackSize = 1;
    d.lore = (i % 10 == 0);
    d.quest = false;
    d.collectible = false;
    d.heirloom = false;
    d.attuneable = false;
    auto [shouldLoot, reason] = rulesEngine.ShouldItemBeLooted(d);
    (void)shouldLoot;
    (void)reason;
    if (d.lore) (void)HasLoreDuplicate(d.name);
  }
  return static_cast<uint64_t>(GetTickCount64()) - t0;
}

}  // namespace scanners
}  // namespace cooptui
