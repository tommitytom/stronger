local factory = require "factory.ffi"
local parser = require "parser"

local POINTER_SIZE = 4

local stronger = { }

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

local function createTemplateType(t, mod)
	mod = mod or {}
	local template = {
		primitiveType = "template",
		name = mod.name or t.name,
		templateType = mod.templateType or t.templateType,
		value = mod.value or t.value,
		default = mod.default or t.default,
		type = mod.type or t.type
	}

	if template.templateType == nil then
		if template.type ~= nil then
			template.templateType = "value"
		else
			template.templateType = "type"
		end
	end

	return template
end

local function applySystemMetatable(_type)
	setmetatable(_type, {
		__call = function(t, default)
			local ct = cloneTable(t)
			ct.default = default
			return ct
		end,
		__index = {
			newArray = function(size)
				if _type.resolved == true then
					return factory.createArray(_type, size)
				end

				error("Unable to instantiate array of class type '" .. _type.name .. "' as it is unresolved");
			end
		}
	})
end

local function createSystemType(name, size, cType)
	local _type = {
		primitiveType = "system",
		name = name,
		size = size,
		cType = cType,
		pointer = 0,
		resolved = true
	}

	applySystemMetatable(_type)

	systemTypes[name] = _type
	stronger[name] = _type
	if settings.exposed == true then
		_G[name] = _type
	end

	factory.registerSystemType(_type)
end

local function validateParent(p)
	if p == nil then 
		error("Parent class undefined") 
	end

	if p.resolved == false then
		error("Unable to inherit from an unresolved class type")
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
		-- Do some checking here
	elseif type(arg) == "table" then
		if arg.primitiveType == nil then
			error("Template argument must be a valid type")
		end
	else
		error("Template parameters of type '" .. type(arg) .. "' are not supported")
	end
end

local function updateTypeSize(t)
	t.size = 0
	for _, v in ipairs(t.members) do
		assert(v.type.resolved == true)
		if v.type.pointer == 0 then
			t.size = t.size + v.type.size
		else
			t.size = t.size + POINTER_SIZE
		end
	end
end

local function generateCTypeName(name)
	return settings.cPrefix .. name:gsub("<", "_"):gsub(",", "_"):gsub(">", ""):gsub(" ", "")
end

local function createTypeTable(name, super, templates)
	for i, v in ipairs(templates) do
		templates[i] = createTemplateType(v)
	end

	return {  
		name = name,
		primitiveType = "class",
		cType = generateCTypeName(name),
		parent = super or object,
		members = {},
		methods = {},
		templates = templates,
		templateDefaults = 0,
		size = 0,
		resolved = #templates == 0,
		pointer = 0	
	}
end

local function cloneType(t)
	local ct = cloneTable(t)
	ct.members = cloneTable(t.members)
	ct.templates = cloneTable(t.templates)

	for i, v in ipairs(ct.members) do
		if v.type.primitiveType == "template" then
			ct.members[i] = cloneTable(v)
		end
	end

	ct.origin = t.origin or t
	ct.cType = ""

	return ct
end

local function bundleTemplateArgs(args, templates)
	local templateArgs = {}
	for i, arg in ipairs(args) do
		validateTemplateArg(arg)
		table.insert(templateArgs, arg)
	end

	for i = #args + 1, #templates do
		assert(templates[i].default ~= nil)
		table.insert(templateArgs, templates[i].default)
	end

	return templateArgs
end

-- Resolve member variables that are templated types
local function resolveTemplateMember(member, lookup)
	local templateParams = {}
	for i, template in ipairs(member.type.templates) do
		local lookupName = template.name
		if template.value ~= nil then
			lookupName = template.value.name
		end
		
		assert(lookup[lookupName] ~= nil, "Template argument '" .. lookupName .. "' could not be found in the lookup")
		table.insert(templateParams, lookup[lookupName])
	end

	local memberType = member.type
	if memberType.origin ~= nil then
		memberType = memberType.origin
	end

	return { name = member.name, type = memberType(unpack(templateParams)) }
end

local function generateTemplateClassName(name, templates, lookup)
	name = name .. "<"
	for i, v in ipairs(templates) do
		local item = lookup[v.name]
		local tname = item
		if type(item) == "table" then
			tname = item.name
		end

		name = name .. (i > 1 and ", " or "") .. tname
	end

	return name .. ">"
end

local function setTemplateValue(template, value)
	-- This function can probably be tidied up a bit
	local resolved = true
	if type(value) == "string" then
		value = createTemplateType({ name = value })
		template = createTemplateType(template, { value = value })
		resolved = false
	elseif type(value) == "table" then
		if value.primitiveType == "template" then
			template = createTemplateType(template, { value = value })
			resolved = false
		else
			-- Check if this codepath is called
			template = createTemplateType(template, { value = value })
		end
	else
		-- Check if this codepath is called
		template = createTemplateType(template, { value = value })
	end

	return template, resolved
end

local function resolveTemplateArgs(t, ...)
	if t.resolved == false then
		local args = {...}
		if #args >= (#t.templates - t.templateDefaults) and #args <= #t.templates then
			local templateArgs = bundleTemplateArgs(args, t.templates)
			local ct = cloneType(t)
			ct.resolved = true

			local lookup = {}
			for i, arg in ipairs(templateArgs) do
				local template, resolved = setTemplateValue(ct.templates[i], arg)
				ct.templates[i] = template
				lookup[template.name] = template.value

				if resolved == false then
					ct.resolved = false
				end
			end

			for i, v in ipairs(ct.members) do
				if v.type.primitiveType == "template" then
					assert(lookup[v.type.name] ~= nil, "Template argument '" .. v.type.name .. "' could not be found in the lookup")
					ct.members[i] = { name = v.name, type = lookup[v.type.name] }
				elseif (v.type.primitiveType == "class" or v.type.primitiveType == "array") and v.type.resolved == false then
					ct.members[i] = resolveTemplateMember(v, lookup)
				end
			end

			if ct.resolved == true then
				ct.name = generateTemplateClassName(ct.name, ct.templates, lookup)
				ct.cType = generateCTypeName(ct.name)
				updateTypeSize(ct)
			else
				ct.cType = nil
			end

			return ct
		else
			error("Wrong number of template arguments supplied to class '" .. t.name .. "' (" .. #t.templates .. " expected, " .. #args .. " supplied)")
		end
	else
		error("Type '" .. t.name .. "' does not support template arguments")
	end
end

local function applyClassMetatable(_type)
	setmetatable(_type, {
		__call = function(t, ...) 
			local ct = resolveTemplateArgs(t, ...)
			applyClassMetatable(ct)
			return ct
		end,
		__index = {
			new = function(...)
				if _type.resolved == true then
					return factory.create(_type, ...)
				end

				error("Unable to instantiate class type '" .. _type.name .. "' as it is unresolved");
			end,
			newArray = function(size)
				if _type.resolved == true then
					return factory.createArray(_type, size)
				end

				error("Unable to instantiate array of class type '" .. _type.name .. "' as it is unresolved");
			end,
		},
		__newindex = function(t, k, v)
			_type.methods[k] = v
		end
	})
end

local function findTemplate(_type, name)
	for i, v in ipairs(_type.templates) do
		if v.name == name then
			return v
		end
	end
end

local function class(name, super)
	if initialized == false then
		initialize()
	end

	local parsed = parser.parse(name)

	if systemTypes[parsed.name] ~= nil then
		error("The class name '" .. parsed.name .. "' is invalid as it is a reserved system type name")
	end

	if classTypes[parsed.name] ~= nil then
		error("The class name '" .. parsed.name .. "' is invalid as it is already in use")
	end

	local _type = createTypeTable(parsed.name, super, parsed.templates)
	applyClassMetatable(_type)

	classTypes[parsed.name] = _type
	stronger[parsed.name] = _type
	if settings.exposed == true then
		_G[parsed.name] = _type
	end

	local modifier
	modifier = setmetatable({}, {
		__call = function(t, members)
			--TODO: Validate members!

			for k, v in pairs(members) do
				if type(v) == "string" then
					local template = findTemplate(_type, v)
					assert(template ~= nil)
					table.insert(_type.members, { name = k, type = template })
				else 
					table.insert(_type.members, { name = k, type = v })
				end
			end

			if _type.resolved == true then
				updateTypeSize(_type)
			else
				_type.cType = nil
			end
		end,
		__index = {
			inherits = function(parent)
				validateParent(parent)
				_type.parent = parent
				return modifier
			end,

			templates = function(...)
				for i,v in ipairs({...}) do
					validateTemplate(v, _type.templateDefaults > 0)

					local template
					if type(v) == "string" then
						template = createTemplateType({ name = v })
					else
						template = createTemplateType(v)
						if template.default ~= nil then
							_type.templateDefaults = _type.templateDefaults + 1
						end
					end

					table.insert(_type.templates, template)
				end

				_type.resolved = false
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

	if _settings.cPrefix ~= nil then
		settings.cPrefix = _settings.cPrefix
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

	class("object") {}
	class("Array").templates("T") { }
	class("StaticArray").templates("T", { name = "Size", type = uint32 }) { }
	stronger.Array.primitiveType = "array"
	stronger.StaticArray.primitiveType = "array"

	--class("array").templates("ValueType", { ["Size"] = 0 }) { }	
	--class "array<ValueType, Size = 0>" { }
end

local function typeOf(obj)
	if type(obj) == "cdata" then
		return factory.typeOf(obj)
	end

	assert(false)
end

local function templateOf(obj, name)
	local t = typeOf(obj)
	return findTemplate(t, name).value
end

local function p(_type, level)
	local t = cloneTable(_type)
	t.pointer = level or 1
	t.origin = _type.origin or _type

	if _type.primitiveType == "class" then
		applyClassMetatable(t)
		t.size = POINTER_SIZE
	elseif _type.primitiveType == "system" then
		applySystemMetatable(t)
		t.size = POINTER_SIZE
	end
	
	return t
end

stronger.setup = initialize
stronger.class = class
stronger.typeOf = typeOf
stronger.templateOf = templateOf
stronger.p = p

return stronger