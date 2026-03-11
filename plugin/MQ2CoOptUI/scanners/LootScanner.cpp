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
#include "../core/ItemDataPopulate.h"
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

      if (item->GetID() <= 0) continue;

      core::CoOptItemData d;
      core::PopulateItemData(d, item, def, 0, i + 1, "loot");

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
  (void)force;  // Always refresh when window open so list matches current corpse after looting
  DoScan();
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
