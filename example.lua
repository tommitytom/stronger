local stronger = require "stronger"
require "printr"

stronger.setup({ exposed = true })

class("TempType").templates("T") {
	val = "T"
}

class("List").templates("ValueType", "V2") {
	item = TempType("ValueType"),
	--item2 = TempType("ValueType"),
	item3 = TempType("V2"),
	--values = array("ValueType")
	test = "ValueType",
	test2 = "V2"
}

function List:init(size)

end

IntList = List(int32, float)
local l = IntList.new()
