#pragma once

#include <cstdint>
#include <string>

namespace cooptui {
namespace core {

// Log level: 0 = always (WriteChatf), 1-3 = DebugSpew (only when config DebugLevel >= level).
void Log(int level, const char* fmt, ...);

// RAII timer: logs elapsed milliseconds on destruction (at debug level 2).
class ScopedTimer {
 public:
  explicit ScopedTimer(const std::string& name);
  ~ScopedTimer();

  ScopedTimer(const ScopedTimer&) = delete;
  ScopedTimer& operator=(const ScopedTimer&) = delete;

 private:
  std::string name_;
  int64_t startTick_;
};

}  // namespace core
}  // namespace cooptui
