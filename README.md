# Interfaces for Zig

This package contains some utility functions to minimize the amount of
boilerplate & repetition required to create interfaces in Zig, in
particular the need to manually create a vtable for each
implementation type. No casting of "self" is required in method
implementations, though this does require the use of argument tuples
in vtables.

## Creating an interface

The bare minimum interface looks like:

```
const ifc = @import("interface");

const Interface = struct {
    const Vtable = struct {
        foo: ifc.V(.{i32}, i32),
        bar: ifc.V(.{[]const u8}, void),
    };
    ptr: *anyopaque,
    vtable: *const Vtable,

    pub fn foo(self: Interface, x: i32) i32 {
        return self.vtable.foo(self.ptr, .{x});
    }

    pub fn bar(self: Interface, name: []const u8) void {
        return self.vtable.bar(self.ptr, .{name});
    }

    pub fn maybeCast(self: Interface, Ptr: type) ?Ptr {
        return ifc.maybeCast(Ptr, self.vtable, self.ptr);
    }

    pub fn make(ptr: anytype) Interface {
        return .{ .ptr = ptr, .vtable = ifc.makeVtable(Vtable, @TypeOf(ptr)) };
    }
};
```

`ifc.V(args: anytype, Ret: anytype)` returns a vtable method pointer
for the given tuple of arg types and the return type.

`ifc.makeVtable(VtableType: type, ImplPtrType: type)` returns a vtable
pointer for the given implementation pointer type. This function
relies on Zig's memoization to always return the same vtable pointer
and to keep the pointer valid.

`ifc.maybeCast(PtrType: type, vtable: anytype, ptr: *anyopaque)`
returns a pointer of the given type if the vtable used for that type
matches the vtable in the interface, otherwise null. It's best used
from a method on the interface itself, since users shouldn't care what
the interface calls its vtable or pointer fields (in fact they should
probably be private).

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
        self.name = name;
    }
};
```

Note that the methods are normal methods and `self` can be a const
struct or a pointer. The "magic" methods in the vtable handle the
necessary pointer casting.
