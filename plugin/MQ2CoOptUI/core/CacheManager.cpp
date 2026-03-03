#include "CacheManager.h"
#include <Windows.h>

namespace cooptui {
namespace core {

CacheManager& CacheManager::Instance() {
  static CacheManager instance;
  return instance;
}

void CacheManager::Initialize(const CoOptCoreConfig& config) {
  if (initialized_) return;

  scanThrottleMs_ = config.scanThrottleMs;
  if (scanThrottleMs_ < 0) scanThrottleMs_ = 0;

  inventory_.clear();
  bank_.clear();
  loot_.clear();
  sellItems_.clear();

  inventory_.reserve(static_cast<size_t>(config.inventoryReserve > 0 ? config.inventoryReserve : 256));
  bank_.reserve(static_cast<size_t>(config.bankReserve > 0 ? config.bankReserve : 512));
  loot_.reserve(static_cast<size_t>(config.lootReserve > 0 ? config.lootReserve : 512));
  sellItems_.reserve(static_cast<size_t>(config.inventoryReserve > 0 ? config.inventoryReserve : 256));

  dirtyInventory_ = false;
  dirtyBank_ = false;
  dirtyLoot_ = false;
  lastThrottleCheckMs_ = 0;
  lastInventoryScanMs_ = 0;
  lastBankScanMs_ = 0;
  lastLootScanMs_ = 0;
  inventoryScanCount_ = 0;
  bankScanCount_ = 0;
  lootScanCount_ = 0;

  initialized_ = true;
}

void CacheManager::Shutdown() {
  if (!initialized_) return;

  inventory_.clear();
  bank_.clear();
  loot_.clear();
  sellItems_.clear();

  inventory_.shrink_to_fit();
  bank_.shrink_to_fit();
  loot_.shrink_to_fit();
  sellItems_.shrink_to_fit();

  initialized_ = false;
}

bool CacheManager::ThrottleElapsed() {
  uint64_t now = static_cast<uint64_t>(GetTickCount64());
  if (now - lastThrottleCheckMs_ < static_cast<uint64_t>(scanThrottleMs_))
    return false;
  lastThrottleCheckMs_ = now;
  return true;
}

void CacheManager::OnPulse() {
  if (!initialized_) return;
  // Throttled: only do work when ScanThrottleMs has elapsed.
  // Phase 3+ will run scanners here when dirty flags are set.
  (void)ThrottleElapsed();
}

}  // namespace core
}  // namespace cooptui
