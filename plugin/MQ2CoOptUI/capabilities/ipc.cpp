#include "ipc.h"
#include <sol/sol.hpp>
#include <unordered_map>
#include <deque>
#include <string>

namespace cooptui {
namespace ipc {

namespace {

constexpr size_t kMaxChannelSize = 1024;
std::unordered_map<std::string, std::deque<std::string>> s_channels;

}  // namespace

void registerLua(sol::state_view L, sol::table& table) {
  table.set_function("send",
      [](const std::string& channel, const std::string& message) {
        auto& q = s_channels[channel];
        if (q.size() >= kMaxChannelSize) q.pop_front();
        q.push_back(message);
      });

  table.set_function("receive",
      [](const std::string& channel) -> sol::optional<std::string> {
        auto it = s_channels.find(channel);
        if (it == s_channels.end() || it->second.empty())
          return sol::nullopt;
        std::string msg = std::move(it->second.front());
        it->second.pop_front();
        return msg;
      });

  table.set_function("peek",
      [](const std::string& channel) -> sol::optional<std::string> {
        auto it = s_channels.find(channel);
        if (it == s_channels.end() || it->second.empty())
          return sol::nullopt;
        return it->second.front();
      });

  table.set_function("receiveAll",
      [](const std::string& channel, sol::this_state ts) -> sol::table {
        sol::state_view lua(ts);
        sol::table result = lua.create_table();
        auto it = s_channels.find(channel);
        if (it != s_channels.end()) {
          int idx = 1;
          for (auto& msg : it->second) {
            result[idx++] = std::move(msg);
          }
          it->second.clear();
        }
        return result;
      });

  table.set_function("clear",
      [](const std::string& channel) {
        s_channels[channel].clear();
      });
}

void sendFromMacro(const std::string& channel, const std::string& message) {
  auto& q = s_channels[channel];
  if (q.size() >= kMaxChannelSize) q.pop_front();
  q.push_back(message);
}

size_t GetMaxChannelSize() { return kMaxChannelSize; }

}  // namespace ipc
}  // namespace cooptui
