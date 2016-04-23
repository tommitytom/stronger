local s = require "stronger"
local ffi = require "ffi"

s.class "Array<T>" {
	items = s.p("T"),
	capacity = s.int32
}

function s.Array:init(size)
	self.capacity = size or 0
	self:resize(capacity)
end

function s.Array:set(idx, value)
	self.items[idx] = value
end

function s.Array:get(idx)
	return self.items[idx]
end

function s.Array:resize(capacity)
	local old = self.items
	local template = s.templateOf(self, "T")
	self.items = template.newArray(capacity)
	
	if self.capacity > 0 then
		ffi.copy(self.items, old, math.min(self.capacity, capacity) * template.size)
	end

	self.capacity = capacity
end