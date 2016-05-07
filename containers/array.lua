local s = require "stronger"
local ffi = require "ffi"

s.class "Array<T>" {
	items = "T*",
	length = s.int32
}

function s.Array:init(size)
	self.length = size or 0
	if self.length > 0 then
		self:resize(self.length)
	end
end

function s.Array:set(idx, value)
	assert(idx >= 0 and idx < self.length)
	self.items[idx] = value
end

function s.Array:get(idx)
	assert(idx >= 0 and idx < self.length)
	return self.items[idx]
end

function s.Array:resize(length)
	local old = self.items
	local _type = self:__template("T")
	self.items = _type:newArray(length)
	
	if self.length > 0 then
		ffi.copy(self.items, old, math.min(self.length, length) * _type.size)
	end

	self.length = length
end