const std = @import("std");
const print = std.debug.print;
const Type = std.builtin.Type;

inline fn MethodArgs(M: type) type {
    const params = @typeInfo(M).Fn.params[1..];
    comptime var types: []const type = &.{};
    inline for (params) |param| {
        types = types ++ .{param.type.?};
    }
    return std.meta.Tuple(types);
}

inline fn RetType(M: type) type {
    return @typeInfo(M).Fn.return_type.?;
}

inline fn MethodType(M: type) type {
    const params: []const Type.Fn.Param = &.{
        .{
            .is_generic = false,
            .is_noalias = false,
            .type = *anyopaque,
        },
        .{
            .is_generic = false,
            .is_noalias = false,
            .type = MethodArgs(M),
        },
    };
    return @Type(.{ .Fn = .{
        .calling_convention = .Unspecified,
        .is_generic = false,
        .is_var_args = false,
        .return_type = RetType(M),
        .params = params,
    } });
}

inline fn selfCast(Self: type, ptr: *anyopaque) Self {
    switch (@typeInfo(Self)) {
        .Pointer => {
            return @ptrCast(@alignCast(ptr));
        },
        else => {
            return @as(*Self, @ptrCast(@alignCast(ptr))).*;
        },
    }
}

inline fn methodPtr(method: anytype) *const MethodType(@TypeOf(method)) {
    const Fn = @typeInfo(@TypeOf(method)).Fn;
    const Ret = Fn.return_type.?;
    const Self = Fn.params[0].type.?;
    const Args = MethodArgs(@TypeOf(method));
    const inner = struct {
        fn meth(ptr: *anyopaque, args: Args) Ret {
            const self = selfCast(Self, ptr);
            return @call(.auto, method, .{self} ++ args);
        }
    };
    return &inner.meth;
}

// Method pointer taking args
//inline fn methodPtr(method: anytype) {
//}

// Create a vtable for a given implementation type
inline fn MakeVtable(Interface: type, Impl: type) VtableType(Interface) {
    const Vtable = VtableType(Interface);
    const fields = @typeInfo(Vtable).Struct.fields;
    comptime var vtable: Vtable = undefined;

    inline for (fields) |field| {
        @field(vtable, field.name) = methodPtr(@field(Impl, field.name));
    }

    return vtable;
}

// Cast an implementation pointer into an interface
pub inline fn make(Interface: type, value: anytype) Interface {
    const Impl = @typeInfo(@TypeOf(value)).Pointer.child;
    // TODO is this properly memoized?
    const vtable = MakeVtable(Interface, Impl);
    return Interface{
        .vtable = &vtable,
        .impl = value,
    };
}

// Generate the vtable type for an interface based on the interface's methods
inline fn VtableType(I: type) type {
    const decls = @typeInfo(I).Struct.decls;
    comptime var fields: []const Type.StructField = &.{};
    inline for (decls) |decl| {
        const FieldType = *const MethodType(@TypeOf(@field(I, decl.name)));
        fields = fields ++ .{.{ .name = decl.name, .type = FieldType, .default_value = null, .is_comptime = false, .alignment = @alignOf(FieldType) }};
    }
    return @Type(.{ .Struct = .{
        .layout = .auto,
        .fields = fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

// Cast an interface's opaque vtable pointer to the correct vtable type
inline fn getVtable(intfc: anytype) *const VtableType(@TypeOf(intfc)) {
    const Vtable = VtableType(@TypeOf(intfc));
    return @as(*const Vtable, @ptrCast(@alignCast(intfc.vtable)));
}

inline fn FieldEnum(I: type) type {
    return std.meta.FieldEnum(VtableType(I));
}

inline fn MethodReturnType(I: type, method: FieldEnum(I)) type {
    const Vtable = VtableType(I);
    const Child = @typeInfo(std.meta.FieldType(Vtable, method)).Pointer.child;
    return @typeInfo(Child).Fn.return_type.?;
}

pub inline fn call(intfc: anytype, method: FieldEnum(@TypeOf(intfc)), args: anytype) MethodReturnType(@TypeOf(intfc), method) {
    return @field(getVtable(intfc).*, @tagName(method))(intfc.impl, args);
}

pub inline fn maybeCast(T: type, intfc: anytype) ?T {
    const vtable = &MakeVtable(@TypeOf(intfc), T);
    if (intfc.vtable == @as(*const anyopaque, @ptrCast(@alignCast(vtable)))) {
        return selfCast(T, intfc.impl);
    } else {
        return null;
    }
}

test make {
    const FooInterface = struct {
        pub fn foo(self: @This(), x: i32, y: i32) i32 {
            return call(self, .foo, .{ x, y });
        }

        pub fn incr(self: @This(), x: i32) void {
            return call(self, .incr, .{x});
        }

        vtable: *const anyopaque,
        impl: *anyopaque,
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

    const bar = make(FooInterface, &fooImpl);

    try std.testing.expect(bar.foo(6, 7) == 18);
}

test maybeCast {
    const FooInterface = struct {
        pub fn foo(self: @This()) i32 {
            return call(self, .foo, .{});
        }

        vtable: *const anyopaque,
        impl: *anyopaque,
    };

    const FooImpl = struct {
        x: i32,
        pub fn foo(self: @This()) i32 {
            return self.x;
        }
    };

    const BarImpl = struct {
        pub fn foo(_: @This()) i32 {
            return 5;
        }
    };

    var fooImpl = FooImpl{ .x = 1 };
    const foo = make(FooInterface, &fooImpl);
    try std.testing.expect(maybeCast(BarImpl, foo) == null);
    try std.testing.expect(maybeCast(FooImpl, foo) != null);
}