-- luacheck --config .luacheckrc .
std = "lua51"
max_line_length = 120

ignore = { "212/self" }

read_globals = {
    "CreateFrame", "UIParent", "GameTooltip", "GameTooltip_Hide", "UISpecialFrames",
    "InCombatLockdown", "RAID_CLASS_COLORS", "SecondsToClock", "AbbreviateNumbers",
    "CopyTable", "wipe", "tinsert", "tremove", "format", "hooksecurefunc",
    "issecretvalue", "scrubsecretvalues", "print", "UnitGUID",
    "C_DamageMeter", "C_AddOns", "C_Timer", "C_Secrets", "Enum", "C_ChallengeMode",
    "GetNumGroupMembers", "IsInRaid", "GetDifficultyInfo", "select", "math",
    "Settings", "CreateSettingsListSectionHeaderInitializer", "SlashCmdList",
}

globals = {
    "RocketMeterDB",
    "RocketMeter_OnCompartmentClick",
    "SLASH_ROCKETMETER1",
    "SLASH_ROCKETMETER2",
}
