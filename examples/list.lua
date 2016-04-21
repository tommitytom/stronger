local s = require "stronger"
local ffi = require "ffi"

local INITIAL_CAPACITY = 10
local CAPACITY_MODIFIER = 1.5

class("List<T>") {
	items = Array("T"),
	capacity = int32,
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
	if self.length == self.capacity then
		local capacity = math.ceil(self.capacity * CAPACITY_MODIFIER)
		capacity = capacity > 0 and capacity or INITIAL_CAPACITY
		self:resize(capacity)
	end

	self.items[self.length] = item
	self.length = self.length + 1
end

function List:resize(capacity)
	print("Resizing to ", capacity)
	local old = self.items
	local tmp = s.templateOf(self, "T")

	self.items = ffi.new(tmp.value.cType .. "[?]", capacity)
	if self.capacity > 0 then
		ffi.copy(self.items, old, tmp.value.size * self.capacity)
	end

	self.capacity = capacity
end