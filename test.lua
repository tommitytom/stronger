local s = require "stronger"

describe("name parser", function()
	local parser = require "parser"

	it("basic parsing", function()
		local t = parser.parse("List")
		assert.is_true(t.name, "List")
		assert.is_true(t.pointer == 0)
		assert.is_true(#t.templates == 0)

		t = parser.parse("List*")
		assert.is_true(t.pointer == 1)

		t = parser.parse("List**")
		assert.is_true(t.pointer == 2)
	end)
end)

describe("class creation", function()
	it("tests simple class creation", function()
		s.class "Foo" {
			item1 = s.int32,
			item2 = s.float
		}

		assert.is_true(s.Foo ~= nil)
		assert.is_true(s.Foo.name == "Foo")
		assert.is_true(s.Foo.members.item1 == s.int32)
		assert.is_true(s.Foo.members.item2 == s.float)
	end)
	it("tests class instantiation", function()
		local inst = s.Foo.new()
		inst.item1 = 1337
		inst.item2 = 3.14

		print(inst.item1, inst.item2)

		assert.is_true(inst ~= nil)
		assert.is_true(inst.item1 == 1337)
		assert.is_true(inst.item2 == 3.14)
	end)
end)