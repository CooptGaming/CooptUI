#pragma once

#include <sol/forward.hpp>

namespace cooptui {
namespace cursor {

void registerLua(sol::state_view L, sol::table& table);

/// Call from OnPulse to cache cursor item (when MQ item API available).
void updateFromPulse();

}  // namespace cursor
}  // namespace cooptui
