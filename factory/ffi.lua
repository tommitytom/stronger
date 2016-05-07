local ffi = require "ffi"
local writer = require "writer.c"

local debug = true

local ctypes = {}
local arrayTypes = {}

local function callDestructors(_type, instance)
	local destroy = _type.methods["destroy"];
	if destroy ~= nil then
		destroy(instance)
	end

	if _type.parent ~= nil then
		callDestructors(_type.parent, instance)
	end
end

local function buildMethodTable(t, mt)
	if t.parent ~= nil then
		buildMethodTable(t.parent, mt)
	end

	for k, v in pairs(t.methods) do
		mt[k] = v
	end

	mt["__type"] = function(self)
		return t
	end

	if #t.templates > 0 then
		mt["__template"] = function(self, name)
			for i, v in ipairs(t.templates) do
				if v.name == name then
					return v.value
				end
			end
		end
	end

	return mt
end

local function addClassType(_type)
	assert(_type.resolved == true, _type.name .. " is unresolved")

	-- Make sure all parents and member types have been added to the ffi
	if _type.parent ~= nil then
		if _type.parent.primitiveType == "class" and ctypes[_type.parent.name] == nil then
			addClassType(_type.parent)
		end
	end

	for i, v in ipairs(_type.members) do
		if v.type.primitiveType == "class" and ctypes[v.type.name] == nil then
			addClassType(v.type)
		end
	end

	local def = writer.write(_type, "pretty")

	print("-----------------")
	print(def)
	ffi.cdef(def);

	local methods = buildMethodTable(_type, {})

	local ctype = ffi.metatype(_type.cType, { 
		__index = methods,
		__gc = function(instance)
			callDestructors(_type, instance)
		end
	});

	--assert(_type.size == ffi.sizeof(ctype), "Differing type sizes for " .. _type.name .. ": " .. _type.size .. ", " .. ffi.sizeof(ctype))
	ctypes[_type.name] = ctype
	return ctype
end

local function addArrayType(_type)
	assert(_type.primitiveType ~= "template")
	assert(_type.resolved == true)

	local origin
	if _type.primitiveType == "class" then
		origin = _type
	elseif _type.primitiveType == "pointer" then
		origin = _type.origin
	end

	if origin ~= nil then
		if ctypes[origin.name] == nil then
			addClassType(origin)
		end
	end

	if _type.primitiveType == "pointer" then
		assert(false)
	end

	local arrayType = ffi.typeof(_type.cType .. "[?]")
	arrayTypes[_type.name] = arrayType

	return arrayType
end

local function create(_type, ...)
	assert(_type.primitiveType == "class")
	assert(_type.resolved == true)

	local ctype = ctypes[_type.name]
	if ctype == nil then
		ctype = addClassType(_type)
	end

	local obj = ffi.new(ctype)
	if _type.methods.init ~= nil then
		_type.methods.init(obj, ...)
	end

	return obj
end

local function createArray(_type, size)
	local arrayType = arrayTypes[_type.name]
	if arrayType == nil then
		arrayType = addArrayType(_type)
	end

	return ffi.new(arrayType, size)
end

local function registerSystemType(_type)
	if _type.cType ~= _type.name then
		assert(_type.size == ffi.sizeof(_type.cType), "Size mismatch for " .. _type.name .. ": Def - " .. _type.size .. "   C - " .. ffi.sizeof(_type.cType))
	end
end

return { 
	create = create,
	createArray = createArray,
	registerSystemType = registerSystemType, 
	typeOf = typeOf 
}