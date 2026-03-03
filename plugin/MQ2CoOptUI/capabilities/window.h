#pragma once

#include <sol/forward.hpp>

namespace cooptui {
namespace window {

void registerLua(sol::state_view L, sol::table& table);

}  // namespace window
}  // namespace cooptui
