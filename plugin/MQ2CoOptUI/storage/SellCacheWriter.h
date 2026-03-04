#pragma once

#include "../core/ItemData.h"
#include <string>
#include <vector>

namespace cooptui {
namespace storage {

// SellCacheWriter — writes sell_cache.ini using Win32 file APIs.
//
// Matches Lua storage.writeSellCache() format exactly:
//   [Meta]  savedAt=<epoch>  chunks=N
//   [Count] count=M
//   [Items] 1=name1/name2/...  2=name3/...
//
// Each [Items] value is <= kChunkLen chars to stay under MQ macro buffer
// limits (avoids buffer overflow in /call CheckFilterList).
//
// Writes to two locations:
//   1. Char-specific: {macrosPath}sell_config\Chars\{charName}\sell_cache.ini
//   2. Shared:        {macrosPath}sell_config\sell_cache.ini
class SellCacheWriter {
 public:
  // Max chars per [Items] value — matches Lua SELL_CACHE_CHUNK_LEN.
  static constexpr size_t kChunkLen = 1700;

  // Write sell_cache.ini to both the char-specific and shared paths.
  // macrosPath: gPathMacros (e.g. "C:\...\Macros\")
  // charName:   current character name (for Chars/<CharName>/ subfolder)
  // items:      inventory items; those with willSell==true are included
  // Returns true if at least one file was written successfully.
  static bool Write(const std::string& macrosPath,
                    const std::string& charName,
                    const std::vector<core::CoOptItemData>& items);

 private:
  static bool EnsureDirectory(const std::string& dirPath);
  static bool WriteContent(const std::string& path, const std::string& content);
  static std::string EnsureTrailingSlash(const std::string& p);
};

}  // namespace storage
}  // namespace cooptui
