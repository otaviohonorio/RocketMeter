-- luacheck --config .luacheckrc .
std = "lua51"
max_line_length = 120

ignore = { "212/self" }

read_globals = {
    "CreateFrame", "UIParent", "Minimap", "GetCursorPosition", "GameTooltip", "GameTooltip_Hide", "UISpecialFrames",
    "InCombatLockdown", "RAID_CLASS_COLORS", "SecondsToClock", "AbbreviateNumbers",
    "CopyTable", "wipe", "tinsert", "tremove", "format", "hooksecurefunc",
    "issecretvalue", "scrubsecretvalues", "print", "UnitGUID",
    "C_DamageMeter", "C_AddOns", "C_Timer", "C_Secrets", "Enum", "C_ChallengeMode",
    "C_Texture", "C_PlayerInfo", "C_MythicPlus", "CreateColor", "Ambiguate", "GetTime",
    "time", "UnitName", "UnitGroupRolesAssigned", "GetWorldElapsedTimers", "GetWorldElapsedTime",
    "UNKNOWN",
    "table", "string",
    "GetNumGroupMembers", "IsInRaid", "GetDifficultyInfo", "select", "math",
    "IsShiftKeyDown", "IsControlKeyDown", "GetLocale", "tonumber", "tostring", "ipairs", "pairs",
    "Settings", "CreateSettingsListSectionHeaderInitializer", "SlashCmdList",
    "StaticPopupDialogs", "StaticPopup_Show", "YES", "NO", "CLASS_ICON_TCOORDS", "unpack",
    "date", "type", "pcall", "securecallfunction", "BreakUpLargeNumbers", "ipairs",
}

globals = {
    "RocketMeterDB",
    "RocketMeterLogDB",
    "RocketMeterCharDB",
    "RocketMeterRunsDB",
    "RocketMeter_OnCompartmentClick",
    "SLASH_ROCKETMETER1",
    "SLASH_ROCKETMETER2",
}
