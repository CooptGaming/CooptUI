#pragma once

#include "../core/ItemData.h"
#include <cstdint>
#include <vector>

namespace cooptui {
namespace scanners {

// LootScanner — native corpse loot window scanner.
//
// Walks mq.TLO.Corpse loot items via pLootWnd / pCorpseItemList,
// extracts all item properties, pre-evaluates ShouldItemBeLooted()
// via RulesEngine, and performs native lore duplicate checking using
// FindItemByName (no TLO calls from Lua needed).
//
// Pre-reserves output vector to 512. Auto-resizes with warning if exceeded.
class LootScanner {
 public:
  static LootScanner& Instance();

  // Scan the current loot window. Returns scanned items with pre-evaluated
  // willLoot/lootReason fields. If loot window is not open, returns empty.
  // force=true rescans even if called multiple times per pulse.
  const std::vector<core::CoOptItemData>& Scan(bool force = false);

  // True if the most recent Scan() found items (loot window was open).
  bool HasItems() const { return !items_.empty(); }

  // Number of items from last scan.
  size_t GetItemCount() const { return items_.size(); }

  // True when the loot window is currently open.
  static bool IsLootWindowOpen();

  // Phase 12: simulate N-item loot evaluation (rules + lore) for benchmarking.
  // Returns elapsed time in milliseconds.
  uint64_t RunStressScan(size_t numItems);

  LootScanner(const LootScanner&) = delete;
  LootScanner& operator=(const LootScanner&) = delete;

 private:
  LootScanner();

  void DoScan();
  bool HasLoreDuplicate(const std::string& itemName) const;

  std::vector<core::CoOptItemData> items_;
  uint64_t lastScanTimeMs_ = 0;
};

}  // namespace scanners
}  // namespace cooptui
