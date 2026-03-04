#pragma once

#include "../core/ItemData.h"
#include <cstdint>
#include <vector>

namespace cooptui {
namespace scanners {

// SellScanner — evaluates cached inventory items against sell rules.
//
// Reads from CacheManager::GetInventory() (populated by InventoryScanner) and
// applies RulesEngine::WillItemBeSold() to produce a sell list entirely in
// memory — no TLO calls needed.
//
// Returns ALL inventory items with willSell/sellReason populated, matching
// the shape of Lua's env.sellItems (the Sell tab shows all items, filtered
// by willSell for the sell batch).
class SellScanner {
 public:
  static SellScanner& Instance();

  // Evaluate inventory items against sell rules. Returns all inventory items
  // with willSell/sellReason fields populated. force=true re-evaluates even
  // when results are already cached.
  const std::vector<core::CoOptItemData>& Scan(bool force = false);

  // Count of items that will be sold from the last scan.
  size_t GetSellCount() const;

  SellScanner(const SellScanner&) = delete;
  SellScanner& operator=(const SellScanner&) = delete;

 private:
  SellScanner() = default;

  void DoScan();

  std::vector<core::CoOptItemData> items_;
  uint64_t lastScanTimeMs_ = 0;
};

}  // namespace scanners
}  // namespace cooptui
