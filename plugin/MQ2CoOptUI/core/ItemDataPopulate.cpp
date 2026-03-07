#include "ItemDataPopulate.h"

#include "eqlib/game/Constants.h"
#include "eqlib/game/EverQuest.h"
#include "eqlib/game/Globals.h"

#include <sstream>
#include <string>

namespace cooptui {
namespace core {

static std::string ItemTypeString(uint8_t itemClass) {
  if (itemClass < eqlib::MAX_ITEMCLASSES && eqlib::szItemClasses[itemClass] != nullptr)
    return eqlib::szItemClasses[itemClass];
  return "";
}

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
  const auto* itemClient = item.get();
  d.accuracy = itemClient ? itemClient->GetAccuracy() : 0;
  d.avoidance = itemClient ? itemClient->GetAvoidance() : 0;
  d.shielding = itemClient ? itemClient->GetShielding() : 0;
  d.haste = def->Haste;
  d.damage = def->Damage;
  d.itemDelay = static_cast<int32_t>(def->Delay);
  d.dmgBonus = static_cast<int32_t>(def->ElementalDamage);
  if (def->ElementalFlag < 6)
    d.dmgBonusType = kDmgBonusTypeNames[def->ElementalFlag];
  d.spellDamage = def->SpellDamage;
  d.strikeThrough = itemClient ? itemClient->GetStrikeThrough() : 0;
  d.damageShield = itemClient ? itemClient->GetDamShield() : 0;
  d.combatEffects = itemClient ? itemClient->GetCombatEffects() : 0;
  d.dotShielding = itemClient ? itemClient->GetDoTShielding() : 0;
  d.hpRegen = def->HPRegen;
  d.manaRegen = def->ManaRegen;
  d.enduranceRegen = def->EnduranceRegen;
  d.spellShield = itemClient ? itemClient->GetSpellShield() : 0;
  d.damageShieldMitigation = itemClient ? itemClient->GetDamageShieldMitigation() : 0;
  d.stunResist = itemClient ? itemClient->GetStunResist() : 0;
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
  d.heroicSvMagic = itemClient ? itemClient->GetHeroicSvMagic() : 0;
  d.heroicSvFire = itemClient ? itemClient->GetHeroicSvFire() : 0;
  d.heroicSvCold = itemClient ? itemClient->GetHeroicSvCold() : 0;
  d.heroicSvDisease = itemClient ? itemClient->GetHeroicSvDisease() : 0;
  d.heroicSvPoison = itemClient ? itemClient->GetHeroicSvPoison() : 0;
  d.heroicSvCorruption = itemClient ? itemClient->GetHeroicSvCorruption() : 0;
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

void PopulateItemData(CoOptItemData& d,
                     const eqlib::ItemPtr& item,
                     const eqlib::ItemDefinition* def,
                     int bag,
                     int slot,
                     const std::string& source) {
  if (!item || !def) return;

  using namespace eqlib;

  d.id = item->GetID();
  d.bag = bag;
  d.slot = slot;
  d.source = source;
  d.name = def->Name;
  d.type = ItemTypeString(def->ItemClass);
  d.value = def->Cost;
  d.stackSize = item->GetItemCount();
  if (d.stackSize < 1) d.stackSize = 1;
  d.totalValue = d.value * d.stackSize;
  d.weight = def->Weight;
  d.icon = def->IconNumber;
  d.tribute = def->Favor;
  d.nodrop = !def->IsDroppable;
  d.notrade = !def->IsDroppable;
  d.lore = (def->Lore != 0);
  d.attuneable = def->Attuneable;
  d.heirloom = def->Heirloom;
  d.collectible = def->Collectible;
  d.quest = def->QuestItem;

  d.augSlots = 0;
  for (int a = 0; a < MAX_AUG_SOCKETS; ++a) {
    if (def->AugData.IsSocketValid(a)) ++d.augSlots;
  }

  d.clicky = 0;
  {
    int sid = def->SpellData.GetSpellId(ItemSpellType_Clicky);
    eItemEffectType eff = def->SpellData.GetSpellEffectType(ItemSpellType_Clicky);
    if (sid > 0 && (eff == ItemEffectClicky || eff == ItemEffectClickyWorn ||
                    eff == ItemEffectClickyRestricted)) {
      d.clicky = sid;
    }
  }

  PopulateItemDataFromDefinition(d, def, item);
}

}  // namespace core
}  // namespace cooptui
