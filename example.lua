local stronger = require "stronger"
require "printr"

stronger.setup({ exposed = true })

class("BaseBase").templates("BaseBaseValueType") {
	basebaseval = "BaseBaseValueType"
}

class "NonTemp" {
	val = int32
}

class("In").inherits(NonTemp) {
	
}

class("Base").templates("BaseValueType") {
	baseval = BaseBase("BaseValueType")
}

class("Nest").templates("NestValueType") {
	nestval = Base("NestValueType")
}

--class("Array<typename T, int32 Size = 0>")

--print_r(Nest(int32))
print_r(In)
print(In.parent)
In.new()
--Nest(int32).new()

--[[class("Nest").templates("NestValueType") {
	nestval = Base("NestValueType")
}

Nest(int32).new()]]