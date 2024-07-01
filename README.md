# Interfaces for Zig

This package contains some utility functions to minimize the amount of
boilerplate & repetition required to create interfaces in Zig.

## Creating an interface

The bare minimum interface looks like:

```
const Interface = struct {
    ptr: *anyopaque,
    vtable: *const anyopaque,

    pub fn foo(self: Interface, x: i32) i32 {
        return interface.call(self, .foo, .{x});
    }

    pub fn bar(self: Interface, name: []const u8) void {
        interface.call(self, .bar, .{name});
    }
};
```

`interface.call(intfc, .method, args)` is a generic function that
calls the correct method pointer from the vtable.

## Implementating an interface

An implementation looks like:

```
const Foo = struct {
    y: i32,
    name: []const u8,

    pub fn foo(self: Foo, x: i32) i32 {
        return x + y;
    }

    pub fn bar(self: *Foo, name: []const u8) void {
        self.*.name = name;
    }
};
```

Note that the methods are normal methods and can be a const struct or
a pointer. The "magic" methods in the vtable handle the necessary
pointer casting. However, there is currently no way to specify a const
interface; they're always mutable.

## Instantiating an interface

To create an interface "fat pointer" from an interface and a concrete struct:

```
const myFoo = interface.make(Interface, Foo{ .x = 3, .name = "baz" });
```

The `make` function contains most of the magic. It creates a vtable
type and vtable for the type of its second argument based on the decls
(TODO: skip non-function decls) of the interface. The vtable contains
pointers not directly to the functions of the implementation struct,
but to instances of a generic function that handles all the necessary
casting for you.

## Dynamic casts

Besides virtual methods, interfaces are also used for dynamic casts.

```
if (interface.maybeCast(Foo, myFoo) |baz| {
    // baz is a pointer to a Foo
}
```
