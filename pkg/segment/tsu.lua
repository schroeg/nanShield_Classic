-- Package segment/tsu
function aura_env:on_tsu(allstates, ...)
    -- self:log('TSU', self.config.segmentCount)
    local now = GetTime()
    local timestamp = self.timestamp or 0
    local active = self.active or 0
    local changed

    for i = #allstates + 1, self.config.segmentCount do
        allstates[i] = {
            changed = true,
            show = false,
            school = "All"
        }
    end

    if now - timestamp > 0.25 / self.config.segmentCount then
        self.timestamp = now
        if active < #allstates and allstates[active + 1].show then
            for i = #allstates, active + 1, -1 do
                if allstates[i].show then
                    allstates[i].show = false
                    allstates[i].changed = true
                    changed = true
                    break
                end
            end
        else
            for i = 1, active do
                if i <= #allstates and not allstates[i].show then
                    allstates[i].show = true
                    allstates[i].changed = true
                    changed = true
                    break
                end
            end
        end
        for i = 1, active do
            if i <= #allstates and allstates[i].show then
                if allstates[i].school ~= self.segmentSchool[i] then
                    self:log('TSUSchool', i, allstates[i].school, self.segmentSchool[i])
                    allstates[i].school = self.segmentSchool[i]
                    allstates[i].changed = true
                    changed = true
                end
            end
        end
    end
    return changed
end
-- Package end

