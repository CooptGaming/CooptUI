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
