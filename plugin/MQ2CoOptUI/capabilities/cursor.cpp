#include "cursor.h"
#include <sol/sol.hpp>
#include <string>

namespace cooptui {
namespace cursor {

namespace {

bool s_hasItem = false;
int s_itemId = 0;
std::string s_itemName;

}  // namespace

void updateFromPulse() {
  // TODO: when building in MQ tree, use pLocalPlayer->GetItemByGlobalIndex(
  //   eItemContainerCursor, 0) to set s_hasItem, s_itemId, s_itemName.
  (void)s_hasItem;
  (void)s_itemId;
  (void)s_itemName;
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
}

}  // namespace cursor
}  // namespace cooptui
