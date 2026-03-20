#pragma once

#include <sol/forward.hpp>

namespace cooptui {
namespace sound {

void registerLua(sol::state_view L, sol::table& table);

}  // namespace sound
}  // namespace cooptui
