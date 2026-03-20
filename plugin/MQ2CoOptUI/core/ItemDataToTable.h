#pragma once

#include "ItemData.h"
#include <sol/sol.hpp>

namespace cooptui {
namespace core {

// Convert a CoOptItemData struct into a plain sol::table for Lua.
// Field names must exactly match buildItemFromMQ() in item_helpers.lua.
// Shared by items.cpp and loot.cpp to avoid duplication.
sol::table ItemDataToTable(sol::state_view sv, const CoOptItemData& d);

}  // namespace core
}  // namespace cooptui
