#pragma once

#include "ItemData.h"

#include "eqlib/game/Items.h"

namespace cooptui {
namespace core {

// Populates CoOptItemData from ItemDefinition and ItemPtr.
// Shared by InventoryScanner, BankScanner, LootScanner, and items.getItem.
// Call after setting id, bag, slot, source, name, type, value, stackSize, totalValue.
void PopulateItemDataFromDefinition(CoOptItemData& d,
                                    const eqlib::ItemDefinition* def,
                                    const eqlib::ItemPtr& item);

}  // namespace core
}  // namespace cooptui
