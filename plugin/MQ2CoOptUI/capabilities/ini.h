#pragma once

#include <sol/forward.hpp>
#include <string>

namespace cooptui {
namespace ini {

void registerLua(sol::state_view L, sol::table& table);

}  // namespace ini
}  // namespace cooptui
