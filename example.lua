local stronger = require "stronger"
require "printr"

stronger.setup({ exposed = true })

class("BaseBase").templates("BaseBaseValueType") {
	basebaseval = "BaseBaseValueType"
}

class("Base").templates("BaseValueType") {
	baseval = BaseBase("BaseValueType")
}

class("Nest").templates("NestValueType") {
	nestval = Base("NestValueType")
}

print_r(Nest(int32))
Nest(int32).new()

--[[class("Nest").templates("NestValueType") {
	nestval = Base("NestValueType")
}

Nest(int32).new()]]