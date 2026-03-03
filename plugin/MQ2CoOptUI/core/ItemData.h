#pragma once

#include <cstdint>
#include <string>

namespace cooptui {
namespace core {

// Item struct matching Lua buildItemFromMQ output for UI views.
// All text fields use std::string; no char[] anywhere.
struct CoOptItemData {
  int32_t id = 0;
  int32_t bag = 0;
  int32_t slot = 0;
  std::string source;  // "inv", "bank", "loot"
  std::string name;
  std::string type;
  int32_t value = 0;
  int32_t totalValue = 0;
  int32_t stackSize = 1;
  int32_t weight = 0;
  int32_t icon = 0;
  int32_t tribute = 0;
  bool nodrop = false;
  bool notrade = false;
  bool lore = false;
  bool attuneable = false;
  bool heirloom = false;
  bool collectible = false;
  bool quest = false;
  int32_t augSlots = 0;
  int32_t clicky = 0;
  std::string wornSlots;
  // Pre-evaluated rule results (Phase 5+)
  bool willSell = false;
  std::string sellReason;
  bool willLoot = false;
  std::string lootReason;
};

}  // namespace core
}  // namespace cooptui
