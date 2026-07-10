-- list-api.lua — overview of the EEex API surface in THIS install.
-- For full lists use: EEexRemote.ListGlobals("^EEex_Sprite_") etc.
local groups = {}
for _, entry in ipairs(EEexRemote.ListGlobals("^EEex_")) do
    local prefix = entry.name:match("^(EEex_%a+_)") or "EEex_<misc>"
    groups[prefix] = (groups[prefix] or 0) + 1
end
return groups
