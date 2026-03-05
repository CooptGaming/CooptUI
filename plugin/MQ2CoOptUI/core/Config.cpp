#include "Config.h"
#include <Windows.h>
#include <algorithm>
#include <cstring>
#include <fstream>
#include <sstream>

namespace cooptui {
namespace core {

namespace {

constexpr const char* kSectionGeneral = "General";
constexpr const char* kSectionCache = "Cache";
constexpr const char* kSectionRules = "Rules";
constexpr DWORD kMaxProfileString = 1024;

std::string getString(const std::string& path, const char* section,
                      const char* key, const std::string& defaultVal) {
  std::string buf(kMaxProfileString, '\0');
  DWORD n = GetPrivateProfileStringA(section, key, defaultVal.c_str(),
                                     &buf[0], static_cast<DWORD>(buf.size()),
                                     path.c_str());
  buf.resize(n);
  return buf;
}

int getInt(const std::string& path, const char* section, const char* key,
           int defaultVal) {
  std::string s = getString(path, section, key, std::to_string(defaultVal));
  if (s.empty()) return defaultVal;
  try {
    return std::stoi(s);
  } catch (...) {
    return defaultVal;
  }
}

bool getBool(const std::string& path, const char* section, const char* key,
             bool defaultVal) {
  std::string s = getString(path, section, key, defaultVal ? "true" : "false");
  if (s.empty()) return defaultVal;
  if (s == "1" || s == "true" || s == "yes" || s == "on") return true;
  if (s == "0" || s == "false" || s == "no" || s == "off") return false;
  return defaultVal;
}

const char* kDefaultIniContent =
    "[General]\r\n"
    "DebugLevel=0\r\n"
    "\r\n"
    "[Cache]\r\n"
    "InventoryReserve=256\r\n"
    "BankReserve=512\r\n"
    "LootReserve=512\r\n"
    "ScanThrottleMs=100\r\n"
    "\r\n"
    "[Rules]\r\n"
    "AutoReloadOnChange=true\r\n";

}  // namespace

Config& Config::Instance() {
  static Config instance;
  return instance;
}

void Config::Initialize(const std::string& configFilePath) {
  configPath_ = configFilePath;
  CreateDefaultIfMissing();
  ReadFromFile();
}

void Config::Reload() {
  if (configPath_.empty()) return;
  CreateDefaultIfMissing();
  ReadFromFile();
}

void Config::SetDebugLevel(int level) {
  config_.debugLevel = std::clamp(level, 0, 3);
}

void Config::CreateDefaultIfMissing() {
  if (configPath_.empty()) return;
  std::ifstream f(configPath_);
  if (f.good()) return;
  f.close();
  std::ofstream out(configPath_, std::ios::out | std::ios::binary);
  if (out) out.write(kDefaultIniContent, static_cast<std::streamsize>(strlen(kDefaultIniContent)));
}

void Config::ReadFromFile() {
  if (configPath_.empty()) return;

  CoOptCoreConfig c;
  c.debugLevel = getInt(configPath_, kSectionGeneral, "DebugLevel", 0);
  c.debugLevel = std::clamp(c.debugLevel, 0, 3);

  c.inventoryReserve = getInt(configPath_, kSectionCache, "InventoryReserve", 256);
  c.bankReserve = getInt(configPath_, kSectionCache, "BankReserve", 512);
  c.lootReserve = getInt(configPath_, kSectionCache, "LootReserve", 512);
  c.scanThrottleMs = getInt(configPath_, kSectionCache, "ScanThrottleMs", 100);

  c.autoReloadOnChange = getBool(configPath_, kSectionRules, "AutoReloadOnChange", true);

  config_ = c;
}

}  // namespace core
}  // namespace cooptui
