#pragma once

#include "ItemData.h"

#include "eqlib/game/Items.h"

namespace cooptui {
namespace core {

// Populates CoOptItemData from ItemDefinition and ItemPtr (stats, descriptive, spell IDs, etc.).
// Call after setting id, bag, slot, source, name, type, value, stackSize, totalValue.
void PopulateItemDataFromDefinition(CoOptItemData& d,
                                    const eqlib::ItemDefinition* def,
                                    const eqlib::ItemPtr& item);

// Full population: core fields + PopulateItemDataFromDefinition.
// Shared by scanners and items.getItem so both paths produce identical field sets.
// bag/slot: Lua convention (1-based for inv/bank, 0-based equipment index for equipped).
void PopulateItemData(CoOptItemData& d,
                     const eqlib::ItemPtr& item,
                     const eqlib::ItemDefinition* def,
                     int bag,
                     int slot,
                     const std::string& source);

}  // namespace core
}  // namespace cooptui
