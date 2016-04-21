local tokenTypes = {
	["<"] = { name = "LESS_THAN" },
	[">"] = { name = "GREATER_THAN" },
	["="] = { name = "EQUALS" },
	[","] = { name = "COMMA" },
	["("] = { name = "BRACKET_LEFT" },
	[")"] = { name = "BRACKET_RIGHT" },
	[" "] = false
}

local function tokenize(s)
	local idx = 1
	local nameIdx = 1
	local name = ""
	local tokens = {}

	while idx <= #s do
		local c = s:sub(idx, idx)
		local t = tokenTypes[c]
		if t == nil then
			name = name .. c
		else
			local token
			if #name > 0 then
				table.insert(tokens, { name = "NAME", value = name, pos = nameIdx })
				name = ""
			end

			if t ~= false then
				table.insert(tokens, { name = t.name, value = t.value, pos = idx })
			end

			nameIdx = idx
		end

		idx = idx + 1
	end

	if #name > 0 then
		table.insert(tokens, { name = "NAME", value = name, pos = nameIdx })
	end

	return tokens
end

local function TokenIterator(items)
	return setmetatable({ 
		items = items, 
		idx = 1,
		current = nil
	}, {
		__index = {
			value = function(self)
				if self.idx <= #self.items then
					return self.items[self.idx]
				end

				return { name = "END" }
			end,

			next = function(self)
				self.idx = self.idx + 1
				self.current = self:value()
				return self.current
			end
		}
	});
end

local function logParserError(token)
	error("Unexpected token '" .. token.name .. "' at position " .. token.pos)
end

local function parseTemplates(it)
	local templates = {}
	while it:next().name ~= "GREATER_THAN" and it:value().name ~= "END" do
		local template = {}
		if it:value().name == "NAME" then
			template.name = it:value().value
			if it:next().name ~= "COMMA" and it:value().name ~= "GREATER_THAN" then
				if it:value().name == "NAME" then
					template.type = template.name
					template.name = it:value().value
					it:next()
				end

				if it:value().name == "EQUALS" then
					if it:next().name == "NAME" then
						template.default = tonumber(it:value().value)
						it:next()
					else
						logParserError(token:value())
					end
				elseif it:value().name ~= "GREATER_THAN" and it:value().name ~= "COMMA" then
					logParserError(it:value())
				end
			end

			table.insert(templates, template)
		else
			logParserError(it:value())
		end
	end

	return templates
end

local function parseRoot(it)
	local _type = { templates = {} }
	if it:value().name == "NAME" then
		_type.name = it:value().value

		if it:next().name ~= "END" then
			if it:value().name == "LESS_THAN" then
				_type.templates = parseTemplates(it)
			else 
				logParserError(it:value())
			end
		end
	else
		logParserError(it:value())
	end

	return _type
end

local function parse(s)
	local tokens = tokenize(s)
	local it = TokenIterator(tokens)
	return parseRoot(it)
end

return { parse = parse }