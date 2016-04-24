local s = require "stronger"
local ffi = require "ffi"

s.class "Array<T>" {
	items = "T*",
	capacity = s.int32
}

function s.Array:init(size)
	self.capacity = size or 0
	if self.capacity > 0 then
		self:resize(self.capacity)
	end
end

function s.Array:set(idx, value)
	assert(idx >= 0 and idx < self.capacity)
	self.items[idx] = value
end

function s.Array:get(idx)
	assert(idx >= 0 and idx < self.capacity)
	return self.items[idx]
end

function s.Array:resize(capacity)
	local old = self.items
	local type = self:__template("T")
	self.items = type:newArray(capacity)
	
	if self.capacity > 0 then
		ffi.copy(self.items, old, math.min(self.capacity, capacity) * type.size)
	end

	self.capacity = capacity
end