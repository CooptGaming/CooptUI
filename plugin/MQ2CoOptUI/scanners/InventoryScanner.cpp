#include "InventoryScanner.h"

#include <mq/Plugin.h>
#include "eqlib/game/Constants.h"
#include "eqlib/game/Globals.h"
#include "eqlib/game/Items.h"
#include "eqlib/game/PcClient.h"

#include "../core/CacheManager.h"
#include "../core/Config.h"
#include "../core/ItemDataPopulate.h"
#include "../core/Logger.h"

namespace cooptui {
namespace scanners {

InventoryScanner& InventoryScanner::Instance() {
  static InventoryScanner instance;
  return instance;
}

// FNV-1a 64-bit hash over a pair of ints — fast inline fingerprint accumulator.
static inline uint64_t fnv1a_mix(uint64_t hash, int a, int b) {
  hash ^= static_cast<uint64_t>(static_cast<uint32_t>(a));
  hash *= 0x00000100000001B3ULL;
  hash ^= static_cast<uint64_t>(static_cast<uint32_t>(b));
  hash *= 0x00000100000001B3ULL;
  return hash;
}

uint64_t InventoryScanner::ComputeFingerprint() const {
  if (!pLocalPC) return 0;

  constexpr uint64_t kFNVOffset = 0xcbf29ce484222325ULL;
  uint64_t hash = kFNVOffset;

  auto& inv = pLocalPC->GetCurrentPcProfile()->GetInventory();
  for (int bag = InvSlot_FirstBagSlot; bag <= InvSlot_LastBagSlot; ++bag) {
    ItemPtr bagItem = inv.GetItem(bag);
    if (!bagItem) continue;
    if (!bagItem->IsContainer()) {
      // Single item in a worn slot (shouldn't happen for bag slots, but guard)
      hash = fnv1a_mix(hash, bagItem->GetID(), bagItem->GetItemCount());
      continue;
    }
    auto& contents = bagItem->GetHeldItems();
    int sz = contents.GetSize();
    for (int s = 0; s < sz; ++s) {
      ItemPtr item = contents.GetItem(s);
      if (!item) continue;
      hash = fnv1a_mix(hash, item->GetID(), item->GetItemCount());
    }
  }
  return hash;
}

const std::vector<core::CoOptItemData>& InventoryScanner::Scan(bool force) {
  if (!pLocalPC) {
    items_.clear();
    changed_ = false;
    return items_;
  }

  // Fingerprint check: skip full scan if nothing changed.
  uint64_t fp = ComputeFingerprint();
  if (!force && !dirty_ && fp == lastFingerprint_) {
    changed_ = false;
    return items_;
  }

  const bool fingerprintChanged = (fp != lastFingerprint_);
  lastFingerprint_ = fp;
  dirty_ = false;
  changed_ = fingerprintChanged || force;

  items_.clear();

  const int debugLevel = core::Config::Instance().GetDebugLevel();

  try {
    auto& inv = pLocalPC->GetCurrentPcProfile()->GetInventory();

    // Walk bag slots: InvSlot_Bag1 (23) through InvSlot_Bag10 (32), 0-based.
    // Lua uses 1-based bag numbers 1-10 matching pack1-pack10.
    for (int bagIdx = InvSlot_FirstBagSlot; bagIdx <= InvSlot_LastBagSlot; ++bagIdx) {
      ItemPtr bagItem = inv.GetItem(bagIdx);
      if (!bagItem || !bagItem->IsContainer()) continue;

      // Lua bag number is 1-based offset from InvSlot_FirstBagSlot.
      int luaBag = bagIdx - InvSlot_FirstBagSlot + 1;

      auto& contents = bagItem->GetHeldItems();
      int sz = contents.GetSize();

      for (int s = 0; s < sz; ++s) {
        ItemPtr item = contents.GetItem(s);
        if (!item) continue;

        ItemDefinition* def = item->GetItemDefinition();
        if (!def) continue;

        if (item->GetID() <= 0) continue;

        core::CoOptItemData d;
        core::PopulateItemData(d, item, def, luaBag, s + 1, "inv");
        items_.push_back(std::move(d));
      }
    }
  } catch (...) {
    if (debugLevel >= 1) {
      core::Log(1, "InventoryScanner::Scan caught exception — returning partial results");
    }
  }

  // Store in CacheManager so /cooptui status shows live counts.
  auto& cache = core::CacheManager::Instance();
  cache.GetInventoryMut() = items_;
  cache.SetInventoryDirty(false);

  if (debugLevel >= 2) {
    core::Log(2, "InventoryScanner: scanned %zu items (fp changed=%s force=%s)",
              items_.size(), fingerprintChanged ? "yes" : "no", force ? "yes" : "no");
  }

  return items_;
}

}  // namespace scanners
}  // namespace cooptui
