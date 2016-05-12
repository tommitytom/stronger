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

	it("should parse simple template pointers", function()
		local t = parser.parse("List<T>*")
		assert.are.same(t.name, "List")
		assert.is_true(#t.templates == 1)
		assert.is_true(t.templates[1].name == "T")
		assert.is_true(t.pointer == 1)
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
		local invalidInput = {
			"Allocator<",
			"Allocator<T",
			"123Allocator",
			"Allo-cator",
			"Allocator<>",
			"Allocator<T,>",
			"Allocator<,",
			"Alloc,",
			",Allocator",
			"Allo!cator"
		}

		for i,v in ipairs(invalidInput) do
			assert.has.errors(function() parser.parse(v) end)
		end
	end)
end)

describe("class type creator", function()
	it("should create basic class types", function()
		s.class "Foo" {
			item1 = s.int32,
			item2 = s.uint32
		}

		local member1 = s.Foo:findMember("item1")
		local member2 = s.Foo:findMember("item2")

		function s.Foo:foo(v)
			return "Foo.foo"
		end

		function s.Foo:bar(v)
			return "Foo.bar"
		end

		assert.is_true(member1 ~= nil)
		assert.is_true(member2 ~= nil)

		assert.is_true(s.Foo ~= nil)
		assert.is_true(s.Foo.name == "Foo")

		assert.is_true(member1.type == s.int32)
		assert.is_true(member2.type == s.uint32)
	end)

	it("should create instantiatable classes", function()
		local inst = s.Foo:new()
		assert.is_true(inst ~= nil)

		inst.item1 = 1337
		inst.item2 = 2

		assert.is_true(inst.item1 == 1337)
		assert.is_true(inst:foo() == "Foo.foo")
		assert.is_true(inst:bar() == "Foo.bar")
	end)

	it("should allow inheritance", function()
		s.class("Bar", s.Foo) {
			item3 = s.f32
		}

		function s.Bar:bar(v)
			return "Bar.bar"
		end

		local inst = s.Bar:new()
		inst.item1 = 999
		inst.item2 = 2
		inst.item3 = 3

		assert.is_true(inst:foo() == "Foo.foo")
		assert.is_true(inst:bar() == "Bar.bar")
	end)
end)