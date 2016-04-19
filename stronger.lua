local factory = require "factory.default"

local settings = {
	exposed = false,
	cPrefix = ""
}

local initialized = false
local systemTypes = {}
local classTypes = {}
local templateParamTypes = {}
local intialize

local function cloneTable(t)
	local ct = {}
	for k, v in pairs(t) do
		ct[k] = v
	end

	return ct
end

local function createSystemType(name, size, ctype)
	local _type = {
		name = name,
		size = size,
		ctype = ctype,
		baseType = "system"
	}

	setmetatable(_type, {
		__call = function(t, default)
			local ct = cloneTable(t)
			ct.default = default
			return ct
		end
	})

	systemTypes[name] = _type
	if settings.exposed == true then
		_G[name] = _type
	end

	factory.registerSystemType(_type)
end

local function validateParent(p)
	if p == nil then 
		error("Parent class undefined") 
	end

	if p.complete == false then
		error("Unable to inherit from an incomplete class type")
	end
end

local function validateTemplate(t)
end

local function validateTemplateArg(arg)
	if arg == nil then
		error("Template argument undefined")
	elseif type(arg) == "string" then
		-- TODO: Make sure this isn't a reserved word
	elseif type(arg) == "number" then
		error("Number parameters are not supported yet")
	elseif type(arg) == "table" then
		if arg.baseType == nil then
			error("Template argument must be a valid type")
		end
	else
		error("Template parameters of type '" .. type(arg) .. "' are not supported")
	end
end

local function updateTypeSize(t)
	t.size = 0
	for k,v in pairs(t.members) do
		t.size = t.size + v.size
	end
end

local function generateCName(name)
	return settings.cPrefix .. name:gsub("<", "_"):gsub(",", "_"):gsub(">", ""):gsub(" ", "")
end

local function createTypeTable(name, super)
	return {  
		name = name,
		cName = generateCName(name),
		parent = super,
		members = {},
		methods = {},
		templates = {},
		templateDefaults = 0,
		complete = true,
		size = 0,
		baseType = "class"
	}
end

local function cloneType(t)
	local ct = cloneTable(t)
	ct.members = cloneTable(t.members)
	ct.templates = cloneTable(t.templates)
	ct.base = t
	return ct
end

local function createTemplateParamType(name)
	local t = templateParamTypes[name]
	if t == nil then
		t = {  
			name = name,
			complete = false,
			size = 0,
			baseType = "templateParam"
		}

		templateParamTypes[name] = t
	end

	return t
end

local function createTemplate(original, modifier)
	assert(original.placeholder == nil)
	assert(original.type == nil)
	assert(original.value == nil)

	local t = {
		name = original.name,
		default = original.default,
		type = {}
	}

	if type(modifier) == "string" then
		t.placeholder = modifier
	elseif type(modifier) == "number" then
		t.value = modifier
		error("Number parameters are not supported yet")
	elseif type(modifier) == "table" then
		t.type = modifier
	end

	return t
end

local function bundleTemplateArgs(args, templates)
	local templateArgs = {}
	for i, arg in ipairs(args) do
		validateTemplateArg(arg)
		table.insert(templateArgs, arg)
	end

	for i = #args + 1, #templates do
		print(#args, #templates)
		assert(templates[i].default ~= nil)
		table.insert(templateArgs, templates[i].default)
	end

	return templateArgs
end

-- Resolve member variables that are templated types
local function resolveTemplateMember(templateType, lookup)
	local templateParams = {}
	for i, template in ipairs(templateType.templates) do
		if template.type ~= nil then
			table.insert(templateParams, template.type)
		elseif template.placeholder ~= nil then
			assert(lookup[template.placeholder] ~= nil, "Template argument '" .. template.placeholder .. "' could not be found in the lookup")
			table.insert(templateParams, lookup[template.placeholder])
		else
			error("Template contains no type or placeholder")
		end
	end

	return templateType.base(unpack(templateParams))
end

local function resolveTemplateArgs(t, ...)
	if t.complete == false then
		local args = {...}
		if #args >= (#t.templates - t.templateDefaults) and #args <= #t.templates then
			local complete = true
			local templateArgs = bundleTemplateArgs(args, t.templates)
			local ct = cloneType(t)
			
			ct.name = ct.name .. "<"

			local lookup = {}
			for i, arg in ipairs(templateArgs) do
				local template = createTemplate(ct.templates[i], arg)
				local name
				if template.placeholder ~= nil then
					name = template.placeholder
					complete = false
				elseif template.type ~= nil then
					name = template.type.name
				end

				ct.templates[i] = template
				lookup[template.name] = template.type
				ct.name = ct.name .. (i > 1 and ", " or "") .. name
			end

			ct.name = ct.name .. ">"

			print(ct.name)

			for k, v in pairs(ct.members) do
				if type(v) == "string" then
					assert(lookup[v] ~= nil, "Template argument '" .. v .. "' could not be found in the lookup")
					ct.members[k] = lookup[v]
				elseif type(v) == "table" and v.complete == false then
					ct.members[k] = resolveTemplateMember(v, lookup)
				end
			end

			ct.complete = complete
			ct.cName = generateCName(ct.name)
			updateTypeSize(ct)

			return ct
		else
			error("Wrong number of template arguments supplied to class '" .. t.name .. "' (" .. #t.templates .. " expected, " .. #args .. " supplied)")
		end
	else
		error("Type '" .. t.name .. "' does not support template arguments")
	end
end

local function applyTypeMetatable(_type)
	setmetatable(_type, {
		__call = function(t, ...) 
			local ct = resolveTemplateArgs(t, ...)
			applyTypeMetatable(ct)
			return ct
		end,
		__index = {
			new = function(...)
				if _type.complete == true then
					return factory.create(_type, ...)
				end

				error("Unable to instantiate class type '" .. _type.name .. "' as it is incomplete");
			end,
		},
		__newindex = function(t, k, v)
			_type.methods[k] = v
		end
	})
end

local function class(name, super)
	if initialized == false then
		initialize()
	end

	if systemTypes[name] ~= nil then
		error("The class name '" .. name .. "' is invalid as it is a reserved system type name")
	end

	if classTypes[name] ~= nil then
		error("The class name '" .. name .. "' is invalid as it is already in use")
	end

	local _type = createTypeTable(name, super)
	applyTypeMetatable(_type)

	classTypes[name] = _type
	if settings.exposed == true then
		_G[name] = _type
	end

	local modifier
	modifier = setmetatable({}, {
		__call = function(t, members)
			--TODO: Validate members!
			_type.members = members

			if _type.complete == true then
				updateTypeSize(_type)
			end
		end,
		__index = {
			inherits = function(parent)
				validateParent(parent)
				_type.parent = parent
				return modifier
			end,

			templates = function(...)
				local defaultSet = false
				for i,v in ipairs({...}) do
					validateTemplate(v, defaultSet)

					local template
					if type(v) == "string" then
						template = { name = v }
					else
						template = { name = v[1], default = v[2] }
						defaultSet = true
						_type.templateDefaults = _type.templateDefaults + 1
					end

					table.insert(_type.templates, template)
				end

				_type.complete = false
				return modifier
			end
		}
	})

	return modifier
end

initialize = function(_settings)
	if _settings == nil then
		_settings = settings
	end

	if _settings.exposed == true then
		_G["class"] = class
		settings.exposed = true
	end

	createSystemType("bool", 4)
	createSystemType("float", 4)
	createSystemType("double", 4)
	createSystemType("int8", 1, "signed char")
	createSystemType("uint8", 1, "unsigned char")
	createSystemType("int16", 2, "signed short")
	createSystemType("uint16", 2, "unsigned short")
	createSystemType("int32", 4, "signed int")
	createSystemType("uint32", 4, "unsigned int")
	createSystemType("int64", 8, "signed long long")
	createSystemType("uint64", 8, "unsigned long long")

	if _settings.extraShortSystemTypes == true then
		createSystemType("i8", 1, "signed char")
		createSystemType("u8", 1, "unsigned char")
		createSystemType("i16", 2, "signed short")
		createSystemType("u16", 2, "unsigned short")
		createSystemType("i32", 4, "signed int")
		createSystemType("u32", 4, "unsigned int")
		createSystemType("i64", 8, "signed long long")
		createSystemType("u64", 8, "unsigned long long")
		createSystemType("f32", 4, "float")
		createSystemType("f64", 8, "double")
		settings.extraShortSystemTypes = true
	else
		settings.extraShortSystemTypes = false
	end

	initialized = true

	--class("array").templates("ValueType", { ["Size"] = 0 }) { }	
	--class "array<ValueType, Size = 0>" { }
end

local stronger = {
	setup = initialize,
	class = class
}

return stronger