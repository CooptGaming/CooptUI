#pragma once

#include <cstdint>
#include <string>

namespace cooptui {
namespace core {

// Item struct matching Lua buildItemFromMQ output for UI views.
// All text fields use std::string; no char[] anywhere.
// Phase A: extended with all definition-time fields (stats, descriptive, spell IDs, aug, etc.).
struct CoOptItemData {
  // --- Core fields ---
  int32_t id = 0;
  int32_t bag = 0;
  int32_t slot = 0;
  std::string source;  // "inv", "bank", "loot"
  std::string name;
  std::string type;
  int32_t value = 0;
  int32_t totalValue = 0;
  int32_t stackSize = 1;
  int32_t weight = 0;
  int32_t icon = 0;
  int32_t tribute = 0;
  bool nodrop = false;
  bool notrade = false;
  bool lore = false;
  bool attuneable = false;
  bool heirloom = false;
  bool collectible = false;
  bool quest = false;
  int32_t augSlots = 0;
  int32_t clicky = 0;
  std::string wornSlots;
  // Pre-evaluated rule results (Phase 5+)
  bool willSell = false;
  std::string sellReason;
  bool willLoot = false;
  std::string lootReason;

  // --- Spell effect IDs (Proc, Focus, Spell, Worn, Focus2, Familiar, Illusion, Mount) ---
  int32_t proc = 0;
  int32_t focus = 0;
  int32_t spell = 0;
  int32_t worn = 0;
  int32_t focus2 = 0;
  int32_t familiar = 0;
  int32_t illusion = 0;
  int32_t mount = 0;

  // --- Augment properties (for augmentation-type items) ---
  int32_t augType = 0;
  int32_t augRestrictions = 0;

  // --- Stat fields (match STAT_TLO_MAP keys exactly) ---
  int32_t ac = 0;
  int32_t hp = 0;
  int32_t mana = 0;
  int32_t endurance = 0;
  int32_t str = 0;
  int32_t sta = 0;
  int32_t agi = 0;
  int32_t dex = 0;
  int32_t _int = 0;  // "int" is reserved; Lua key is "int"
  int32_t wis = 0;
  int32_t cha = 0;
  int32_t attack = 0;
  int32_t accuracy = 0;
  int32_t avoidance = 0;
  int32_t shielding = 0;
  int32_t haste = 0;
  int32_t damage = 0;
  int32_t itemDelay = 0;
  int32_t dmgBonus = 0;
  std::string dmgBonusType;
  int32_t spellDamage = 0;
  int32_t strikeThrough = 0;
  int32_t damageShield = 0;
  int32_t combatEffects = 0;
  int32_t dotShielding = 0;
  int32_t hpRegen = 0;
  int32_t manaRegen = 0;
  int32_t enduranceRegen = 0;
  int32_t spellShield = 0;
  int32_t damageShieldMitigation = 0;
  int32_t stunResist = 0;
  int32_t clairvoyance = 0;
  int32_t healAmount = 0;
  int32_t heroicSTR = 0;
  int32_t heroicSTA = 0;
  int32_t heroicAGI = 0;
  int32_t heroicDEX = 0;
  int32_t heroicINT = 0;
  int32_t heroicWIS = 0;
  int32_t heroicCHA = 0;
  int32_t svMagic = 0;
  int32_t svFire = 0;
  int32_t svCold = 0;
  int32_t svPoison = 0;
  int32_t svDisease = 0;
  int32_t svCorruption = 0;
  int32_t heroicSvMagic = 0;
  int32_t heroicSvFire = 0;
  int32_t heroicSvCold = 0;
  int32_t heroicSvDisease = 0;
  int32_t heroicSvPoison = 0;
  int32_t heroicSvCorruption = 0;
  int32_t charges = 0;
  int32_t range = 0;
  int32_t skillModValue = 0;
  int32_t skillModMax = 0;
  int32_t baneDMG = 0;
  std::string baneDMGType;
  int32_t luck = 0;
  int32_t purity = 0;

  // --- Descriptive fields (match DESCRIPTIVE_FIELDS keys) ---
  int32_t size = 0;
  int32_t sizeCapacity = 0;
  int32_t container = 0;
  int32_t stackSizeMax = 0;
  bool norent = false;
  bool magic = false;
  bool prestige = false;
  bool tradeskills = false;
  int32_t requiredLevel = 0;
  int32_t recommendedLevel = 0;
  std::string instrumentType;
  int32_t instrumentMod = 0;
  std::string classStr;   // Lua key: "class"
  std::string raceStr;    // Lua key: "race"
  std::string deityStr;   // Lua key: "deity"

  // --- Capture-all: additional definition-time fields ---
  bool stackable = false;
  bool loreEquipped = false;
  bool noDestroy = false;
  bool summoned = false;
  bool expendable = false;
  int32_t procRate = 0;
  int32_t ornamentationIcon = 0;
  int32_t ldoNCost = 0;
  std::string ldoNTheme;
  int32_t maxLuck = 0;
  int32_t minLuck = 0;
  int32_t weightReduction = 0;
  int32_t contentSize = 0;
  int32_t slotsUsedByItem = 0;
  int32_t power = 0;
  int32_t maxPower = 0;
  float pctPower = 0.f;
  int32_t quality = 0;
  int32_t delay = 0;
  std::string idFile;
  std::string idFile2;
};

}  // namespace core
}  // namespace cooptui
