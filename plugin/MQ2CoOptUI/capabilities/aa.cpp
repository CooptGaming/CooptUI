#include "aa.h"

#include <mq/Plugin.h>
#include <sol/sol.hpp>
#include <algorithm>
#include <vector>

#include "eqlib/game/AltAbilities.h"
#include "eqlib/game/Containers.h"
#include "eqlib/game/Globals.h"
#include "eqlib/game/PcClient.h"

namespace cooptui {
namespace aa {

namespace {

// The AA table holds EVERY ability in the game - other classes' lines
// included. The client's own AA window filters with CanSeeAbility, which is
// also where this emu server's per-character rules (multi-class actives etc.)
// take effect. We enumerate via the manager's own hash table (the same walk
// MQ's developer tools use) - no id-space probing.
//
// SEH-guarded per-entry check: this server ships a heavily customized AA
// table, and a malformed row (or an unexercised client path) inside
// CanSeeAbility must skip the row - or abort the listing - rather than take
// down the client. v1 of this function called CanSeeAbility unguarded and
// crashed the game. Plain locals only: x86 SEH cannot share a frame with
// C++ unwinding.
int visibleIndexSafe(eqlib::AltAdvManager* mgr, eqlib::PcClient* pc,
                     eqlib::CAltAbilityData* ab, int* outIndex) {
  __try {
    if (!ab || !ab->bShowInAbilityWindow) return 0;
    if (!mgr->CanSeeAbility(pc, ab)) return 0;
    *outIndex = ab->Index;
    return 1;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return -1;
  }
}

}  // namespace

void registerLua(sol::state_view L, sol::table& table) {
  lua_State* rawL = L.lua_state();

  // Array of AltAbility TLO ids (CAltAbilityData::Index) visible to THIS
  // character right now, ascending (rank ids stay - the Lua side dedupes by
  // name keeping the lowest, same as its full scan). nil when the managers
  // aren't up or the check is misbehaving - the Lua side then falls back to
  // its full id-space scan.
  table.set_function("getVisibleAAIds", [rawL]() -> sol::object {
    sol::state_view sv(rawL);
    using namespace eqlib;
    AltAdvManager* mgr = pAltAdvManager.get();
    PcClient* pc = pLocalPC;
    if (!mgr || !pc || !mgr->abilities) return sol::make_object(sv, sol::lua_nil);

    std::vector<int> ids;
    int faults = 0;
    const auto& abilities = *mgr->abilities;
    for (CAltAbilityData** pp = abilities.WalkFirst(); pp; pp = abilities.WalkNext(pp)) {
      int index = -1;
      int r = visibleIndexSafe(mgr, pc, *pp, &index);
      if (r == 1 && index >= 0) {
        ids.push_back(index);
      } else if (r == -1) {
        ++faults;
        if (faults > 25) {
          // Systemic (bad offsets / hostile table): stop trusting ourselves.
          return sol::make_object(sv, sol::lua_nil);
        }
      }
    }
    if (ids.empty()) return sol::make_object(sv, sol::lua_nil);
    std::sort(ids.begin(), ids.end());

    sol::table out = sv.create_table(static_cast<int>(ids.size()), 0);
    int n = 0;
    for (int id : ids) out[++n] = id;
    return sol::make_object(sv, out);
  });
}

}  // namespace aa
}  // namespace cooptui
