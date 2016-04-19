local ffi = require "ffi"

local ctypes = {}

local function memberString(_type)
	local def = ""
	if _type.parent ~= nil then
		def = def .. memberString(_type.parent)
	end

	for k, v in pairs(_type.members) do
		local memberType = v.cName or v.name
		def = def .. "\t" .. memberType .. " " .. k .. ";\n"
	end

	return def
end

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
		buildMethodTable(t, mt)
	end

	for k, v in pairs(t.methods) do
		mt[k] = v
	end

	return mt
end

local function addCType(_type)
	assert(_type.complete == true, _type.name .. " is incomplete")

	-- Make sure all parents and member types have been added to the ffi
	if _type.parent ~= nil then
		if _type.parent.baseType == "class" and ctypes[_type.parent.name] == nil then
			addCType(v)
		end
	end

	for k, v in pairs(_type.members) do
		if v.baseType == "class" and ctypes[v.name] == nil then
			addCType(v)
		end
	end

	-- Write out the struct definition
	local def = "typedef struct {\n"
	def = def .. memberString(_type)
	def = def .. "} " .. _type.cName .. ";"

	print("-----------------")
	print(def)
	ffi.cdef(def);
	--print_r(_type)

	local methods = _type.methods
	if _type.parent ~= nil then
		methods = buildMethodTable(_type, {})
	end

	local ctype = ffi.metatype(_type.cName, { 
		__index = methods,
		__gc = function(instance)
			callDestructors(_type, instance)
		end
	});

	--assert(_type.size == ffi.sizeof(ctype), "Differing type sizes for " .. _type.name .. ": " .. _type.size .. ", " .. ffi.sizeof(ctype))
	ctypes[_type.name] = ctype

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

local function registerSystemType(_type)
	if _type.ctype ~= nil then
		ffi.cdef("typedef " .. _type.ctype .. " " .. _type.name .. ";")
	end
end

return { create = create, registerSystemType = registerSystemType }