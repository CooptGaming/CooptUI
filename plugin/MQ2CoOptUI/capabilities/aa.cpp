#include "aa.h"

#include <mq/Plugin.h>
#include <sol/sol.hpp>
#include <algorithm>
#include <vector>

#include "eqlib/game/AltAbilities.h"
#include "eqlib/game/Constants.h"
#include "eqlib/game/Globals.h"
#include "eqlib/game/PcClient.h"

namespace cooptui {
namespace aa {

namespace {

// Visibility filter built from RUNTIME-PROVEN primitives only. Two earlier
// builds crashed the client here by trusting unexercised paths on this
// 2013-era emu client:
//   v1 probed GetAAById over 0..65535 - but the proven internal index range
//      is 0..NUM_ALT_ABILITIES-1 (the AltAbility TLO's own loop bound; the
//      Lua full scan exercised exactly that, billions of iterations). Beyond
//      it: crash.
//   v2 walked pAltAdvManager->abilities dev-tools-style - member offset /
//      hash-table layout unproven on emu; faulted before the guarded call.
// What IS proven: mq::GetAAById(n) for n in [0, NUM_ALT_ABILITIES), and
// CAltAbilityData field reads (the TLO serves Type/Cost/MaxRank/GroupID from
// the same struct). The Lua-side "AA id" is the GROUP id - dataAltAbility
// matches szIndex against GroupID - so that's what we return.
//
// Filter (conservative, targets the two user-visible problems):
//   - bShowInAbilityWindow false -> hidden everywhere
//   - Archetype/Class (Type 2/3) whose Classes bitmask excludes our class ->
//     other classes' lines (the server maintains the masks per character,
//     which is how multi-class actives surface in the native window)
//   - QuestOnly (granted) abilities the character does NOT have - ownership
//     via pLocalPC->HasAlternateAbility(Index), the same proven call the
//     TLO's Rank member makes. (CAltAbilityData::CurrentRank is the entry's
//     STATIC rank position - "Group Level" - not character state.)
//
// Plain locals only: x86 SEH cannot share a frame with C++ unwinding.
// Returns 1 = visible (outGroupId set), 0 = hidden/absent, -1 = faulted.
int checkAbilitySafe(eqlib::PcClient* pc, int classMask, int n, int* outGroupId) {
  __try {
    eqlib::CAltAbilityData* ab = mq::GetAAById(n);
    if (!ab) return 0;
    if (!ab->bShowInAbilityWindow) return 0;
    int type = ab->Type;
    if ((type == 2 || type == 3) && classMask != 0 && ab->Classes != 0
        && (ab->Classes & classMask) == 0) {
      return 0;
    }
    if (ab->QuestOnly && !pc->HasAlternateAbility(ab->Index)) return 0;
    *outGroupId = ab->GroupID;
    return 1;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return -1;
  }
}

// Table facts for the AA import cost gate: group id + the entry's static
// rank position + that rank's cost. Same proven primitives, SEH per entry.
// Returns 1 = valid entry, 0 = absent, -1 = faulted.
int readRankCostSafe(int n, int* outGroupId, int* outRank, int* outCost) {
  __try {
    eqlib::CAltAbilityData* ab = mq::GetAAById(n);
    if (!ab) return 0;
    *outGroupId = ab->GroupID;
    *outRank = ab->CurrentRank;
    *outCost = ab->Cost;
    return 1;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return -1;
  }
}

}  // namespace

void registerLua(sol::state_view L, sol::table& table) {
  lua_State* rawL = L.lua_state();

  // Array of AltAbility ids (GROUP ids - what the AltAbility TLO takes)
  // visible to THIS character, ascending and unique. nil when unavailable or
  // misbehaving - the Lua side then falls back to its full id-space scan.
  table.set_function("getVisibleAAIds", [rawL]() -> sol::object {
    sol::state_view sv(rawL);
    using namespace eqlib;
    if (!pAltAdvManager.get() || !pLocalPC) return sol::make_object(sv, sol::lua_nil);

    int classId = 0;
    if (PcProfile* prof = pLocalPC->GetCurrentPcProfile()) classId = prof->Class;
    int classMask = (classId > 0 && classId < 31) ? (1 << classId) : 0;

    std::vector<int> ids;
    int faults = 0;
    for (int n = 0; n < NUM_ALT_ABILITIES; ++n) {
      int groupId = -1;
      int r = checkAbilitySafe(pLocalPC, classMask, n, &groupId);
      if (r == 1 && groupId > 0) {
        ids.push_back(groupId);
      } else if (r == -1) {
        ++faults;
        if (faults > 25) {
          // Systemic: stop trusting ourselves; Lua falls back to full scan.
          return sol::make_object(sv, sol::lua_nil);
        }
      }
    }
    if (ids.empty()) return sol::make_object(sv, sol::lua_nil);

    // Ranks share a GroupID - return each group once, ascending.
    std::sort(ids.begin(), ids.end());
    ids.erase(std::unique(ids.begin(), ids.end()), ids.end());

    sol::table out = sv.create_table(static_cast<int>(ids.size()), 0);
    int n = 0;
    for (int id : ids) out[++n] = id;
    return sol::make_object(sv, out);
  });

  // Per-rank table ids for every group: { [groupId] = { [rank] = index } }.
  // The import buys EXACT ranks with these - the global TLO's first match
  // for a group is not guaranteed to be rank 1 on this server's custom
  // table, and /alt buy with a mid-chain id gets "Unable to train".
  table.set_function("getGroupRankIndexes", [rawL]() -> sol::object {
    sol::state_view sv(rawL);
    using namespace eqlib;
    if (!pAltAdvManager.get()) return sol::make_object(sv, sol::lua_nil);

    sol::table out = sv.create_table();
    int faults = 0;
    for (int n = 0; n < NUM_ALT_ABILITIES; ++n) {
      int groupId = -1, rank = -1, cost = -1;
      int r = readRankCostSafe(n, &groupId, &rank, &cost);
      if (r == 1 && groupId > 0 && rank > 0) {
        sol::object cur = out[groupId];
        sol::table group;
        if (cur.is<sol::table>()) {
          group = cur.as<sol::table>();
        } else {
          group = sv.create_table();
          out[groupId] = group;
        }
        group[rank] = n;
      } else if (r == -1) {
        ++faults;
        if (faults > 25) return sol::make_object(sv, sol::lua_nil);
      }
    }
    return sol::make_object(sv, out);
  });

  // Per-rank AA point costs for every group: { [groupId] = { [rank] = cost } }.
  // Drives the import's "enough points?" gate. nil when unavailable.
  table.set_function("getGroupRankCosts", [rawL]() -> sol::object {
    sol::state_view sv(rawL);
    using namespace eqlib;
    if (!pAltAdvManager.get()) return sol::make_object(sv, sol::lua_nil);

    sol::table out = sv.create_table();
    int faults = 0;
    for (int n = 0; n < NUM_ALT_ABILITIES; ++n) {
      int groupId = -1, rank = -1, cost = -1;
      int r = readRankCostSafe(n, &groupId, &rank, &cost);
      if (r == 1 && groupId > 0 && rank > 0 && cost >= 0) {
        sol::object cur = out[groupId];
        sol::table group;
        if (cur.is<sol::table>()) {
          group = cur.as<sol::table>();
        } else {
          group = sv.create_table();
          out[groupId] = group;
        }
        group[rank] = cost;
      } else if (r == -1) {
        ++faults;
        if (faults > 25) return sol::make_object(sv, sol::lua_nil);
      }
    }
    return sol::make_object(sv, out);
  });
}

}  // namespace aa
}  // namespace cooptui
