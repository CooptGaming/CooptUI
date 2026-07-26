#include "aa.h"

#include <mq/Plugin.h>
#include <sol/sol.hpp>

#include "eqlib/game/AltAbilities.h"
#include "eqlib/game/Globals.h"
#include "eqlib/game/PcClient.h"

namespace cooptui {
namespace aa {

// The AltAbility TLO id space is sparse and holds EVERY ability in the game's
// table - other classes' lines included. The client's own AA window filters
// with AltAdvManager::CanSeeAbility, which is also where this emu server's
// per-character rules (multi-class actives etc.) take effect. Exposing that
// filter lets the Lua browser show exactly what the native window would.

void registerLua(sol::state_view L, sol::table& table) {
  lua_State* rawL = L.lua_state();

  // Array of AltAbility TLO ids visible to THIS character right now, in
  // ascending id order (rank ids stay - the Lua side dedupes by name keeping
  // the lowest, same as its full scan). nil when the managers aren't up yet.
  table.set_function("getVisibleAAIds", [rawL]() -> sol::object {
    sol::state_view sv(rawL);
    using namespace eqlib;
    if (!pAltAdvManager || !pLocalPC) return sol::make_object(sv, sol::lua_nil);
    sol::table out = sv.create_table();
    int n = 0;
    for (int i = 0; i <= 65535; ++i) {
      CAltAbilityData* ab = pAltAdvManager->GetAAById(i);
      if (!ab) continue;
      if (!ab->bShowInAbilityWindow) continue;
      if (!pAltAdvManager->CanSeeAbility(pLocalPC, ab)) continue;
      out[++n] = i;
    }
    return sol::make_object(sv, out);
  });
}

}  // namespace aa
}  // namespace cooptui
