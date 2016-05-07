local s = require "stronger"
require "printr"

describe("name parser", function()
	local parser = require "parser"

	it("should parse basic class names", function()
		local t = parser.parse("List")
		assert.are.same(t.name, "List")
		assert.is_true(t.pointer == nil)
		assert.is_true(#t.templates == 0)
	end)

	it("should parse pointers of multiple indirections", function()
		local t = parser.parse("List*")
		assert.is_true(t.pointer == 1)

		t = parser.parse("List**")
		assert.is_true(t.pointer == 2)

		t = parser.parse("List*****")
		assert.is_true(t.pointer == 5)
	end)

	it("should parse simple templates", function()
		local t = parser.parse("List<T>")
		assert.are.same(t.name, "List")
		assert.is_true(#t.templates == 1)
		assert.is_true(t.templates[1].name == "T")
	end)

	it("should parse simple templates with multiple arguments", function()
		local t = parser.parse("Allocator<T, U>")
		assert.are.same(t.name, "Allocator")
		assert.is_true(#t.templates == 2)
		assert.is_true(t.templates[1].name == "T")
		assert.is_true(t.templates[2].name == "U")
	end)

	it("should parse typed template arguments", function()
		local t = parser.parse("Allocator<int32 T>")
		assert.are.same(t.name, "Allocator")
		assert.is_true(#t.templates == 1)
		assert.is_true(t.templates[1].type == "int32")
		assert.is_true(t.templates[1].name == "T")
	end)

	it("should parse typed template arguments with defaults", function()
		local t = parser.parse("Allocator<int32 T = 10>")
		assert.are.same(t.name, "Allocator")
		assert.is_true(#t.templates == 1)
		assert.is_true(t.templates[1].name == "T")
		assert.is_true(t.templates[1].type == "int32")
		assert.is_true(t.templates[1].default == 10)
	end)

	it("should not allow erroneous input", function()
		assert.has.errors(function() parser.parse("Allocator<") end)
		assert.has.errors(function() parser.parse("Allocator<T") end)
		assert.has.errors(function() parser.parse("123Allocator") end)
		assert.has.errors(function() parser.parse("Allo-cator") end)
		assert.has.errors(function() parser.parse("Allocator<>") end)
		assert.has.errors(function() parser.parse("Allocator<T,>") end)
		assert.has.errors(function() parser.parse("Allocator<,") end)
		assert.has.errors(function() parser.parse("Alloc,") end)
		assert.has.errors(function() parser.parse(",Allocator") end)
	end)
end)

describe("class type creator", function()
	it("should create basic class types", function()
		s.class "Foo" {
			item1 = s.int32,
			item2 = s.float
		}

		local member1 = s.Foo:findMember("item1")
		local member2 = s.Foo:findMember("item2")

		assert.is_true(member1 ~= nil)
		assert.is_true(member2 ~= nil)

		assert.is_true(s.Foo ~= nil)
		assert.is_true(s.Foo.name == "Foo")

		assert.is_true(member1.type == s.int32)
		assert.is_true(member2.type == s.float)
	end)

	it("should create instantiatable classes", function()
		local inst = s.Foo:new()
		inst.item1 = 1337
		inst.item2 = 3.14

		assert.is_true(inst ~= nil)
		assert.is_true(inst.item1 == 1337)
		--assert.is_true(inst.item2 == 3.14)
	end)
end)