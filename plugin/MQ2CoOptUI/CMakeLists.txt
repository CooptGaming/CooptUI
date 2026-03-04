# MQ2CoOptUI plugin. Built as part of MacroQuest when this directory is
# present under MQ's plugins/ (e.g. via symlink from CoOpt UI repo).
# Configure MQ with -DMQ_BUILD_CUSTOM_PLUGINS=ON.
#
# Custom plugins are in a different add_subdirectory scope than src/plugins/*,
# so Plugin.cmake's PATH_TO_Plugin_DIR is not set here. Set it so
# target_Plugin_props can find Common.cmake (and Plugin-private.cmake).
set(PATH_TO_Plugin_DIR "${CMAKE_SOURCE_DIR}/src")
include("${CMAKE_SOURCE_DIR}/src/Plugin.cmake")

set(MQ2CoOptUI_SOURCES
  MQ2CoOptUI.cpp
  core/Config.cpp
  core/CacheManager.cpp
  core/Logger.cpp
  capabilities/ini.cpp
  capabilities/ipc.cpp
  capabilities/cursor.cpp
  capabilities/window.cpp
  capabilities/items.cpp
  capabilities/loot.cpp
  scanners/BankScanner.cpp
  scanners/InventoryScanner.cpp
)

add_library(MQ2CoOptUI MODULE ${MQ2CoOptUI_SOURCES})
target_Plugin_props(MQ2CoOptUI)

# Lua/sol2: need LuaPlugin and luajit so sol2 headers can find lua.h (MQ2Lua uses luajit + sol2).
find_package(luajit REQUIRED)
if(TARGET LuaPlugin::LuaPlugin)
  target_link_libraries(MQ2CoOptUI PRIVATE LuaPlugin::LuaPlugin luajit::luajit)
else()
  target_link_libraries(MQ2CoOptUI PRIVATE luajit::luajit)
endif()

# C++20 for sol2 (match MQ2Lua per gotchas §7).
set_target_properties(MQ2CoOptUI PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED YES
)

