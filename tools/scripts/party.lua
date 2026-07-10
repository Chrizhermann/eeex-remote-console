-- party.lua — names of the active party (portrait order)
local party = {}
for i = 0, 5 do
    local sprite = EEex_Sprite_GetInPortrait(i)
    if sprite then
        party[#party + 1] = { portrait = i, name = sprite:getName() }
    end
end
return party
