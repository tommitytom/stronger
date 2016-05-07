local s = require "stronger"
require "containers.Array"

local INITIAL_CAPACITY = 10
local CAPACITY_MULTIPLIER = 1.5

s.class "List<T>" {
	items = s.Array("T"),
	count = s.int32
}

function s.List:init(capacity)
	self.count = 0
	if capacity ~= nil and capacity > 0 then
		self:resize(capacity)
	end
end

function s.List:add(item)
	if self.count == self.items.length then
		local capacity = math.ceil(self.items.length * CAPACITY_MULTIPLIER)
		self.items:resize(capacity > 0 and capacity or INITIAL_CAPACITY)
	end

	self.items:set(self.count, item)
	self.count = self.count + 1
end

function s.List:get(idx)
	assert(idx < self.count)
	return self.items:get(idx)
end

function s.List:set(idx, v)
	assert(idx < self.count)
	self.items:set(idx, v)
end

function s.List:resize(capacity)
	self.items:resize(capacity)
	self.capacity = capacity
end