#include "SellCacheWriter.h"

#include <Windows.h>
#include <ctime>
#include <sstream>
#include <string>

#include "../core/Logger.h"

namespace cooptui {
namespace storage {

std::string SellCacheWriter::EnsureTrailingSlash(const std::string& p) {
  if (p.empty()) return p;
  char last = p.back();
  if (last != '\\' && last != '/') return p + '\\';
  return p;
}

bool SellCacheWriter::EnsureDirectory(const std::string& dirPath) {
  if (dirPath.empty()) return false;
  if (!CreateDirectoryA(dirPath.c_str(), nullptr)) {
    return GetLastError() == ERROR_ALREADY_EXISTS;
  }
  return true;
}

bool SellCacheWriter::WriteContent(const std::string& path,
                                    const std::string& content) {
  HANDLE hFile = CreateFileA(path.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (hFile == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  BOOL ok = WriteFile(hFile, content.c_str(),
                      static_cast<DWORD>(content.size()), &written, nullptr);
  CloseHandle(hFile);
  return ok && written == static_cast<DWORD>(content.size());
}

bool SellCacheWriter::Write(const std::string& macrosPath,
                             const std::string& charName,
                             const std::vector<core::CoOptItemData>& items) {
  if (macrosPath.empty() || items.empty()) return false;

  // Collect items with willSell == true, trimmed and sanitized
  std::vector<std::string> toSell;
  toSell.reserve(items.size());
  for (const auto& it : items) {
    if (!it.willSell || it.name.empty()) continue;

    // Trim leading/trailing whitespace (match Lua behavior)
    std::string name = it.name;
    size_t start = name.find_first_not_of(" \t\r\n");
    if (start == std::string::npos) continue;
    size_t end = name.find_last_not_of(" \t\r\n");
    name = name.substr(start, end - start + 1);

    // Replace CR/LF with space inside the name
    for (auto& c : name) {
      if (c == '\r' || c == '\n') c = ' ';
    }

    if (!name.empty()) toSell.push_back(std::move(name));
  }

  if (toSell.empty()) return false;

  // Build slash-delimited chunks, each <= kChunkLen chars
  std::vector<std::string> chunks;
  std::string current;
  for (const auto& name : toSell) {
    size_t addLen = name.size() + (current.empty() ? 0u : 1u);
    if (!current.empty() && current.size() + addLen > kChunkLen) {
      chunks.push_back(current);
      current = name;
    } else {
      if (!current.empty()) current += '/';
      current += name;
    }
  }
  if (!current.empty()) chunks.push_back(current);

  // Build INI file content matching Lua format
  std::time_t now = std::time(nullptr);
  std::ostringstream oss;
  oss << "[Meta]\n";
  oss << "savedAt=" << static_cast<long long>(now) << "\n";
  oss << "chunks=" << chunks.size() << "\n";
  oss << "\n";
  oss << "[Count]\n";
  oss << "count=" << toSell.size() << "\n";
  oss << "\n";
  oss << "[Items]\n";
  for (size_t i = 0; i < chunks.size(); ++i) {
    oss << (i + 1) << "=" << chunks[i] << "\n";
  }
  const std::string content = oss.str();

  const std::string base = EnsureTrailingSlash(macrosPath);
  bool ok = false;

  // Char-specific path: sell_config\Chars\<CharName>\sell_cache.ini
  if (!charName.empty()) {
    std::string sellConfigDir = base + "sell_config";
    EnsureDirectory(sellConfigDir);
    std::string charsDir = sellConfigDir + "\\Chars";
    EnsureDirectory(charsDir);
    std::string charDir = charsDir + "\\" + charName;
    EnsureDirectory(charDir);
    std::string charPath = charDir + "\\sell_cache.ini";
    ok = WriteContent(charPath, content);
    if (!ok) {
      core::Log(1, "SellCacheWriter: failed writing char path: %s",
                charPath.c_str());
    }
  }

  // Shared path: sell_config\sell_cache.ini
  {
    std::string sellConfigDir = base + "sell_config";
    EnsureDirectory(sellConfigDir);
    std::string sharedPath = sellConfigDir + "\\sell_cache.ini";
    bool okShared = WriteContent(sharedPath, content);
    if (!okShared) {
      core::Log(1, "SellCacheWriter: failed writing shared path: %s",
                sharedPath.c_str());
    }
    ok = ok || okShared;
  }

  return ok;
}

}  // namespace storage
}  // namespace cooptui
