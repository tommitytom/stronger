local function shallowCloneTable(t)
	local ct = {}
	for k, v in pairs(t) do
		ct[k] = v
	end

	return ct
end

return {
	shallowCloneTable = shallowCloneTable
}