#include "Logger.h"
#include "Config.h"
#include <mq/Plugin.h>
#include <cstdarg>
#include <cstdio>
#include <chrono>

namespace cooptui {
namespace core {

namespace {

constexpr const char* kPrefix = "[MQ2CoOptUI] ";

void LogV(int level, const char* fmt, std::va_list args) {
  std::va_list argsCopy;
  va_copy(argsCopy, args);
  int n = std::vsnprintf(nullptr, 0, fmt, argsCopy);
  va_end(argsCopy);
  if (n < 0) return;
  std::string buf(static_cast<size_t>(n) + 1, '\0');
  n = std::vsnprintf(&buf[0], buf.size(), fmt, args);
  if (n < 0) return;
  buf.resize(static_cast<size_t>(n));
  std::string msg = std::string(kPrefix) + buf;

  if (level == 0) {
    WriteChatf("%s", msg.c_str());
    return;
  }
  if (Config::Instance().GetDebugLevel() < level) return;
  DebugSpew("%s", msg.c_str());
}

}  // namespace

void Log(int level, const char* fmt, ...) {
  std::va_list args;
  va_start(args, fmt);
  LogV(level, fmt, args);
  va_end(args);
}

ScopedTimer::ScopedTimer(const std::string& name) : name_(name) {
  startTick_ = static_cast<int64_t>(
      std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now().time_since_epoch())
          .count());
}

ScopedTimer::~ScopedTimer() {
  int64_t endTick = static_cast<int64_t>(
      std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now().time_since_epoch())
          .count());
  int64_t elapsed = endTick - startTick_;
  Log(2, "%s: %lld ms", name_.c_str(), static_cast<long long>(elapsed));
}

}  // namespace core
}  // namespace cooptui
