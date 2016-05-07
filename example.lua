require "printr"
local s = require "stronger"
s.setup({ exposed = true })

require "containers.List"

local l = List(int32):new()

l:add(100)
print(l:get(0))