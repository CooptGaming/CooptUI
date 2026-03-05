#pragma once

#include <cstddef>
#include <sol/forward.hpp>
#include <string>

namespace cooptui {
namespace ipc {

void registerLua(sol::state_view L, sol::table& table);

/// Called from slash command or TLO so macros can write to channels.
void sendFromMacro(const std::string& channel, const std::string& message);

/// Max messages per channel (for /cooptui status).
size_t GetMaxChannelSize();

}  // namespace ipc
}  // namespace cooptui
