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

// FNV-1a 64-bit hash over a pair of ints — fast inline fingerprint accumulator.
// (Same helper as InventoryScanner.cpp; file-local by design.)
static inline uint64_t fnv1a_mix(uint64_t hash, int a, int b) {
  hash ^= static_cast<uint64_t>(static_cast<uint32_t>(a));
  hash *= 0x00000100000001B3ULL;
  hash ^= static_cast<uint64_t>(static_cast<uint32_t>(b));
  hash *= 0x00000100000001B3ULL;
  return hash;
}

// Id/stack fingerprint over all bank rows — modeled on
// InventoryScanner::ComputeFingerprint. Cheap: reads only id + count, no
// ItemDefinition access and no CoOptItemData population.
uint64_t BankScanner::ComputeFingerprint() const {
  if (!pLocalPC) return 0;

  constexpr uint64_t kFNVOffset = 0xcbf29ce484222325ULL;
  uint64_t hash = kFNVOffset;

  auto& bankItems = pLocalPC->BankItems;
  int bankSize = bankItems.GetSize();
  for (int bagIdx = 0; bagIdx < bankSize; ++bagIdx) {
    ItemPtr bagItem = bankItems.GetItem(bagIdx);
    if (!bagItem) continue;
    if (!bagItem->IsContainer()) {
      // Single item directly in a bank slot
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

          if (item->GetID() <= 0) continue;

          core::CoOptItemData d;
          core::PopulateItemData(d, item, def, luaBag, s + 1, "bank");
          fresh.push_back(std::move(d));
        }
      } else {
        // Single item directly in a bank slot (not a container bag)
        if (bagItem->GetID() <= 0) continue;

        core::CoOptItemData d;
        core::PopulateItemData(d, bagItem, bagDef, luaBag, 1, "bank");
        fresh.push_back(std::move(d));
      }
    }
  } catch (...) {
    if (debugLevel >= 1) {
      core::Log(1, "BankScanner::DoScan caught exception — partial results");
    }
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

  if (!force && !bankOpen) {
    // Bank closed: keep the last-seen snapshot (Lua behaviour matches).
    changed_ = false;
    return snapshot_;
  }

  // Fingerprint check: skip the full populate scan if bank content is unchanged.
  uint64_t fp = ComputeFingerprint();
  if (!force && fp == lastFingerprint_) {
    changed_ = false;
    return snapshot_;
  }

  changed_ = (fp != lastFingerprint_) || force;
  lastFingerprint_ = fp;

  DoScan();
  return snapshot_;
}

}  // namespace scanners
}  // namespace cooptui
