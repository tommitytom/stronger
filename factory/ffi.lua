local ffi = require "ffi"
local writer = require "writer.c"

local ctypes = {}
local typeLookup = {}

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

	return mt
end

local function addCType(_type)
	assert(_type.resolved == true, _type.name .. " is unresolved")

	-- Make sure all parents and member types have been added to the ffi
	if _type.parent ~= nil then
		if _type.parent.primitiveType == "class" and ctypes[_type.parent.name] == nil then
			addCType(_type.parent)
		end
	end

	for i, v in ipairs(_type.members) do
		if v.type.primitiveType == "class" and ctypes[v.type.name] == nil then
			addCType(v.type)
		end
	end

	local def = writer.write(_type, "pretty")

	print("-----------------")
	print(def)
	ffi.cdef(def);

	local methods = _type.methods
	if _type.parent ~= nil then
		methods = buildMethodTable(_type, {})
	end

	local ctype = ffi.metatype(_type.cType, { 
		__index = methods,
		__gc = function(instance)
			callDestructors(_type, instance)
		end
	});

	--assert(_type.size == ffi.sizeof(ctype), "Differing type sizes for " .. _type.name .. ": " .. _type.size .. ", " .. ffi.sizeof(ctype))
	ctypes[_type.name] = ctype
	typeLookup[tonumber(ctype)] = _type

	return ctype
end

local function create(_type, ...)
	local ctype = ctypes[_type.name]
	if ctype == nil then
		ctype = addCType(_type)
	end

	local obj = ffi.new(ctype)
	if _type.methods.init ~= nil then
		_type.methods.init(obj, ...)
	end

	return obj
end

local function createArray(_type, size)
	if _type.primitiveType == "class" then
		local ctype = ctypes[_type.name]
		if ctype == nil then
			addCType(_type)
		end
	end

	return ffi.new(_type.cType .. "[?]", size)
end

local function registerSystemType(_type)
	if _type.cType ~= _type.name then
		ffi.cdef("typedef " .. _type.cType .. " " .. _type.name .. ";")
		assert(_type.size == ffi.sizeof(_type.cType), "Size mismatch for " .. _type.name .. ": Def - " .. _type.size .. "   C - " .. ffi.sizeof(_type.name))
	end
end

local function typeOf(obj)
	local id = tonumber(ffi.typeof(obj))
	assert(typeLookup[id] ~= nil)
	return typeLookup[id]
end

return { 
	create = create,
	createArray = createArray,
	registerSystemType = registerSystemType, 
	typeOf = typeOf 
}