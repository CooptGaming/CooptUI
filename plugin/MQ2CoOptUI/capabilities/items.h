#pragma once

#include <optional>
#include <sol/forward.hpp>
#include <string>

namespace cooptui {
namespace core {
struct CoOptItemData;
}

namespace items {

void registerLua(sol::state_view L, sol::table& table);

// C++ helper for getItem: resolve (bag, slot, source) to CoOptItemData.
// Returns nullopt for empty slots, invalid args, or when source data unavailable.
std::optional<core::CoOptItemData> GetItemData(int bag, int slot, const std::string& source);

}  // namespace items
}  // namespace cooptui
