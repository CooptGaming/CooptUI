#include "cursor.h"

#include <cstdio>
#include <sol/sol.hpp>
#include <string>

#include "eqlib/game/Constants.h"
#include "eqlib/game/Globals.h"
#include "eqlib/game/ItemLinks.h"
#include "eqlib/game/Items.h"
#include "eqlib/game/PcClient.h"

#include "../core/Logger.h"

namespace cooptui {
namespace cursor {

namespace {

bool s_hasItem = false;
int s_itemId = 0;
int s_itemStack = 1;
std::string s_itemName;
std::string s_itemType;
std::string s_itemLink;

static std::string ItemTypeString(uint8_t itemClass) {
  if (itemClass < eqlib::MAX_ITEMCLASSES && eqlib::szItemClasses[itemClass] != nullptr)
    return eqlib::szItemClasses[itemClass];
  return "";
}

}  // namespace

void updateFromPulse() {
  if (!eqlib::pLocalPC) {
    s_hasItem = false;
    s_itemId = 0;
    s_itemStack = 1;
    s_itemName.clear();
    s_itemType.clear();
    s_itemLink.clear();
    return;
  }

  eqlib::ItemPtr cursorItem = eqlib::pLocalPC->GetInventorySlot(eqlib::InvSlot_Cursor);
  if (cursorItem && cursorItem->GetID() > 0) {
    s_hasItem = true;
    s_itemId = cursorItem->GetID();
    s_itemStack = cursorItem->GetItemCount();
    if (s_itemStack < 1) s_itemStack = 1;
    eqlib::ItemDefinition* def = cursorItem->GetItemDefinition();
    s_itemName = def ? def->Name : "";
    s_itemType = def ? ItemTypeString(def->ItemClass) : "";

    char linkBuf[4096] = {0};
    eqlib::FormatItemLink(linkBuf, sizeof(linkBuf), cursorItem.get());
    s_itemLink = linkBuf;
  } else {
    s_hasItem = false;
    s_itemId = 0;
    s_itemStack = 1;
    s_itemName.clear();
    s_itemType.clear();
    s_itemLink.clear();
  }
}

void registerLua(sol::state_view L, sol::table& table) {
  (void)L;
  table.set_function("hasItem", []() { return s_hasItem; });
  table.set_function("getItemId", []() -> sol::optional<int> {
    return s_hasItem ? sol::optional<int>(s_itemId) : sol::nullopt;
  });
  table.set_function("getItemName", []() -> sol::optional<std::string> {
    return s_hasItem ? sol::optional<std::string>(s_itemName) : sol::nullopt;
  });
  table.set_function("getItemType", []() -> sol::optional<std::string> {
    return s_hasItem ? sol::optional<std::string>(s_itemType) : sol::nullopt;
  });
  table.set_function("getItemLink", []() -> sol::optional<std::string> {
    return s_hasItem && !s_itemLink.empty()
        ? sol::optional<std::string>(s_itemLink)
        : sol::nullopt;
  });
  table.set_function("getItemStack", []() -> sol::optional<int> {
    return s_hasItem ? sol::optional<int>(s_itemStack) : sol::nullopt;
  });
}

void LogCursorState() {
  updateFromPulse();  // refresh cache before logging
  if (!s_hasItem) {
    core::Log(0, "cursor: hasItem=false (no item on cursor)");
    return;
  }
  core::Log(0, "cursor: hasItem=true id=%d name=\"%s\" type=%s stack=%d",
            s_itemId, s_itemName.c_str(), s_itemType.c_str(), s_itemStack);
  if (!s_itemLink.empty()) {
    // Link is binary (contains nulls/non-printable bytes); show length and hex of first few bytes
    size_t n = s_itemLink.size();
    const size_t show = (n < 12u) ? n : 12u;
    char hex[64] = {0};
    for (size_t i = 0; i < show; ++i) {
      unsigned char b = static_cast<unsigned char>(s_itemLink[i]);
      snprintf(hex + (i * 3), sizeof(hex) - (i * 3), "%02X%c", b, (i + 1 < show) ? ' ' : '\0');
    }
    core::Log(0, "  link: %zu bytes (hex: %s%s)", n, hex, (n > show) ? " ..." : "");
  }
}

}  // namespace cursor
}  // namespace cooptui
