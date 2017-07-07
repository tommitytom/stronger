# stronger
Strongly typed LuaJIT class library that utilizes the LuaJIT FFI

:warning: **This library is more a proof of concept at this time and should be considered a prototype!  I would be keen to collaborate with a person or group on this!** :warning:

## Features
* Provides a C++ style interface for defining strongly typed classes in pure lua
* Properties (getters/setters)
* Inheritance
* Pointer support
* C++ style templating
* Runtime type information (RTTI)
* Converts definitions to C structs and injects them in to the LuaJIT FFI
* Instantiates classes with LuaJIT ctype values using malloc (with scope for allocator support)

### Not yet implemented
* String support is pretty flakey right now, but has scope for improvement
* Run-time type checking
* Access modifiers (such as `const`, `public`, `private`, `protected`)
* Virtual functions
* Array support is lacking
* Tests are a bit sparse
* Decorators, as seen in TypeScript and early versions of Babel.  Similar to C# attributes.  Just an idea at this point!
* Contributors and pull requests welcome!

### What it will never do
* Provide strongly typed methods

## Table of contents
1. [Basic Usage](#basic-usage)
2. [Inheritance](#inheritance)
3. [Properties](#properties)
4. [Pointers](#pointers)
5. [Templates](#templates)
6. [RTTI](#rtti)
7. [Why/Alternatives](#why)
8. [Contact](#contact)


## Basic Usage
### Prerequisites
The library can be used in one of 2 ways:
* Expose the library to the global scope, so every class type will be accessible  with no prefix (recommended)
* Call `local s = require "stronger"` at the beggining of each file and prefix every call to the library with `s.` (this includes all types that are accessed)

To keep this documentation clean I will be using method 1 throughout.  To enable global exposure, this needs to be called once (ideally at the start of your application)
```lua
local s = require "stronger"
s.setup({ exposed = true }) -- exposes to the global scope
```

### System types
The following system types are available: `bool`, `char`, `float`, `double`, `f32`, `f64`, `int8`, `uint8`, `int16`, `uint16`, `int32`, `uint32`, `int64`, `uint64`, `intptr`, `uintptr`

### Garbage collection
Since objects are instantiated using malloc() this also means that you need to clean up your garbage!

## Basic class
```lua
-- Class and data definition
class "Vector2" {
	x = float,
	y = float
}

-- Constructor
function Vector2:init(x, y)
	self.x = x or 0
	self.y = y or 0
end

-- Method
function Vector2:add(x, y)
	self.x = self.x + (x or 0)
	self.y = self.y + (y or 0)
end

-- Property
function Vector2:get_lengthSquared()
	return self.x * self.x + self.y * self.y
end

-- Usage
local pos = Vector2:new(1, 2) -- Returns Vector2*
pos:add(1, 1)
print(pos.x .. ", " .. pos.x) -- Outputs '2, 3'
print(pos.lengthSquared) -- Outputs '5'

local posArray = Vector2:newArray(10) -- Creates an array of 10 positions
```

## Properties
Properties are automatically created when a member function is prefixed with `get_` or `set_`.  Once a property is created it can be accessed just like a member variable.
```lua
class "Rectangle" {
	x = int32,
	y = int32,
	width = int32,
	height = int32
}

-- .. constructor ..

function Rectangle:get_right()
	return self.x + self.width
end

function Rectangle:set_right(value)
	self.width = value - self.x
end

function Rectangle:get_area()
	return self.width * self.height
end

local rect = Rectangle:new(10, 10, 50, 50)
print(rect.area) -- 2500
print(rect.right) -- 60
rect.right = 50 -- Updates rect.width
```

## Inheritance
Single inheritance is supported.  Data members, methods and properties from the super class (and all other parent classes) are inherited by the child.  Methods and properties can be overidden by simply redefining them on the child.
```lua
----------------------- Animal base class -----------------------
class "Animal" {
	age = int32
}

function Animal:init(age)
	self.age = age
end

function Animal:talk()
	return "Silence..."
end

function Animal:get_speed()
	return 0
end

----------------------- Dog class -----------------------
class("Dog", Animal) {
	furLength = f32
}

function Dog:init(age, furLength)
	Animal.init(self, age) -- Call the constructor of the base class
	self.furLength = furLength
end

function Dog:talk()
	-- Override method
	return "Woof!"
end

function Dog:get_speed()
	-- Override property getter
	return 30 - (self.age + self.furLength)
end

----------------------- Cat class -----------------------
-- NOTE: You can inherit from the name of type as well as the type object
class("Cat", "Animal") {
	lives = int32
}

function Cat:init(age, lives)
	Animal.init(self, age)
	self.lives = lives
end

function Cat:talk()
	return "Meooow!"
end

function Cat:get_speed()
	return 30 - self.age
end

----------------------- Class usage -----------------------
local dog = Dog:new(10, 4)
print(dog.talk()) -- Woof!
print(dog.age) -- 10
print(dog.furLength) -- 4
print(dog.speed) -- 16

local cat = Cat:new(5, 9)
print(cat.talk()) -- Meow!
print(cat.age) -- 5
print(cat.lives) -- 9
print(cat.speed) -- 25
```

## Pointers
Pointers can be created and are to be used in the same way they would be used in C or C++.  When you call `Type:new()` it actually returns a pointer to the object.
Pointers to types can be created with the `p()` function or provided as a string.
```lua
-- Using the p() function
class "Player" {
	controller = p(XboxController)
}

-- Using a string
class "Player" {
	controller = "XboxController*"
}

local player = Player:new() -- Player*
local controller = XboxController:new() -- XboxController*
player.controller = controller
```

Multiple levels of indirection are supported
```lua
class "Player" {
	currentGun = p(Gun),
	guns = p(Gun, 2) -- Second parameter is indirection level
}

class "Player" {
	currentGun = "Gun*",
	guns = "Gun**"
}

local player = Player:new()
player.currentGun = player.guns[0]
```

## Templates
:warning: **There is plenty of room for improvement here so this will most likely change at some point**

A C++ style syntax is provided for templating.  Template arguments are supplied in the class name, and are referenced within the class definition as a string.

```lua
class "Vector2<T>" {
	x = "T",
	y = "T"
}

local floatPos = Vector2(f32):new()
local doublePos = Vector2(f64):new()
```

The template type values can be accessed at runtime using the `__template()` method
```lua
class "Array<T>" {
	values = "T*",
	size = int32
}

function Array:init(size)
	local valueType = self:__template("T")
	self.values = valueType:newArray(size)
	self.size = size
end
```

Also similar to C++, you can supply value type arguments, with optional default values.
```lua
class "FixedArray<T, int32 Size = 10>" {
	values = "T*",
	size = int32
}

function FixedArray:init()
	local valueType = self:__template("T")
	local size = self.__template("Size")
	self.values = valueType:newArray(size)
	self.size = size
end

local positions1 = FixedArray(Vector2):new() -- Creates an array of the default size (10)
local positions2 = FixedArray(Vector2, 20):new() -- Creates an array with 20 elements
```

## RTTI
It is possible to get information about a class type at runtime.  The class type itself contains all the information needed to know everything about the class.  To get the class type of an object, use the `__type()` method.

```lua
Vector2.name == "Vector2"
Vector2:findMember("x").type == f32

local pos = Vector2:new()
pos.__type().name == "Vector2*"
```

## Why/Alternatives
This library was created to solve a two very specific problems:
1. To allow for runtime compilable Lua without having a persistence layer.  The advantage of this library is it allows all objects that are created to survive even when the Lua context is destroyed, since they are ctype objects and not first class Lua objects.  A new Lua context can be constructed and the data from the previous context can be given to it with a simple pointer copy.
2. Almost an extension of the first problem, but it allows us to create objects in Lua _or_ C/C++, in different Lua contexts and threads, and pass them to the single threaded Lua context.

The runtime compilable aspect is mainly for use in real time audio and graphics programming.  Since under the hood a lot of RTTI information is generated it allows us to track specific changes to classes when files are edited.  The pointer support also allows us to create more complex data structures, and gives more scope for optimizations.

There are a number of different alternatives to this library should you be looking for other class libraries or ways of making your data a bit more type safe:
* [TypedLua](https://github.com/andremm/typedlua) - Optional full typing for Lua, though you still have to roll your own classes.  There is a fork [here](https://github.com/kevinclancy/typedlua) that has preliminary support for classes but support seems minimal.  As far as I am aware at this time there are no IDE plugins that allow for static analysis.
* [Terra](http://terralang.org/) - A low-level system programming language that is designed to interoperate seamlessly with the Lua programming language.  Includes static typing for functions and variables.  Roll your own classes.

## Contact
Author - Tom Yaxley / _tommitytom at gmail dot com_

Feel free to open issues!