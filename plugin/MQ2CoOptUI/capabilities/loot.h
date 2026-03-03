#pragma once

#include <sol/forward.hpp>

namespace cooptui {
namespace loot {

void registerLua(sol::state_view L, sol::table& table);

}  // namespace loot
}  // namespace cooptui
