# webgpu_zig

Auto-generated Zig bindings for [webgpu.h](https://github.com/webgpu-native/webgpu-headers).

## Features and stuff

- auto-generated from the official `webgpu-headers` spec.
- **blazingly thin** wrappers.
- **Zero-cost abstractions**[^1] on top of the raw C API.
- **zig in the frontend, rust in the backend for more brrrrr**[^2]
- sync helpers like `requestAdapterSync`, `requestDeviceSync`, etc. because async GPU APIs are annoying
- optional backends: [wgpu-native](https://github.com/gfx-rs/wgpu-native) or [WGVK](https://github.com/shreyassanthu77/WGVK)
- works on linux, windows, macos, ios, android

## Usage
slightly different from regular Zig packages [^3]

add this in `build.zig.zon`:

```zig
.{
    .dependencies = .{
        .webgpu_zig = .{
            .url = "git+https://github.com/shreyassanthu77/webgpu_zig.git#<commit-or-tag>",
            .hash = "<hash>",
        },
    },
}
```

or do

```bash
zig fetch --save git+https://github.com/shreyassanthu77/webgpu_zig.git@<commit-or-tag> # or just omit @tag if you want the latest
```

in your `build.zig`:

```zig
const webgpu = @import("webgpu_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const webgpu_mod = webgpu.buildWebgpu(b, .{
        .target = target,
        .optimize = optimize,
        .backend = .wgpu_native, // or .wgvk, .none
    });

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("webgpu", webgpu_mod);

    b.installArtifact(exe);
}
```

then in your code:

```zig
const webgpu = @import("webgpu");
```

## basic example

```zig
const std = @import("std");
const webgpu = @import("webgpu");

pub fn main() !void {
    const instance = webgpu.createInstance(&.{});
    defer instance.release();

    const adapter = try (try instance.requestAdapterSync(&.{})).unwrap();
    defer adapter.release();

    const device = try (try adapter.requestDeviceSync(instance, &.{})).unwrap();
    defer device.release();

    const queue = device.getQueue();
    defer queue.release();

    // ... buffers, pipelines, command encoders, whatever
}
```

## so how is this different from raw webgpu.h?

### Real enums

unsigned integer constants in C API are replaced with typed zig enums.

```zig
const adapter_type: webgpu.AdapterType = .discrete_GPU;
```

### bitflags are structs with bools

In C you OR together untyped integer constants like `WGPUBufferUsage_VERTEX | WGPUBufferUsage_UNIFORM`. Here, flags are `packed struct(u64)` values with named `bool` fields:

```zig
const usage = webgpu.BufferUsage{
    .vertex = true,
    .uniform = true,
};
```

The memory layout is identical to the C bitflags, so ABI compatibility is preserved.

### bools and slices just work (**in functions only**)

Zig types are converted to the underlying C representation automatically. `bool` fields in descriptors map to the internal `Bool`/`OptionalBool` types, and functions that take a raw pointer + length in C accept Zig slices here.

```zig
queue.writeBuffer(buffer, 0, my_data); // my_data: []const u8
```

This is equivalent to calling `wgpuQueueWriteBuffer(instance, buffer, 0, my_data.ptr, my_data.len)`.

### structs stay C-compatible

All descriptor and data structs are `extern struct` and match the memory layout of `webgpu.h` exactly. You can pass them to C code or mix them with hand-written C interop without worrying about layout. ABI tests verify this. The Zig-specific improvements only affect function wrappers and non-layout fields.

### String helpers

The C API uses `WGPUStringView`, a `{ ptr, len }` pair. The bindings expose this as `webgpu.String`:

```zig
const s = webgpu.String.from("hello");
const str = s.into(); // []const u8
```

`String.NULL` represents the null/empty sentinel. Wrapper functions that take a label accept `[]const u8` directly, so you usually don't need to construct `String` values yourself.

### Result and sync helpers

WebGPU's async operations are callback-based. The bindings provide blocking `*Sync` wrappers that call `instance.waitAny` internally and return a `Result`:

```zig
const result = try instance.requestAdapterSync(&.{});
const adapter = try result.unwrap();
```

`Result(Status, Payload)` is a union of `.ok` with the payload, or `.err` with a status and message. `unwrap()` returns the payload or `error.WebGpuFailed`. Error messages are copied into a thread-local buffer, so they remain valid after the call returns.

The raw async methods (`requestAdapter`, `requestDevice`, etc.) are still available if you prefer callbacks.

## chained struct helpers

WebGPU uses extension structs chained through `nextInChain`, each tagged with an `sType`. Instead of building that chain by hand, extension structs provide helper methods that return the parent descriptor with the chain already attached.

For example, creating a shader module from WGSL:

```zig
const shader_source = webgpu.ShaderSourceWGSL{
    .code = .from(@embedFile("shader.wgsl")),
};
const shader = device.createShaderModule(&shader_source.shaderModuleDescriptor());
```

Or creating a Windows surface:

```zig
const surface_source = webgpu.SurfaceSourceWindowsHWND{
    .hwnd = my_hwnd,
    .hinstance = my_hinstance,
};
const surface = instance.createSurface(&surface_source.surfaceDescriptor());
```

You can still construct chains manually when you need multiple extensions or special behavior, but these helpers handle the common single-extension case.

## backends

| backend        | what it does |
| -------------- | ------------ |
| `none`         | bindings only, no native lib linked |
| `wgpu_native`  | links prebuilt wgpu-native binaries |
| `wgvk`         | links my WGVK vulkan backend |

## local dev commands

only if you're hacking on this repo itself. consumers should use the dep setup above.

```bash
# run tests, needs a backend for ABI tests
zig build test -Dbackend=wgpu_native

# regenerate src/bindings.zig from webgpu.json
zig build gen

# generate docs
zig build docs
```

## license

MIT

---

[^1]: lol, there's no such thing btw
[^2]: only if you want, you are free to use WGVK or link your own WGPU backend ig? idk
[^3]: you can still use the regular b.dependency thing, but because of how zig lazy dependencies work,
    you'll end up with more dependencies downloaded than you actually need. But  if you like that way you can do:
    ```zig
    pub fn build(b: *std.Build) void {
        // ... other stuff
        const webgpu_dep = b.dependency("webgpu_zig", .{
            .target = target,
            .optimize = optimize,
            .backend = .wgpu_native, // or .wgvk, .none
        });
        const webgpu_mod = webgpu_dep.module("webgpu");

        const exe = b.addExecutable(.{
            .name = "my-app",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        exe.root_module.addImport("webgpu", webgpu_mod);

        b.installArtifact(exe);
    }
    ```

