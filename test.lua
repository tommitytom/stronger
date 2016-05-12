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

		function s.Foo:foo(v)
			return "Foo.foo"
		end

		function s.Foo:bar(v)
			return "Foo.bar"
		end

		assert.is_true(s.Foo ~= nil)
		assert.is_true(s.Foo.name == "Foo")

		local member1 = s.Foo:findMember("item1")
		local member2 = s.Foo:findMember("item2")

		assert.is_true(member1 ~= nil)
		assert.is_true(member2 ~= nil)
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

	it("should allow properties", function()
		s.class "ProperTest" {
			_item1 = s.int32
		}

		function s.ProperTest:foo(v)
			return "ProperTest.foo"
		end

		function s.ProperTest:set_item1(v)
			self._item1 = v
		end

		function s.ProperTest:get_item1()
			return self._item1
		end

		local inst = s.ProperTest:new()
		inst.item1 = 1337

		assert.is_true(inst.item1 == 1337)
		assert.is_true(inst._item1 == 1337)
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

	it("should allow templated types", function()
		s.class "TempTest<T>" {
			item1 = "T",
			item2 = "T*"
		}

		assert.is_false(s.TempTest.resolved)
		assert.has.errors(function() TempTest:new() end)

		local TempTestInt32 = s.TempTest(s.int32)

		assert.is_true(TempTestInt32.name == "TempTest<int32>")

		local member1 = TempTestInt32:findMember("item1")
		local member2 = TempTestInt32:findMember("item2")

		assert.is_true(member1 ~= nil)
		assert.is_true(member2 ~= nil)
		assert.is_true(member1.type == s.int32)
		assert.is_true(member2.type.name == s.p(s.int32).name)

		local tt = TempTestInt32:new()
		tt.item1 = 10
		assert.is_true(tt.item1 == 10)
	end)

	it("should allow template value type arguments with defaults", function()
		s.class "DefaultTest<T, int32 Count = 30>" {
			item1 = "T*",
		}

		print_r(s.DefaultTest)

		function s.DefaultTest:init()
			local c = self:__templateDefault("Count")
			self.item1 = self:__template("T"):newArray(10)
		end

		local dt1 = s.DefaultTest(s.int32):new()
		local dt2 = s.DefaultTest(s.int32, 20):new()
	end)

	it("should allow inheriting from templated types", function()
		s.class("InheriTest1", "DefaultTest<float>") {
			item2 = int32
		}

		s.class("InheriTest2", s.DefaultTest(s.float, 50)) {
			item2 = int32
		}
	end)

	it("should allow a templated type to inherit from other templated types", function()
	end)
end)