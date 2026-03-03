#include "items.h"
#include <sol/sol.hpp>
#include <string>

namespace cooptui {
namespace items {

void registerLua(sol::state_view L, sol::table& table) {
  lua_State* rawL = L.lua_state();
  table.set_function("scanInventory", [rawL]() {
    sol::state_view sv(rawL);
    return sv.create_table();
  });
  table.set_function("scanBank", [rawL]() {
    sol::state_view sv(rawL);
    return sv.create_table();
  });
  table.set_function("getItem", [](int, int, const std::string&) -> sol::optional<sol::table> {
    return sol::nullopt;
  });
  table.set_function("hasInventoryChanged", []() { return false; });
}

}  // namespace items
}  // namespace cooptui
