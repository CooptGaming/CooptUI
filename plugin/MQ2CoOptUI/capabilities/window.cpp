#include "window.h"
#include <sol/sol.hpp>
#include <string>

namespace cooptui {
namespace window {

void registerLua(sol::state_view L, sol::table& table) {
  (void)L;
  // API surface per PLUGIN_DEEP_DIVE §3.2, §3.6.3. Stub returns so Lua falls back
  // until real impl using FindMQ2Window/CXWnd is built in MQ tree.
  table.set_function("isWindowOpen", [](const std::string&) { return false; });
  table.set_function("click", [](const std::string&, const std::string&) { return false; });
  table.set_function("getText", [](const std::string&, const std::string&) -> sol::optional<std::string> {
    return sol::nullopt;
  });
  table.set_function("waitOpen", [](const std::string&, int) { return false; });
  table.set_function("inspectItem", [](int, int, const std::string&) { (void)0; });
  table.set_function("isMerchantOpen", []() { return false; });
}

}  // namespace window
}  // namespace cooptui
