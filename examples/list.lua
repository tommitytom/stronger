local s = require "stronger"
require "containers.Array"

local INITIAL_CAPACITY = 10
local CAPACITY_MODIFIER = 1.5

class "List<T>" {
	items = Array("T"),
	length = int32
}

function List:init(capacity)
	capacity = capacity or 0
	self.length = 0
	if capacity > 0 then
		self:resize(capacity)
	end
end

function List:add(item)
	if self.length == self.items.capacity then
		local capacity = math.ceil(self.items.capacity * CAPACITY_MODIFIER)
		self.items:resize(capacity > 0 and capacity or INITIAL_CAPACITY)
	end

	self.items:set(self.length, item)
	self.length = self.length + 1
end

function List:get(idx)
	assert(idx < self.length)
	return self.items:get(idx)
end

function List:set(idx, v)
	assert(idx < self.length)
	self.items:set(idx, v)
end

function List:resize(capacity)
	self.items:resize(capacity)
	self.capacity = capacity
end