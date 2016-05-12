local POINTER_SIZE = 4

local function createSystemType(name, size, cType)
	return {
		primitiveType = "system",
		name = name,
		size = size,
		cType = cType or name,
		resolved = true
	}
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

	template.resolved = template.value ~= nil

	if template.templateType == nil then
		if template.type ~= nil then
			template.templateType = "value"
		else
			template.templateType = "type"
		end
	end

	return template
end

local function createClassType(data)
	data.templates = data.templates or {}

	for i, v in ipairs(data.templates) do
		data.templates[i] = createTemplateType(v)
	end

	return {  
		primitiveType = "class",
		name = data.name,
		cType = data.cType,
		parent = data.super or object,
		templates = data.templates,
		members = {},
		methods = {},
		properties = {},
		templateDefaults = 0,
		size = 0,
		resolved = #data.templates == 0,
	}
end

local function createPointerType(origin, indirection)
	local resolved = true
	local name = origin
	local cType

	if type(origin) == "table" then
		name = origin.name
		cType = origin.cType
		resolved = origin.resolved
	end
	
	indirection = indirection or 1
	for i = 1, indirection do
		name = name .. "*"
		if cType ~= nil then
			cType = cType .. "*"
		end
	end

	return {
		primitiveType = "pointer",
		name = name,
		cType = cType,
		origin = origin,
		indirection = indirection,
		size = POINTER_SIZE,
		resolved = resolved
	}
end

return {
	SystemType = createSystemType,
	ClassType = createClassType,
	PointerType = createPointerType,
	TemplateType = createTemplateType
}