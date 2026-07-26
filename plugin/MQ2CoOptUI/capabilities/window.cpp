#include "window.h"

#include <mq/Plugin.h>
#include <sol/sol.hpp>
#include <string>

#include "eqlib/game/Constants.h"
#include "eqlib/game/CXWnd.h"
#include "eqlib/game/Globals.h"
#include "eqlib/game/Items.h"
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

// Window round (2026-07): direct CXWnd access so the Lua side can stop
// simulating input. Everything here is handler/state-level - no synthetic
// mouse events, so EQ's mouse capture is never involved (the wedge that
// forced the old deferred, MouseOver-gated un-latch dance).

eqlib::CXWnd* findChild(const std::string& wndName, const std::string& childName) {
  eqlib::CXWnd* wnd = mq::FindMQ2Window(wndName.c_str());
  if (!wnd) return nullptr;
  if (childName.empty()) return wnd;
  return wnd->GetChildItem(eqlib::CXStr(childName));
}

eqlib::CButtonWnd* findButton(const std::string& wndName, const std::string& childName) {
  eqlib::CXWnd* c = findChild(wndName, childName);
  if (!c || !c->IsType(eqlib::WRT_BUTTON)) return nullptr;
  return static_cast<eqlib::CButtonWnd*>(c);
}

}  // namespace

void registerLua(sol::state_view L, sol::table& table) {
  lua_State* rawL = L.lua_state();

  table.set_function("isWindowOpen", [](const std::string& name) {
    return isWindowOpenImpl(name);
  });
  table.set_function("isMerchantOpen", []() { return isWindowOpenImpl("MerchantWnd"); });

  // Checked state of a button/checkbox child; nil when absent or not a button.
  table.set_function("getChecked",
                     [rawL](const std::string& wnd, const std::string& child) -> sol::object {
    sol::state_view sv(rawL);
    eqlib::CButtonWnd* btn = findButton(wnd, child);
    if (!btn) return sol::make_object(sv, sol::lua_nil);
    return sol::make_object(sv, btn->Checked);
  });

  // Direct state write via CButtonWnd::SetCheck - the clean un-latch: no
  // synthetic click, no notification echo, no capture involvement.
  table.set_function("setChecked",
                     [](const std::string& wnd, const std::string& child, bool checked) -> bool {
    eqlib::CButtonWnd* btn = findButton(wnd, child);
    if (!btn) return false;
    btn->SetCheck(checked);
    return true;
  });

  // SetWindowText on any child: labels, buttons, and edit boxes all override
  // it - status lines no longer have to be EditBoxes.
  table.set_function("setText",
                     [](const std::string& wnd, const std::string& child, const std::string& text) -> bool {
    eqlib::CXWnd* c = findChild(wnd, child);
    if (!c) return false;
    c->SetWindowText(eqlib::CXStr(text));
    return true;
  });

  // Real click: dispatch XWM_LCLICK to the child's parent handler chain - the
  // same code path a mouse click ends in, minus the mouse. Works on stock EQ
  // buttons (their action lives in the parent's WndNotification).
  table.set_function("click",
                     [](const std::string& wnd, const std::string& child) -> bool {
    eqlib::CXWnd* c = findChild(wnd, child);
    if (!c) return false;
    eqlib::CXWnd* target = c->GetParentWindow() ? c->GetParentWindow() : c;
    target->WndNotification(c, eqlib::XWM_LCLICK, nullptr);
    return true;
  });

  // The native inv slot under the mouse, resolved to a CoOpt item location:
  //   { source = "inv"|"bank"|"equipped", bag, slot, itemId, itemName }
  // in CoOpt conventions (inv: pack 1-10 / slot 1-based; bank: bag 1-based /
  // slot 1-based inside, 0 = top-level; equipped: slot = worn index 0-22).
  // nil when no slot is hovered, the slot is empty, or it belongs to a
  // container we don't map (corpse, merchant, trade, cursor...). This is what
  // makes bag/bank hover possible: those slot windows are nameless template
  // clones, invisible to the Window TLO, but every one is registered with
  // CInvSlotMgr and carries its ItemGlobalIndex.
  table.set_function("getMouseOverSlot", [rawL]() -> sol::object {
    sol::state_view sv(rawL);
    using namespace eqlib;
    if (!pInvSlotMgr || !pLocalPC) return sol::make_object(sv, sol::lua_nil);
    for (int i = 0; i < MAX_INV_SLOTS; ++i) {
      CInvSlot* slot = pInvSlotMgr->SlotArray[i];
      if (!slot || !slot->bEnabled) continue;
      CInvSlotWnd* w = slot->pInvSlotWnd;
      if (!w || !w->IsVisible() || !w->IsMouseOver()) continue;
      if (w->LinkedItem) continue;  // chat item links, not real slots

      const ItemGlobalIndex& loc = w->ItemLocation;
      short top = loc.GetTopSlot();
      short sub = loc.GetIndex().GetSlot(1);
      std::string source;
      int bag = 0;
      int slotOut = 0;
      if (loc.GetLocation() == eItemContainerPossessions) {
        if (top >= InvSlot_FirstBagSlot && top <= InvSlot_LastBagSlot) {
          source = "inv";
          bag = top - InvSlot_FirstBagSlot + 1;
          slotOut = (sub >= 0) ? sub + 1 : 0;
        } else if (top >= InvSlot_FirstWornItem && top <= InvSlot_LastWornItem) {
          source = "equipped";
          bag = 0;
          slotOut = top;
        } else {
          return sol::make_object(sv, sol::lua_nil);  // cursor etc.
        }
      } else if (loc.GetLocation() == eItemContainerBank) {
        source = "bank";
        bag = top + 1;
        slotOut = (sub >= 0) ? sub + 1 : 0;
      } else {
        return sol::make_object(sv, sol::lua_nil);  // corpse/merchant/trade/...
      }

      ItemPtr item = slot->GetItem();
      if (!item) return sol::make_object(sv, sol::lua_nil);  // empty slot
      ItemDefinition* def = item->GetItemDefinition();
      sol::table t = sv.create_table_with(
          "source", source,
          "bag", bag,
          "slot", slotOut,
          "itemId", item->GetID(),
          "itemName", def ? std::string(def->Name) : std::string());
      return sol::make_object(sv, t);
    }
    return sol::make_object(sv, sol::lua_nil);
  });
}

}  // namespace window
}  // namespace cooptui
