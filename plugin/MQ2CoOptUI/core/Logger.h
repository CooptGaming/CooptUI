#pragma once

#include <cstdint>
#include <string>

namespace cooptui {
namespace core {

// High-resolution monotonic time for perf/stress timing (avoids GetTickCount64's ~15 ms resolution).
// Returns microseconds since an arbitrary epoch.
uint64_t MonotonicUs();
// Elapsed ms between two MonotonicUs() values (rounded).
inline uint64_t ElapsedMsFromUs(uint64_t startUs, uint64_t endUs) {
  return (endUs - startUs + 500) / 1000;
}

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
