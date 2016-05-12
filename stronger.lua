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

local function validateTemplateLookup(v, name)
	assert(v ~= nil, "Template argument '" .. name .. "' could not be found in the lookup")
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
		assert(value.primitiveType ~= "pointer")
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

local function resolveMembers(_type, lookup)
	for i, v in ipairs(_type.members) do
		if v.type.primitiveType == "template" then
			local temp = lookup[v.type.name]
			validateTemplateLookup(temp, v.type.name)
			_type.members[i] = { name = v.name, type = temp }
		elseif v.type.primitiveType == "pointer" and v.type.resolved == false then
			local temp = lookup[v.type.origin.name]
			validateTemplateLookup(temp, v.type.origin.name)
			local pt = TypeFactory.PointerType(temp, v.type.indirection)
			_type.members[i] = { name = v.name, type = pt }
		elseif v.type.primitiveType == "class" and v.type.resolved == false then
			_type.members[i] = resolveTemplateMember(v, lookup)
		end
	end
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

			resolveMembers(ct, lookup)			

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
			newArray = function(t, size)
				return ObjectFactory.createArray(_type, size)
			end
		}
	})
end

local function applyPointerMetatable(_type)
	setmetatable(_type, {
		__index = {
			new = function(self, ...)
				if self.origin.resolved == true then
					return ObjectFactory.create(self.origin, ...)
				end

				error("Unable to instantiate class type '" .. self.name .. "' as it is unresolved");
			end,
			newArray = function(self, size)
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
			new = function(self, ...)
				if self.resolved == true then
					return ObjectFactory.create(self, ...)
				end

				error("Unable to instantiate class type '" .. self.name .. "' as it is unresolved");
			end,
			newArray = function(self, size)
				if self.resolved == true then
					return ObjectFactory.createArray(self, size)
				end

				error("Unable to instantiate array of class type '" .. self.name .. "' as it is unresolved");
			end,
			findMember = function(self, name)
				for i,v in ipairs(self.members) do
					if v.name == name then
						return v
					end
				end
			end,
			findTemplate = function(self, name)
				for i,v in ipairs(self.templates) do
					if v.name == name then
						return v
					end
				end
			end
		},
		__newindex = function(t, k, v)
			_type.methods[k] = v

			if #k > 4 then
				local s = k:sub(1, 4)
				local n = k:sub(5)
				local prop = _type.properties[n]

				if s == "get_" then
					prop = prop or {}
					prop.getter = v
				elseif s == "set_" then
					prop = prop or {}
					prop.setter = v
				end

				_type.properties[n] = prop
			end
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
		templates = parsed.templates
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
					table.insert(_type.members, { name = k, type = v })
				end
			end

			if _type.resolved == true then
				updateTypeSize(_type)
			else
				_type.cType = nil
			end

			return _type
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
	addSystemType("int8", 1, "int8_t")
	addSystemType("uint8", 1, "uint8_t")
	addSystemType("int16", 2, "int16_t")
	addSystemType("uint16", 2, "uint16_t")
	addSystemType("int32", 4, "int32_t")
	addSystemType("uint32", 4, "uint32_t")
	addSystemType("int64", 8, "int64_t")
	addSystemType("uint64", 8, "uint64_t")
	addSystemType("intptr", 4, "intptr_t")
	addSystemType("uintptr", 4, "uintptr_t")
	addSystemType("f32", 4, "float")
	addSystemType("f64", 8, "double")

	initialized = true

	local o = class("object") {}

	function o:isTypeOf(other)
		return self.__type() == other
	end
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

	local pointerType = TypeFactory.PointerType(t, level)
	applyPointerMetatable(pointerType)

	return pointerType
end

local function typeOf(_type)
	if type(_type) == "string" then
		local t = systemTypes[_type]
		if t ~= nil then return t end

		t = classTypes[_type]
		if t ~= nil then return t end
	elseif type(_type) == "table" then
		if _type.primitiveType ~= nil then
			return _type
		end
	elseif type(_type) == "cdata" then
		if _type.__type ~= nil then
			return _type.__type()
		end
	end
end

local function typeDef(from, to)

end

local function parseClass(name, fields)
end

stronger.setup = initialize
stronger.class = class
stronger.typeOf = typeOf
stronger.templateOf = templateOf
stronger.p = p
stronger.typeDef = typeDef
stronger.parseClass = parseClass

return stronger