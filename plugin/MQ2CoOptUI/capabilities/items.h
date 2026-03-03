#pragma once

#include <sol/forward.hpp>

namespace cooptui {
namespace items {

void registerLua(sol::state_view L, sol::table& table);

}  // namespace items
}  // namespace cooptui
