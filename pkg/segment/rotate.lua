-- Package segment/rotate
function aura_env:rotate()
    local segments = self.config.segmentCount
    local angle = self.config.curveAngle
    local direction = -(self.config.direction - 1.5) * 2
    local base = (self.config.rotationOffset + self.config.direction * 180)
    -- Since WeakAuras-5.3.5 the region:Rotate has been renamed to SetRotation
    self.region:SetRotation(base + direction * (angle / (segments - 1)) * (self.cloneId - (segments + 1) / 2))
end
-- Package end

