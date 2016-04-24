local stronger = require "stronger"
stronger.setup({ exposed = true })

require "printr"
require "examples.List"

local l = List(int32):new()

l:add(100)
print(l:get(0))