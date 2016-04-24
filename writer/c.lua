local function memberString(_type, ch)
	assert(_type.resolved == true)

	local def = ""
	if _type.parent ~= nil then
		def = def .. memberString(_type.parent, ch)
	end

	for i, v in ipairs(_type.members) do
		local memberType = v.type.cType
		if v.type.primitiveType == "system" then
			memberType = v.type.name
		end

		def = def .. ch.tab .. memberType .. " " .. v.name .. ";" .. ch.line
	end

	return def
end

local charsPretty = {
	tab = "\t",
	line = "\n"
}

local chars = {
	tab = "",
	line = ""
}

return {
	write = function(_type, mode)
		local ch = chars
		if mode == "pretty" then
			ch = charsPretty
		end

		local def = "typedef struct {" .. ch.line
		def = def .. memberString(_type, ch)
		def = def .. "} " .. _type.cType .. ";"
		return def
	end
}

