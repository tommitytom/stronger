local factory = require "factory.ffi"

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

local function createTemplateType(name, value, default)
	return {
		name = name,
		value = value,
		default = default,
		primitiveType = "template"
	}
end

local function createSystemType(name, size, ctype)
	local _type = {
		name = name,
		size = size,
		ctype = ctype,
		primitiveType = "system",
		complete = true
	}

	setmetatable(_type, {
		__call = function(t, default)
			local ct = cloneTable(t)
			ct.default = default
			return ct
		end
	})

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
		assert(v.type.complete == true)
		t.size = t.size + v.type.size
	end
end

local function generateCName(name)
	return settings.cPrefix .. name:gsub("<", "_"):gsub(",", "_"):gsub(">", ""):gsub(" ", "")
end

local function createTypeTable(name, super)
	return {  
		name = name,
		cName = generateCName(name),
		parent = super or object,
		members = {},
		methods = {},
		templates = {},
		templateDefaults = 0,
		complete = true,
		size = 0,
		primitiveType = "class"
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
		name = name .. (i > 1 and ", " or "") .. lookup[v.name].name
	end

	return name .. ">"
end

local function resolveTemplateArgs(t, ...)
	if t.complete == false then
		local args = {...}
		if #args >= (#t.templates - t.templateDefaults) and #args <= #t.templates then
			local templateArgs = bundleTemplateArgs(args, t.templates)
			local ct = cloneType(t)
			ct.complete = true

			local lookup = {}
			for i, arg in ipairs(templateArgs) do
				local template = ct.templates[i]
				if type(arg) == "string" then
					arg = createTemplateType(arg, nil, template.default)
					ct.templates[i] = createTemplateType(template.name, arg, template.default)
					ct.complete = false
				elseif arg.primitiveType == "template" then
					arg = createTemplateType(template.name, arg.value, template.default)
					ct.templates[i] = arg
					ct.complete = false
				else
					ct.templates[i] = createTemplateType(template.name, arg, template.default)
				end

				lookup[template.name] = arg
			end

			for i, v in ipairs(ct.members) do
				if v.type.primitiveType == "template" then
					assert(lookup[v.type.name] ~= nil, "Template argument '" .. v.type.name .. "' could not be found in the lookup")
					ct.members[i] = { name = v.name, type = lookup[v.type.name] }
				elseif (v.type.primitiveType == "class" or v.type.primitiveType == "array") and v.type.complete == false then
					ct.members[i] = resolveTemplateMember(v, lookup)
				end
			end

			if ct.complete == true then
				ct.name = generateTemplateClassName(ct.name, ct.templates, lookup)
				ct.cName = generateCName(ct.name)
				updateTypeSize(ct)
			end

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

	if systemTypes[name] ~= nil then
		error("The class name '" .. name .. "' is invalid as it is a reserved system type name")
	end

	if classTypes[name] ~= nil then
		error("The class name '" .. name .. "' is invalid as it is already in use")
	end

	local _type = createTypeTable(name, super)
	applyTypeMetatable(_type)

	classTypes[name] = _type
	stronger[name] = _type
	if settings.exposed == true then
		_G[name] = _type
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
				for i,v in ipairs({...}) do
					validateTemplate(v, _type.templateDefaults > 0)

					local template
					if type(v) == "string" then
						template = createTemplateType(v)
					else
						template = createTemplateType(v[1], nil, v[2])
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

	class("object") {}
	class("array").templates("T") { }
	stronger.array.primitiveType = "array"

	--class("array").templates("ValueType", { ["Size"] = 0 }) { }	
	--class "array<ValueType, Size = 0>" { }
end

stronger.setup = initialize
stronger.class = class

return stronger