-- Package value/calc
aura_env.active = 0
aura_env.spellSchool = {}
aura_env.currentAbsorb = {}
aura_env.maxAbsorb = {}
aura_env.totalAbsorb = 0
aura_env.schoolAbsorb = {0, 0, 0, 0, 0, 0, 0, 0, 0}

local function improvedPowerWordShieldMultiplier()
    -- FIXME: GetTalentInfo(1, 5)
    --return 1.15
    
    local _,_,_,_,r = GetTalentInfo(1,5)
    local m = r*0.05
    
    aura_env:log('improvedPowerWordShieldMultiplier', m)
    return 1+m
end

aura_env.talentMultiplier = {
    [   17] = improvedPowerWordShieldMultiplier,
    [  592] = improvedPowerWordShieldMultiplier,
    [  600] = improvedPowerWordShieldMultiplier,
    [ 3747] = improvedPowerWordShieldMultiplier,
    [ 6065] = improvedPowerWordShieldMultiplier,
    [ 6066] = improvedPowerWordShieldMultiplier,
    [10898] = improvedPowerWordShieldMultiplier,
    [10899] = improvedPowerWordShieldMultiplier,
    [10900] = improvedPowerWordShieldMultiplier,
    [10901] = improvedPowerWordShieldMultiplier,
    [25217] = improvedPowerWordShieldMultiplier,
    [25218] = improvedPowerWordShieldMultiplier,
}

function aura_env:CalculateAbsorbValue(spellName, spellId, absorbInfo)
    -- FIXME: if caster != player
    local value
    local keys = self.absorbDbKeys
    local bonusHealing = GetSpellBonusHealing()
    local level = UnitLevel("player")
    local base = absorbInfo[keys.basePoints]
    local perLevel = absorbInfo[keys.pointsPerLevel]
    local baseLevel = absorbInfo[keys.baseLevel]
    local maxLevel = absorbInfo[keys.maxLevel]
    local spellLevel = absorbInfo[keys.spellLevel]
    local bonusMult = absorbInfo[keys.healingMultiplier]
    local baseMultFn = self.talentMultiplier[spellId]
    local levelPenalty = min(1, 1 - (20 - spellLevel) * .03)
    local levels = max(0, min(level, maxLevel) - baseLevel)
    local baseMult = baseMultFn and baseMultFn() or 1

    value = (
        baseMult * (base + levels * perLevel) +
        bonusHealing * bonusMult * levelPenalty
    )

    self:log('CalculateAbsorbValue', spellName,
        value, base, perLevel, levels, baseMult,
        bonusHealing, bonusMult, levelPenalty)

    return value
end

function aura_env:GetBuffId(spellName)
    local spellId
    for i = 1, 255 do
        local auraName, _, _, _, _, _, _, _, _, spell_id = UnitBuff("player", i)
        spellId = spell_id
        if auraName == spellName then
            break
        elseif not auraName then
            spellId = nil
            break
        end
    end
    return spellId
end

function aura_env:ApplyAura(spellName)
    local school = self.spellSchool[spellName]
    self:log('ApplyAura', spellName, school)

    if 0 ~= school then
        local spellId = self:GetBuffId(spellName)
        local absorbInfo = self.absorbDb[spellId]

        self:log('ApplyAuraAbsorbOrNew', spellId)

        if absorbInfo then
            local value = self:CalculateAbsorbValue(
            spellName, spellId, absorbInfo)

            self:log('ApplyAuraSchool', school)
            if nil == school then
                school = absorbInfo[self.absorbDbKeys.school]
                self.spellSchool[spellName] = school
            end

            if self.maxAbsorb[spellName] then
                self:log('ApplyAuraUpdateCurrent', spellName, value)
                self.currentAbsorb[spellName] = value
            else
                self:log('ApplyAuraSetCurrent', spellName, value)
                self.active = self.active + 1

                -- If damage event happened before aura was removed
                local prevValue = self.currentAbsorb[spellName]
                self.currentAbsorb[spellName] = value + (prevValue or 0)
            end

            self:log('ApplyAuraSetMax', spellName, value)
            self.maxAbsorb[spellName] = value
            self:UpdateValues()
        end
    end
end

function aura_env:RemoveAura(spellName)
    self:log('RemoveAura', spellName)
    if self.currentAbsorb[spellName] then
        self.currentAbsorb[spellName] = nil
        self.active = self.active - 1
        self:log('RemoveAuraRemaining', self.active)
        if self.active < 1 then
            self.active = 0
            wipe(self.maxAbsorb)
        end
        self:UpdateValues()
    end
end

function aura_env:ApplyDamage(spellName, value)
    self:log('ApplyDamage', spellName, value)
    local newValue = (self.currentAbsorb[spellName] or 0) - value
    if self.maxAbsorb[spellName] then
        self.currentAbsorb[spellName] = max(0, newValue)
        self:UpdateValues()
    else
        self.currentAbsorb[spellName] = newValue
    end
end

function aura_env:ResetValues()
    self:log('ResetValues')
    local spellName
    wipe(self.currentAbsorb)
    wipe(self.maxAbsorb)
    self.active = 0
    for i = 1, 255 do
        spellName = UnitBuff("player", i)
        if not spellName then
            break
        end
        self:ApplyAura(spellName)
    end
    self:UpdateValues()
end

function aura_env:UpdateValues()
    self:log('UpdateValues')
    local values = self.schoolAbsorb
    local keys = self.schoolIdx
    local spellSchool = self.spellSchool
    local current = self.currentAbsorb
    local total = 0
    local key, value, school

    for i = 1, #values do
        values[i] = 0
    end

    for spell, maxValue in pairs(self.maxAbsorb) do
        school = spellSchool[spell]
        key = keys[school]
        total = total + maxValue
        value = (current[spell] or 0)
        values[key] = values[key] + value
        self:log('UpdateValues', spell, school, key, maxValue, value)
    end

    self.totalAbsorb = total
    WeakAuras.ScanEvents("WA_NAN_SHIELD", total, unpack(values))
    self:log('UpdateValues', total > 0)
end
-- Package end

-- Package value/cleu
function aura_env:on_cleu(triggerEvent, ...)
    local event, spellName, value
    local casterGUID = select(8, ...)

    if triggerEvent == 'OPTIONS' then
        self:log(triggerEvent, ...)
    elseif self.playerGUID == casterGUID then
        self:log(triggerEvent, ...)
        event = select(2, ...)
        if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
            spellName = select(13, ...)
            self:ApplyAura(spellName)
        elseif event == "SPELL_AURA_REMOVED" then
            spellName = select(13, ...)
            self:RemoveAura(spellName)
        elseif event == "SPELL_ABSORBED" then
            if select(20, ...) then
                spellName = select(20, ...)
                value = select(22, ...) or 0
            else
                spellName = select(17, ...)
                value = select(19, ...) or 0
            end
            self:ApplyDamage(spellName, value)
        end
    elseif not casterGUID then
        self:log(triggerEvent, ...)
        self:ResetValues()
    end
end
-- Package end

-- Package value/init
aura_env.playerGUID = UnitGUID("player")
-- Package end

-- Package common/lowabsorb
function aura_env:LowestAbsorb(totalAbsorb, all, physical, magic, ...)
    self:log('LowestAbsorb', all, physical, magic, ...)
    local minValue
    local minIdx
    local value

    for i = 1, select('#', ...) do
        value = select(i, ...)
        if value > 0 and value <= (minValue or value) then
            minIdx = i + 3
            minValue = value
        end
    end

    if minIdx then
        minValue = minValue + magic
    elseif magic > 0 then
        minValue = magic
        minIdx = 3
    end

    if physical > 0 and physical <= (minValue or physical) then
        minValue = physical
        minIdx = 2
    end

    if minIdx then
        minValue = minValue + all
    else
        minValue = all
        minIdx = 1
    end

    self:log('LowestAbsorbResult', minValue, totalAbsorb, minIdx)
    return minValue, totalAbsorb, minIdx
end
-- Package end

-- Package common/logging
aura_env.logPalette = {
    "ff6e7dda",
    "ff21dfb9",
    "ffe3f57a",
    "ffed705a",
    "fff8a3e6",
}

function aura_env:log(...)
    if self.config and self.config.debugEnabled then
        local palette = self.logPalette
        local args = {
            self.cloneId and
            format("[%s:%s]", self.id, self.cloneId) or
            format("[%s]", self.id),
            ...
        }
        for i = 1, #args do
            args[i] = format(
                "|c%s%s|r",
                palette[1 + (i - 1) % #palette],
                tostring(args[i]))
        end
        print(unpack(args))
    end
end
-- Package end

-- Package common/schools
aura_env.schools = {
    "All",
    "Physical",
    "Magic",
    "Holy",
    "Fire",
    "Nature",
    "Frost",
    "Shadow",
    "Arcane",
}
aura_env.schoolIds = { 127, 1, 126, 2, 4, 8, 16, 32, 64 }
aura_env.schoolIdx = {}
for idx, id in ipairs(aura_env.schoolIds) do
    aura_env.schoolIdx[id] = idx
end
-- Package end

-- Generated by nan-wa-utils
aura_env.absorbDbKeys = {
    ["school"] = 1,
    ["basePoints"] = 2,
    ["pointsPerLevel"] = 3,
    ["baseLevel"] = 4,
    ["maxLevel"] = 5,
    ["spellLevel"] = 6,
    ["healingMultiplier"] = 7,
}
aura_env.absorbDb = {
    [  7848] = {   1,    49,    0,  0,  0,  0, 0  }, -- Absorption
    [ 25750] = {   1,   247,    0, 20,  0,  0, 0  }, -- Damage Absorb
    [ 25747] = {   1,   309,    0, 20,  0,  0, 0  }, -- Damage Absorb
    [ 25746] = {   1,   391,    0, 20,  0,  0, 0  }, -- Damage Absorb
    [ 23991] = {   1,   494,    0, 20,  0,  0, 0  }, -- Damage Absorb
    [ 42137] = {   1,   399,    0,  0,  0,  0, 0  }, -- Greater Rune of Warding
    [ 11657] = {   1,    54,    0, 48,  0, 48, 0  }, -- Jang'thraze
    [  7447] = {   1,    24,    0,  0,  0,  0, 0  }, -- Lesser Absorption
    [ 42134] = {   1,   199,    0,  0,  0,  0, 0  }, -- Lesser Rune of Warding
    [  8373] = {   1,   999,    0,  0,  0,  0, 0  }, -- Mana Shield (PT)
    [  7423] = {   1,     9,    0,  0,  0,  0, 0  }, -- Minor Absorption
    [  3288] = {   1,    19,    0, 21,  0, 21, 0  }, -- Moss Hide
    [ 21956] = {   1,   349,    0, 20,  0,  0, 0  }, -- Physical Protection
    [ 34206] = {   1,  1949,    0, 40,  0,  0, 0  }, -- Physical Protection
    [ 37414] = {   1,   499,    0,  0,  0,  0, 0  }, -- Shield Block
    [ 37729] = {   1,  1079,    0, 20,  0,  0, 0  }, -- Unholy Armor
    [ 37416] = {   1,   499,    0,  0,  0,  0, 0  }, -- Weapon Deflection
    [ 28538] = {   2,  2799,    0, 40,  0,  0, 0  }, -- Holy Protection
    [  7245] = {   2,   299,    0, 20,  0,  0, 0  }, -- Holy Protection (Rank 1)
    [ 16892] = {   2,   299,    0, 20,  0,  0, 0  }, -- Holy Protection (Rank 1)
    [  7246] = {   2,   524,    0, 25,  0,  0, 0  }, -- Holy Protection (Rank 2)
    [  7247] = {   2,   674,    0, 30,  0,  0, 0  }, -- Holy Protection (Rank 3)
    [  7248] = {   2,   974,    0, 35,  0,  0, 0  }, -- Holy Protection (Rank 4)
    [  7249] = {   2,  1349,    0, 40,  0,  0, 0  }, -- Holy Protection (Rank 5)
    [ 17545] = {   2,  1949,    0, 40,  0,  0, 0  }, -- Holy Protection (Rank 6)
    [ 27536] = {   2,   299,    0, 60,  0,  0, 0  }, -- Holy Resistance
    [ 30997] = {   4,   899,    0, 40,  0,  0, 0  }, -- Fire Absorption
    [ 29432] = {   4,  1499,    0, 35,  0,  0, 0  }, -- Fire Protection
    [ 17543] = {   4,  1949,    0, 35,  0,  0, 0  }, -- Fire Protection
    [ 18942] = {   4,  1949,    0, 35,  0,  0, 0  }, -- Fire Protection
    [ 28511] = {   4,  2799,    0, 35,  0,  0, 0  }, -- Fire Protection
    [  7230] = {   4,   299,    0, 20,  0,  0, 0  }, -- Fire Protection (Rank 1)
    [ 12561] = {   4,   299,    0, 20,  0,  0, 0  }, -- Fire Protection (Rank 1)
    [  7231] = {   4,   524,    0, 25,  0,  0, 0  }, -- Fire Protection (Rank 2)
    [  7232] = {   4,   674,    0, 30,  0,  0, 0  }, -- Fire Protection (Rank 3)
    [  7233] = {   4,   974,    0, 35,  0,  0, 0  }, -- Fire Protection (Rank 4)
    [ 16894] = {   4,   974,    0, 35,  0,  0, 0  }, -- Fire Protection (Rank 4)
    [  7234] = {   4,  1349,    0, 35,  0,  0, 0  }, -- Fire Protection (Rank 5)
    [ 27533] = {   4,   299,    0, 60,  0,  0, 0  }, -- Fire Resistance
    [  4057] = {   4,   499,    0,  0,  0, 25, 0  }, -- Fire Resistance
    [ 30999] = {   8,   899,    0, 40,  0,  0, 0  }, -- Nature Absorption
    [ 17546] = {   8,  1949,    0, 40,  0,  0, 0  }, -- Nature Protection
    [ 28513] = {   8,  2799,    0, 40,  0,  0, 0  }, -- Nature Protection
    [  7250] = {   8,   299,    0, 20,  0,  0, 0  }, -- Nature Protection (Rank 1)
    [  7251] = {   8,   524,    0, 25,  0,  0, 0  }, -- Nature Protection (Rank 2)
    [  7252] = {   8,   674,    0, 30,  0,  0, 0  }, -- Nature Protection (Rank 3)
    [  7253] = {   8,   974,    0, 35,  0,  0, 0  }, -- Nature Protection (Rank 4)
    [  7254] = {   8,  1349,    0, 40,  0,  0, 0  }, -- Nature Protection (Rank 5)
    [ 16893] = {   8,  1349,    0, 40,  0,  0, 0  }, -- Nature Protection (Rank 5)
    [ 27538] = {   8,   299,    0, 60,  0,  0, 0  }, -- Nature Resistance
    [ 30994] = {  16,   899,    0, 40,  0,  0, 0  }, -- Frost Absorption
    [ 17544] = {  16,  1949,    0, 40,  0,  0, 0  }, -- Frost Protection
    [ 28512] = {  16,  2799,    0, 40,  0,  0, 0  }, -- Frost Protection
    [  7240] = {  16,   299,    0, 20,  0,  0, 0  }, -- Frost Protection (Rank 1)
    [  7236] = {  16,   524,    0, 25,  0,  0, 0  }, -- Frost Protection (Rank 2)
    [  7238] = {  16,   674,    0, 30,  0,  0, 0  }, -- Frost Protection (Rank 3)
    [  7237] = {  16,   974,    0, 35,  0,  0, 0  }, -- Frost Protection (Rank 4)
    [  7239] = {  16,  1349,    0, 40,  0,  0, 0  }, -- Frost Protection (Rank 5)
    [ 16895] = {  16,  1349,    0, 40,  0,  0, 0  }, -- Frost Protection (Rank 5)
    [ 27534] = {  16,   299,    0, 60,  0,  0, 0  }, -- Frost Resistance
    [  4077] = {  16,   599,    0,  0,  0, 25, 0  }, -- Frost Resistance
    [ 31000] = {  32,   899,    0, 40,  0,  0, 0  }, -- Shadow Absorption
    [ 33482] = {  32,  2294,    0, 60,  0, 60, 0  }, -- Shadow Defense
    [ 17548] = {  32,  1949,    0, 40,  0,  0, 0  }, -- Shadow Protection
    [ 28537] = {  32,  2799,    0, 40,  0,  0, 0  }, -- Shadow Protection
    [  7235] = {  32,   299,    0, 20,  0,  0, 0  }, -- Shadow Protection (Rank 1)
    [  7241] = {  32,   524,    0, 25,  0,  0, 0  }, -- Shadow Protection (Rank 2)
    [  7242] = {  32,   674,    0, 30,  0,  0, 0  }, -- Shadow Protection (Rank 3)
    [ 16891] = {  32,   674,    0, 30,  0,  0, 0  }, -- Shadow Protection (Rank 3)
    [  7243] = {  32,   974,    0, 35,  0,  0, 0  }, -- Shadow Protection (Rank 4)
    [  7244] = {  32,  1349,    0, 40,  0,  0, 0  }, -- Shadow Protection (Rank 5)
    [ 27535] = {  32,   299,    0, 60,  0,  0, 0  }, -- Shadow Resistance
    [  6229] = {  32,   289,    0, 32, 41, 32, 0  }, -- Shadow Ward (Rank 1)
    [ 11739] = {  32,   469,    0, 42, 51, 42, 0  }, -- Shadow Ward (Rank 2)
    [ 11740] = {  32,   674,    0, 52, 59, 52, 0  }, -- Shadow Ward (Rank 3)
    [ 28610] = {  32,   874,    0, 60, 69, 60, 0  }, -- Shadow Ward (Rank 4)
    [ 40322] = {  32, 11399,    0, 70,  0, 70, 0  }, -- Spirit Shield
    [ 31002] = {  64,   899,    0, 40,  0,  0, 0  }, -- Arcane Absorption
    [ 17549] = {  64,  1949,    0, 35,  0,  0, 0  }, -- Arcane Protection
    [ 28536] = {  64,  2799,    0, 35,  0,  0, 0  }, -- Arcane Protection
    [ 27540] = {  64,   299,    0, 60,  0,  0, 0  }, -- Arcane Resistance
    [ 31662] = { 126,199999,    0, 70,  0, 70, 0  }, -- Anti-Magic Shell
    [ 10618] = { 126,   599,    0, 30,  0,  0, 0  }, -- Elemental Protection
    [ 20620] = { 127, 29999,    0, 20,  0, 20, 0  }, -- Aegis of Ragnaros
    [ 36481] = { 127, 99999,    0,  0,  0,  0, 0  }, -- Arcane Barrier
    [ 39228] = { 127,  1149,    0,  0,  0,  1, 0  }, -- Argussian Compass
    [ 23506] = { 127,   749,    0, 20,  0,  0, 0  }, -- Aura of Protection
    [ 41341] = { 127,     0,    0,  0,  0,  0, 0  }, -- Balance of Power
    [ 11445] = { 127,   277,    0, 35,  0, 35, 0  }, -- Bone Armor
    [ 38882] = { 127,   878,    0, 60,  0, 60, 0  }, -- Bone Armor
    [ 16431] = { 127,  1387,    0, 55,  0, 55, 0  }, -- Bone Armor
    [ 27688] = { 127,  2499,    0,  0,  0,  0, 0  }, -- Bone Shield
    [ 33896] = { 127,   999,    0, 20,  0, 20, 0  }, -- Desperate Defense
    [ 28527] = { 127,   749,    0, 20,  0,  0, 0  }, -- Fel Blossom
    [ 33147] = { 127, 24999,    0,  0,  0,  0, 0  }, -- Greater Power Word: Shield
    [ 29701] = { 127,  3999,    0,  0,  0,  0, 0  }, -- Greater Shielding
    [ 29719] = { 127,  3999,    0,  0,  0,  0, 0  }, -- Greater Shielding
    [ 32278] = { 127,   399,    0,  0,  0,  0, 0  }, -- Greater Warding Shield
    [ 13234] = { 127,   499,    0,  0,  0,  0, 0  }, -- Harm Prevention Belt
    [  9800] = { 127,   174,    0, 52,  0,  0, 0  }, -- Holy Shield
    [ 33245] = { 127,   649,    0, 60,  0, 60, 0.1}, -- Ice Barrier
    [ 29674] = { 127,   999,    0,  0,  0,  0, 0  }, -- Lesser Shielding
    [ 29503] = { 127,   199,    0,  0,  0,  0, 0  }, -- Lesser Warding Shield
    [ 17252] = { 127,   499,    0,  0,  0,  0, 0  }, -- Mark of the Dragon Lord
    [ 30456] = { 127,  3999,    0,  0,  0,  0, 0  }, -- Nigh-Invulnerability
    [ 11835] = { 127,   115,    0, 20,  0, 20, 0.1}, -- Power Word: Shield
    [ 11974] = { 127,   136, 6.85, 20,  0, 20, 0.1}, -- Power Word: Shield
    [ 22187] = { 127,   205, 10.2, 20,  0, 20, 0.1}, -- Power Word: Shield
    [ 17139] = { 127,   273, 13.7, 20,  0, 20, 0.1}, -- Power Word: Shield
    [ 32595] = { 127,   410, 13.7, 20,  0, 20, 0.1}, -- Power Word: Shield
    [ 35944] = { 127,   547, 18.3, 20,  0, 20, 0.1}, -- Power Word: Shield
    [ 11647] = { 127,   780,  3.9, 54, 59,  1, 0.1}, -- Power Word: Shield
    [ 36052] = { 127,   821, 27.4, 20,  0, 20, 0.1}, -- Power Word: Shield
    [ 29408] = { 127,  2499,    0, 70,  0, 70, 0.1}, -- Power Word: Shield
    [ 20697] = { 127,  4999,    0,  0,  0,  0, 0.1}, -- Power Word: Shield
    [ 41373] = { 127,  4999,    0, 70,  0, 70, 0.1}, -- Power Word: Shield
    [ 41475] = { 127, 24999,    0, 70,  0, 70, 0  }, -- Reflective Shield
    [ 33810] = { 127,   136, 6.85, 20,  0, 20, 0  }, -- Rock Shell
    [ 41431] = { 127, 49999,    0,  0,  0,  0, 0  }, -- Rune Shield
    [ 31976] = { 127,   136, 6.85, 20,  0, 20, 0  }, -- Shadow Shield
    [ 12040] = { 127,   199,   10, 20,  0, 20, 0  }, -- Shadow Shield
    [ 22417] = { 127,   399,   20, 20,  0, 20, 0  }, -- Shadow Shield
    [ 31771] = { 127,   439,    0, 20,  0,  0, 0  }, -- Shell of Deterrence
    [ 27759] = { 127,    49,    0,  0,  0,  0, 0  }, -- Shield Generator
    [ 46165] = { 127,  9999,    0,  0,  0,  0, 0  }, -- Shock Barrier
    [ 36815] = { 127, 79999,    0,  0,  0,  0, 0  }, -- Shock Barrier
    [ 35618] = { 127,    19,    0,  0,  0,  1, 0  }, -- Spirit of Redemption
    [ 29506] = { 127,   899,    0, 20,  0,  0, 0  }, -- The Burrower's Shell
    [  1234] = { 127,     0,    0,  0,  0,  0, 0  }, -- Tony's God Mode
    [ 10368] = { 127,   199,  2.3, 30, 35, 30, 0  }, -- Uther's Light Effect (Rank 1)
    [ 37515] = { 127,   199,    0,  0,  0,  1, 0  }, -- [Warrior] Blade Turning
    [ 31228] = { 127,    32,    0,  0,  0,  1, 0  }, -- [Rogue] Cheat Death (Rank 1)
    [ 31229] = { 127,    65,    0,  0,  0,  1, 0  }, -- [Rogue] Cheat Death (Rank 2)
    [ 31230] = { 127,    99,    0,  0,  0,  1, 0  }, -- [Rogue] Cheat Death (Rank 3)
    [ 40251] = { 127,    99,    0, 70,  0, 70, 0  }, -- [Rogue] Shadow of Death
    [ 32504] = {  -2,  1318,  4.7, 65, 69, 65, 0  }, -- [Priest] Power Word: Warding (Rank 11)
    [ 28810] = { 127,   499,    0,  0,  0,  1, 0  }, -- [Priest] Armor of Faith
    [ 27779] = { 127,   349,    0,  0,  0,  0, 0  }, -- [Priest] Divine Protection
    [ 44175] = { 127,  1454,    0, 60,  0, 60, 0.1}, -- [Priest] Power Word: Shield
    [ 44291] = { 127,  1454,    0, 60,  0, 60, 0.1}, -- [Priest] Power Word: Shield
    [ 46193] = { 127,  2909,    0, 60,  0, 60, 0.1}, -- [Priest] Power Word: Shield
    [    17] = { 127,    43,  0.8,  6, 11,  6, 0.1}, -- [Priest] Power Word: Shield (Rank 1)
    [ 10901] = { 127,   941,  4.3, 60, 65, 60, 0.1}, -- [Priest] Power Word: Shield (Rank 10)
    [ 27607] = { 127,   941,  4.3, 60, 65, 60, 0.1}, -- [Priest] Power Word: Shield (Rank 10)
    [ 25217] = { 127,  1124,  4.7, 65, 69, 65, 0.1}, -- [Priest] Power Word: Shield (Rank 11)
    [ 25218] = { 127,  1264,  5.1, 70, 74, 70, 0.1}, -- [Priest] Power Word: Shield (Rank 12)
    [   592] = { 127,    87,  1.2, 12, 17, 12, 0.1}, -- [Priest] Power Word: Shield (Rank 2)
    [   600] = { 127,   157,  1.6, 18, 23, 18, 0.1}, -- [Priest] Power Word: Shield (Rank 3)
    [  3747] = { 127,   233,    2, 24, 29, 24, 0.1}, -- [Priest] Power Word: Shield (Rank 4)
    [  6065] = { 127,   300,  2.3, 30, 35, 30, 0.1}, -- [Priest] Power Word: Shield (Rank 5)
    [  6066] = { 127,   380,  2.6, 36, 41, 36, 0.1}, -- [Priest] Power Word: Shield (Rank 6)
    [ 10898] = { 127,   483,    3, 42, 47, 42, 0.1}, -- [Priest] Power Word: Shield (Rank 7)
    [ 10899] = { 127,   604,  3.4, 48, 53, 48, 0.1}, -- [Priest] Power Word: Shield (Rank 8)
    [ 10900] = { 127,   762,  3.9, 54, 59, 54, 0.1}, -- [Priest] Power Word: Shield (Rank 9)
    [ 20706] = { 127,   499,    3, 42, 47, 42, 0  }, -- [Priest] Power Word: Shield 500 (Rank 7)
    [ 17740] = {   1,   119,    6, 20,  0, 20, 0  }, -- [Mage] Mana Shield
    [ 30973] = {   1,   119,    6, 20,  0, 20, 0  }, -- [Mage] Mana Shield
    [ 17741] = {   1,   239,   12, 20,  0, 20, 0  }, -- [Mage] Mana Shield
    [ 46151] = {   1,   719,   36, 20,  0, 20, 0  }, -- [Mage] Mana Shield
    [ 15041] = {   4,   119,    0, 20,  0, 20, 0  }, -- [Mage] Fire Ward
    [ 37844] = {   4,   159,    8, 20,  0, 20, 0  }, -- [Mage] Fire Ward
    [   543] = {   4,   164,    0, 20, 29, 20, 0  }, -- [Mage] Fire Ward (Rank 1)
    [  8457] = {   4,   289,    0, 30, 39, 30, 0  }, -- [Mage] Fire Ward (Rank 2)
    [  8458] = {   4,   469,    0, 40, 49, 40, 0  }, -- [Mage] Fire Ward (Rank 3)
    [ 10223] = {   4,   674,    0, 50, 59, 50, 0  }, -- [Mage] Fire Ward (Rank 4)
    [ 10225] = {   4,   874,    0, 60, 68, 60, 0  }, -- [Mage] Fire Ward (Rank 5)
    [ 27128] = {   4,  1124,    0, 69, 78, 69, 0  }, -- [Mage] Fire Ward (Rank 6)
    [ 25641] = {   4,   499,   10, 60,  0, 60, 0  }, -- [Mage] Frost Ward
    [ 15044] = {  16,   119,    0, 20,  0, 20, 0  }, -- [Mage] Frost Ward
    [  6143] = {  16,   164,    0, 22, 31, 22, 0  }, -- [Mage] Frost Ward (Rank 1)
    [  8461] = {  16,   289,    0, 32, 41, 32, 0  }, -- [Mage] Frost Ward (Rank 2)
    [  8462] = {  16,   469,    0, 42, 51, 42, 0  }, -- [Mage] Frost Ward (Rank 3)
    [ 10177] = {  16,   674,    0, 52, 59, 52, 0  }, -- [Mage] Frost Ward (Rank 4)
    [ 28609] = {  16,   874,    0, 60, 69, 60, 0  }, -- [Mage] Frost Ward (Rank 5)
    [ 32796] = {  16,  1124,    0, 70, 78, 70, 0  }, -- [Mage] Frost Ward (Rank 6)
    [ 11426] = { 127,   437,  2.8, 40, 46, 40, 0.1}, -- [Mage] Ice Barrier (Rank 1)
    [ 13031] = { 127,   548,  3.2, 46, 52, 46, 0.1}, -- [Mage] Ice Barrier (Rank 2)
    [ 13032] = { 127,   677,  3.6, 52, 58, 52, 0.1}, -- [Mage] Ice Barrier (Rank 3)
    [ 13033] = { 127,   817,    4, 58, 64, 58, 0.1}, -- [Mage] Ice Barrier (Rank 4)
    [ 27134] = { 127,   924,  4.4, 64, 70, 64, 0.1}, -- [Mage] Ice Barrier (Rank 5)
    [ 33405] = { 127,  1074,  4.8, 70, 76, 70, 0.1}, -- [Mage] Ice Barrier (Rank 6)
    [ 35064] = { 127,  7999,    0, 20,  0, 20, 0  }, -- [Mage] Mana Shield
    [ 38151] = { 127,  9999,    0, 20,  0, 20, 0  }, -- [Mage] Mana Shield
    [ 29880] = { 127, 60000,    6, 20,  0, 20, 0  }, -- [Mage] Mana Shield
    [  1463] = { 127,   119,    0, 20, 27, 20, 0  }, -- [Mage] Mana Shield (Rank 1)
    [  8494] = { 127,   209,    0, 28, 35, 28, 0  }, -- [Mage] Mana Shield (Rank 2)
    [  8495] = { 127,   299,    0, 36, 43, 36, 0  }, -- [Mage] Mana Shield (Rank 3)
    [ 10191] = { 127,   389,    0, 44, 51, 44, 0  }, -- [Mage] Mana Shield (Rank 4)
    [ 10192] = { 127,   479,    0, 52, 59, 52, 0  }, -- [Mage] Mana Shield (Rank 5)
    [ 10193] = { 127,   569,    0, 60, 67, 60, 0  }, -- [Mage] Mana Shield (Rank 6)
    [ 27131] = { 127,   714,    0, 68, 75, 68, 0  }, -- [Mage] Mana Shield (Rank 7)
    [ 26470] = { 127,     0,    0,  0,  0,  1, 0  }, -- [Mage] Persistent Shield
    [  7812] = { 127,   304,  2.3, 16, 22, 16, 0  }, -- [Warlock] Sacrifice (Rank 1)
    [ 19438] = { 127,   509,  3.1, 24, 30, 24, 0  }, -- [Warlock] Sacrifice (Rank 2)
    [ 19440] = { 127,   769,  3.9, 32, 38, 32, 0  }, -- [Warlock] Sacrifice (Rank 3)
    [ 19441] = { 127,  1094,  4.7, 40, 46, 40, 0  }, -- [Warlock] Sacrifice (Rank 4)
    [ 19442] = { 127,  1469,  5.5, 48, 54, 48, 0  }, -- [Warlock] Sacrifice (Rank 5)
    [ 19443] = { 127,  1904,  6.4, 56, 62, 56, 0  }, -- [Warlock] Sacrifice (Rank 6)
    [ 27273] = { 127,  2854,  7.5, 64, 70, 64, 0  }, -- [Warlock] Sacrifice (Rank 7)
}
