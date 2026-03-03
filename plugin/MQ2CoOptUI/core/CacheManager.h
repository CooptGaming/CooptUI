#pragma once

#include "Config.h"
#include "ItemData.h"
#include <cstdint>
#include <vector>

namespace cooptui {
namespace core {

// Central cache for inventory, bank, loot, and sell items.
// Pre-reserves vectors from config; scanners (Phase 3+) populate them.
// OnPulse() is throttled by ScanThrottleMs; Phase 3+ will run scanners when dirty.
class CacheManager {
 public:
  static CacheManager& Instance();

  void Initialize(const CoOptCoreConfig& config);
  void Shutdown();

  // Called every MQ pulse. Throttled: only does work when ScanThrottleMs has elapsed.
  void OnPulse();

  // Const accessors for scanners and Lua bridge
  const std::vector<CoOptItemData>& GetInventory() const { return inventory_; }
  const std::vector<CoOptItemData>& GetBank() const { return bank_; }
  const std::vector<CoOptItemData>& GetLoot() const { return loot_; }
  const std::vector<CoOptItemData>& GetSellItems() const { return sellItems_; }

  // Mutable accessors for scanners (Phase 3+) to fill
  std::vector<CoOptItemData>& GetInventoryMut() { return inventory_; }
  std::vector<CoOptItemData>& GetBankMut() { return bank_; }
  std::vector<CoOptItemData>& GetLootMut() { return loot_; }
  std::vector<CoOptItemData>& GetSellItemsMut() { return sellItems_; }

  // Dirty flags: set by scanners or external triggers when a rescan is needed
  bool IsInventoryDirty() const { return dirtyInventory_; }
  bool IsBankDirty() const { return dirtyBank_; }
  bool IsLootDirty() const { return dirtyLoot_; }
  void SetInventoryDirty(bool v = true) { dirtyInventory_ = v; }
  void SetBankDirty(bool v = true) { dirtyBank_ = v; }
  void SetLootDirty(bool v = true) { dirtyLoot_ = v; }

  // Capacity (reserved) and size (used) for status display
  size_t GetInventoryReserve() const { return inventory_.capacity(); }
  size_t GetBankReserve() const { return bank_.capacity(); }
  size_t GetLootReserve() const { return loot_.capacity(); }
  size_t GetInventoryCount() const { return inventory_.size(); }
  size_t GetBankCount() const { return bank_.size(); }
  size_t GetLootCount() const { return loot_.size(); }
  size_t GetSellItemsCount() const { return sellItems_.size(); }

  // Last scan time (ms) and scan counts for status
  uint64_t GetLastInventoryScanTimeMs() const { return lastInventoryScanMs_; }
  uint64_t GetLastBankScanTimeMs() const { return lastBankScanMs_; }
  uint64_t GetLastLootScanTimeMs() const { return lastLootScanMs_; }
  uint32_t GetInventoryScanCount() const { return inventoryScanCount_; }
  uint32_t GetBankScanCount() const { return bankScanCount_; }
  uint32_t GetLootScanCount() const { return lootScanCount_; }

  CacheManager(const CacheManager&) = delete;
  CacheManager& operator=(const CacheManager&) = delete;

 private:
  CacheManager() = default;

  bool ThrottleElapsed();

  std::vector<CoOptItemData> inventory_;
  std::vector<CoOptItemData> bank_;
  std::vector<CoOptItemData> loot_;
  std::vector<CoOptItemData> sellItems_;

  bool initialized_ = false;
  int scanThrottleMs_ = 100;
  uint64_t lastThrottleCheckMs_ = 0;

  bool dirtyInventory_ = false;
  bool dirtyBank_ = false;
  bool dirtyLoot_ = false;

  uint64_t lastInventoryScanMs_ = 0;
  uint64_t lastBankScanMs_ = 0;
  uint64_t lastLootScanMs_ = 0;
  uint32_t inventoryScanCount_ = 0;
  uint32_t bankScanCount_ = 0;
  uint32_t lootScanCount_ = 0;
};

}  // namespace core
}  // namespace cooptui
