#include "ItemDataPopulate.h"

#include "eqlib/game/Constants.h"
#include "eqlib/game/EverQuest.h"
#include "eqlib/game/Globals.h"

#include <sstream>

namespace cooptui {
namespace core {

// Slot index 0-22 to display name (matches Lua SLOT_DISPLAY_NAMES in item_tlo.lua).
static const char* const kSlotDisplayNames[] = {
    "Charm", "Ear", "Head", "Face", "Ear", "Neck", "Shoulder", "Arms", "Back",
    "Wrist", "Wrist", "Ranged", "Hands", "Primary", "Secondary", "Ring", "Ring",
    "Chest", "Legs", "Feet", "Waist", "Power", "Ammo",
};

static std::string BuildWornSlotsString(int equipSlots) {
  if (equipSlots == 0) return "";
  int count = 0;
  for (int i = 0; i <= eqlib::InvSlot_LastWornItem; ++i) {
    if (equipSlots & (1 << i)) ++count;
  }
  if (count >= 20) return "All";
  std::ostringstream oss;
  bool first = true;
  for (int i = 0; i <= eqlib::InvSlot_LastWornItem; ++i) {
    if (equipSlots & (1 << i)) {
      if (!first) oss << ", ";
      oss << kSlotDisplayNames[i];
      first = false;
    }
  }
  return oss.str();
}

static std::string BuildClassString(int classes) {
  if (classes <= 0) return "";
  if (classes >= 16) return "All";
  if (!eqlib::pEverQuest) return "";
  std::ostringstream oss;
  bool first = true;
  for (int i = 0; i < eqlib::TotalPlayerClasses; ++i) {
    if (classes & (1 << i)) {
      const char* name = eqlib::pEverQuest->GetClassDesc(static_cast<eqlib::EQClass>(i + 1));
      if (name && name[0]) {
        if (!first) oss << " ";
        oss << name;
        first = false;
      }
    }
  }
  return oss.str();
}

static int RaceBitToId(int num) {
  switch (num) {
    case 12: return 128;   // IKS
    case 13: return 130;   // VAH
    case 14: return 330;   // FRG
    case 15: return 522;   // DRK
    default: return num + 1;
  }
}

static std::string BuildRaceString(int races) {
  if (races <= 0) return "";
  if (races >= 15) return "All";
  if (!eqlib::pEverQuest) return "";
  std::ostringstream oss;
  bool first = true;
  for (int i = 0; i < 16; ++i) {
    if (races & (1 << i)) {
      int raceId = RaceBitToId(i);
      const char* name = eqlib::pEverQuest->GetRaceDesc(static_cast<eqlib::EQRace>(raceId));
      if (name && name[0]) {
        if (!first) oss << " ";
        oss << name;
        first = false;
      }
    }
  }
  return oss.str();
}

static std::string BuildDeityString(int deity) {
  if (deity == 0) return "";
  if (!eqlib::pEverQuest) return "";
  std::ostringstream oss;
  bool first = true;
  for (int i = 0; i < 16; ++i) {
    if (deity & (1 << i)) {
      const char* name = eqlib::pEverQuest->GetDeityDesc(200 + i);
      if (name && name[0]) {
        if (!first) oss << " ";
        oss << name;
        first = false;
      }
    }
  }
  return oss.str();
}

// DMGBonusType: ElementalFlag 0=None, 1=Magic, 2=Fire, 3=Cold, 4=Poison, 5=Disease
static const char* const kDmgBonusTypeNames[] = {
    "None", "Magic", "Fire", "Cold", "Poison", "Disease",
};

void PopulateItemDataFromDefinition(CoOptItemData& d,
                                    const eqlib::ItemDefinition* def,
                                    const eqlib::ItemPtr& item) {
  if (!def) return;

  using namespace eqlib;

  // Spell effect IDs
  d.proc = def->SpellData.GetSpellId(ItemSpellType_Proc);
  d.focus = def->SpellData.GetSpellId(ItemSpellType_Focus);
  d.spell = def->SpellData.GetSpellId(ItemSpellType_Scroll);
  d.worn = def->SpellData.GetSpellId(ItemSpellType_Worn);
  d.focus2 = def->SpellData.GetSpellId(ItemSpellType_Focus2);
  d.familiar = def->SpellData.GetSpellId(ItemSpellType_Familiar);
  d.illusion = def->SpellData.GetSpellId(ItemSpellType_Illusion);
  d.mount = def->SpellData.GetSpellId(ItemSpellType_Mount);

  // Proc rate (from Proc spell data)
  d.procRate = def->SpellData.GetSpellChanceProc(ItemSpellType_Proc);

  // Augment
  d.augType = def->AugType;
  d.augRestrictions = def->AugRestrictions;

  // Stats
  d.ac = def->AC;
  d.hp = def->HP;
  d.mana = def->Mana;
  d.endurance = def->Endurance;
  d.str = static_cast<int32_t>(def->STR);
  d.sta = static_cast<int32_t>(def->STA);
  d.agi = static_cast<int32_t>(def->AGI);
  d.dex = static_cast<int32_t>(def->DEX);
  d._int = static_cast<int32_t>(def->INT);
  d.wis = static_cast<int32_t>(def->WIS);
  d.cha = static_cast<int32_t>(def->CHA);
  d.attack = def->Attack;
  d.accuracy = def->Accuracy;
  d.avoidance = def->Avoidance;
  d.shielding = def->Shielding;
  d.haste = def->Haste;
  d.damage = def->Damage;
  d.itemDelay = static_cast<int32_t>(def->Delay);
  d.dmgBonus = static_cast<int32_t>(def->ElementalDamage);
  if (def->ElementalFlag < 6)
    d.dmgBonusType = kDmgBonusTypeNames[def->ElementalFlag];
  d.spellDamage = def->SpellDamage;
  d.strikeThrough = def->StrikeThrough;
  d.damageShield = def->DamShield;
  d.combatEffects = def->CombatEffects;
  d.dotShielding = def->DoTShielding;
  d.hpRegen = def->HPRegen;
  d.manaRegen = def->ManaRegen;
  d.enduranceRegen = def->EnduranceRegen;
  d.spellShield = def->SpellShield;
  d.damageShieldMitigation = def->DamageShieldMitigation;
  d.stunResist = def->StunResist;
  d.clairvoyance = def->Clairvoyance;
  d.healAmount = def->HealAmount;
  d.heroicSTR = def->HeroicSTR;
  d.heroicSTA = def->HeroicSTA;
  d.heroicAGI = def->HeroicAGI;
  d.heroicDEX = def->HeroicDEX;
  d.heroicINT = def->HeroicINT;
  d.heroicWIS = def->HeroicWIS;
  d.heroicCHA = def->HeroicCHA;
  d.svMagic = static_cast<int32_t>(def->SvMagic);
  d.svFire = static_cast<int32_t>(def->SvFire);
  d.svCold = static_cast<int32_t>(def->SvCold);
  d.svPoison = static_cast<int32_t>(def->SvPoison);
  d.svDisease = static_cast<int32_t>(def->SvDisease);
  d.svCorruption = static_cast<int32_t>(def->SvCorruption);
  d.heroicSvMagic = def->HeroicSvMagic;
  d.heroicSvFire = def->HeroicSvFire;
  d.heroicSvCold = def->HeroicSvCold;
  d.heroicSvDisease = def->HeroicSvDisease;
  d.heroicSvPoison = def->HeroicSvPoison;
  d.heroicSvCorruption = def->HeroicSvCorruption;
  d.range = static_cast<int32_t>(def->Range);
  d.skillModValue = def->SkillModValue;
  d.skillModMax = def->SkillModMax;
  d.baneDMG = def->BaneDMGRaceValue;  // Primary bane value
  if (d.baneDMG == 0) d.baneDMG = def->BaneDMGBodyTypeValue;
  d.luck = def->GetMinLuck();  // Definition has min/max; use min
  d.purity = def->Purity;

  // Descriptive
  d.size = static_cast<int32_t>(def->Size);
  d.sizeCapacity = static_cast<int32_t>(def->SizeCapacity);
  d.container = static_cast<int32_t>(def->Slots);
  d.stackSizeMax = def->StackSize;
  d.norent = def->NoRent;
  d.magic = def->Magic;
  d.prestige = def->Prestige;
  d.tradeskills = def->TradeSkills;
  d.requiredLevel = def->RequiredLevel;
  d.recommendedLevel = def->RecommendedLevel;
  d.instrumentMod = def->InstrumentMod;
  if (def->InstrumentType >= 0 && def->InstrumentType < 256)
    d.instrumentType = std::to_string(def->InstrumentType);

  d.classStr = BuildClassString(def->Classes);
  d.raceStr = BuildRaceString(def->Races);
  d.deityStr = BuildDeityString(def->Deity);

  d.wornSlots = BuildWornSlotsString(def->EquipSlots);

  // Capture-all
  d.stackable = (def->StackSize > 1);
  d.loreEquipped = false;  // ItemBase::IsLoreEquipped returns false
  d.noDestroy = def->NoDestroy;
  d.summoned = def->Summoned;
  d.expendable = def->Expendable;
  d.ornamentationIcon = item ? item->OrnamentationIcon : 0;
  d.ldoNCost = def->LDCost;
  d.ldoNTheme = "";  // LDTheme is int; LDoN theme string would need lookup
  d.maxLuck = def->GetMaxLuck();
  d.minLuck = def->GetMinLuck();
  d.weightReduction = static_cast<int32_t>(def->WeightReduction);
  d.contentSize = static_cast<int32_t>(def->ContainerType);
  d.slotsUsedByItem = 1;
  d.power = item ? item->Power : 0;
  d.maxPower = def->MaxPower;
  d.pctPower = 0.f;
  d.quality = 0;
  d.delay = static_cast<int32_t>(def->Delay);
  d.idFile = def->IDFile;
  d.idFile2 = def->IDFile2;

  // Charges from ItemPtr (instance)
  d.charges = item ? item->Charges : 0;
}

}  // namespace core
}  // namespace cooptui
