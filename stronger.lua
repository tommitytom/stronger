local ObjectFactory = require "factory.ffi"
local parser = require "parser"
local TypeFactory = require "type"
local Util = require "util"

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

local function findTemplate(_type, name)
	for i, v in ipairs(_type.templates) do
		if v.name == name then
			return v
		end
	end
end

local function getType(name)
	local t = classTypes[name]
	if t ~= nil then
		return t
	end

	t = systemTypes[name]
	if t ~= nil then
		return t
	end
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
		assert(v.type.resolved == nil or v.type.resolved == true)
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

local function cloneType(t)
	local ct = Util.shallowCloneTable(t)
	ct.members = Util.shallowCloneTable(t.members)
	ct.templates = Util.shallowCloneTable(t.templates)

	for i, v in ipairs(ct.members) do
		if v.type.primitiveType == "template" then
			ct.members[i] = Util.shallowCloneTable(v)
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
		value = TypeFactory.TemplateType({ name = value })
		template = TypeFactory.TemplateType(template, { value = value })
		resolved = false
	elseif type(value) == "table" then
		if value.primitiveType == "template" then
			template = TypeFactory.TemplateType(template, { value = value })
			resolved = false
		else
			-- Check if this codepath is called
			template = TypeFactory.TemplateType(template, { value = value })
		end
	else
		-- Check if this codepath is called
		template = TypeFactory.TemplateType(template, { value = value })
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

local function applySystemMetatable(_type)
	setmetatable(_type, {
		__call = function(t, default)
			local ct = Util.shallowCloneTable(t)
			ct.default = default
			return ct
		end,
		__index = {
			newArray = function(size)
				return ObjectFactory.createArray(_type, size)
			end
		}
	})
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
					return ObjectFactory.create(_type, ...)
				end

				error("Unable to instantiate class type '" .. _type.name .. "' as it is unresolved");
			end,
			newArray = function(size)
				if _type.resolved == true then
					return ObjectFactory.createArray(_type, size)
				end

				error("Unable to instantiate array of class type '" .. _type.name .. "' as it is unresolved");
			end,
		},
		__newindex = function(t, k, v)
			_type.methods[k] = v
		end
	})
end

local function addSystemType(name, size, cType)
	local _type = TypeFactory.SystemType(name, size, cType)
	applySystemMetatable(_type)

	systemTypes[name] = _type
	stronger[name] = _type

	if settings.exposed == true then
		_G[name] = _type
	end

	ObjectFactory.registerSystemType(_type)
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

	local _type = TypeFactory.ClassType({
		name = parsed.name,
		cType = generateCTypeName(parsed.name),
		super = super,
		tempaltes = parsed.templates
	})

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
					local parsed = parser.parse(v)
					local t = getType(parsed.name)
					if t == nil then
						t = findTemplate(_type, parsed.name)
						assert(t ~= nil)
					end

					if parsed.pointer ~= nil then
						t = TypeFactory.PointerType(t, parsed.pointer)
					end

					table.insert(_type.members, { name = k, type = t })
				elseif type(v) == "table" then
					if v.primitiveType == "pointer" then
						assert(false)
						--if v.
					else
						table.insert(_type.members, { name = k, type = v })
					end
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
						template = TypeFactory.TemplateType({ name = v })
					else
						template = TypeFactory.TemplateType(v)
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

	addSystemType("bool", 4)
	addSystemType("float", 4)
	addSystemType("double", 4)
	addSystemType("int8", 1, "signed char")
	addSystemType("uint8", 1, "unsigned char")
	addSystemType("int16", 2, "signed short")
	addSystemType("uint16", 2, "unsigned short")
	addSystemType("int32", 4, "signed int")
	addSystemType("uint32", 4, "unsigned int")
	addSystemType("int64", 8, "signed long long")
	addSystemType("uint64", 8, "unsigned long long")

	if _settings.extraShortSystemTypes == true then
		addSystemType("i8", 1, "signed char")
		addSystemType("u8", 1, "unsigned char")
		addSystemType("i16", 2, "signed short")
		addSystemType("u16", 2, "unsigned short")
		addSystemType("i32", 4, "signed int")
		addSystemType("u32", 4, "unsigned int")
		addSystemType("i64", 8, "signed long long")
		addSystemType("u64", 8, "unsigned long long")
		addSystemType("f32", 4, "float")
		addSystemType("f64", 8, "double")
		settings.extraShortSystemTypes = true
	else
		settings.extraShortSystemTypes = false
	end

	initialized = true

	--class("object") {}
	--class("array").templates("T") { }
	--class("StaticArray").templates("T", { name = "Size", type = uint32 }) { }
	--stronger.array.primitiveType = "array"
	--stronger.StaticArray.primitiveType = "array"

	--class("array").templates("ValueType", { ["Size"] = 0 }) { }	
	--class "array<ValueType, Size = 0>" { }
end

local function typeOf(obj)
	if type(obj) == "cdata" then
		return ObjectFactory.typeOf(obj)
	end

	assert(false)
end

local function templateOf(obj, name)
	local t = typeOf(obj)
	return findTemplate(t, name).value
end



local function p(_type, level)
	local t = _type
	if type(_type) == "string" then
		local parsed = parser.parse(_type)
		t = getType(parsed.name)
		if t == nil then
			t = parsed.name
		end

		if parsed.pointer ~= nil then
			level = (level or 1) + parsed.pointer
		end
	end

	return TypeFactory.PointerType(t, level)
end

stronger.setup = initialize
stronger.class = class
stronger.typeOf = typeOf
stronger.templateOf = templateOf
stronger.p = p

return stronger