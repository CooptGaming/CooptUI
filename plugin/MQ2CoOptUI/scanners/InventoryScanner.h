#pragma once

#include "../core/ItemData.h"
#include <cstdint>
#include <string>
#include <vector>

namespace cooptui {
namespace scanners {

class InventoryScanner {
 public:
  static InventoryScanner& Instance();

  // Run a full inventory scan. Returns the scanned items.
  // If the fingerprint has not changed since the last scan, returns cached
  // results without rescanning (fast path). Force=true bypasses fingerprint check.
  const std::vector<core::CoOptItemData>& Scan(bool force = false);

  // True if the inventory fingerprint changed since the last call to Scan().
  bool HasChanged() const { return changed_; }

  // Force invalidation on next pulse (called by event hooks in Phase 8).
  void Invalidate() { dirty_ = true; }

  InventoryScanner(const InventoryScanner&) = delete;
  InventoryScanner& operator=(const InventoryScanner&) = delete;

 private:
  InventoryScanner() = default;

  uint64_t ComputeFingerprint() const;
  std::string ItemTypeString(uint8_t itemClass) const;

  std::vector<core::CoOptItemData> items_;
  uint64_t lastFingerprint_ = 0;
  bool dirty_ = true;
  bool changed_ = false;
};

}  // namespace scanners
}  // namespace cooptui
