#include "window.h"

#include <sol/sol.hpp>
#include <string>

#include "eqlib/game/Globals.h"
#include "eqlib/game/UI.h"

namespace cooptui {
namespace window {

namespace {

// Phase D: isWindowOpen for the 4 main windows using eqlib window pointers
// (declared in eqlib/game/Globals.h). getText and click remain TLO/commands.
bool isWindowOpenImpl(const std::string& name) {
  if (name == "BigBankWnd")
    return eqlib::pBankWnd && eqlib::pBankWnd->IsVisible();
  if (name == "MerchantWnd")
    return eqlib::pMerchantWnd && eqlib::pMerchantWnd->IsVisible();
  if (name == "LootWnd")
    return eqlib::pLootWnd && eqlib::pLootWnd->IsVisible();
  if (name == "InventoryWindow")
    return eqlib::pInventoryWnd && eqlib::pInventoryWnd->IsVisible();
  return false;
}

}  // namespace

void registerLua(sol::state_view L, sol::table& table) {
  (void)L;
  table.set_function("isWindowOpen", [](const std::string& name) {
    return isWindowOpenImpl(name);
  });
  table.set_function("isMerchantOpen", []() { return isWindowOpenImpl("MerchantWnd"); });
}

}  // namespace window
}  // namespace cooptui
