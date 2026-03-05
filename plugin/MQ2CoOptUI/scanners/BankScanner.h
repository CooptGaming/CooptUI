#pragma once

#include "../core/ItemData.h"
#include <cstdint>
#include <vector>

namespace cooptui {
namespace scanners {

// BankScanner — native bank item scanner.
//
// Design:
//   - Scan() always returns the cached snapshot (from the last time the bank
//     window was open and a scan completed).
//   - When the bank window is currently open, Scan() performs a fresh native
//     scan, updates the snapshot, and returns the fresh data.
//   - After the bank window closes the snapshot stays in memory so the Bank
//     tab can still display "last-seen" items (Lua behaviour matches).
//
// Matches the Lua scanBank() field shape from item_helpers.buildItemFromMQ().
class BankScanner {
 public:
  static BankScanner& Instance();

  // Return cached items (or fresh scan if bank window is open).
  // force=true rescans even if the window is closed (for /cooptui scan bank).
  const std::vector<core::CoOptItemData>& Scan(bool force = false);

  // True if the snapshot changed on the last Scan() call.
  bool HasChanged() const { return changed_; }

  // Time (ms since epoch) when the last successful scan completed.
  uint64_t GetLastScanTimeMs() const { return lastScanTimeMs_; }

  // True when the bank window is currently open.
  static bool IsBankWindowOpen();

  BankScanner(const BankScanner&) = delete;
  BankScanner& operator=(const BankScanner&) = delete;

 private:
  BankScanner() = default;

  void DoScan();

  std::vector<core::CoOptItemData> snapshot_;  // retained after bank closes
  uint64_t lastScanTimeMs_ = 0;
  bool changed_ = false;
};

}  // namespace scanners
}  // namespace cooptui
