#pragma once

#include <sol/forward.hpp>
#include <string>

namespace cooptui {
namespace ipc {

void registerLua(sol::state_view L, sol::table& table);

/// Called from slash command or TLO so macros can write to channels.
void sendFromMacro(const std::string& channel, const std::string& message);

}  // namespace ipc
}  // namespace cooptui
