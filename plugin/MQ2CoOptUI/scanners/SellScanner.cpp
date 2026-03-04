#include "SellScanner.h"

#include <Windows.h>

#include "../core/CacheManager.h"
#include "../core/Config.h"
#include "../core/Logger.h"
#include "../rules/RulesEngine.h"

namespace cooptui {
namespace scanners {

SellScanner& SellScanner::Instance() {
  static SellScanner instance;
  return instance;
}

void SellScanner::DoScan() {
  const auto& inv = core::CacheManager::Instance().GetInventory();
  const auto& re = rules::RulesEngine::Instance();

  items_.clear();
  if (items_.capacity() < inv.size()) {
    items_.reserve(inv.size() + 32);
  }

  for (const auto& item : inv) {
    core::CoOptItemData d = item;
    auto [willSell, reason] = re.WillItemBeSold(d);
    d.willSell = willSell;
    d.sellReason = reason;
    items_.push_back(std::move(d));
  }

  lastScanTimeMs_ = GetTickCount64();

  // Publish evaluated sell items to CacheManager
  core::CacheManager::Instance().GetSellItemsMut() = items_;

  const int debugLevel = core::Config::Instance().GetDebugLevel();
  if (debugLevel >= 2) {
    core::Log(2, "SellScanner: %zu items evaluated (%zu will sell)",
              items_.size(), GetSellCount());
  }
}

const std::vector<core::CoOptItemData>& SellScanner::Scan(bool force) {
  if (force || items_.empty()) {
    DoScan();
  }
  return items_;
}

size_t SellScanner::GetSellCount() const {
  size_t count = 0;
  for (const auto& it : items_) {
    if (it.willSell) ++count;
  }
  return count;
}

}  // namespace scanners
}  // namespace cooptui
