#pragma once

#include <sol/forward.hpp>

namespace cooptui {
namespace cursor {

void registerLua(sol::state_view L, sol::table& table);

/// Call from OnPulse to cache cursor item (when MQ item API available).
void updateFromPulse();

/// Log current cached cursor state to MQ chat (for /cooptui test cursor).
void LogCursorState();

}  // namespace cursor
}  // namespace cooptui
