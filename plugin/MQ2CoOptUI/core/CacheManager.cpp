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
  // Throttled check — Phase 8 auto-scans are driven from MQ2CoOptUI.cpp's
  // OnPulse() which calls the scanners directly; dirty flags here are for
  // informational purposes and future use.
  (void)ThrottleElapsed();
}

void CacheManager::InvalidateAll() {
  dirtyInventory_ = true;
  dirtyBank_ = true;
  dirtyLoot_ = true;
  ++inventoryVersion_;
  ++bankVersion_;
  ++lootVersion_;
  ++sellVersion_;
}

void CacheManager::InvalidateInventory() {
  dirtyInventory_ = true;
  ++inventoryVersion_;
}

void CacheManager::RecordInventoryScanMs(uint64_t ms) {
  lastInventoryScanMs_ = ms;
  ++inventoryScanCount_;
  ++perfInv_.count;
  perfInv_.totalMs += ms;
  if (ms > perfInv_.maxMs) perfInv_.maxMs = ms;
}

void CacheManager::RecordBankScanMs(uint64_t ms) {
  lastBankScanMs_ = ms;
  ++bankScanCount_;
  ++perfBank_.count;
  perfBank_.totalMs += ms;
  if (ms > perfBank_.maxMs) perfBank_.maxMs = ms;
}

void CacheManager::RecordLootScanMs(uint64_t ms) {
  lastLootScanMs_ = ms;
  ++lootScanCount_;
  ++perfLoot_.count;
  perfLoot_.totalMs += ms;
  if (ms > perfLoot_.maxMs) perfLoot_.maxMs = ms;
}

void CacheManager::RecordSellScanMs(uint64_t ms) {
  ++perfSell_.count;
  perfSell_.totalMs += ms;
  if (ms > perfSell_.maxMs) perfSell_.maxMs = ms;
}

void CacheManager::RecordRulesLoadMs(uint64_t ms) {
  ++perfRulesLoad_.count;
  perfRulesLoad_.totalMs += ms;
  if (ms > perfRulesLoad_.maxMs) perfRulesLoad_.maxMs = ms;
}

void CacheManager::ResetPerf() {
  perfInv_ = {};
  perfBank_ = {};
  perfLoot_ = {};
  perfSell_ = {};
  perfRulesLoad_ = {};
}

}  // namespace core
}  // namespace cooptui
