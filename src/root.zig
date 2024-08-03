const std = @import("std");

pub inline fn V(comptime Args: anytype, comptime Ret: type) type {
    const arrgs: [Args.len]type = Args;
    return *const fn (ptr: *anyopaque, args: std.meta.Tuple(&arrgs)) Ret;
}

fn RetType(comptime method: anytype) type {
    return @typeInfo(@TypeOf(method)).Fn.return_type.?;
}

fn ArgsTuple(comptime method: anytype) type {
    const params = @typeInfo(@TypeOf(method)).Fn.params[1..];
    comptime var types: []const type = &.{};
    inline for (params) |p| {
        types = types ++ .{p.type.?};
    }
    return std.meta.Tuple(types);
}

// The "magic" method pointer that we store in the vtable
inline fn methodPtr(comptime method: anytype) *const fn (*anyopaque, ArgsTuple(method)) RetType(method) {
    const inner = struct {
        const Self = @typeInfo(@TypeOf(method)).Fn.params[0].type.?;
        fn meth(ptr: *anyopaque, args: ArgsTuple(method)) RetType(method) {
            const self: Self = switch (@typeInfo(Self)) {
                .Pointer => @ptrCast(@alignCast(ptr)),
                else => @as(*Self, @ptrCast(@alignCast(ptr))).*,
            };
            return @call(.auto, method, .{self} ++ args);
        }
    };
    return &inner.meth;
}

// Create a vtable for a given implementation type
pub fn makeVtable(comptime Vtable: type, comptime ImplPtr: type) *const Vtable {
    const fields = @typeInfo(Vtable).Struct.fields;
    const Impl = @typeInfo(ImplPtr).Pointer.child;
    comptime var vtable: Vtable = undefined;

    inline for (fields) |field| {
        @field(vtable, field.name) = methodPtr(@field(Impl, field.name));
    }

    const ret: Vtable = vtable;
    return &ret;
}

pub fn maybeCast(comptime Ptr: type, vtable: anytype, ptr: *anyopaque) ?Ptr {
    return if (vtable == makeVtable(@typeInfo(@TypeOf(vtable)).Pointer.child, Ptr)) @alignCast(@ptrCast(ptr)) else null;
}

test "interface" {
    const FooInterface = struct {
        const Vtable = struct {
            foo: V(.{ i32, i32 }, i32),
            incr: V(.{i32}, void),
        };

        pub fn foo(self: @This(), x: i32, y: i32) i32 {
            return self.vtable.foo(self.ptr, .{ x, y });
        }

        pub fn incr(self: @This(), x: i32) void {
            return self.vtable.incr(self.ptr, .{x});
        }

        pub fn make(obj: anytype) @This() {
            return .{ .vtable = makeVtable(Vtable, @TypeOf(obj)), .ptr = obj };
        }

        pub fn cast(self: @This(), comptime Ptr: type) ?Ptr {
            return maybeCast(Ptr, self.vtable, self.ptr);
        }

        vtable: *const Vtable,
        ptr: *anyopaque,
    };

    const FooImpl = struct {
        z: i32,
        pub fn foo(self: @This(), x: i32, y: i32) i32 {
            return x + y + self.z;
        }

        pub fn incr(self: *@This(), x: i32) void {
            self.z = self.z + x;
        }
    };

    var fooImpl = FooImpl{
        .z = 5,
    };

    var fooImpl2 = FooImpl{
        .z = 3,
    };

    const bar = FooInterface.make(&fooImpl);
    const baz = FooInterface.make(&fooImpl2);
    try std.testing.expect(bar.foo(6, 7) == 18);
    bar.incr(3);
    try std.testing.expect(fooImpl.z == 8);
    try std.testing.expect(bar.vtable == baz.vtable);
    try std.testing.expect(bar.cast(*FooImpl) == &fooImpl);
    try std.testing.expect(baz.cast(*FooImpl) == &fooImpl2);
}
