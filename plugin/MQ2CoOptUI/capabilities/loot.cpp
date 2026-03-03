#include "loot.h"
#include <sol/sol.hpp>

namespace cooptui {
namespace loot {

void registerLua(sol::state_view L, sol::table& table) {
  lua_State* rawL = L.lua_state();
  table.set_function("pollEvents", [rawL]() {
    sol::state_view sv(rawL);
    return sv.create_table();
  });
}

}  // namespace loot
}  // namespace cooptui
