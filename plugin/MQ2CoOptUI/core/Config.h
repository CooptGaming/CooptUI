#pragma once

#include <cstdint>
#include <string>

namespace cooptui {
namespace core {

struct CoOptCoreConfig {
  // [General]
  int debugLevel = 0;  // 0-3

  // [Cache]
  int inventoryReserve = 256;
  int bankReserve = 512;
  int lootReserve = 512;
  int scanThrottleMs = 100;

  // [Rules]
  bool autoReloadOnChange = true;
};

class Config {
 public:
  static Config& Instance();

  void Initialize(const std::string& configFilePath);
  void Reload();

  const std::string& GetConfigPath() const { return configPath_; }
  const CoOptCoreConfig& Get() const { return config_; }
  CoOptCoreConfig& GetMutable() { return config_; }

  int GetDebugLevel() const { return config_.debugLevel; }
  void SetDebugLevel(int level);

 private:
  Config() = default;
  Config(const Config&) = delete;
  Config& operator=(const Config&) = delete;

  void CreateDefaultIfMissing();
  void ReadFromFile();

  std::string configPath_;
  CoOptCoreConfig config_;
};

}  // namespace core
}  // namespace cooptui
