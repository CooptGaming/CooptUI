#include "ini.h"
#include <sol/sol.hpp>
#include <Windows.h>
#include <vector>
#include <algorithm>

namespace cooptui {
namespace ini {

namespace {

constexpr DWORD kMaxProfileString = 32767;

std::string getString(const std::string& path, const std::string& section,
                      const std::string& key, const std::string& defaultVal) {
  std::vector<char> buf(kMaxProfileString, '\0');
  DWORD n = GetPrivateProfileStringA(
      section.c_str(), key.c_str(), defaultVal.c_str(),
      buf.data(), static_cast<DWORD>(buf.size()), path.c_str());
  return std::string(buf.data(), n);
}

}  // namespace

void registerLua(sol::state_view L, sol::table& table) {
  lua_State* rawL = L.lua_state();

  table.set_function("read",
      [](const std::string& path, const std::string& section,
         const std::string& key, sol::optional<std::string> defaultVal) {
        std::string def = defaultVal.value_or("");
        return getString(path, section, key, def);
      });

  table.set_function("write",
      [](const std::string& path, const std::string& section,
         const std::string& key, const std::string& value) {
        return WritePrivateProfileStringA(
            section.c_str(), key.c_str(), value.c_str(), path.c_str()) != 0;
      });

  table.set_function("readSection",
      [rawL](const std::string& path, const std::string& section) {
        sol::state_view sv(rawL);
        std::vector<char> buf(kMaxProfileString * 2, '\0');
        DWORD n = GetPrivateProfileSectionA(
            section.c_str(), buf.data(), static_cast<DWORD>(buf.size()),
            path.c_str());
        sol::table result = sv.create_table();
        std::string block(buf.data(), n);
        std::string key, val;
        size_t i = 0;
        while (i < block.size()) {
          size_t end = block.find('\0', i);
          if (end == std::string::npos) end = block.size();
          std::string line(block.data() + i, end - i);
          i = end + 1;
          size_t eq = line.find('=');
          if (eq != std::string::npos) {
            key = line.substr(0, eq);
            val = (eq + 1 < line.size()) ? line.substr(eq + 1) : "";
            result[key] = val;
          }
        }
        return result;
      });

  table.set_function("readBatch",
      [rawL](sol::table requests) {
        sol::state_view sv(rawL);
        sol::table results = sv.create_table();
        for (size_t i = 1; i <= requests.size(); ++i) {
          sol::optional<sol::table> req = requests.get<sol::optional<sol::table>>(i);
          if (!req) continue;
          std::string path, section, key, def;
          if (req->get<sol::optional<std::string>>(1)) {
            path = req->get<std::string>(1);
            section = req->get<std::string>(2);
            key = req->get<std::string>(3);
            def = req->get<sol::optional<std::string>>(4).value_or("");
          } else {
            sol::optional<std::string> p = req->get<sol::optional<std::string>>("path");
            sol::optional<std::string> s = req->get<sol::optional<std::string>>("section");
            sol::optional<std::string> k = req->get<sol::optional<std::string>>("key");
            if (!p || !s || !k) continue;
            path = *p;
            section = *s;
            key = *k;
            def = req->get<sol::optional<std::string>>("default").value_or("");
          }
          std::string val = getString(path, section, key, def);
          results.add(val);
        }
        return results;
      });
}

}  // namespace ini
}  // namespace cooptui
