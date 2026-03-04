#pragma once

#include "../core/ItemData.h"
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace cooptui {
namespace rules {

// -----------------------------------------------------------------------
// Sell config cache — mirrors Lua rules.loadSellConfigCache()
// -----------------------------------------------------------------------
struct SellConfig {
  // Flag settings (sell_flags.ini)
  bool protectNoDrop = true;
  bool protectNoTrade = true;
  bool protectLore = true;
  bool protectQuest = true;
  bool protectCollectible = true;
  bool protectHeirloom = true;
  bool protectEpic = true;
  bool protectAttuneable = false;
  bool protectAugSlots = false;

  // Value thresholds (sell_value.ini)
  int minSell = 50;
  int minStack = 10;
  int maxKeep = 10000;
  int tributeKeepOverride = 1000;

  // Sets / lists (O(1) lookup)
  std::unordered_set<std::string> keepSet;           // shared valuable_exact + sell_keep_exact
  std::unordered_set<std::string> junkSet;           // sell_always_sell_exact
  std::vector<std::string> junkContainsList;         // sell_always_sell_contains
  std::unordered_set<std::string> augmentAlwaysSellSet;   // sell_augment_always_sell_exact
  std::unordered_set<std::string> neverLootSellSet;       // loot_skip_exact
  std::unordered_set<std::string> augmentNeverLootSellSet; // loot_augment_skip_exact
  std::unordered_set<std::string> protectedTypeSet;  // sell_protected_types
  std::vector<std::string> keepContainsList;         // shared valuable_contains + sell_keep_contains
  std::unordered_set<std::string> keepTypeSet;       // shared valuable_types + sell_keep_types + protected_types
  std::unordered_set<std::string> epicItemSet;       // class-filtered epic items
};

// -----------------------------------------------------------------------
// Loot config cache — mirrors Lua rules.loadLootConfigCache()
// -----------------------------------------------------------------------
struct LootConfig {
  // Value thresholds (loot_value.ini)
  int minLootValue = 999;
  int minLootValueStack = 200;
  int tributeOverride = 0;

  // Flag settings (loot_flags.ini)
  bool lootClickies = false;
  bool lootQuest = false;
  bool lootCollectible = false;
  bool lootHeirloom = false;
  bool lootAttuneable = false;
  bool lootAugSlots = false;
  bool alwaysLootEpic = true;

  // Sets / lists
  std::unordered_set<std::string> skipExactSet;
  std::unordered_set<std::string> augmentSkipExactSet;
  std::vector<std::string> skipContainsList;
  std::unordered_set<std::string> skipTypeSet;
  std::unordered_set<std::string> alwaysLootExactSet;
  std::vector<std::string> alwaysLootContainsList;
  std::unordered_set<std::string> alwaysLootTypeSet;
  std::unordered_set<std::string> epicItemSet;
};

// -----------------------------------------------------------------------
// RulesEngine singleton
// -----------------------------------------------------------------------
class RulesEngine {
 public:
  static RulesEngine& Instance();

  // Initialize with the MQ macros directory path (gPathMacros).
  // Call from InitializePlugin after Config is ready.
  void Initialize(const std::string& macrosPath);

  // Reload all INI files (called by /cooptui reloadrules and after config reload).
  void Reload();

  void Shutdown() {}

  // Evaluate sell decision for one item. Mirrors Lua willItemBeSold().
  // Returns {willSell, reason}.
  std::pair<bool, std::string> WillItemBeSold(const core::CoOptItemData& item) const;

  // Evaluate loot decision for one item. Mirrors Lua shouldItemBeLooted().
  std::pair<bool, std::string> ShouldItemBeLooted(const core::CoOptItemData& item) const;

  // Attach willSell/sellReason to all items in a vector.
  void AttachSellStatus(std::vector<core::CoOptItemData>& items) const;

  bool IsLoaded() const { return loaded_; }

  // Diagnostic counts for /cooptui status
  size_t GetKeepSetSize() const { return sell_.keepSet.size(); }
  size_t GetJunkSetSize() const { return sell_.junkSet.size(); }
  size_t GetAlwaysLootSize() const { return loot_.alwaysLootExactSet.size(); }
  size_t GetSkipLootSize() const { return loot_.skipExactSet.size(); }
  size_t GetEpicSellSize() const { return sell_.epicItemSet.size(); }

  RulesEngine(const RulesEngine&) = delete;
  RulesEngine& operator=(const RulesEngine&) = delete;

 private:
  RulesEngine() = default;

  // INI helpers
  std::string ReadIni(const std::string& path, const char* section,
                      const char* key, const char* defaultVal) const;
  std::string ReadChunkedList(const std::string& path, const char* section,
                              const char* key) const;

  // Path builders
  std::string SellPath(const char* file) const;
  std::string SharedPath(const char* file) const;
  std::string LootPath(const char* file) const;

  // Loaders
  void LoadSellConfig();
  void LoadLootConfig();
  std::unordered_set<std::string> LoadEpicItemSet() const;

  // Helpers
  static void ParseSlashList(const std::string& raw,
                             std::unordered_set<std::string>& outSet);
  static void ParseSlashList(const std::string& raw,
                             std::vector<std::string>& outVec);
  static std::string NormalizeName(const std::string& s);
  static bool IsValidEntry(const std::string& s);
  static std::string TrimStr(const std::string& s);

  std::string macrosPath_;  // gPathMacros (e.g. "...\CoOptUI7\Macros\")
  SellConfig sell_;
  LootConfig loot_;
  bool loaded_ = false;
};

}  // namespace rules
}  // namespace cooptui
