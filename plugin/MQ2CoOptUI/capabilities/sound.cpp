#include "sound.h"

#include <sol/sol.hpp>
#include <string>
#include <Windows.h>
#include <mmsystem.h>

#pragma comment(lib, "winmm.lib")

namespace cooptui {
namespace sound {

// Play a .wav file asynchronously. Returns true if the file was found and playback started.
// If path is empty, stops any currently playing sound.
static bool playSoundFile(const std::string& path) {
  if (path.empty()) {
    PlaySoundA(nullptr, nullptr, 0);
    return true;
  }
  // SND_ASYNC: non-blocking. SND_NODEFAULT: don't play default beep on failure.
  BOOL ok = PlaySoundA(path.c_str(), nullptr, SND_FILENAME | SND_ASYNC | SND_NODEFAULT);
  return ok != FALSE;
}

// Play a simple system beep (no file needed).
static void playBeep() {
  MessageBeep(MB_OK);
}

void registerLua(sol::state_view L, sol::table& table) {
  (void)L;
  table.set_function("playSound", [](const std::string& path) {
    return playSoundFile(path);
  });
  table.set_function("stopSound", []() {
    PlaySoundA(nullptr, nullptr, 0);
  });
  table.set_function("beep", []() {
    playBeep();
  });
}

}  // namespace sound
}  // namespace cooptui
