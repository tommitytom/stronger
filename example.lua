local stronger = require "stronger"
stronger.setup({ exposed = true })

require "printr"
--require "examples.List"

local v = stronger.p("T")
print_r(v)

class("Test").templates("T") {
	val = "int32*"
}

print_r(Test(float))
Test(float).new()

--[[IntList = List(int32)
local l = IntList.new()

for i = 1, 30 do
	l:add(i)
end

for i = 1, 30 do
	print(l.items[i - 1])
end]]