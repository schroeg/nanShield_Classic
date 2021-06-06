function(...)
    local theTime = GetTime()
    if not aura_env.last or aura_env.last < theTime - 0.05 then
        aura_env.last = theTime
        
        return aura_env:on_tsu(...)
    end
end
