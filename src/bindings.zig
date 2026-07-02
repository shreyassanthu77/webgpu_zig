const std = @import("std");

pub const String = extern struct {
    data: ?[*]const u8,
    length: usize,

    /// The null string view (`{ NULL, 0 }`), matching a zero-initialized
    /// `WGPUStringView`. Distinct from an empty-but-non-null string.
    pub const NULL: String = .{ .data = null, .length = 0 };

    pub fn from(str: []const u8) String {
        return String{
            .data = str.ptr,
            .length = str.len,
        };
    }

    pub fn into(self: String) []const u8 {
        const data = self.data orelse return "";
        if (self.length == 0) return "";
        // WGPU_STRLEN: the view is null-terminated instead of length-delimited.
        if (self.length == std.math.maxInt(usize))
            return std.mem.span(@as([*:0]const u8, @ptrCast(data)));
        return data[0..self.length];
    }
};

pub const Bool = enum(u32) {
    false = 0,
    true = 1,

    /// Converts a `bool` to a `Bool`
    pub fn from(value: bool) Bool {
        return @enumFromInt(@intFromBool(value));
    }

    /// Converts a `Bool` to a `bool`
    pub fn into(self: Bool) bool {
        return self == .true;
    }

    /// Converts a `Bool` to a `Bool.Optional`
    pub fn optional(self: Bool) Optional {
        return @enumFromInt(@intFromEnum(self));
    }

    pub const Optional = enum(u32) {
        false = 0,
        true = 1,
        undefined = 2,

        /// Converts a `?bool` to a `Bool.Optional`
        pub fn from(value: ?bool) Optional {
            return if (value) |v|
                @enumFromInt(@intFromBool(v))
            else
                .undefined;
        }

        /// Converts a `Bool.Optional` to a `?bool`
        pub fn into(self: Optional) ?bool {
            if (self == .undefined) return null;
            return self == .true;
        }

        /// **UNSAFE** in ReleaseFast builds
        /// Converts a `Bool.Optional` to a `bool`
        /// assumes that the value is not `.undefined`
        pub fn assert(self: Optional) bool {
            std.debug.assert(self != .undefined);
            return self == .true;
        }

        /// Converts a Bool.Optional to a `Bool`
        /// returns false if the value is `.undefined`
        pub fn truthy(self: Optional) bool {
            return self == .true;
        }
    };
};

/// Result of a synchronous (`...Sync`) wrapper around an async webgpu operation.
/// `ok` holds the operation's payload; `err` holds the failing status and its
/// message. Wait failures (from `waitAny`) are reported via the outer
/// `error{WaitFailed}` on the `...Sync` function, not here.
pub fn Result(comptime Stat: type, comptime Payload: type) type {
    return union(enum) {
        ok: Payload,
        err: struct { status: Stat, message: []const u8 },

        /// Returns the payload on success, or `error.WebGpuFailed` otherwise.
        /// Use a `switch` on the union directly if you need the status/message.
        pub fn unwrap(self: @This()) error{WebGpuFailed}!Payload {
            return switch (self) {
                .ok => |v| v,
                .err => error.WebGpuFailed,
            };
        }
    };
}

/// Copies a callback message (only valid during the callback) into a
/// thread-local buffer so it can outlive the callback. The returned slice is
/// valid until the next `...Sync` call on the same thread.
threadlocal var sync_msg_buf: [1024]u8 = undefined;
pub fn copyMessage(s: String) []const u8 {
    const src = s.into();
    const n = @min(src.len, sync_msg_buf.len);
    @memcpy(sync_msg_buf[0..n], src[0..n]);
    return sync_msg_buf[0..n];
}

pub const Proc = *const fn () callconv(.c) void;

extern fn wgpuGetProcAddress(procName: String) ?Proc;
/// Returns null if `procName` is not recognized.
pub fn getProcAddress(procName: []const u8) ?Proc {
    return wgpuGetProcAddress(String.from(procName));
}

/// Indicates no array layer count is specified. For more info,
/// see @ref SentinelValues and the places that use this sentinel value.
pub const array_layer_count_undefined = std.math.maxInt(u32);

/// Indicates no copy stride is specified. For more info,
/// see @ref SentinelValues and the places that use this sentinel value.
pub const copy_stride_undefined = std.math.maxInt(u32);

/// Indicates no depth clear value is specified. For more info,
/// see @ref SentinelValues and the places that use this sentinel value.
pub const depth_clear_value_undefined = std.math.nan(f32);

/// Indicates no depth slice is specified. For more info,
/// see @ref SentinelValues and the places that use this sentinel value.
pub const depth_slice_undefined = std.math.maxInt(u32);

/// For `uint32_t` limits, indicates no limit value is specified. For more info,
/// see @ref SentinelValues and the places that use this sentinel value.
pub const limit_u32_undefined = std.math.maxInt(u32);

/// For `uint64_t` limits, indicates no limit value is specified. For more info,
/// see @ref SentinelValues and the places that use this sentinel value.
pub const limit_u64_undefined = std.math.maxInt(u64);

/// Indicates no mip level count is specified. For more info,
/// see @ref SentinelValues and the places that use this sentinel value.
pub const mip_level_count_undefined = std.math.maxInt(u32);

/// Indicates no query set index is specified. For more info,
/// see @ref SentinelValues and the places that use this sentinel value.
pub const query_set_index_undefined = std.math.maxInt(u32);

/// Sentinel value used in @ref WGPUStringView to indicate that the pointer
/// is to a null-terminated string, rather than an explicitly-sized string.
pub const strlen = std.math.maxInt(usize);

/// Indicates a size extending to the end of the buffer. For more info,
/// see @ref SentinelValues and the places that use this sentinel value.
pub const whole_map_size = std.math.maxInt(usize);

/// Indicates a size extending to the end of the buffer. For more info,
/// see @ref SentinelValues and the places that use this sentinel value.
pub const whole_size = std.math.maxInt(u64);

pub const BufferUsage = packed struct(u64) {
    /// The buffer can be *mapped* on the CPU side in *read* mode (using @ref WGPUMapMode_Read).
    map_read: bool = false,
    /// The buffer can be *mapped* on the CPU side in *write* mode (using @ref WGPUMapMode_Write).
    /// 
    /// @note This usage is **not** required to set `mappedAtCreation` to `true` in @ref WGPUBufferDescriptor.
    map_write: bool = false,
    /// The buffer can be used as the *source* of a GPU-side copy operation.
    copy_src: bool = false,
    /// The buffer can be used as the *destination* of a GPU-side copy operation.
    copy_dst: bool = false,
    /// The buffer can be used as an Index buffer when doing indexed drawing in a render pipeline.
    index: bool = false,
    /// The buffer can be used as a Vertex buffer when using a render pipeline.
    vertex: bool = false,
    /// The buffer can be bound to a shader as a uniform buffer.
    uniform: bool = false,
    /// The buffer can be bound to a shader as a storage buffer.
    storage: bool = false,
    /// The buffer can store arguments for an indirect draw call.
    indirect: bool = false,
    /// The buffer can store the result of a timestamp or occlusion query.
    query_resolve: bool = false,
    _: u54 = 0,

    pub const none: @This() = .{};
};

pub const ColorWriteMask = packed struct(u64) {
    red: bool = false,
    green: bool = false,
    blue: bool = false,
    alpha: bool = false,
    _: u60 = 0,

    pub const none: @This() = .{};
    pub const all: @This() = .{
        .red = true,
        .green = true,
        .blue = true,
        .alpha = true,
    };
};

pub const MapMode = packed struct(u64) {
    read: bool = false,
    write: bool = false,
    _: u62 = 0,

    pub const none: @This() = .{};
};

pub const ShaderStage = packed struct(u64) {
    vertex: bool = false,
    fragment: bool = false,
    compute: bool = false,
    _: u61 = 0,

    pub const none: @This() = .{};
};

pub const TextureUsage = packed struct(u64) {
    copy_src: bool = false,
    copy_dst: bool = false,
    texture_binding: bool = false,
    storage_binding: bool = false,
    render_attachment: bool = false,
    transient_attachment: bool = false,
    _: u58 = 0,

    pub const none: @This() = .{};
};

pub const AdapterType = enum(u32) {
    discrete_GPU = 0x00000001,
    integrated_GPU = 0x00000002,
    CPU = 0x00000003,
    unknown = 0x00000004,
    _,
};

pub const AddressMode = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    clamp_to_edge = 0x00000001,
    repeat = 0x00000002,
    mirror_repeat = 0x00000003,
    _,
};

pub const BackendType = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    @"null" = 0x00000001,
    WebGPU = 0x00000002,
    D3D11 = 0x00000003,
    D3D12 = 0x00000004,
    metal = 0x00000005,
    vulkan = 0x00000006,
    openGL = 0x00000007,
    openGLES = 0x00000008,
    _,
};

pub const BlendFactor = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    zero = 0x00000001,
    one = 0x00000002,
    src = 0x00000003,
    one_minus_src = 0x00000004,
    src_alpha = 0x00000005,
    one_minus_src_alpha = 0x00000006,
    dst = 0x00000007,
    one_minus_dst = 0x00000008,
    dst_alpha = 0x00000009,
    one_minus_dst_alpha = 0x0000000a,
    src_alpha_saturated = 0x0000000b,
    constant = 0x0000000c,
    one_minus_constant = 0x0000000d,
    src1 = 0x0000000e,
    one_minus_src1 = 0x0000000f,
    src1_alpha = 0x00000010,
    one_minus_src1_alpha = 0x00000011,
    _,
};

pub const BlendOperation = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    add = 0x00000001,
    subtract = 0x00000002,
    reverse_subtract = 0x00000003,
    min = 0x00000004,
    max = 0x00000005,
    _,
};

pub const BufferBindingType = enum(u32) {
    /// Indicates that this @ref WGPUBufferBindingLayout member of
    /// its parent @ref WGPUBindGroupLayoutEntry is not used.
    /// (See also @ref SentinelValues.)
    binding_not_used = 0x00000000,
    /// `1`. Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000001,
    uniform = 0x00000002,
    storage = 0x00000003,
    read_only_storage = 0x00000004,
    _,
};

pub const BufferMapState = enum(u32) {
    unmapped = 0x00000001,
    pending = 0x00000002,
    mapped = 0x00000003,
    _,
};

/// The callback mode controls how a callback for an asynchronous operation may be fired. See @ref Asynchronous-Operations for how these are used.
pub const CallbackMode = enum(u32) {
    /// Callbacks created with `WGPUCallbackMode_WaitAnyOnly`:
    /// - fire when the asynchronous operation's future is passed to a call to @ref wgpuInstanceWaitAny
    ///   AND the operation has already completed or it completes inside the call to @ref wgpuInstanceWaitAny.
    wait_any_only = 0x00000001,
    /// Callbacks created with `WGPUCallbackMode_AllowProcessEvents`:
    /// - fire for the same reasons as callbacks created with `WGPUCallbackMode_WaitAnyOnly`
    /// - fire inside a call to @ref wgpuInstanceProcessEvents if the asynchronous operation is complete.
    allow_process_events = 0x00000002,
    /// Callbacks created with `WGPUCallbackMode_AllowSpontaneous`:
    /// - fire for the same reasons as callbacks created with `WGPUCallbackMode_AllowProcessEvents`
    /// - **may** fire spontaneously on an arbitrary or application thread, when the WebGPU implementations discovers that the asynchronous operation is complete.
    /// 
    ///   Implementations _should_ fire spontaneous callbacks as soon as possible.
    /// 
    /// @note Because spontaneous callbacks may fire at an arbitrary time on an arbitrary thread, applications should take extra care when acquiring locks or mutating state inside the callback. It undefined behavior to re-entrantly call into the webgpu.h API if the callback fires while inside the callstack of another webgpu.h function that is not `wgpuInstanceWaitAny` or `wgpuInstanceProcessEvents`.
    allow_spontaneous = 0x00000003,
    _,
};

pub const CompareFunction = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    never = 0x00000001,
    less = 0x00000002,
    equal = 0x00000003,
    less_equal = 0x00000004,
    greater = 0x00000005,
    not_equal = 0x00000006,
    greater_equal = 0x00000007,
    always = 0x00000008,
    _,
};

pub const CompilationInfoRequestStatus = enum(u32) {
    success = 0x00000001,
    /// See @ref CallbackStatuses.
    callback_cancelled = 0x00000002,
    _,
};

pub const CompilationMessageType = enum(u32) {
    @"error" = 0x00000001,
    warning = 0x00000002,
    info = 0x00000003,
    _,
};

pub const ComponentSwizzle = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    /// Force its value to 0.
    zero = 0x00000001,
    /// Force its value to 1.
    one = 0x00000002,
    /// Take its value from the red channel of the texture.
    r = 0x00000003,
    /// Take its value from the green channel of the texture.
    g = 0x00000004,
    /// Take its value from the blue channel of the texture.
    b = 0x00000005,
    /// Take its value from the alpha channel of the texture.
    a = 0x00000006,
    _,
};

/// Describes how frames are composited with other contents on the screen when @ref wgpuSurfacePresent is called.
pub const CompositeAlphaMode = enum(u32) {
    /// Lets the WebGPU implementation choose the best mode (supported, and with the best performance) between @ref WGPUCompositeAlphaMode_Opaque or @ref WGPUCompositeAlphaMode_Inherit.
    auto = 0x00000000,
    /// The alpha component of the image is ignored and teated as if it is always 1.0.
    @"opaque" = 0x00000001,
    /// The alpha component is respected and non-alpha components are assumed to be already multiplied with the alpha component. For example, (0.5, 0, 0, 0.5) is semi-transparent bright red.
    premultiplied = 0x00000002,
    /// The alpha component is respected and non-alpha components are assumed to NOT be already multiplied with the alpha component. For example, (1.0, 0, 0, 0.5) is semi-transparent bright red.
    unpremultiplied = 0x00000003,
    /// The handling of the alpha component is unknown to WebGPU and should be handled by the application using system-specific APIs. This mode may be unavailable (for example on Wasm).
    inherit = 0x00000004,
    _,
};

pub const CreatePipelineAsyncStatus = enum(u32) {
    success = 0x00000001,
    /// See @ref CallbackStatuses.
    callback_cancelled = 0x00000002,
    validation_error = 0x00000003,
    internal_error = 0x00000004,
    _,
};

pub const CullMode = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    none = 0x00000001,
    front = 0x00000002,
    back = 0x00000003,
    _,
};

pub const DeviceLostReason = enum(u32) {
    unknown = 0x00000001,
    destroyed = 0x00000002,
    /// See @ref CallbackStatuses.
    callback_cancelled = 0x00000003,
    failed_creation = 0x00000004,
    _,
};

pub const ErrorFilter = enum(u32) {
    validation = 0x00000001,
    out_of_memory = 0x00000002,
    internal = 0x00000003,
    _,
};

pub const ErrorType = enum(u32) {
    no_error = 0x00000001,
    validation = 0x00000002,
    out_of_memory = 0x00000003,
    internal = 0x00000004,
    unknown = 0x00000005,
    _,
};

/// See @ref WGPURequestAdapterOptions::featureLevel.
pub const FeatureLevel = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    /// "Compatibility" profile which can be supported on OpenGL ES 3.1 and D3D11.
    compatibility = 0x00000001,
    /// "Core" profile which can be supported on Vulkan/Metal/D3D12 (at least).
    core = 0x00000002,
    _,
};

pub const FeatureName = enum(u32) {
    core_features_and_limits = 0x00000001,
    depth_clip_control = 0x00000002,
    depth32_float_stencil8 = 0x00000003,
    texture_compression_BC = 0x00000004,
    texture_compression_BC_sliced_3D = 0x00000005,
    texture_compression_ETC2 = 0x00000006,
    texture_compression_ASTC = 0x00000007,
    texture_compression_ASTC_sliced_3D = 0x00000008,
    timestamp_query = 0x00000009,
    indirect_first_instance = 0x0000000a,
    shader_f16 = 0x0000000b,
    RG11B10_ufloat_renderable = 0x0000000c,
    BGRA8_unorm_storage = 0x0000000d,
    float32_filterable = 0x0000000e,
    float32_blendable = 0x0000000f,
    clip_distances = 0x00000010,
    dual_source_blending = 0x00000011,
    subgroups = 0x00000012,
    texture_formats_tier_1 = 0x00000013,
    texture_formats_tier_2 = 0x00000014,
    primitive_index = 0x00000015,
    texture_component_swizzle = 0x00000016,
    subgroup_size_control = 0x00000017,
    _,
};

pub const FilterMode = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    nearest = 0x00000001,
    linear = 0x00000002,
    _,
};

pub const FrontFace = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    CCW = 0x00000001,
    CW = 0x00000002,
    _,
};

pub const IndexFormat = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    uint16 = 0x00000001,
    uint32 = 0x00000002,
    _,
};

pub const InstanceFeatureName = enum(u32) {
    /// Enable use of ::wgpuInstanceWaitAny with `timeoutNS > 0`.
    timed_wait_any = 0x00000001,
    /// Enable passing SPIR-V shaders to @ref wgpuDeviceCreateShaderModule,
    /// via @ref WGPUShaderSourceSPIRV.
    shader_source_SPIRV = 0x00000002,
    /// Normally, a @ref WGPUAdapter can only create a single device. If this is
    /// available and enabled, then adapters won't immediately expire when they
    /// create a device, so can be reused to make multiple devices. They may
    /// still expire for other reasons.
    multiple_devices_per_adapter = 0x00000003,
    _,
};

pub const LoadOp = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    load = 0x00000001,
    clear = 0x00000002,
    _,
};

pub const MapAsyncStatus = enum(u32) {
    success = 0x00000001,
    /// See @ref CallbackStatuses.
    callback_cancelled = 0x00000002,
    @"error" = 0x00000003,
    aborted = 0x00000004,
    _,
};

pub const MipmapFilterMode = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    nearest = 0x00000001,
    linear = 0x00000002,
    _,
};

pub const PopErrorScopeStatus = enum(u32) {
    /// The error scope stack was successfully popped and a result was reported.
    success = 0x00000001,
    /// See @ref CallbackStatuses.
    callback_cancelled = 0x00000002,
    /// The error scope stack could not be popped, because it was empty.
    @"error" = 0x00000003,
    _,
};

pub const PowerPreference = enum(u32) {
    /// No preference. (See also @ref SentinelValues.)
    undefined = 0x00000000,
    low_power = 0x00000001,
    high_performance = 0x00000002,
    _,
};

pub const PredefinedColorSpace = enum(u32) {
    SRGB = 0x00000001,
    display_p3 = 0x00000002,
    _,
};

/// Describes when and in which order frames are presented on the screen when @ref wgpuSurfacePresent is called.
pub const PresentMode = enum(u32) {
    /// Present mode is not specified. Use the default.
    undefined = 0x00000000,
    /// The presentation of the image to the user waits for the next vertical blanking period to update in a first-in, first-out manner.
    /// Tearing cannot be observed and frame-loop will be limited to the display's refresh rate.
    /// This is the only mode that's always available.
    fifo = 0x00000001,
    /// The presentation of the image to the user tries to wait for the next vertical blanking period but may decide to not wait if a frame is presented late.
    /// Tearing can sometimes be observed but late-frame don't produce a full-frame stutter in the presentation.
    /// This is still a first-in, first-out mechanism so a frame-loop will be limited to the display's refresh rate.
    fifo_relaxed = 0x00000002,
    /// The presentation of the image to the user is updated immediately without waiting for a vertical blank.
    /// Tearing can be observed but latency is minimized.
    immediate = 0x00000003,
    /// The presentation of the image to the user waits for the next vertical blanking period to update to the latest provided image.
    /// Tearing cannot be observed and a frame-loop is not limited to the display's refresh rate.
    mailbox = 0x00000004,
    _,
};

pub const PrimitiveTopology = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    point_list = 0x00000001,
    line_list = 0x00000002,
    line_strip = 0x00000003,
    triangle_list = 0x00000004,
    triangle_strip = 0x00000005,
    _,
};

pub const QueryType = enum(u32) {
    occlusion = 0x00000001,
    timestamp = 0x00000002,
    _,
};

pub const QueueWorkDoneStatus = enum(u32) {
    success = 0x00000001,
    /// See @ref CallbackStatuses.
    callback_cancelled = 0x00000002,
    /// There was some deterministic error. (Note this is currently never used,
    /// but it will be relevant when it's possible to create a queue object.)
    @"error" = 0x00000003,
    _,
};

pub const RequestAdapterStatus = enum(u32) {
    success = 0x00000001,
    /// See @ref CallbackStatuses.
    callback_cancelled = 0x00000002,
    unavailable = 0x00000003,
    @"error" = 0x00000004,
    _,
};

pub const RequestDeviceStatus = enum(u32) {
    success = 0x00000001,
    /// See @ref CallbackStatuses.
    callback_cancelled = 0x00000002,
    @"error" = 0x00000003,
    _,
};

pub const SType = enum(u32) {
    shader_source_SPIRV = 0x00000001,
    shader_source_WGSL = 0x00000002,
    render_pass_max_draw_count = 0x00000003,
    surface_source_metal_layer = 0x00000004,
    surface_source_windows_HWND = 0x00000005,
    surface_source_xlib_window = 0x00000006,
    surface_source_wayland_surface = 0x00000007,
    surface_source_android_native_window = 0x00000008,
    surface_source_XCB_window = 0x00000009,
    surface_color_management = 0x0000000a,
    request_adapter_WebXR_options = 0x0000000b,
    texture_component_swizzle_descriptor = 0x0000000c,
    external_texture_binding_layout = 0x0000000d,
    external_texture_binding_entry = 0x0000000e,
    compatibility_mode_limits = 0x0000000f,
    texture_binding_view_dimension = 0x00000010,
    _,
};

pub const SamplerBindingType = enum(u32) {
    /// Indicates that this @ref WGPUSamplerBindingLayout member of
    /// its parent @ref WGPUBindGroupLayoutEntry is not used.
    /// (See also @ref SentinelValues.)
    binding_not_used = 0x00000000,
    /// `1`. Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000001,
    filtering = 0x00000002,
    non_filtering = 0x00000003,
    comparison = 0x00000004,
    _,
};

/// Status code returned (synchronously) from many operations. Generally
/// indicates an invalid input like an unknown enum value or @ref OutStructChainError.
/// Read the function's documentation for specific error conditions.
pub const Status = enum(u32) {
    success = 0x00000001,
    @"error" = 0x00000002,
    _,
};

pub const StencilOperation = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    keep = 0x00000001,
    zero = 0x00000002,
    replace = 0x00000003,
    invert = 0x00000004,
    increment_clamp = 0x00000005,
    decrement_clamp = 0x00000006,
    increment_wrap = 0x00000007,
    decrement_wrap = 0x00000008,
    _,
};

pub const StorageTextureAccess = enum(u32) {
    /// Indicates that this @ref WGPUStorageTextureBindingLayout member of
    /// its parent @ref WGPUBindGroupLayoutEntry is not used.
    /// (See also @ref SentinelValues.)
    binding_not_used = 0x00000000,
    /// `1`. Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000001,
    write_only = 0x00000002,
    read_only = 0x00000003,
    read_write = 0x00000004,
    _,
};

pub const StoreOp = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    store = 0x00000001,
    discard = 0x00000002,
    _,
};

/// The status enum for @ref wgpuSurfaceGetCurrentTexture.
pub const SurfaceGetCurrentTextureStatus = enum(u32) {
    /// Yay! Everything is good and we can render this frame.
    success_optimal = 0x00000001,
    /// Still OK - the surface can present the frame, but in a suboptimal way. The surface may need reconfiguration.
    success_suboptimal = 0x00000002,
    /// Some operation timed out while trying to acquire the frame.
    timeout = 0x00000003,
    /// The surface is too different to be used, compared to when it was originally created.
    outdated = 0x00000004,
    /// The connection to whatever owns the surface was lost, or generally needs to be fully reinitialized.
    lost = 0x00000005,
    /// There was some deterministic error (for example, the surface is not configured, or there was an @ref OutStructChainError). Should produce @ref ImplementationDefinedLogging containing details.
    @"error" = 0x00000006,
    _,
};

pub const TextureAspect = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    all = 0x00000001,
    stencil_only = 0x00000002,
    depth_only = 0x00000003,
    _,
};

pub const TextureDimension = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    @"1D" = 0x00000001,
    @"2D" = 0x00000002,
    @"3D" = 0x00000003,
    _,
};

pub const TextureFormat = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    R8_unorm = 0x00000001,
    R8_snorm = 0x00000002,
    R8_uint = 0x00000003,
    R8_sint = 0x00000004,
    R16_unorm = 0x00000005,
    R16_snorm = 0x00000006,
    R16_uint = 0x00000007,
    R16_sint = 0x00000008,
    R16_float = 0x00000009,
    RG8_unorm = 0x0000000a,
    RG8_snorm = 0x0000000b,
    RG8_uint = 0x0000000c,
    RG8_sint = 0x0000000d,
    R32_float = 0x0000000e,
    R32_uint = 0x0000000f,
    R32_sint = 0x00000010,
    RG16_unorm = 0x00000011,
    RG16_snorm = 0x00000012,
    RG16_uint = 0x00000013,
    RG16_sint = 0x00000014,
    RG16_float = 0x00000015,
    RGBA8_unorm = 0x00000016,
    RGBA8_unorm_srgb = 0x00000017,
    RGBA8_snorm = 0x00000018,
    RGBA8_uint = 0x00000019,
    RGBA8_sint = 0x0000001a,
    BGRA8_unorm = 0x0000001b,
    BGRA8_unorm_srgb = 0x0000001c,
    RGB10_A2_uint = 0x0000001d,
    RGB10_A2_unorm = 0x0000001e,
    RG11_B10_ufloat = 0x0000001f,
    RGB9_E5_ufloat = 0x00000020,
    RG32_float = 0x00000021,
    RG32_uint = 0x00000022,
    RG32_sint = 0x00000023,
    RGBA16_unorm = 0x00000024,
    RGBA16_snorm = 0x00000025,
    RGBA16_uint = 0x00000026,
    RGBA16_sint = 0x00000027,
    RGBA16_float = 0x00000028,
    RGBA32_float = 0x00000029,
    RGBA32_uint = 0x0000002a,
    RGBA32_sint = 0x0000002b,
    stencil8 = 0x0000002c,
    depth16_unorm = 0x0000002d,
    depth24_plus = 0x0000002e,
    depth24_plus_stencil8 = 0x0000002f,
    depth32_float = 0x00000030,
    depth32_float_stencil8 = 0x00000031,
    BC1_RGBA_unorm = 0x00000032,
    BC1_RGBA_unorm_srgb = 0x00000033,
    BC2_RGBA_unorm = 0x00000034,
    BC2_RGBA_unorm_srgb = 0x00000035,
    BC3_RGBA_unorm = 0x00000036,
    BC3_RGBA_unorm_srgb = 0x00000037,
    BC4_Runorm = 0x00000038,
    BC4_Rsnorm = 0x00000039,
    BC5_RG_unorm = 0x0000003a,
    BC5_RG_snorm = 0x0000003b,
    BC6H_RGB_ufloat = 0x0000003c,
    BC6H_RGB_float = 0x0000003d,
    BC7_RGBA_unorm = 0x0000003e,
    BC7_RGBA_unorm_srgb = 0x0000003f,
    ETC2_RGB8_unorm = 0x00000040,
    ETC2_RGB8_unorm_srgb = 0x00000041,
    ETC2_RGB8A1_unorm = 0x00000042,
    ETC2_RGB8A1_unorm_srgb = 0x00000043,
    ETC2_RGBA8_unorm = 0x00000044,
    ETC2_RGBA8_unorm_srgb = 0x00000045,
    EAC_R11_unorm = 0x00000046,
    EAC_R11_snorm = 0x00000047,
    EAC_RG11_unorm = 0x00000048,
    EAC_RG11_snorm = 0x00000049,
    ASTC_4x4_unorm = 0x0000004a,
    ASTC_4x4_unorm_srgb = 0x0000004b,
    ASTC_5x4_unorm = 0x0000004c,
    ASTC_5x4_unorm_srgb = 0x0000004d,
    ASTC_5x5_unorm = 0x0000004e,
    ASTC_5x5_unorm_srgb = 0x0000004f,
    ASTC_6x5_unorm = 0x00000050,
    ASTC_6x5_unorm_srgb = 0x00000051,
    ASTC_6x6_unorm = 0x00000052,
    ASTC_6x6_unorm_srgb = 0x00000053,
    ASTC_8x5_unorm = 0x00000054,
    ASTC_8x5_unorm_srgb = 0x00000055,
    ASTC_8x6_unorm = 0x00000056,
    ASTC_8x6_unorm_srgb = 0x00000057,
    ASTC_8x8_unorm = 0x00000058,
    ASTC_8x8_unorm_srgb = 0x00000059,
    ASTC_10x5_unorm = 0x0000005a,
    ASTC_10x5_unorm_srgb = 0x0000005b,
    ASTC_10x6_unorm = 0x0000005c,
    ASTC_10x6_unorm_srgb = 0x0000005d,
    ASTC_10x8_unorm = 0x0000005e,
    ASTC_10x8_unorm_srgb = 0x0000005f,
    ASTC_10x10_unorm = 0x00000060,
    ASTC_10x10_unorm_srgb = 0x00000061,
    ASTC_12x10_unorm = 0x00000062,
    ASTC_12x10_unorm_srgb = 0x00000063,
    ASTC_12x12_unorm = 0x00000064,
    ASTC_12x12_unorm_srgb = 0x00000065,
    _,
};

pub const TextureSampleType = enum(u32) {
    /// Indicates that this @ref WGPUTextureBindingLayout member of
    /// its parent @ref WGPUBindGroupLayoutEntry is not used.
    /// (See also @ref SentinelValues.)
    binding_not_used = 0x00000000,
    /// `1`. Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000001,
    float = 0x00000002,
    unfilterable_float = 0x00000003,
    depth = 0x00000004,
    sint = 0x00000005,
    uint = 0x00000006,
    _,
};

pub const TextureViewDimension = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    @"1D" = 0x00000001,
    @"2D" = 0x00000002,
    @"2D_array" = 0x00000003,
    cube = 0x00000004,
    cube_array = 0x00000005,
    @"3D" = 0x00000006,
    _,
};

pub const ToneMappingMode = enum(u32) {
    standard = 0x00000001,
    extended = 0x00000002,
    _,
};

pub const VertexFormat = enum(u32) {
    uint8 = 0x00000001,
    uint8x2 = 0x00000002,
    uint8x4 = 0x00000003,
    sint8 = 0x00000004,
    sint8x2 = 0x00000005,
    sint8x4 = 0x00000006,
    unorm8 = 0x00000007,
    unorm8x2 = 0x00000008,
    unorm8x4 = 0x00000009,
    snorm8 = 0x0000000a,
    snorm8x2 = 0x0000000b,
    snorm8x4 = 0x0000000c,
    uint16 = 0x0000000d,
    uint16x2 = 0x0000000e,
    uint16x4 = 0x0000000f,
    sint16 = 0x00000010,
    sint16x2 = 0x00000011,
    sint16x4 = 0x00000012,
    unorm16 = 0x00000013,
    unorm16x2 = 0x00000014,
    unorm16x4 = 0x00000015,
    snorm16 = 0x00000016,
    snorm16x2 = 0x00000017,
    snorm16x4 = 0x00000018,
    float16 = 0x00000019,
    float16x2 = 0x0000001a,
    float16x4 = 0x0000001b,
    float32 = 0x0000001c,
    float32x2 = 0x0000001d,
    float32x3 = 0x0000001e,
    float32x4 = 0x0000001f,
    uint32 = 0x00000020,
    uint32x2 = 0x00000021,
    uint32x3 = 0x00000022,
    uint32x4 = 0x00000023,
    sint32 = 0x00000024,
    sint32x2 = 0x00000025,
    sint32x3 = 0x00000026,
    sint32x4 = 0x00000027,
    unorm10_10_10_2 = 0x00000028,
    unorm8x4_BGRA = 0x00000029,
    _,
};

pub const VertexStepMode = enum(u32) {
    /// Indicates no value is passed for this argument. See @ref SentinelValues.
    undefined = 0x00000000,
    vertex = 0x00000001,
    instance = 0x00000002,
    _,
};

/// Status returned from a call to ::wgpuInstanceWaitAny.
pub const WaitStatus = enum(u32) {
    /// At least one WGPUFuture completed successfully.
    success = 0x00000001,
    /// The wait operation succeeded, but no WGPUFutures completed within the timeout.
    timed_out = 0x00000002,
    /// The call was invalid for some reason (see @ref Wait-Any).
    /// Should produce @ref ImplementationDefinedLogging containing details.
    @"error" = 0x00000003,
    _,
};

pub const WGSLLanguageFeatureName = enum(u32) {
    readonly_and_readwrite_storage_textures = 0x00000001,
    packed4x8_integer_dot_product = 0x00000002,
    unrestricted_pointer_parameters = 0x00000003,
    pointer_composite_access = 0x00000004,
    uniform_buffer_standard_layout = 0x00000005,
    subgroup_id = 0x00000006,
    texture_and_sampler_let = 0x00000007,
    subgroup_uniformity = 0x00000008,
    texture_formats_tier1 = 0x00000009,
    linear_indexing = 0x0000000a,
    immediate_address_space = 0x0000000b,
    _,
};

pub const ChainedStruct = extern struct {
    next: ?*ChainedStruct = null,
    s_type: SType,
};

pub const BufferMapCallback = *const fn (
    status: MapAsyncStatus,
    message: String,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.c) void;

pub const CompilationInfoCallback = *const fn (
    status: CompilationInfoRequestStatus,
    /// This argument contains multiple @ref ImplementationAllocatedStructChain roots.
    /// Arbitrary chains must be handled gracefully by the application!
    compilation_info: *const CompilationInfo,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.c) void;

pub const CreateComputePipelineAsyncCallback = *const fn (
    status: CreatePipelineAsyncStatus,
    pipeline: ?*ComputePipeline,
    message: String,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.c) void;

pub const CreateRenderPipelineAsyncCallback = *const fn (
    status: CreatePipelineAsyncStatus,
    pipeline: ?*RenderPipeline,
    message: String,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.c) void;

pub const DeviceLostCallback = *const fn (
    /// Pointer to the device which was lost. This is always a non-null pointer.
    /// The pointed-to @ref WGPUDevice will be null if, and only if, either:
    /// (1) The `reason` is @ref WGPUDeviceLostReason_FailedCreation.
    /// (2) The last ref of the device has been (or is being) released: see @ref DeviceRelease.
    device: *const ?*Device,
    /// An error code explaining why the device was lost.
    reason: DeviceLostReason,
    /// A @ref LocalizableHumanReadableMessageString describing why the device was lost.
    message: String,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.c) void;

pub const PopErrorScopeCallback = *const fn (
    /// See @ref WGPUPopErrorScopeStatus.
    status: PopErrorScopeStatus,
    /// The type of the error caught by the scope, or @ref WGPUErrorType_NoError if there was none.
    /// If the `status` is not @ref WGPUPopErrorScopeStatus_Success, this is @ref WGPUErrorType_NoError.
    type: ErrorType,
    /// If the `status` is not @ref WGPUPopErrorScopeStatus_Success **or**
    /// the `type` is not @ref WGPUErrorType_NoError, this is a non-empty
    /// @ref LocalizableHumanReadableMessageString;
    /// otherwise, this is an empty string.
    message: String,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.c) void;

pub const QueueWorkDoneCallback = *const fn (
    /// See @ref WGPUQueueWorkDoneStatus.
    status: QueueWorkDoneStatus,
    /// If the `status` is not @ref WGPUQueueWorkDoneStatus_Success,
    /// this is a non-empty @ref LocalizableHumanReadableMessageString;
    /// otherwise, this is an empty string.
    message: String,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.c) void;

pub const RequestAdapterCallback = *const fn (
    status: RequestAdapterStatus,
    adapter: ?*Adapter,
    message: String,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.c) void;

pub const RequestDeviceCallback = *const fn (
    status: RequestDeviceStatus,
    device: ?*Device,
    message: String,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.c) void;

pub const UncapturedErrorCallback = *const fn (
    device: *const ?*Device,
    type: ErrorType,
    message: String,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.c) void;

pub const BufferMapCallbackInfo = extern struct {
    next_in_chain: ?*ChainedStruct = null,
    mode: CallbackMode = .wait_any_only,
    callback: ?BufferMapCallback = null,
    userdata1: ?*anyopaque = null,
    userdata2: ?*anyopaque = null,
};

pub const CompilationInfoCallbackInfo = extern struct {
    next_in_chain: ?*ChainedStruct = null,
    mode: CallbackMode = .wait_any_only,
    callback: ?CompilationInfoCallback = null,
    userdata1: ?*anyopaque = null,
    userdata2: ?*anyopaque = null,
};

pub const CreateComputePipelineAsyncCallbackInfo = extern struct {
    next_in_chain: ?*ChainedStruct = null,
    mode: CallbackMode = .wait_any_only,
    callback: ?CreateComputePipelineAsyncCallback = null,
    userdata1: ?*anyopaque = null,
    userdata2: ?*anyopaque = null,
};

pub const CreateRenderPipelineAsyncCallbackInfo = extern struct {
    next_in_chain: ?*ChainedStruct = null,
    mode: CallbackMode = .wait_any_only,
    callback: ?CreateRenderPipelineAsyncCallback = null,
    userdata1: ?*anyopaque = null,
    userdata2: ?*anyopaque = null,
};

pub const DeviceLostCallbackInfo = extern struct {
    next_in_chain: ?*ChainedStruct = null,
    mode: CallbackMode = .wait_any_only,
    callback: ?DeviceLostCallback = null,
    userdata1: ?*anyopaque = null,
    userdata2: ?*anyopaque = null,
};

pub const PopErrorScopeCallbackInfo = extern struct {
    next_in_chain: ?*ChainedStruct = null,
    mode: CallbackMode = .wait_any_only,
    callback: ?PopErrorScopeCallback = null,
    userdata1: ?*anyopaque = null,
    userdata2: ?*anyopaque = null,
};

pub const QueueWorkDoneCallbackInfo = extern struct {
    next_in_chain: ?*ChainedStruct = null,
    mode: CallbackMode = .wait_any_only,
    callback: ?QueueWorkDoneCallback = null,
    userdata1: ?*anyopaque = null,
    userdata2: ?*anyopaque = null,
};

pub const RequestAdapterCallbackInfo = extern struct {
    next_in_chain: ?*ChainedStruct = null,
    mode: CallbackMode = .wait_any_only,
    callback: ?RequestAdapterCallback = null,
    userdata1: ?*anyopaque = null,
    userdata2: ?*anyopaque = null,
};

pub const RequestDeviceCallbackInfo = extern struct {
    next_in_chain: ?*ChainedStruct = null,
    mode: CallbackMode = .wait_any_only,
    callback: ?RequestDeviceCallback = null,
    userdata1: ?*anyopaque = null,
    userdata2: ?*anyopaque = null,
};

pub const UncapturedErrorCallbackInfo = extern struct {
    next_in_chain: ?*ChainedStruct = null,
    callback: ?UncapturedErrorCallback = null,
    userdata1: ?*anyopaque = null,
    userdata2: ?*anyopaque = null,
};

pub const AdapterInfo = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    vendor: String = String.NULL,
    architecture: String = String.NULL,
    device: String = String.NULL,
    description: String = String.NULL,
    backend_type: BackendType = .undefined,
    adapter_type: AdapterType,
    vendor_ID: u32 = 0,
    device_ID: u32 = 0,
    subgroup_min_size: u32 = 0,
    subgroup_max_size: u32 = 0,

    extern fn wgpuAdapterInfoFreeMembers(self: @This()) void;
    pub const free = wgpuAdapterInfoFreeMembers;
};

pub const BindGroupDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    layout: *BindGroupLayout,
    entries_count: usize = 0,
    entries: ?[*]const BindGroupEntry = null,
};

pub const BindGroupEntry = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// Binding index in the bind group.
    binding: u32 = 0,
    /// Set this if the binding is a buffer object.
    /// Otherwise must be null.
    buffer: ?*Buffer = null,
    /// If the binding is a buffer, this is the byte offset of the binding range.
    /// Otherwise ignored.
    offset: u64 = 0,
    /// If the binding is a buffer, this is the byte size of the binding range
    /// (@ref WGPU_WHOLE_SIZE means the binding ends at the end of the buffer).
    /// Otherwise ignored.
    size: u64 = whole_size,
    /// Set this if the binding is a sampler object.
    /// Otherwise must be null.
    sampler: ?*Sampler = null,
    /// Set this if the binding is a texture view object.
    /// Otherwise must be null.
    texture_view: ?*TextureView = null,
};

pub const BindGroupLayoutDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    entries_count: usize = 0,
    entries: ?[*]const BindGroupLayoutEntry = null,
};

pub const BindGroupLayoutEntry = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    binding: u32 = 0,
    visibility: ShaderStage = .{},
    /// If non-zero, this entry defines a binding array with this size.
    binding_array_size: u32 = 0,
    buffer: BufferBindingLayout = std.mem.zeroes(BufferBindingLayout),
    sampler: SamplerBindingLayout = std.mem.zeroes(SamplerBindingLayout),
    texture: TextureBindingLayout = std.mem.zeroes(TextureBindingLayout),
    storage_texture: StorageTextureBindingLayout = std.mem.zeroes(StorageTextureBindingLayout),
};

pub const BlendComponent = extern struct {
    /// If set to @ref WGPUBlendOperation_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUBlendOperation_Add.
    operation: BlendOperation = .undefined,
    /// If set to @ref WGPUBlendFactor_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUBlendFactor_One.
    src_factor: BlendFactor = .undefined,
    /// If set to @ref WGPUBlendFactor_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUBlendFactor_Zero.
    dst_factor: BlendFactor = .undefined,
};

pub const BlendState = extern struct {
    color: BlendComponent = .{},
    alpha: BlendComponent = .{},
};

pub const BufferBindingLayout = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// If set to @ref WGPUBufferBindingType_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUBufferBindingType_Uniform.
    type: BufferBindingType = .undefined,
    has_dynamic_offset: Bool = Bool.false,
    min_binding_size: u64 = 0,
};

pub const BufferDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    usage: BufferUsage = .{},
    size: u64 = 0,
    /// When true, the buffer is mapped in write mode at creation. It should thus be unmapped once its initial data has been written.
    /// 
    /// @note Mapping at creation does **not** require the usage @ref WGPUBufferUsage_MapWrite.
    mapped_at_creation: Bool = Bool.false,
};

/// An RGBA color. Represents a `f32`, `i32`, or `u32` color using @ref DoubleAsSupertype.
/// 
/// If any channel is non-finite, produces a @ref NonFiniteFloatValueError.
pub const Color = extern struct {
    r: f64 = 0,
    g: f64 = 0,
    b: f64 = 0,
    a: f64 = 0,
};

pub const ColorTargetState = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// The texture format of the target. If @ref WGPUTextureFormat_Undefined,
    /// indicates a "hole" in the parent @ref WGPUFragmentState `targets` array:
    /// the pipeline does not output a value at this `location`.
    format: TextureFormat = .undefined,
    blend: ?*const BlendState = null,
    write_mask: ColorWriteMask = ColorWriteMask.all,
};

pub const CommandBufferDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
};

pub const CommandEncoderDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
};

/// Note: While Compatibility Mode is optional to implement, this extension struct
/// is required to be supported (for both queries and requests) and behave as
/// defined in the WebGPU spec.
pub const CompatibilityModeLimits = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .compatibility_mode_limits },

    max_storage_buffers_in_vertex_stage: u32 = limit_u32_undefined,
    max_storage_textures_in_vertex_stage: u32 = limit_u32_undefined,
    max_storage_buffers_in_fragment_stage: u32 = limit_u32_undefined,
    max_storage_textures_in_fragment_stage: u32 = limit_u32_undefined,

    pub fn limits(self: *const @This()) Limits {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

pub const CompilationInfo = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    messages_count: usize = 0,
    messages: ?[*]const CompilationMessage = null,
};

pub const CompilationMessage = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// A @ref LocalizableHumanReadableMessageString.
    message: String = String.NULL,
    /// Severity level of the message.
    type: CompilationMessageType,
    /// Line number where the message is attached, starting at 1.
    line_num: u64 = 0,
    /// Offset in UTF-8 code units (bytes) from the beginning of the line, starting at 1.
    line_pos: u64 = 0,
    /// Offset in UTF-8 code units (bytes) from the beginning of the shader code, starting at 0.
    offset: u64 = 0,
    /// Length in UTF-8 code units (bytes) of the span the message corresponds to.
    length: u64 = 0,
};

pub const ComputePassDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    timestamp_writes: ?*const PassTimestampWrites = null,
};

pub const ComputePipelineDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    layout: ?*PipelineLayout = null,
    compute: ComputeState,
};

pub const ComputeState = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    module: *ShaderModule,
    entry_point: String = String.NULL,
    constants_count: usize = 0,
    constants: ?[*]const ConstantEntry = null,
};

pub const ConstantEntry = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    key: String = String.NULL,
    /// Represents a WGSL numeric or boolean value using @ref DoubleAsSupertype.
    /// 
    /// If non-finite, produces a @ref NonFiniteFloatValueError.
    value: f64 = 0,
};

pub const DepthStencilState = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    format: TextureFormat = .undefined,
    depth_write_enabled: Bool.Optional = .false,
    depth_compare: CompareFunction = .undefined,
    stencil_front: StencilFaceState = .{},
    stencil_back: StencilFaceState = .{},
    stencil_read_mask: u32 = 0xFFFFFFFF,
    stencil_write_mask: u32 = 0xFFFFFFFF,
    depth_bias: i32 = 0,
    /// TODO
    /// 
    /// If non-finite, produces a @ref NonFiniteFloatValueError.
    depth_bias_slope_scale: f32 = 0,
    /// TODO
    /// 
    /// If non-finite, produces a @ref NonFiniteFloatValueError.
    depth_bias_clamp: f32 = 0,
};

pub const DeviceDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    required_features_count: usize = 0,
    required_features: ?[*]const FeatureName = null,
    required_limits: ?*const Limits = null,
    default_queue: QueueDescriptor = .{},
    device_lost_callback_info: DeviceLostCallbackInfo = .{},
    /// Called when there is an uncaptured error on this device, from any thread.
    /// See @ref ErrorScopes.
    /// 
    /// **Important:** This callback does not have a configurable @ref WGPUCallbackMode; it may be called at any time (like @ref WGPUCallbackMode_AllowSpontaneous). As such, calls into the `webgpu.h` API from this callback are unsafe. See @ref CallbackReentrancy.
    uncaptured_error_callback_info: UncapturedErrorCallbackInfo = .{},
};

pub const Extent3D = extern struct {
    width: u32 = 0,
    height: u32 = 1,
    depth_or_array_layers: u32 = 1,
};

/// Chained in an @ref WGPUBindGroupEntry to set it to an @ref WGPUExternalTexture. This must have a corresponding @ref WGPUExternalTextureBindingLayout in the @ref WGPUBindGroupLayout.
pub const ExternalTextureBindingEntry = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .external_texture_binding_entry },

    external_texture: *ExternalTexture,

    pub fn bindGroupEntry(self: *const @This()) BindGroupEntry {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

/// Chained in @ref WGPUBindGroupLayoutEntry to specify that the corresponding entries in an @ref WGPUBindGroup will contain an @ref WGPUExternalTexture.
pub const ExternalTextureBindingLayout = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .external_texture_binding_layout },


    pub fn bindGroupLayoutEntry(self: *const @This()) BindGroupLayoutEntry {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

pub const FragmentState = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    module: *ShaderModule,
    entry_point: String = String.NULL,
    constants_count: usize = 0,
    constants: ?[*]const ConstantEntry = null,
    targets_count: usize = 0,
    targets: ?[*]const ColorTargetState = null,
};

/// Opaque handle to an asynchronous operation. See @ref Asynchronous-Operations for more information.
pub const Future = extern struct {
    /// Opaque id of the @ref WGPUFuture
    id: u64 = 0,
};

/// Struct holding a future to wait on, and a `completed` boolean flag.
pub const FutureWaitInfo = extern struct {
    /// The future to wait on.
    future: Future = .{},
    /// Whether or not the future completed.
    completed: Bool = Bool.false,
};

pub const InstanceDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    required_features_count: usize = 0,
    required_features: ?[*]const InstanceFeatureName = null,
    required_limits: ?*const InstanceLimits = null,
};

pub const InstanceLimits = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// The maximum number @ref WGPUFutureWaitInfo supported in a call to ::wgpuInstanceWaitAny with `timeoutNS > 0`.
    timed_wait_any_max_count: usize = 0,
};

pub const Limits = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    max_texture_dimension_1D: u32 = limit_u32_undefined,
    max_texture_dimension_2D: u32 = limit_u32_undefined,
    max_texture_dimension_3D: u32 = limit_u32_undefined,
    max_texture_array_layers: u32 = limit_u32_undefined,
    max_bind_groups: u32 = limit_u32_undefined,
    max_bind_groups_plus_vertex_buffers: u32 = limit_u32_undefined,
    max_bindings_per_bind_group: u32 = limit_u32_undefined,
    max_dynamic_uniform_buffers_per_pipeline_layout: u32 = limit_u32_undefined,
    max_dynamic_storage_buffers_per_pipeline_layout: u32 = limit_u32_undefined,
    max_sampled_textures_per_shader_stage: u32 = limit_u32_undefined,
    max_samplers_per_shader_stage: u32 = limit_u32_undefined,
    max_storage_buffers_per_shader_stage: u32 = limit_u32_undefined,
    max_storage_textures_per_shader_stage: u32 = limit_u32_undefined,
    max_uniform_buffers_per_shader_stage: u32 = limit_u32_undefined,
    max_uniform_buffer_binding_size: u64 = limit_u64_undefined,
    max_storage_buffer_binding_size: u64 = limit_u64_undefined,
    min_uniform_buffer_offset_alignment: u32 = limit_u32_undefined,
    min_storage_buffer_offset_alignment: u32 = limit_u32_undefined,
    max_vertex_buffers: u32 = limit_u32_undefined,
    max_buffer_size: u64 = limit_u64_undefined,
    max_vertex_attributes: u32 = limit_u32_undefined,
    max_vertex_buffer_array_stride: u32 = limit_u32_undefined,
    max_inter_stage_shader_variables: u32 = limit_u32_undefined,
    max_color_attachments: u32 = limit_u32_undefined,
    max_color_attachment_bytes_per_sample: u32 = limit_u32_undefined,
    max_compute_workgroup_storage_size: u32 = limit_u32_undefined,
    max_compute_invocations_per_workgroup: u32 = limit_u32_undefined,
    max_compute_workgroup_size_x: u32 = limit_u32_undefined,
    max_compute_workgroup_size_y: u32 = limit_u32_undefined,
    max_compute_workgroup_size_z: u32 = limit_u32_undefined,
    max_compute_workgroups_per_dimension: u32 = limit_u32_undefined,
    max_immediate_size: u32 = limit_u32_undefined,
};

pub const MultisampleState = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    count: u32 = 1,
    mask: u32 = 0xFFFFFFFF,
    alpha_to_coverage_enabled: Bool = Bool.false,
};

pub const Origin3D = extern struct {
    x: u32 = 0,
    y: u32 = 0,
    z: u32 = 0,
};

pub const PassTimestampWrites = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// Query set to write timestamps to.
    query_set: *QuerySet,
    beginning_of_pass_write_index: u32 = query_set_index_undefined,
    end_of_pass_write_index: u32 = query_set_index_undefined,
};

pub const PipelineLayoutDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    bind_group_layouts_count: usize = 0,
    bind_group_layouts: ?[*]const ?*BindGroupLayout = null,
    immediate_size: u32 = 0,
};

pub const PrimitiveState = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// If set to @ref WGPUPrimitiveTopology_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUPrimitiveTopology_TriangleList.
    topology: PrimitiveTopology = .undefined,
    strip_index_format: IndexFormat = .undefined,
    /// If set to @ref WGPUFrontFace_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUFrontFace_CCW.
    front_face: FrontFace = .undefined,
    /// If set to @ref WGPUCullMode_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUCullMode_None.
    cull_mode: CullMode = .undefined,
    unclipped_depth: Bool = Bool.false,
};

pub const QuerySetDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    type: QueryType,
    count: u32 = 0,
};

pub const QueueDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
};

pub const RenderBundleDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
};

pub const RenderBundleEncoderDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    color_formats_count: usize = 0,
    color_formats: ?[*]const TextureFormat = null,
    depth_stencil_format: TextureFormat = .undefined,
    sample_count: u32 = 1,
    depth_read_only: Bool = Bool.false,
    stencil_read_only: Bool = Bool.false,
};

pub const RenderPassColorAttachment = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// If `NULL`, indicates a hole in the parent
    /// @ref WGPURenderPassDescriptor::colorAttachments array.
    view: ?*TextureView = null,
    depth_slice: u32 = depth_slice_undefined,
    resolve_target: ?*TextureView = null,
    load_op: LoadOp = .undefined,
    store_op: StoreOp = .undefined,
    clear_value: Color = .{},
};

pub const RenderPassDepthStencilAttachment = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    view: *TextureView,
    depth_load_op: LoadOp = .undefined,
    depth_store_op: StoreOp = .undefined,
    /// This is a @ref NullableFloatingPointType.
    /// 
    /// If `NaN`, indicates an `undefined` value (as defined by the JS spec).
    /// Use @ref WGPU_DEPTH_CLEAR_VALUE_UNDEFINED to indicate this semantically.
    /// 
    /// If infinite, produces a @ref NonFiniteFloatValueError.
    depth_clear_value: f32 = depth_clear_value_undefined,
    depth_read_only: Bool = Bool.false,
    stencil_load_op: LoadOp = .undefined,
    stencil_store_op: StoreOp = .undefined,
    stencil_clear_value: u32 = 0,
    stencil_read_only: Bool = Bool.false,
};

pub const RenderPassDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    color_attachments_count: usize = 0,
    color_attachments: ?[*]const RenderPassColorAttachment = null,
    depth_stencil_attachment: ?*const RenderPassDepthStencilAttachment = null,
    occlusion_query_set: ?*QuerySet = null,
    timestamp_writes: ?*const PassTimestampWrites = null,
};

pub const RenderPassMaxDrawCount = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .render_pass_max_draw_count },

    max_draw_count: u64 = 50000000,

    pub fn renderPassDescriptor(self: *const @This()) RenderPassDescriptor {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

pub const RenderPipelineDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    layout: ?*PipelineLayout = null,
    vertex: VertexState,
    primitive: PrimitiveState = .{},
    depth_stencil: ?*const DepthStencilState = null,
    multisample: MultisampleState = .{},
    fragment: ?*const FragmentState = null,
};

pub const RequestAdapterOptions = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// "Feature level" for the adapter request. If an adapter is returned, it must support the features and limits in the requested feature level.
    /// 
    /// If set to @ref WGPUFeatureLevel_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUFeatureLevel_Core.
    /// Additionally, implementations may ignore @ref WGPUFeatureLevel_Compatibility
    /// and provide @ref WGPUFeatureLevel_Core instead.
    feature_level: FeatureLevel = .undefined,
    power_preference: PowerPreference = .undefined,
    /// If true, requires the adapter to be a "fallback" adapter as defined by the JS spec.
    /// If this is not possible, the request returns null.
    force_fallback_adapter: Bool = Bool.false,
    /// If set, requires the adapter to have a particular backend type.
    /// If this is not possible, the request returns null.
    backend_type: BackendType = .undefined,
    /// If set, requires the adapter to be able to output to a particular surface.
    /// If this is not possible, the request returns null.
    compatible_surface: ?*Surface = null,
};

/// Extension providing requestAdapter options for implementations with WebXR interop (i.e. Wasm).
pub const RequestAdapterWebXROptions = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .request_adapter_WebXR_options },

    /// Sets the `xrCompatible` option in the JS API.
    xr_compatible: Bool = Bool.false,

    pub fn requestAdapterOptions(self: *const @This()) RequestAdapterOptions {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

pub const SamplerBindingLayout = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// If set to @ref WGPUSamplerBindingType_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUSamplerBindingType_Filtering.
    type: SamplerBindingType = .undefined,
};

pub const SamplerDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    /// If set to @ref WGPUAddressMode_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUAddressMode_ClampToEdge.
    address_mode_u: AddressMode = .undefined,
    /// If set to @ref WGPUAddressMode_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUAddressMode_ClampToEdge.
    address_mode_v: AddressMode = .undefined,
    /// If set to @ref WGPUAddressMode_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUAddressMode_ClampToEdge.
    address_mode_w: AddressMode = .undefined,
    /// If set to @ref WGPUFilterMode_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUFilterMode_Nearest.
    mag_filter: FilterMode = .undefined,
    /// If set to @ref WGPUFilterMode_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUFilterMode_Nearest.
    min_filter: FilterMode = .undefined,
    /// If set to @ref WGPUFilterMode_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUMipmapFilterMode_Nearest.
    mipmap_filter: MipmapFilterMode = .undefined,
    /// TODO
    /// 
    /// If non-finite, produces a @ref NonFiniteFloatValueError.
    lod_min_clamp: f32 = 0,
    /// TODO
    /// 
    /// If non-finite, produces a @ref NonFiniteFloatValueError.
    lod_max_clamp: f32 = 32,
    compare: CompareFunction = .undefined,
    max_anisotropy: u16 = 1,
};

pub const ShaderModuleDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
};

pub const ShaderSourceSPIRV = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .shader_source_SPIRV },

    code_size: u32 = 0,
    code: *const u32,

    pub fn shaderModuleDescriptor(self: *const @This()) ShaderModuleDescriptor {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

pub const ShaderSourceWGSL = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .shader_source_WGSL },

    code: String = String.NULL,

    pub fn shaderModuleDescriptor(self: *const @This()) ShaderModuleDescriptor {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

pub const StencilFaceState = extern struct {
    /// If set to @ref WGPUCompareFunction_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUCompareFunction_Always.
    compare: CompareFunction = .undefined,
    /// If set to @ref WGPUStencilOperation_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUStencilOperation_Keep.
    fail_op: StencilOperation = .undefined,
    /// If set to @ref WGPUStencilOperation_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUStencilOperation_Keep.
    depth_fail_op: StencilOperation = .undefined,
    /// If set to @ref WGPUStencilOperation_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUStencilOperation_Keep.
    pass_op: StencilOperation = .undefined,
};

pub const StorageTextureBindingLayout = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// If set to @ref WGPUStorageTextureAccess_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUStorageTextureAccess_WriteOnly.
    access: StorageTextureAccess = .undefined,
    format: TextureFormat = .undefined,
    /// If set to @ref WGPUTextureViewDimension_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUTextureViewDimension_2D.
    view_dimension: TextureViewDimension = .undefined,
};

pub const SupportedFeatures = extern struct {
    features_count: usize = 0,
    features: ?[*]const FeatureName = null,

    extern fn wgpuSupportedFeaturesFreeMembers(self: @This()) void;
    pub const free = wgpuSupportedFeaturesFreeMembers;
};

pub const SupportedInstanceFeatures = extern struct {
    features_count: usize = 0,
    features: ?[*]const InstanceFeatureName = null,

    extern fn wgpuSupportedInstanceFeaturesFreeMembers(self: @This()) void;
    pub const free = wgpuSupportedInstanceFeaturesFreeMembers;
};

pub const SupportedWGSLLanguageFeatures = extern struct {
    features_count: usize = 0,
    features: ?[*]const WGSLLanguageFeatureName = null,

    extern fn wgpuSupportedWGSLLanguageFeaturesFreeMembers(self: @This()) void;
    pub const free = wgpuSupportedWGSLLanguageFeaturesFreeMembers;
};

/// Filled by @ref wgpuSurfaceGetCapabilities with what's supported for @ref wgpuSurfaceConfigure for a pair of @ref WGPUSurface and @ref WGPUAdapter.
pub const SurfaceCapabilities = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// The bit set of supported @ref WGPUTextureUsage bits.
    /// Guaranteed to contain @ref WGPUTextureUsage_RenderAttachment.
    usages: TextureUsage = .{},
    /// A list of supported @ref WGPUTextureFormat values, in order of preference.
    formats_count: usize = 0,
    formats: ?[*]const TextureFormat = null,
    /// A list of supported @ref WGPUPresentMode values.
    /// Guaranteed to contain @ref WGPUPresentMode_Fifo.
    present_modes_count: usize = 0,
    present_modes: ?[*]const PresentMode = null,
    /// A list of supported @ref WGPUCompositeAlphaMode values.
    /// @ref WGPUCompositeAlphaMode_Auto will be an alias for the first element and will never be present in this array.
    alpha_modes_count: usize = 0,
    alpha_modes: ?[*]const CompositeAlphaMode = null,

    extern fn wgpuSurfaceCapabilitiesFreeMembers(self: @This()) void;
    pub const free = wgpuSurfaceCapabilitiesFreeMembers;
};

/// Extension of @ref WGPUSurfaceConfiguration for color spaces and HDR.
pub const SurfaceColorManagement = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .surface_color_management },

    color_space: PredefinedColorSpace,
    tone_mapping_mode: ToneMappingMode,
};

/// Options to @ref wgpuSurfaceConfigure for defining how a @ref WGPUSurface will be rendered to and presented to the user.
/// See @ref Surface-Configuration for more details.
pub const SurfaceConfiguration = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// The @ref WGPUDevice to use to render to surface's textures.
    device: *Device,
    /// The @ref WGPUTextureFormat of the surface's textures.
    format: TextureFormat = .undefined,
    /// The @ref WGPUTextureUsage of the surface's textures.
    usage: TextureUsage = .{ .render_attachment = true },
    /// The width of the surface's textures.
    width: u32 = 0,
    /// The height of the surface's textures.
    height: u32 = 0,
    /// The additional @ref WGPUTextureFormat for @ref WGPUTextureView format reinterpretation of the surface's textures.
    view_formats_count: usize = 0,
    view_formats: ?[*]const TextureFormat = null,
    /// How the surface's frames will be composited on the screen.
    /// 
    /// If set to @ref WGPUCompositeAlphaMode_Auto,
    /// [defaults] to @ref WGPUCompositeAlphaMode_Inherit in native (allowing the mode
    /// to be configured externally), and to @ref WGPUCompositeAlphaMode_Opaque in Wasm.
    alpha_mode: CompositeAlphaMode = .auto,
    /// When and in which order the surface's frames will be shown on the screen.
    /// 
    /// If set to @ref WGPUPresentMode_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUPresentMode_Fifo.
    present_mode: PresentMode = .undefined,
};

/// The root descriptor for the creation of an @ref WGPUSurface with @ref wgpuInstanceCreateSurface.
/// It isn't sufficient by itself and must have one of the `WGPUSurfaceSource*` in its chain.
/// See @ref Surface-Creation for more details.
pub const SurfaceDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// Label used to refer to the object.
    label: String = String.NULL,
};

/// Chained in @ref WGPUSurfaceDescriptor to make an @ref WGPUSurface wrapping an Android [`ANativeWindow`](https://developer.android.com/ndk/reference/group/a-native-window).
pub const SurfaceSourceAndroidNativeWindow = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .surface_source_android_native_window },

    /// The pointer to the [`ANativeWindow`](https://developer.android.com/ndk/reference/group/a-native-window) that will be wrapped by the @ref WGPUSurface.
    window: *anyopaque,

    pub fn surfaceDescriptor(self: *const @This()) SurfaceDescriptor {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

/// Chained in @ref WGPUSurfaceDescriptor to make an @ref WGPUSurface wrapping a [`CAMetalLayer`](https://developer.apple.com/documentation/quartzcore/cametallayer?language=objc).
pub const SurfaceSourceMetalLayer = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .surface_source_metal_layer },

    /// The pointer to the [`CAMetalLayer`](https://developer.apple.com/documentation/quartzcore/cametallayer?language=objc) that will be wrapped by the @ref WGPUSurface.
    layer: *anyopaque,

    pub fn surfaceDescriptor(self: *const @This()) SurfaceDescriptor {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

/// Chained in @ref WGPUSurfaceDescriptor to make an @ref WGPUSurface wrapping a [Wayland](https://wayland.freedesktop.org/) [`wl_surface`](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_surface).
pub const SurfaceSourceWaylandSurface = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .surface_source_wayland_surface },

    /// A [`wl_display`](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_display) for this Wayland instance.
    display: *anyopaque,
    /// A [`wl_surface`](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_surface) that will be wrapped by the @ref WGPUSurface
    surface: *anyopaque,

    pub fn surfaceDescriptor(self: *const @This()) SurfaceDescriptor {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

/// Chained in @ref WGPUSurfaceDescriptor to make an @ref WGPUSurface wrapping a Windows [`HWND`](https://learn.microsoft.com/en-us/windows/apps/develop/ui-input/retrieve-hwnd).
pub const SurfaceSourceWindowsHWND = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .surface_source_windows_HWND },

    /// The [`HINSTANCE`](https://learn.microsoft.com/en-us/windows/win32/learnwin32/winmain--the-application-entry-point) for this application.
    /// Most commonly `GetModuleHandle(nullptr)`.
    hinstance: *anyopaque,
    /// The [`HWND`](https://learn.microsoft.com/en-us/windows/apps/develop/ui-input/retrieve-hwnd) that will be wrapped by the @ref WGPUSurface.
    hwnd: *anyopaque,

    pub fn surfaceDescriptor(self: *const @This()) SurfaceDescriptor {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

/// Chained in @ref WGPUSurfaceDescriptor to make an @ref WGPUSurface wrapping an [XCB](https://xcb.freedesktop.org/) `xcb_window_t`.
pub const SurfaceSourceXCBWindow = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .surface_source_XCB_window },

    /// The `xcb_connection_t` for the connection to the X server.
    connection: *anyopaque,
    /// The `xcb_window_t` for the window that will be wrapped by the @ref WGPUSurface.
    window: u32 = 0,

    pub fn surfaceDescriptor(self: *const @This()) SurfaceDescriptor {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

/// Chained in @ref WGPUSurfaceDescriptor to make an @ref WGPUSurface wrapping an [Xlib](https://www.x.org/releases/current/doc/libX11/libX11/libX11.html) `Window`.
pub const SurfaceSourceXlibWindow = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .surface_source_xlib_window },

    /// A pointer to the [`Display`](https://www.x.org/releases/current/doc/libX11/libX11/libX11.html#Opening_the_Display) connected to the X server.
    display: *anyopaque,
    /// The [`Window`](https://www.x.org/releases/current/doc/libX11/libX11/libX11.html#Creating_Windows) that will be wrapped by the @ref WGPUSurface.
    window: u64 = 0,

    pub fn surfaceDescriptor(self: *const @This()) SurfaceDescriptor {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

/// Queried each frame from a @ref WGPUSurface to get a @ref WGPUTexture to render to along with some metadata.
/// See @ref Surface-Presenting for more details.
pub const SurfaceTexture = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// The @ref WGPUTexture representing the frame that will be shown on the surface.
    /// It is @ref ReturnedWithOwnership from @ref wgpuSurfaceGetCurrentTexture.
    texture: *Texture,
    /// Whether the call to @ref wgpuSurfaceGetCurrentTexture succeeded and a hint as to why it might not have.
    status: SurfaceGetCurrentTextureStatus,
};

pub const TexelCopyBufferInfo = extern struct {
    layout: TexelCopyBufferLayout = .{},
    buffer: *Buffer,
};

pub const TexelCopyBufferLayout = extern struct {
    offset: u64 = 0,
    bytes_per_row: u32 = copy_stride_undefined,
    rows_per_image: u32 = copy_stride_undefined,
};

pub const TexelCopyTextureInfo = extern struct {
    texture: *Texture,
    mip_level: u32 = 0,
    origin: Origin3D = .{},
    /// If set to @ref WGPUTextureAspect_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUTextureAspect_All.
    aspect: TextureAspect = .undefined,
};

pub const TextureBindingLayout = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    /// If set to @ref WGPUTextureSampleType_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUTextureSampleType_Float.
    sample_type: TextureSampleType = .undefined,
    /// If set to @ref WGPUTextureViewDimension_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUTextureViewDimension_2D.
    view_dimension: TextureViewDimension = .undefined,
    multisampled: Bool = Bool.false,
};

/// Note: While Compatibility Mode is optional to implement, this extension struct
/// is required to be accepted (but per the WebGPU spec, its contents are ignored
/// on devices that have the @ref WGPUFeatureName_CoreFeaturesAndLimits feature).
pub const TextureBindingViewDimension = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .texture_binding_view_dimension },

    texture_binding_view_dimension: TextureViewDimension = .undefined,

    pub fn textureDescriptor(self: *const @This()) TextureDescriptor {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

/// When accessed by a shader, the red/green/blue/alpha channels are replaced
/// by the value corresponding to the component specified in r, g, b, and a,
/// respectively unlike the JS API which uses a string of length four, with
/// each character mapping to the texture view's red/green/blue/alpha channels.
pub const TextureComponentSwizzle = extern struct {
    /// The value that replaces the red channel in the shader.
    /// 
    /// If set to @ref WGPUComponentSwizzle_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUComponentSwizzle_R.
    r: ComponentSwizzle = .undefined,
    /// The value that replaces the green channel in the shader.
    /// 
    /// If set to @ref WGPUComponentSwizzle_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUComponentSwizzle_G.
    g: ComponentSwizzle = .undefined,
    /// The value that replaces the blue channel in the shader.
    /// 
    /// If set to @ref WGPUComponentSwizzle_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUComponentSwizzle_B.
    b: ComponentSwizzle = .undefined,
    /// The value that replaces the alpha channel in the shader.
    /// 
    /// If set to @ref WGPUComponentSwizzle_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUComponentSwizzle_A.
    a: ComponentSwizzle = .undefined,
};

pub const TextureComponentSwizzleDescriptor = extern struct {
    chain: ChainedStruct = .{ .next = null, .s_type = .texture_component_swizzle_descriptor },

    swizzle: TextureComponentSwizzle = .{},

    pub fn textureViewDescriptor(self: *const @This()) TextureViewDescriptor {
        return .{ .next_in_chain = @constCast(&self.chain) };
    }
};

pub const TextureDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    usage: TextureUsage = .{},
    /// If set to @ref WGPUTextureDimension_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUTextureDimension_2D.
    dimension: TextureDimension = .undefined,
    size: Extent3D = .{},
    format: TextureFormat = .undefined,
    mip_level_count: u32 = 1,
    sample_count: u32 = 1,
    view_formats_count: usize = 0,
    view_formats: ?[*]const TextureFormat = null,
};

pub const TextureViewDescriptor = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    label: String = String.NULL,
    format: TextureFormat = .undefined,
    dimension: TextureViewDimension = .undefined,
    base_mip_level: u32 = 0,
    mip_level_count: u32 = mip_level_count_undefined,
    base_array_layer: u32 = 0,
    array_layer_count: u32 = array_layer_count_undefined,
    /// If set to @ref WGPUTextureAspect_Undefined,
    /// [defaults](@ref SentinelValues) to @ref WGPUTextureAspect_All.
    aspect: TextureAspect = .undefined,
    usage: TextureUsage = .{},
};

pub const VertexAttribute = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    format: VertexFormat,
    offset: u64 = 0,
    shader_location: u32 = 0,
};

/// If `attributes` is empty *and* `stepMode` is @ref WGPUVertexStepMode_Undefined,
/// indicates a "hole" in the parent @ref WGPUVertexState `buffers` array,
/// with behavior equivalent to `null` in the JS API.
/// 
/// If `attributes` is empty but `stepMode` is *not* @ref WGPUVertexStepMode_Undefined,
/// indicates a vertex buffer with no attributes, with behavior equivalent to
/// `{ attributes: [] }` in the JS API. (TODO: If the JS API changes not to
/// distinguish these cases, then this distinction doesn't matter and we can
/// remove this documentation.)
/// 
/// If `stepMode` is @ref WGPUVertexStepMode_Undefined but `attributes` is *not* empty,
/// `stepMode` [defaults](@ref SentinelValues) to @ref WGPUVertexStepMode_Vertex.
pub const VertexBufferLayout = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    step_mode: VertexStepMode = .undefined,
    array_stride: u64 = 0,
    attributes_count: usize = 0,
    attributes: ?[*]const VertexAttribute = null,
};

pub const VertexState = extern struct {
    next_in_chain: ?*ChainedStruct = null,

    module: *ShaderModule,
    entry_point: String = String.NULL,
    constants_count: usize = 0,
    constants: ?[*]const ConstantEntry = null,
    buffers_count: usize = 0,
    buffers: ?[*]const VertexBufferLayout = null,
};

pub const Adapter = opaque {
    extern fn wgpuAdapterGetLimits(self: *Adapter, limits: *Limits) Status;
    pub fn getLimits(self: *Adapter, limits: *Limits) Status {
        return wgpuAdapterGetLimits(self, limits);
    }

    extern fn wgpuAdapterHasFeature(self: *Adapter, feature: FeatureName) Bool;
    pub fn hasFeature(self: *Adapter, feature: FeatureName) bool {
        return (wgpuAdapterHasFeature(self, feature)).into();
    }

    /// Get the list of @ref WGPUFeatureName values supported by the adapter.
    extern fn wgpuAdapterGetFeatures(self: *Adapter, features: *SupportedFeatures) void;
    /// Get the list of @ref WGPUFeatureName values supported by the adapter.
    pub fn getFeatures(self: *Adapter, features: *SupportedFeatures) void {
        return wgpuAdapterGetFeatures(self, features);
    }

    extern fn wgpuAdapterGetInfo(self: *Adapter, info: *AdapterInfo) Status;
    pub fn getInfo(self: *Adapter, info: *AdapterInfo) Status {
        return wgpuAdapterGetInfo(self, info);
    }

    extern fn wgpuAdapterRequestDevice(self: *Adapter, descriptor: ?*const DeviceDescriptor, callback_info: RequestDeviceCallbackInfo) Future;
    pub fn requestDevice(self: *Adapter, descriptor: ?*const DeviceDescriptor, callback_info: RequestDeviceCallbackInfo) Future {
        return wgpuAdapterRequestDevice(self, descriptor, callback_info);
    }

    /// Blocking wrapper around `requestDevice`: waits on the returned future with
    /// `waitAny` (forever) until the callback fires.
    /// 
    /// On failure, `err.message` is copied into a thread-local buffer (truncated
    /// to 1024 bytes) and is only valid until the next `...Sync` call on the
    /// same thread.
    pub fn requestDeviceSync(self: *Adapter, instance: *Instance, descriptor: ?*const DeviceDescriptor) error{WaitFailed}!Result(RequestDeviceStatus, *Device) {
        const Capture = struct {
            result: Result(RequestDeviceStatus, *Device) = undefined,
            done: bool = false,
            fn cb(status: RequestDeviceStatus, device: ?*Device, message: String, ud1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                const cap_ptr: *@This() = @ptrCast(@alignCast(ud1.?));
                cap_ptr.result = if (status == .success) .{ .ok = device.? } else .{ .err = .{ .status = status, .message = copyMessage(message) } };
                cap_ptr.done = true;
            }
        };
        var cap: Capture = .{};
        const callback_info: RequestDeviceCallbackInfo = .{ .mode = .wait_any_only, .callback = &Capture.cb, .userdata1 = &cap };
        const future = self.requestDevice(descriptor, callback_info);
        var infos = [_]FutureWaitInfo{.{ .future = future }};
        while (!cap.done) {
            switch (instance.waitAny(&infos, std.math.maxInt(u64))) {
                .success, .timed_out => {},
                else => return error.WaitFailed,
            }
        }
        return cap.result;
    }

    extern fn wgpuAdapterAddRef(self: *@This()) void;
    pub const addRef = wgpuAdapterAddRef;

    extern fn wgpuAdapterRelease(self: *@This()) void;
    pub const release = wgpuAdapterRelease;
};

pub const BindGroup = opaque {
    extern fn wgpuBindGroupSetLabel(self: *BindGroup, label: String) void;
    pub fn setLabel(self: *BindGroup, label: []const u8) void {
        return wgpuBindGroupSetLabel(self, String.from(label));
    }

    extern fn wgpuBindGroupAddRef(self: *@This()) void;
    pub const addRef = wgpuBindGroupAddRef;

    extern fn wgpuBindGroupRelease(self: *@This()) void;
    pub const release = wgpuBindGroupRelease;
};

pub const BindGroupLayout = opaque {
    extern fn wgpuBindGroupLayoutSetLabel(self: *BindGroupLayout, label: String) void;
    pub fn setLabel(self: *BindGroupLayout, label: []const u8) void {
        return wgpuBindGroupLayoutSetLabel(self, String.from(label));
    }

    extern fn wgpuBindGroupLayoutAddRef(self: *@This()) void;
    pub const addRef = wgpuBindGroupLayoutAddRef;

    extern fn wgpuBindGroupLayoutRelease(self: *@This()) void;
    pub const release = wgpuBindGroupLayoutRelease;
};

pub const Buffer = opaque {
    extern fn wgpuBufferMapAsync(self: *Buffer, mode: MapMode, offset: usize, size: usize, callback_info: BufferMapCallbackInfo) Future;
    pub fn mapAsync(self: *Buffer, mode: MapMode, offset: usize, size: usize, callback_info: BufferMapCallbackInfo) Future {
        return wgpuBufferMapAsync(self, mode, offset, size, callback_info);
    }

    /// Blocking wrapper around `mapAsync`: waits on the returned future with
    /// `waitAny` (forever) until the callback fires.
    /// 
    /// On failure, `err.message` is copied into a thread-local buffer (truncated
    /// to 1024 bytes) and is only valid until the next `...Sync` call on the
    /// same thread.
    pub fn mapAsyncSync(self: *Buffer, instance: *Instance, mode: MapMode, offset: usize, size: usize) error{WaitFailed}!Result(MapAsyncStatus, void) {
        const Capture = struct {
            result: Result(MapAsyncStatus, void) = undefined,
            done: bool = false,
            fn cb(status: MapAsyncStatus, message: String, ud1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                const cap_ptr: *@This() = @ptrCast(@alignCast(ud1.?));
                cap_ptr.result = if (status == .success) .{ .ok = {} } else .{ .err = .{ .status = status, .message = copyMessage(message) } };
                cap_ptr.done = true;
            }
        };
        var cap: Capture = .{};
        const callback_info: BufferMapCallbackInfo = .{ .mode = .wait_any_only, .callback = &Capture.cb, .userdata1 = &cap };
        const future = self.mapAsync(mode, offset, size, callback_info);
        var infos = [_]FutureWaitInfo{.{ .future = future }};
        while (!cap.done) {
            switch (instance.waitAny(&infos, std.math.maxInt(u64))) {
                .success, .timed_out => {},
                else => return error.WaitFailed,
            }
        }
        return cap.result;
    }

    /// Returns a mutable pointer to beginning of the mapped range.
    /// See @ref MappedRangeBehavior for error conditions and guarantees.
    /// This function is safe to call inside spontaneous callbacks (see @ref CallbackReentrancy).
    /// 
    /// In Wasm, if `memcpy`ing into this range, prefer using @ref wgpuBufferWriteMappedRange
    /// instead for better performance.
    extern fn wgpuBufferGetMappedRange(self: *Buffer, offset: usize, size: usize) ?*anyopaque;
    /// Returns a mutable pointer to beginning of the mapped range.
    /// See @ref MappedRangeBehavior for error conditions and guarantees.
    /// This function is safe to call inside spontaneous callbacks (see @ref CallbackReentrancy).
    /// 
    /// In Wasm, if `memcpy`ing into this range, prefer using @ref wgpuBufferWriteMappedRange
    /// instead for better performance.
    pub fn getMappedRange(self: *Buffer, offset: usize, size: usize) ?*anyopaque {
        return wgpuBufferGetMappedRange(self, offset, size);
    }

    /// Slice view of the mapped range. `size` must be the exact byte length —
    /// the `whole_map_size` sentinel is not supported here, since the slice
    /// length has to be known. Returns null if the range could not be mapped.
    pub fn getMappedRangeSlice(self: *Buffer, offset: usize, size: usize) ?[]u8 {
        std.debug.assert(size != whole_map_size);
        const ptr = wgpuBufferGetMappedRange(self, offset, size) orelse return null;
        return @as([*]u8, @ptrCast(ptr))[0..size];
    }

    /// Returns a const pointer to beginning of the mapped range.
    /// It must not be written; writing to this range causes undefined behavior.
    /// See @ref MappedRangeBehavior for error conditions and guarantees.
    /// This function is safe to call inside spontaneous callbacks (see @ref CallbackReentrancy).
    /// 
    /// In Wasm, if `memcpy`ing from this range, prefer using @ref wgpuBufferReadMappedRange
    /// instead for better performance.
    extern fn wgpuBufferGetConstMappedRange(self: *Buffer, offset: usize, size: usize) ?*const anyopaque;
    /// Returns a const pointer to beginning of the mapped range.
    /// It must not be written; writing to this range causes undefined behavior.
    /// See @ref MappedRangeBehavior for error conditions and guarantees.
    /// This function is safe to call inside spontaneous callbacks (see @ref CallbackReentrancy).
    /// 
    /// In Wasm, if `memcpy`ing from this range, prefer using @ref wgpuBufferReadMappedRange
    /// instead for better performance.
    pub fn getConstMappedRange(self: *Buffer, offset: usize, size: usize) ?*const anyopaque {
        return wgpuBufferGetConstMappedRange(self, offset, size);
    }

    /// Slice view of the mapped range. `size` must be the exact byte length —
    /// the `whole_map_size` sentinel is not supported here, since the slice
    /// length has to be known. Returns null if the range could not be mapped.
    pub fn getConstMappedRangeSlice(self: *Buffer, offset: usize, size: usize) ?[]const u8 {
        std.debug.assert(size != whole_map_size);
        const ptr = wgpuBufferGetConstMappedRange(self, offset, size) orelse return null;
        return @as([*]const u8, @ptrCast(ptr))[0..size];
    }

    /// Copies a range of data from the buffer mapping into the provided destination pointer.
    /// See @ref MappedRangeBehavior for error conditions and guarantees.
    /// This function is safe to call inside spontaneous callbacks (see @ref CallbackReentrancy).
    /// 
    /// In Wasm, this is more efficient than copying from a mapped range into a `malloc`'d range.
    extern fn wgpuBufferReadMappedRange(self: *Buffer, offset: usize, data: *anyopaque, size: usize) Status;
    /// Copies a range of data from the buffer mapping into the provided destination pointer.
    /// See @ref MappedRangeBehavior for error conditions and guarantees.
    /// This function is safe to call inside spontaneous callbacks (see @ref CallbackReentrancy).
    /// 
    /// In Wasm, this is more efficient than copying from a mapped range into a `malloc`'d range.
    pub fn readMappedRange(self: *Buffer, offset: usize, data: []u8) Status {
        return wgpuBufferReadMappedRange(self, offset, data.ptr, data.len);
    }

    /// Copies a range of data from the provided source pointer into the buffer mapping.
    /// See @ref MappedRangeBehavior for error conditions and guarantees.
    /// This function is safe to call inside spontaneous callbacks (see @ref CallbackReentrancy).
    /// 
    /// In Wasm, this is more efficient than copying from a `malloc`'d range into a mapped range.
    extern fn wgpuBufferWriteMappedRange(self: *Buffer, offset: usize, data: *const anyopaque, size: usize) Status;
    /// Copies a range of data from the provided source pointer into the buffer mapping.
    /// See @ref MappedRangeBehavior for error conditions and guarantees.
    /// This function is safe to call inside spontaneous callbacks (see @ref CallbackReentrancy).
    /// 
    /// In Wasm, this is more efficient than copying from a `malloc`'d range into a mapped range.
    pub fn writeMappedRange(self: *Buffer, offset: usize, data: []const u8) Status {
        return wgpuBufferWriteMappedRange(self, offset, data.ptr, data.len);
    }

    extern fn wgpuBufferSetLabel(self: *Buffer, label: String) void;
    pub fn setLabel(self: *Buffer, label: []const u8) void {
        return wgpuBufferSetLabel(self, String.from(label));
    }

    extern fn wgpuBufferGetUsage(self: *Buffer) BufferUsage;
    pub fn getUsage(self: *Buffer) BufferUsage {
        return wgpuBufferGetUsage(self);
    }

    extern fn wgpuBufferGetSize(self: *Buffer) u64;
    pub fn getSize(self: *Buffer) u64 {
        return wgpuBufferGetSize(self);
    }

    extern fn wgpuBufferGetMapState(self: *Buffer) BufferMapState;
    pub fn getMapState(self: *Buffer) BufferMapState {
        return wgpuBufferGetMapState(self);
    }

    extern fn wgpuBufferUnmap(self: *Buffer) void;
    pub fn unmap(self: *Buffer) void {
        return wgpuBufferUnmap(self);
    }

    extern fn wgpuBufferDestroy(self: *Buffer) void;
    pub fn destroy(self: *Buffer) void {
        return wgpuBufferDestroy(self);
    }

    extern fn wgpuBufferAddRef(self: *@This()) void;
    pub const addRef = wgpuBufferAddRef;

    extern fn wgpuBufferRelease(self: *@This()) void;
    pub const release = wgpuBufferRelease;
};

pub const CommandBuffer = opaque {
    extern fn wgpuCommandBufferSetLabel(self: *CommandBuffer, label: String) void;
    pub fn setLabel(self: *CommandBuffer, label: []const u8) void {
        return wgpuCommandBufferSetLabel(self, String.from(label));
    }

    extern fn wgpuCommandBufferAddRef(self: *@This()) void;
    pub const addRef = wgpuCommandBufferAddRef;

    extern fn wgpuCommandBufferRelease(self: *@This()) void;
    pub const release = wgpuCommandBufferRelease;
};

pub const CommandEncoder = opaque {
    extern fn wgpuCommandEncoderFinish(self: *CommandEncoder, descriptor: ?*const CommandBufferDescriptor) *CommandBuffer;
    pub fn finish(self: *CommandEncoder, descriptor: ?*const CommandBufferDescriptor) *CommandBuffer {
        return wgpuCommandEncoderFinish(self, descriptor);
    }

    extern fn wgpuCommandEncoderBeginComputePass(self: *CommandEncoder, descriptor: ?*const ComputePassDescriptor) *ComputePassEncoder;
    pub fn beginComputePass(self: *CommandEncoder, descriptor: ?*const ComputePassDescriptor) *ComputePassEncoder {
        return wgpuCommandEncoderBeginComputePass(self, descriptor);
    }

    extern fn wgpuCommandEncoderBeginRenderPass(self: *CommandEncoder, descriptor: *const RenderPassDescriptor) *RenderPassEncoder;
    pub fn beginRenderPass(self: *CommandEncoder, descriptor: *const RenderPassDescriptor) *RenderPassEncoder {
        return wgpuCommandEncoderBeginRenderPass(self, descriptor);
    }

    extern fn wgpuCommandEncoderCopyBufferToBuffer(self: *CommandEncoder, source: *Buffer, source_offset: u64, destination: *Buffer, destination_offset: u64, size: u64) void;
    pub fn copyBufferToBuffer(self: *CommandEncoder, source: *Buffer, source_offset: u64, destination: *Buffer, destination_offset: u64, size: u64) void {
        return wgpuCommandEncoderCopyBufferToBuffer(self, source, source_offset, destination, destination_offset, size);
    }

    extern fn wgpuCommandEncoderCopyBufferToTexture(self: *CommandEncoder, source: *const TexelCopyBufferInfo, destination: *const TexelCopyTextureInfo, copy_size: *const Extent3D) void;
    pub fn copyBufferToTexture(self: *CommandEncoder, source: *const TexelCopyBufferInfo, destination: *const TexelCopyTextureInfo, copy_size: *const Extent3D) void {
        return wgpuCommandEncoderCopyBufferToTexture(self, source, destination, copy_size);
    }

    extern fn wgpuCommandEncoderCopyTextureToBuffer(self: *CommandEncoder, source: *const TexelCopyTextureInfo, destination: *const TexelCopyBufferInfo, copy_size: *const Extent3D) void;
    pub fn copyTextureToBuffer(self: *CommandEncoder, source: *const TexelCopyTextureInfo, destination: *const TexelCopyBufferInfo, copy_size: *const Extent3D) void {
        return wgpuCommandEncoderCopyTextureToBuffer(self, source, destination, copy_size);
    }

    extern fn wgpuCommandEncoderCopyTextureToTexture(self: *CommandEncoder, source: *const TexelCopyTextureInfo, destination: *const TexelCopyTextureInfo, copy_size: *const Extent3D) void;
    pub fn copyTextureToTexture(self: *CommandEncoder, source: *const TexelCopyTextureInfo, destination: *const TexelCopyTextureInfo, copy_size: *const Extent3D) void {
        return wgpuCommandEncoderCopyTextureToTexture(self, source, destination, copy_size);
    }

    extern fn wgpuCommandEncoderClearBuffer(self: *CommandEncoder, buffer: *Buffer, offset: u64, size: u64) void;
    pub fn clearBuffer(self: *CommandEncoder, buffer: *Buffer, offset: u64, size: u64) void {
        return wgpuCommandEncoderClearBuffer(self, buffer, offset, size);
    }

    extern fn wgpuCommandEncoderInsertDebugMarker(self: *CommandEncoder, marker_label: String) void;
    pub fn insertDebugMarker(self: *CommandEncoder, marker_label: []const u8) void {
        return wgpuCommandEncoderInsertDebugMarker(self, String.from(marker_label));
    }

    extern fn wgpuCommandEncoderPopDebugGroup(self: *CommandEncoder) void;
    pub fn popDebugGroup(self: *CommandEncoder) void {
        return wgpuCommandEncoderPopDebugGroup(self);
    }

    extern fn wgpuCommandEncoderPushDebugGroup(self: *CommandEncoder, group_label: String) void;
    pub fn pushDebugGroup(self: *CommandEncoder, group_label: []const u8) void {
        return wgpuCommandEncoderPushDebugGroup(self, String.from(group_label));
    }

    extern fn wgpuCommandEncoderResolveQuerySet(self: *CommandEncoder, query_set: *QuerySet, first_query: u32, query_count: u32, destination: *Buffer, destination_offset: u64) void;
    pub fn resolveQuerySet(self: *CommandEncoder, query_set: *QuerySet, first_query: u32, query_count: u32, destination: *Buffer, destination_offset: u64) void {
        return wgpuCommandEncoderResolveQuerySet(self, query_set, first_query, query_count, destination, destination_offset);
    }

    extern fn wgpuCommandEncoderWriteTimestamp(self: *CommandEncoder, query_set: *QuerySet, query_index: u32) void;
    pub fn writeTimestamp(self: *CommandEncoder, query_set: *QuerySet, query_index: u32) void {
        return wgpuCommandEncoderWriteTimestamp(self, query_set, query_index);
    }

    extern fn wgpuCommandEncoderSetLabel(self: *CommandEncoder, label: String) void;
    pub fn setLabel(self: *CommandEncoder, label: []const u8) void {
        return wgpuCommandEncoderSetLabel(self, String.from(label));
    }

    extern fn wgpuCommandEncoderAddRef(self: *@This()) void;
    pub const addRef = wgpuCommandEncoderAddRef;

    extern fn wgpuCommandEncoderRelease(self: *@This()) void;
    pub const release = wgpuCommandEncoderRelease;
};

pub const ComputePassEncoder = opaque {
    extern fn wgpuComputePassEncoderInsertDebugMarker(self: *ComputePassEncoder, marker_label: String) void;
    pub fn insertDebugMarker(self: *ComputePassEncoder, marker_label: []const u8) void {
        return wgpuComputePassEncoderInsertDebugMarker(self, String.from(marker_label));
    }

    extern fn wgpuComputePassEncoderPopDebugGroup(self: *ComputePassEncoder) void;
    pub fn popDebugGroup(self: *ComputePassEncoder) void {
        return wgpuComputePassEncoderPopDebugGroup(self);
    }

    extern fn wgpuComputePassEncoderPushDebugGroup(self: *ComputePassEncoder, group_label: String) void;
    pub fn pushDebugGroup(self: *ComputePassEncoder, group_label: []const u8) void {
        return wgpuComputePassEncoderPushDebugGroup(self, String.from(group_label));
    }

    extern fn wgpuComputePassEncoderSetPipeline(self: *ComputePassEncoder, pipeline: *ComputePipeline) void;
    pub fn setPipeline(self: *ComputePassEncoder, pipeline: *ComputePipeline) void {
        return wgpuComputePassEncoderSetPipeline(self, pipeline);
    }

    extern fn wgpuComputePassEncoderSetBindGroup(self: *ComputePassEncoder, group_index: u32, group: ?*BindGroup, dynamic_offsets_count: usize, dynamic_offsets: [*]const u32) void;
    pub fn setBindGroup(self: *ComputePassEncoder, group_index: u32, group: ?*BindGroup, dynamic_offsets: []const u32) void {
        return wgpuComputePassEncoderSetBindGroup(self, group_index, group, dynamic_offsets.len, dynamic_offsets.ptr);
    }

    extern fn wgpuComputePassEncoderSetImmediates(self: *ComputePassEncoder, offset: u32, data: *const anyopaque, size: usize) void;
    pub fn setImmediates(self: *ComputePassEncoder, offset: u32, data: []const u8) void {
        return wgpuComputePassEncoderSetImmediates(self, offset, data.ptr, data.len);
    }

    extern fn wgpuComputePassEncoderDispatchWorkgroups(self: *ComputePassEncoder, workgroupCountX: u32, workgroupCountY: u32, workgroupCountZ: u32) void;
    pub fn dispatchWorkgroups(self: *ComputePassEncoder, workgroupCountX: u32, workgroupCountY: u32, workgroupCountZ: u32) void {
        return wgpuComputePassEncoderDispatchWorkgroups(self, workgroupCountX, workgroupCountY, workgroupCountZ);
    }

    extern fn wgpuComputePassEncoderDispatchWorkgroupsIndirect(self: *ComputePassEncoder, indirect_buffer: *Buffer, indirect_offset: u64) void;
    pub fn dispatchWorkgroupsIndirect(self: *ComputePassEncoder, indirect_buffer: *Buffer, indirect_offset: u64) void {
        return wgpuComputePassEncoderDispatchWorkgroupsIndirect(self, indirect_buffer, indirect_offset);
    }

    extern fn wgpuComputePassEncoderEnd(self: *ComputePassEncoder) void;
    pub fn end(self: *ComputePassEncoder) void {
        return wgpuComputePassEncoderEnd(self);
    }

    extern fn wgpuComputePassEncoderSetLabel(self: *ComputePassEncoder, label: String) void;
    pub fn setLabel(self: *ComputePassEncoder, label: []const u8) void {
        return wgpuComputePassEncoderSetLabel(self, String.from(label));
    }

    extern fn wgpuComputePassEncoderAddRef(self: *@This()) void;
    pub const addRef = wgpuComputePassEncoderAddRef;

    extern fn wgpuComputePassEncoderRelease(self: *@This()) void;
    pub const release = wgpuComputePassEncoderRelease;
};

pub const ComputePipeline = opaque {
    extern fn wgpuComputePipelineGetBindGroupLayout(self: *ComputePipeline, group_index: u32) *BindGroupLayout;
    pub fn getBindGroupLayout(self: *ComputePipeline, group_index: u32) *BindGroupLayout {
        return wgpuComputePipelineGetBindGroupLayout(self, group_index);
    }

    extern fn wgpuComputePipelineSetLabel(self: *ComputePipeline, label: String) void;
    pub fn setLabel(self: *ComputePipeline, label: []const u8) void {
        return wgpuComputePipelineSetLabel(self, String.from(label));
    }

    extern fn wgpuComputePipelineAddRef(self: *@This()) void;
    pub const addRef = wgpuComputePipelineAddRef;

    extern fn wgpuComputePipelineRelease(self: *@This()) void;
    pub const release = wgpuComputePipelineRelease;
};

/// TODO
/// 
/// Releasing the last ref to a `WGPUDevice` also calls @ref wgpuDeviceDestroy.
/// For more info, see @ref DeviceRelease.
pub const Device = opaque {
    extern fn wgpuDeviceCreateBindGroup(self: *Device, descriptor: *const BindGroupDescriptor) *BindGroup;
    pub fn createBindGroup(self: *Device, descriptor: *const BindGroupDescriptor) *BindGroup {
        return wgpuDeviceCreateBindGroup(self, descriptor);
    }

    extern fn wgpuDeviceCreateBindGroupLayout(self: *Device, descriptor: *const BindGroupLayoutDescriptor) *BindGroupLayout;
    pub fn createBindGroupLayout(self: *Device, descriptor: *const BindGroupLayoutDescriptor) *BindGroupLayout {
        return wgpuDeviceCreateBindGroupLayout(self, descriptor);
    }

    /// TODO
    /// 
    /// If @ref WGPUBufferDescriptor::mappedAtCreation is `true` and the mapping allocation fails,
    /// returns `NULL`.
    extern fn wgpuDeviceCreateBuffer(self: *Device, descriptor: *const BufferDescriptor) ?*Buffer;
    /// TODO
    /// 
    /// If @ref WGPUBufferDescriptor::mappedAtCreation is `true` and the mapping allocation fails,
    /// returns `NULL`.
    pub fn createBuffer(self: *Device, descriptor: *const BufferDescriptor) ?*Buffer {
        return wgpuDeviceCreateBuffer(self, descriptor);
    }

    extern fn wgpuDeviceCreateCommandEncoder(self: *Device, descriptor: ?*const CommandEncoderDescriptor) *CommandEncoder;
    pub fn createCommandEncoder(self: *Device, descriptor: ?*const CommandEncoderDescriptor) *CommandEncoder {
        return wgpuDeviceCreateCommandEncoder(self, descriptor);
    }

    extern fn wgpuDeviceCreateComputePipeline(self: *Device, descriptor: *const ComputePipelineDescriptor) *ComputePipeline;
    pub fn createComputePipeline(self: *Device, descriptor: *const ComputePipelineDescriptor) *ComputePipeline {
        return wgpuDeviceCreateComputePipeline(self, descriptor);
    }

    extern fn wgpuDeviceCreateComputePipelineAsync(self: *Device, descriptor: *const ComputePipelineDescriptor, callback_info: CreateComputePipelineAsyncCallbackInfo) Future;
    pub fn createComputePipelineAsync(self: *Device, descriptor: *const ComputePipelineDescriptor, callback_info: CreateComputePipelineAsyncCallbackInfo) Future {
        return wgpuDeviceCreateComputePipelineAsync(self, descriptor, callback_info);
    }

    /// Blocking wrapper around `createComputePipelineAsync`: waits on the returned future with
    /// `waitAny` (forever) until the callback fires.
    /// 
    /// On failure, `err.message` is copied into a thread-local buffer (truncated
    /// to 1024 bytes) and is only valid until the next `...Sync` call on the
    /// same thread.
    pub fn createComputePipelineAsyncSync(self: *Device, instance: *Instance, descriptor: *const ComputePipelineDescriptor) error{WaitFailed}!Result(CreatePipelineAsyncStatus, *ComputePipeline) {
        const Capture = struct {
            result: Result(CreatePipelineAsyncStatus, *ComputePipeline) = undefined,
            done: bool = false,
            fn cb(status: CreatePipelineAsyncStatus, pipeline: ?*ComputePipeline, message: String, ud1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                const cap_ptr: *@This() = @ptrCast(@alignCast(ud1.?));
                cap_ptr.result = if (status == .success) .{ .ok = pipeline.? } else .{ .err = .{ .status = status, .message = copyMessage(message) } };
                cap_ptr.done = true;
            }
        };
        var cap: Capture = .{};
        const callback_info: CreateComputePipelineAsyncCallbackInfo = .{ .mode = .wait_any_only, .callback = &Capture.cb, .userdata1 = &cap };
        const future = self.createComputePipelineAsync(descriptor, callback_info);
        var infos = [_]FutureWaitInfo{.{ .future = future }};
        while (!cap.done) {
            switch (instance.waitAny(&infos, std.math.maxInt(u64))) {
                .success, .timed_out => {},
                else => return error.WaitFailed,
            }
        }
        return cap.result;
    }

    extern fn wgpuDeviceCreatePipelineLayout(self: *Device, descriptor: *const PipelineLayoutDescriptor) *PipelineLayout;
    pub fn createPipelineLayout(self: *Device, descriptor: *const PipelineLayoutDescriptor) *PipelineLayout {
        return wgpuDeviceCreatePipelineLayout(self, descriptor);
    }

    extern fn wgpuDeviceCreateQuerySet(self: *Device, descriptor: *const QuerySetDescriptor) *QuerySet;
    pub fn createQuerySet(self: *Device, descriptor: *const QuerySetDescriptor) *QuerySet {
        return wgpuDeviceCreateQuerySet(self, descriptor);
    }

    extern fn wgpuDeviceCreateRenderPipelineAsync(self: *Device, descriptor: *const RenderPipelineDescriptor, callback_info: CreateRenderPipelineAsyncCallbackInfo) Future;
    pub fn createRenderPipelineAsync(self: *Device, descriptor: *const RenderPipelineDescriptor, callback_info: CreateRenderPipelineAsyncCallbackInfo) Future {
        return wgpuDeviceCreateRenderPipelineAsync(self, descriptor, callback_info);
    }

    /// Blocking wrapper around `createRenderPipelineAsync`: waits on the returned future with
    /// `waitAny` (forever) until the callback fires.
    /// 
    /// On failure, `err.message` is copied into a thread-local buffer (truncated
    /// to 1024 bytes) and is only valid until the next `...Sync` call on the
    /// same thread.
    pub fn createRenderPipelineAsyncSync(self: *Device, instance: *Instance, descriptor: *const RenderPipelineDescriptor) error{WaitFailed}!Result(CreatePipelineAsyncStatus, *RenderPipeline) {
        const Capture = struct {
            result: Result(CreatePipelineAsyncStatus, *RenderPipeline) = undefined,
            done: bool = false,
            fn cb(status: CreatePipelineAsyncStatus, pipeline: ?*RenderPipeline, message: String, ud1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                const cap_ptr: *@This() = @ptrCast(@alignCast(ud1.?));
                cap_ptr.result = if (status == .success) .{ .ok = pipeline.? } else .{ .err = .{ .status = status, .message = copyMessage(message) } };
                cap_ptr.done = true;
            }
        };
        var cap: Capture = .{};
        const callback_info: CreateRenderPipelineAsyncCallbackInfo = .{ .mode = .wait_any_only, .callback = &Capture.cb, .userdata1 = &cap };
        const future = self.createRenderPipelineAsync(descriptor, callback_info);
        var infos = [_]FutureWaitInfo{.{ .future = future }};
        while (!cap.done) {
            switch (instance.waitAny(&infos, std.math.maxInt(u64))) {
                .success, .timed_out => {},
                else => return error.WaitFailed,
            }
        }
        return cap.result;
    }

    extern fn wgpuDeviceCreateRenderBundleEncoder(self: *Device, descriptor: *const RenderBundleEncoderDescriptor) *RenderBundleEncoder;
    pub fn createRenderBundleEncoder(self: *Device, descriptor: *const RenderBundleEncoderDescriptor) *RenderBundleEncoder {
        return wgpuDeviceCreateRenderBundleEncoder(self, descriptor);
    }

    extern fn wgpuDeviceCreateRenderPipeline(self: *Device, descriptor: *const RenderPipelineDescriptor) *RenderPipeline;
    pub fn createRenderPipeline(self: *Device, descriptor: *const RenderPipelineDescriptor) *RenderPipeline {
        return wgpuDeviceCreateRenderPipeline(self, descriptor);
    }

    extern fn wgpuDeviceCreateSampler(self: *Device, descriptor: ?*const SamplerDescriptor) *Sampler;
    pub fn createSampler(self: *Device, descriptor: ?*const SamplerDescriptor) *Sampler {
        return wgpuDeviceCreateSampler(self, descriptor);
    }

    extern fn wgpuDeviceCreateShaderModule(self: *Device, descriptor: *const ShaderModuleDescriptor) *ShaderModule;
    pub fn createShaderModule(self: *Device, descriptor: *const ShaderModuleDescriptor) *ShaderModule {
        return wgpuDeviceCreateShaderModule(self, descriptor);
    }

    extern fn wgpuDeviceCreateTexture(self: *Device, descriptor: *const TextureDescriptor) *Texture;
    pub fn createTexture(self: *Device, descriptor: *const TextureDescriptor) *Texture {
        return wgpuDeviceCreateTexture(self, descriptor);
    }

    extern fn wgpuDeviceDestroy(self: *Device) void;
    pub fn destroy(self: *Device) void {
        return wgpuDeviceDestroy(self);
    }

    extern fn wgpuDeviceGetLostFuture(self: *Device) Future;
    pub fn getLostFuture(self: *Device) Future {
        return wgpuDeviceGetLostFuture(self);
    }

    extern fn wgpuDeviceGetLimits(self: *Device, limits: *Limits) Status;
    pub fn getLimits(self: *Device, limits: *Limits) Status {
        return wgpuDeviceGetLimits(self, limits);
    }

    extern fn wgpuDeviceHasFeature(self: *Device, feature: FeatureName) Bool;
    pub fn hasFeature(self: *Device, feature: FeatureName) bool {
        return (wgpuDeviceHasFeature(self, feature)).into();
    }

    /// Get the list of @ref WGPUFeatureName values supported by the device.
    extern fn wgpuDeviceGetFeatures(self: *Device, features: *SupportedFeatures) void;
    /// Get the list of @ref WGPUFeatureName values supported by the device.
    pub fn getFeatures(self: *Device, features: *SupportedFeatures) void {
        return wgpuDeviceGetFeatures(self, features);
    }

    extern fn wgpuDeviceGetAdapterInfo(self: *Device, adapter_info: *AdapterInfo) Status;
    pub fn getAdapterInfo(self: *Device, adapter_info: *AdapterInfo) Status {
        return wgpuDeviceGetAdapterInfo(self, adapter_info);
    }

    extern fn wgpuDeviceGetQueue(self: *Device) *Queue;
    pub fn getQueue(self: *Device) *Queue {
        return wgpuDeviceGetQueue(self);
    }

    /// Pushes an error scope to the current thread's error scope stack.
    /// See @ref ErrorScopes.
    extern fn wgpuDevicePushErrorScope(self: *Device, filter: ErrorFilter) void;
    /// Pushes an error scope to the current thread's error scope stack.
    /// See @ref ErrorScopes.
    pub fn pushErrorScope(self: *Device, filter: ErrorFilter) void {
        return wgpuDevicePushErrorScope(self, filter);
    }

    /// Pops an error scope to the current thread's error scope stack,
    /// asynchronously returning the result. See @ref ErrorScopes.
    extern fn wgpuDevicePopErrorScope(self: *Device, callback_info: PopErrorScopeCallbackInfo) Future;
    /// Pops an error scope to the current thread's error scope stack,
    /// asynchronously returning the result. See @ref ErrorScopes.
    pub fn popErrorScope(self: *Device, callback_info: PopErrorScopeCallbackInfo) Future {
        return wgpuDevicePopErrorScope(self, callback_info);
    }

    /// Blocking wrapper around `popErrorScope`: waits on the returned future with
    /// `waitAny` (forever) until the callback fires.
    /// 
    /// On failure, `err.message` is copied into a thread-local buffer (truncated
    /// to 1024 bytes) and is only valid until the next `...Sync` call on the
    /// same thread.
    pub fn popErrorScopeSync(self: *Device, instance: *Instance) error{WaitFailed}!Result(PopErrorScopeStatus, ErrorType) {
        const Capture = struct {
            result: Result(PopErrorScopeStatus, ErrorType) = undefined,
            done: bool = false,
            fn cb(status: PopErrorScopeStatus, @"type": ErrorType, message: String, ud1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                const cap_ptr: *@This() = @ptrCast(@alignCast(ud1.?));
                cap_ptr.result = if (status == .success) .{ .ok = @"type" } else .{ .err = .{ .status = status, .message = copyMessage(message) } };
                cap_ptr.done = true;
            }
        };
        var cap: Capture = .{};
        const callback_info: PopErrorScopeCallbackInfo = .{ .mode = .wait_any_only, .callback = &Capture.cb, .userdata1 = &cap };
        const future = self.popErrorScope(callback_info);
        var infos = [_]FutureWaitInfo{.{ .future = future }};
        while (!cap.done) {
            switch (instance.waitAny(&infos, std.math.maxInt(u64))) {
                .success, .timed_out => {},
                else => return error.WaitFailed,
            }
        }
        return cap.result;
    }

    extern fn wgpuDeviceSetLabel(self: *Device, label: String) void;
    pub fn setLabel(self: *Device, label: []const u8) void {
        return wgpuDeviceSetLabel(self, String.from(label));
    }

    extern fn wgpuDeviceAddRef(self: *@This()) void;
    pub const addRef = wgpuDeviceAddRef;

    extern fn wgpuDeviceRelease(self: *@This()) void;
    pub const release = wgpuDeviceRelease;
};

/// A sampleable 2D texture that may perform 0-copy YUV sampling internally. Creation of @ref WGPUExternalTexture is extremely implementation-dependent and not defined in this header.
pub const ExternalTexture = opaque {
    extern fn wgpuExternalTextureSetLabel(self: *ExternalTexture, label: String) void;
    pub fn setLabel(self: *ExternalTexture, label: []const u8) void {
        return wgpuExternalTextureSetLabel(self, String.from(label));
    }

    extern fn wgpuExternalTextureAddRef(self: *@This()) void;
    pub const addRef = wgpuExternalTextureAddRef;

    extern fn wgpuExternalTextureRelease(self: *@This()) void;
    pub const release = wgpuExternalTextureRelease;
};

pub const Instance = opaque {
    /// Creates a @ref WGPUSurface, see @ref Surface-Creation for more details.
    extern fn wgpuInstanceCreateSurface(self: *Instance, descriptor: *const SurfaceDescriptor) *Surface;
    /// Creates a @ref WGPUSurface, see @ref Surface-Creation for more details.
    pub fn createSurface(self: *Instance, descriptor: *const SurfaceDescriptor) *Surface {
        return wgpuInstanceCreateSurface(self, descriptor);
    }

    /// Get the list of @ref WGPUWGSLLanguageFeatureName values supported by the instance.
    extern fn wgpuInstanceGetWGSLLanguageFeatures(self: *Instance, features: *SupportedWGSLLanguageFeatures) void;
    /// Get the list of @ref WGPUWGSLLanguageFeatureName values supported by the instance.
    pub fn getWGSLLanguageFeatures(self: *Instance, features: *SupportedWGSLLanguageFeatures) void {
        return wgpuInstanceGetWGSLLanguageFeatures(self, features);
    }

    extern fn wgpuInstanceHasWGSLLanguageFeature(self: *Instance, feature: WGSLLanguageFeatureName) Bool;
    pub fn hasWGSLLanguageFeature(self: *Instance, feature: WGSLLanguageFeatureName) bool {
        return (wgpuInstanceHasWGSLLanguageFeature(self, feature)).into();
    }

    /// Processes asynchronous events on this `WGPUInstance`, calling any callbacks for asynchronous operations created with @ref WGPUCallbackMode_AllowProcessEvents.
    /// 
    /// See @ref Process-Events for more information.
    extern fn wgpuInstanceProcessEvents(self: *Instance) void;
    /// Processes asynchronous events on this `WGPUInstance`, calling any callbacks for asynchronous operations created with @ref WGPUCallbackMode_AllowProcessEvents.
    /// 
    /// See @ref Process-Events for more information.
    pub fn processEvents(self: *Instance) void {
        return wgpuInstanceProcessEvents(self);
    }

    extern fn wgpuInstanceRequestAdapter(self: *Instance, options: ?*const RequestAdapterOptions, callback_info: RequestAdapterCallbackInfo) Future;
    pub fn requestAdapter(self: *Instance, options: ?*const RequestAdapterOptions, callback_info: RequestAdapterCallbackInfo) Future {
        return wgpuInstanceRequestAdapter(self, options, callback_info);
    }

    /// Blocking wrapper around `requestAdapter`: waits on the returned future with
    /// `waitAny` (forever) until the callback fires.
    /// 
    /// On failure, `err.message` is copied into a thread-local buffer (truncated
    /// to 1024 bytes) and is only valid until the next `...Sync` call on the
    /// same thread.
    pub fn requestAdapterSync(self: *Instance, options: ?*const RequestAdapterOptions) error{WaitFailed}!Result(RequestAdapterStatus, *Adapter) {
        const Capture = struct {
            result: Result(RequestAdapterStatus, *Adapter) = undefined,
            done: bool = false,
            fn cb(status: RequestAdapterStatus, adapter: ?*Adapter, message: String, ud1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                const cap_ptr: *@This() = @ptrCast(@alignCast(ud1.?));
                cap_ptr.result = if (status == .success) .{ .ok = adapter.? } else .{ .err = .{ .status = status, .message = copyMessage(message) } };
                cap_ptr.done = true;
            }
        };
        var cap: Capture = .{};
        const callback_info: RequestAdapterCallbackInfo = .{ .mode = .wait_any_only, .callback = &Capture.cb, .userdata1 = &cap };
        const future = self.requestAdapter(options, callback_info);
        var infos = [_]FutureWaitInfo{.{ .future = future }};
        while (!cap.done) {
            switch (self.waitAny(&infos, std.math.maxInt(u64))) {
                .success, .timed_out => {},
                else => return error.WaitFailed,
            }
        }
        return cap.result;
    }

    /// Wait for at least one WGPUFuture in `futures` to complete, and call callbacks of the respective completed asynchronous operations.
    /// 
    /// See @ref Wait-Any for more information.
    extern fn wgpuInstanceWaitAny(self: *Instance, future_count: usize, futures: ?[*]FutureWaitInfo, timeout_NS: u64) WaitStatus;
    /// Wait for at least one WGPUFuture in `futures` to complete, and call callbacks of the respective completed asynchronous operations.
    /// 
    /// See @ref Wait-Any for more information.
    pub fn waitAny(self: *Instance, futures: []FutureWaitInfo, timeout_NS: u64) WaitStatus {
        return wgpuInstanceWaitAny(self, futures.len, if (futures.len == 0) null else futures.ptr, timeout_NS);
    }

    extern fn wgpuInstanceAddRef(self: *@This()) void;
    pub const addRef = wgpuInstanceAddRef;

    extern fn wgpuInstanceRelease(self: *@This()) void;
    pub const release = wgpuInstanceRelease;
};

pub const PipelineLayout = opaque {
    extern fn wgpuPipelineLayoutSetLabel(self: *PipelineLayout, label: String) void;
    pub fn setLabel(self: *PipelineLayout, label: []const u8) void {
        return wgpuPipelineLayoutSetLabel(self, String.from(label));
    }

    extern fn wgpuPipelineLayoutAddRef(self: *@This()) void;
    pub const addRef = wgpuPipelineLayoutAddRef;

    extern fn wgpuPipelineLayoutRelease(self: *@This()) void;
    pub const release = wgpuPipelineLayoutRelease;
};

pub const QuerySet = opaque {
    extern fn wgpuQuerySetSetLabel(self: *QuerySet, label: String) void;
    pub fn setLabel(self: *QuerySet, label: []const u8) void {
        return wgpuQuerySetSetLabel(self, String.from(label));
    }

    extern fn wgpuQuerySetGetType(self: *QuerySet) QueryType;
    pub fn getType(self: *QuerySet) QueryType {
        return wgpuQuerySetGetType(self);
    }

    extern fn wgpuQuerySetGetCount(self: *QuerySet) u32;
    pub fn getCount(self: *QuerySet) u32 {
        return wgpuQuerySetGetCount(self);
    }

    extern fn wgpuQuerySetDestroy(self: *QuerySet) void;
    pub fn destroy(self: *QuerySet) void {
        return wgpuQuerySetDestroy(self);
    }

    extern fn wgpuQuerySetAddRef(self: *@This()) void;
    pub const addRef = wgpuQuerySetAddRef;

    extern fn wgpuQuerySetRelease(self: *@This()) void;
    pub const release = wgpuQuerySetRelease;
};

pub const Queue = opaque {
    extern fn wgpuQueueSubmit(self: *Queue, commands_count: usize, commands: [*]const ?*CommandBuffer) void;
    pub fn submit(self: *Queue, commands: []const ?*CommandBuffer) void {
        return wgpuQueueSubmit(self, commands.len, commands.ptr);
    }

    extern fn wgpuQueueOnSubmittedWorkDone(self: *Queue, callback_info: QueueWorkDoneCallbackInfo) Future;
    pub fn onSubmittedWorkDone(self: *Queue, callback_info: QueueWorkDoneCallbackInfo) Future {
        return wgpuQueueOnSubmittedWorkDone(self, callback_info);
    }

    /// Blocking wrapper around `onSubmittedWorkDone`: waits on the returned future with
    /// `waitAny` (forever) until the callback fires.
    /// 
    /// On failure, `err.message` is copied into a thread-local buffer (truncated
    /// to 1024 bytes) and is only valid until the next `...Sync` call on the
    /// same thread.
    pub fn onSubmittedWorkDoneSync(self: *Queue, instance: *Instance) error{WaitFailed}!Result(QueueWorkDoneStatus, void) {
        const Capture = struct {
            result: Result(QueueWorkDoneStatus, void) = undefined,
            done: bool = false,
            fn cb(status: QueueWorkDoneStatus, message: String, ud1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                const cap_ptr: *@This() = @ptrCast(@alignCast(ud1.?));
                cap_ptr.result = if (status == .success) .{ .ok = {} } else .{ .err = .{ .status = status, .message = copyMessage(message) } };
                cap_ptr.done = true;
            }
        };
        var cap: Capture = .{};
        const callback_info: QueueWorkDoneCallbackInfo = .{ .mode = .wait_any_only, .callback = &Capture.cb, .userdata1 = &cap };
        const future = self.onSubmittedWorkDone(callback_info);
        var infos = [_]FutureWaitInfo{.{ .future = future }};
        while (!cap.done) {
            switch (instance.waitAny(&infos, std.math.maxInt(u64))) {
                .success, .timed_out => {},
                else => return error.WaitFailed,
            }
        }
        return cap.result;
    }

    /// Produces a @ref DeviceError both content-timeline (`size` alignment) and device-timeline
    /// errors defined by the WebGPU specification.
    extern fn wgpuQueueWriteBuffer(self: *Queue, buffer: *Buffer, buffer_offset: u64, data: *const anyopaque, size: usize) void;
    /// Produces a @ref DeviceError both content-timeline (`size` alignment) and device-timeline
    /// errors defined by the WebGPU specification.
    pub fn writeBuffer(self: *Queue, buffer: *Buffer, buffer_offset: u64, data: []const u8) void {
        return wgpuQueueWriteBuffer(self, buffer, buffer_offset, data.ptr, data.len);
    }

    extern fn wgpuQueueWriteTexture(self: *Queue, destination: *const TexelCopyTextureInfo, data: *const anyopaque, data_size: usize, data_layout: *const TexelCopyBufferLayout, write_size: *const Extent3D) void;
    pub fn writeTexture(self: *Queue, destination: *const TexelCopyTextureInfo, data: []const u8, data_layout: *const TexelCopyBufferLayout, write_size: *const Extent3D) void {
        return wgpuQueueWriteTexture(self, destination, data.ptr, data.len, data_layout, write_size);
    }

    extern fn wgpuQueueSetLabel(self: *Queue, label: String) void;
    pub fn setLabel(self: *Queue, label: []const u8) void {
        return wgpuQueueSetLabel(self, String.from(label));
    }

    extern fn wgpuQueueAddRef(self: *@This()) void;
    pub const addRef = wgpuQueueAddRef;

    extern fn wgpuQueueRelease(self: *@This()) void;
    pub const release = wgpuQueueRelease;
};

pub const RenderBundle = opaque {
    extern fn wgpuRenderBundleSetLabel(self: *RenderBundle, label: String) void;
    pub fn setLabel(self: *RenderBundle, label: []const u8) void {
        return wgpuRenderBundleSetLabel(self, String.from(label));
    }

    extern fn wgpuRenderBundleAddRef(self: *@This()) void;
    pub const addRef = wgpuRenderBundleAddRef;

    extern fn wgpuRenderBundleRelease(self: *@This()) void;
    pub const release = wgpuRenderBundleRelease;
};

pub const RenderBundleEncoder = opaque {
    extern fn wgpuRenderBundleEncoderSetPipeline(self: *RenderBundleEncoder, pipeline: *RenderPipeline) void;
    pub fn setPipeline(self: *RenderBundleEncoder, pipeline: *RenderPipeline) void {
        return wgpuRenderBundleEncoderSetPipeline(self, pipeline);
    }

    extern fn wgpuRenderBundleEncoderSetBindGroup(self: *RenderBundleEncoder, group_index: u32, group: ?*BindGroup, dynamic_offsets_count: usize, dynamic_offsets: [*]const u32) void;
    pub fn setBindGroup(self: *RenderBundleEncoder, group_index: u32, group: ?*BindGroup, dynamic_offsets: []const u32) void {
        return wgpuRenderBundleEncoderSetBindGroup(self, group_index, group, dynamic_offsets.len, dynamic_offsets.ptr);
    }

    extern fn wgpuRenderBundleEncoderSetImmediates(self: *RenderBundleEncoder, offset: u32, data: *const anyopaque, size: usize) void;
    pub fn setImmediates(self: *RenderBundleEncoder, offset: u32, data: []const u8) void {
        return wgpuRenderBundleEncoderSetImmediates(self, offset, data.ptr, data.len);
    }

    extern fn wgpuRenderBundleEncoderDraw(self: *RenderBundleEncoder, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void;
    pub fn draw(self: *RenderBundleEncoder, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
        return wgpuRenderBundleEncoderDraw(self, vertex_count, instance_count, first_vertex, first_instance);
    }

    extern fn wgpuRenderBundleEncoderDrawIndexed(self: *RenderBundleEncoder, index_count: u32, instance_count: u32, first_index: u32, base_vertex: i32, first_instance: u32) void;
    pub fn drawIndexed(self: *RenderBundleEncoder, index_count: u32, instance_count: u32, first_index: u32, base_vertex: i32, first_instance: u32) void {
        return wgpuRenderBundleEncoderDrawIndexed(self, index_count, instance_count, first_index, base_vertex, first_instance);
    }

    extern fn wgpuRenderBundleEncoderDrawIndirect(self: *RenderBundleEncoder, indirect_buffer: *Buffer, indirect_offset: u64) void;
    pub fn drawIndirect(self: *RenderBundleEncoder, indirect_buffer: *Buffer, indirect_offset: u64) void {
        return wgpuRenderBundleEncoderDrawIndirect(self, indirect_buffer, indirect_offset);
    }

    extern fn wgpuRenderBundleEncoderDrawIndexedIndirect(self: *RenderBundleEncoder, indirect_buffer: *Buffer, indirect_offset: u64) void;
    pub fn drawIndexedIndirect(self: *RenderBundleEncoder, indirect_buffer: *Buffer, indirect_offset: u64) void {
        return wgpuRenderBundleEncoderDrawIndexedIndirect(self, indirect_buffer, indirect_offset);
    }

    extern fn wgpuRenderBundleEncoderInsertDebugMarker(self: *RenderBundleEncoder, marker_label: String) void;
    pub fn insertDebugMarker(self: *RenderBundleEncoder, marker_label: []const u8) void {
        return wgpuRenderBundleEncoderInsertDebugMarker(self, String.from(marker_label));
    }

    extern fn wgpuRenderBundleEncoderPopDebugGroup(self: *RenderBundleEncoder) void;
    pub fn popDebugGroup(self: *RenderBundleEncoder) void {
        return wgpuRenderBundleEncoderPopDebugGroup(self);
    }

    extern fn wgpuRenderBundleEncoderPushDebugGroup(self: *RenderBundleEncoder, group_label: String) void;
    pub fn pushDebugGroup(self: *RenderBundleEncoder, group_label: []const u8) void {
        return wgpuRenderBundleEncoderPushDebugGroup(self, String.from(group_label));
    }

    extern fn wgpuRenderBundleEncoderSetVertexBuffer(self: *RenderBundleEncoder, slot: u32, buffer: ?*Buffer, offset: u64, size: u64) void;
    pub fn setVertexBuffer(self: *RenderBundleEncoder, slot: u32, buffer: ?*Buffer, offset: u64, size: u64) void {
        return wgpuRenderBundleEncoderSetVertexBuffer(self, slot, buffer, offset, size);
    }

    extern fn wgpuRenderBundleEncoderSetIndexBuffer(self: *RenderBundleEncoder, buffer: *Buffer, format: IndexFormat, offset: u64, size: u64) void;
    pub fn setIndexBuffer(self: *RenderBundleEncoder, buffer: *Buffer, format: IndexFormat, offset: u64, size: u64) void {
        return wgpuRenderBundleEncoderSetIndexBuffer(self, buffer, format, offset, size);
    }

    extern fn wgpuRenderBundleEncoderFinish(self: *RenderBundleEncoder, descriptor: ?*const RenderBundleDescriptor) *RenderBundle;
    pub fn finish(self: *RenderBundleEncoder, descriptor: ?*const RenderBundleDescriptor) *RenderBundle {
        return wgpuRenderBundleEncoderFinish(self, descriptor);
    }

    extern fn wgpuRenderBundleEncoderSetLabel(self: *RenderBundleEncoder, label: String) void;
    pub fn setLabel(self: *RenderBundleEncoder, label: []const u8) void {
        return wgpuRenderBundleEncoderSetLabel(self, String.from(label));
    }

    extern fn wgpuRenderBundleEncoderAddRef(self: *@This()) void;
    pub const addRef = wgpuRenderBundleEncoderAddRef;

    extern fn wgpuRenderBundleEncoderRelease(self: *@This()) void;
    pub const release = wgpuRenderBundleEncoderRelease;
};

pub const RenderPassEncoder = opaque {
    extern fn wgpuRenderPassEncoderSetPipeline(self: *RenderPassEncoder, pipeline: *RenderPipeline) void;
    pub fn setPipeline(self: *RenderPassEncoder, pipeline: *RenderPipeline) void {
        return wgpuRenderPassEncoderSetPipeline(self, pipeline);
    }

    extern fn wgpuRenderPassEncoderSetBindGroup(self: *RenderPassEncoder, group_index: u32, group: ?*BindGroup, dynamic_offsets_count: usize, dynamic_offsets: [*]const u32) void;
    pub fn setBindGroup(self: *RenderPassEncoder, group_index: u32, group: ?*BindGroup, dynamic_offsets: []const u32) void {
        return wgpuRenderPassEncoderSetBindGroup(self, group_index, group, dynamic_offsets.len, dynamic_offsets.ptr);
    }

    extern fn wgpuRenderPassEncoderSetImmediates(self: *RenderPassEncoder, offset: u32, data: *const anyopaque, size: usize) void;
    pub fn setImmediates(self: *RenderPassEncoder, offset: u32, data: []const u8) void {
        return wgpuRenderPassEncoderSetImmediates(self, offset, data.ptr, data.len);
    }

    extern fn wgpuRenderPassEncoderDraw(self: *RenderPassEncoder, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void;
    pub fn draw(self: *RenderPassEncoder, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
        return wgpuRenderPassEncoderDraw(self, vertex_count, instance_count, first_vertex, first_instance);
    }

    extern fn wgpuRenderPassEncoderDrawIndexed(self: *RenderPassEncoder, index_count: u32, instance_count: u32, first_index: u32, base_vertex: i32, first_instance: u32) void;
    pub fn drawIndexed(self: *RenderPassEncoder, index_count: u32, instance_count: u32, first_index: u32, base_vertex: i32, first_instance: u32) void {
        return wgpuRenderPassEncoderDrawIndexed(self, index_count, instance_count, first_index, base_vertex, first_instance);
    }

    extern fn wgpuRenderPassEncoderDrawIndirect(self: *RenderPassEncoder, indirect_buffer: *Buffer, indirect_offset: u64) void;
    pub fn drawIndirect(self: *RenderPassEncoder, indirect_buffer: *Buffer, indirect_offset: u64) void {
        return wgpuRenderPassEncoderDrawIndirect(self, indirect_buffer, indirect_offset);
    }

    extern fn wgpuRenderPassEncoderDrawIndexedIndirect(self: *RenderPassEncoder, indirect_buffer: *Buffer, indirect_offset: u64) void;
    pub fn drawIndexedIndirect(self: *RenderPassEncoder, indirect_buffer: *Buffer, indirect_offset: u64) void {
        return wgpuRenderPassEncoderDrawIndexedIndirect(self, indirect_buffer, indirect_offset);
    }

    extern fn wgpuRenderPassEncoderExecuteBundles(self: *RenderPassEncoder, bundles_count: usize, bundles: [*]const ?*RenderBundle) void;
    pub fn executeBundles(self: *RenderPassEncoder, bundles: []const ?*RenderBundle) void {
        return wgpuRenderPassEncoderExecuteBundles(self, bundles.len, bundles.ptr);
    }

    extern fn wgpuRenderPassEncoderInsertDebugMarker(self: *RenderPassEncoder, marker_label: String) void;
    pub fn insertDebugMarker(self: *RenderPassEncoder, marker_label: []const u8) void {
        return wgpuRenderPassEncoderInsertDebugMarker(self, String.from(marker_label));
    }

    extern fn wgpuRenderPassEncoderPopDebugGroup(self: *RenderPassEncoder) void;
    pub fn popDebugGroup(self: *RenderPassEncoder) void {
        return wgpuRenderPassEncoderPopDebugGroup(self);
    }

    extern fn wgpuRenderPassEncoderPushDebugGroup(self: *RenderPassEncoder, group_label: String) void;
    pub fn pushDebugGroup(self: *RenderPassEncoder, group_label: []const u8) void {
        return wgpuRenderPassEncoderPushDebugGroup(self, String.from(group_label));
    }

    extern fn wgpuRenderPassEncoderSetStencilReference(self: *RenderPassEncoder, reference: u32) void;
    pub fn setStencilReference(self: *RenderPassEncoder, reference: u32) void {
        return wgpuRenderPassEncoderSetStencilReference(self, reference);
    }

    extern fn wgpuRenderPassEncoderSetBlendConstant(self: *RenderPassEncoder, color: *const Color) void;
    pub fn setBlendConstant(self: *RenderPassEncoder, color: *const Color) void {
        return wgpuRenderPassEncoderSetBlendConstant(self, color);
    }

    /// TODO
    /// 
    /// If any argument is non-finite, produces a @ref NonFiniteFloatValueError.
    extern fn wgpuRenderPassEncoderSetViewport(self: *RenderPassEncoder, x: f32, y: f32, width: f32, height: f32, min_depth: f32, max_depth: f32) void;
    /// TODO
    /// 
    /// If any argument is non-finite, produces a @ref NonFiniteFloatValueError.
    pub fn setViewport(self: *RenderPassEncoder, x: f32, y: f32, width: f32, height: f32, min_depth: f32, max_depth: f32) void {
        return wgpuRenderPassEncoderSetViewport(self, x, y, width, height, min_depth, max_depth);
    }

    extern fn wgpuRenderPassEncoderSetScissorRect(self: *RenderPassEncoder, x: u32, y: u32, width: u32, height: u32) void;
    pub fn setScissorRect(self: *RenderPassEncoder, x: u32, y: u32, width: u32, height: u32) void {
        return wgpuRenderPassEncoderSetScissorRect(self, x, y, width, height);
    }

    extern fn wgpuRenderPassEncoderSetVertexBuffer(self: *RenderPassEncoder, slot: u32, buffer: ?*Buffer, offset: u64, size: u64) void;
    pub fn setVertexBuffer(self: *RenderPassEncoder, slot: u32, buffer: ?*Buffer, offset: u64, size: u64) void {
        return wgpuRenderPassEncoderSetVertexBuffer(self, slot, buffer, offset, size);
    }

    extern fn wgpuRenderPassEncoderSetIndexBuffer(self: *RenderPassEncoder, buffer: *Buffer, format: IndexFormat, offset: u64, size: u64) void;
    pub fn setIndexBuffer(self: *RenderPassEncoder, buffer: *Buffer, format: IndexFormat, offset: u64, size: u64) void {
        return wgpuRenderPassEncoderSetIndexBuffer(self, buffer, format, offset, size);
    }

    extern fn wgpuRenderPassEncoderBeginOcclusionQuery(self: *RenderPassEncoder, query_index: u32) void;
    pub fn beginOcclusionQuery(self: *RenderPassEncoder, query_index: u32) void {
        return wgpuRenderPassEncoderBeginOcclusionQuery(self, query_index);
    }

    extern fn wgpuRenderPassEncoderEndOcclusionQuery(self: *RenderPassEncoder) void;
    pub fn endOcclusionQuery(self: *RenderPassEncoder) void {
        return wgpuRenderPassEncoderEndOcclusionQuery(self);
    }

    extern fn wgpuRenderPassEncoderEnd(self: *RenderPassEncoder) void;
    pub fn end(self: *RenderPassEncoder) void {
        return wgpuRenderPassEncoderEnd(self);
    }

    extern fn wgpuRenderPassEncoderSetLabel(self: *RenderPassEncoder, label: String) void;
    pub fn setLabel(self: *RenderPassEncoder, label: []const u8) void {
        return wgpuRenderPassEncoderSetLabel(self, String.from(label));
    }

    extern fn wgpuRenderPassEncoderAddRef(self: *@This()) void;
    pub const addRef = wgpuRenderPassEncoderAddRef;

    extern fn wgpuRenderPassEncoderRelease(self: *@This()) void;
    pub const release = wgpuRenderPassEncoderRelease;
};

pub const RenderPipeline = opaque {
    extern fn wgpuRenderPipelineGetBindGroupLayout(self: *RenderPipeline, group_index: u32) *BindGroupLayout;
    pub fn getBindGroupLayout(self: *RenderPipeline, group_index: u32) *BindGroupLayout {
        return wgpuRenderPipelineGetBindGroupLayout(self, group_index);
    }

    extern fn wgpuRenderPipelineSetLabel(self: *RenderPipeline, label: String) void;
    pub fn setLabel(self: *RenderPipeline, label: []const u8) void {
        return wgpuRenderPipelineSetLabel(self, String.from(label));
    }

    extern fn wgpuRenderPipelineAddRef(self: *@This()) void;
    pub const addRef = wgpuRenderPipelineAddRef;

    extern fn wgpuRenderPipelineRelease(self: *@This()) void;
    pub const release = wgpuRenderPipelineRelease;
};

pub const Sampler = opaque {
    extern fn wgpuSamplerSetLabel(self: *Sampler, label: String) void;
    pub fn setLabel(self: *Sampler, label: []const u8) void {
        return wgpuSamplerSetLabel(self, String.from(label));
    }

    extern fn wgpuSamplerAddRef(self: *@This()) void;
    pub const addRef = wgpuSamplerAddRef;

    extern fn wgpuSamplerRelease(self: *@This()) void;
    pub const release = wgpuSamplerRelease;
};

pub const ShaderModule = opaque {
    extern fn wgpuShaderModuleGetCompilationInfo(self: *ShaderModule, callback_info: CompilationInfoCallbackInfo) Future;
    pub fn getCompilationInfo(self: *ShaderModule, callback_info: CompilationInfoCallbackInfo) Future {
        return wgpuShaderModuleGetCompilationInfo(self, callback_info);
    }

    /// Blocking wrapper around `getCompilationInfo`: waits on the returned future with
    /// `waitAny` (forever) until the callback fires.
    /// 
    /// On failure, `err.message` is copied into a thread-local buffer (truncated
    /// to 1024 bytes) and is only valid until the next `...Sync` call on the
    /// same thread.
    pub fn getCompilationInfoSync(self: *ShaderModule, instance: *Instance) error{WaitFailed}!Result(CompilationInfoRequestStatus, *const CompilationInfo) {
        const Capture = struct {
            result: Result(CompilationInfoRequestStatus, *const CompilationInfo) = undefined,
            done: bool = false,
            fn cb(status: CompilationInfoRequestStatus, compilation_info: *const CompilationInfo, ud1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                const cap_ptr: *@This() = @ptrCast(@alignCast(ud1.?));
                cap_ptr.result = if (status == .success) .{ .ok = compilation_info } else .{ .err = .{ .status = status, .message = "" } };
                cap_ptr.done = true;
            }
        };
        var cap: Capture = .{};
        const callback_info: CompilationInfoCallbackInfo = .{ .mode = .wait_any_only, .callback = &Capture.cb, .userdata1 = &cap };
        const future = self.getCompilationInfo(callback_info);
        var infos = [_]FutureWaitInfo{.{ .future = future }};
        while (!cap.done) {
            switch (instance.waitAny(&infos, std.math.maxInt(u64))) {
                .success, .timed_out => {},
                else => return error.WaitFailed,
            }
        }
        return cap.result;
    }

    extern fn wgpuShaderModuleSetLabel(self: *ShaderModule, label: String) void;
    pub fn setLabel(self: *ShaderModule, label: []const u8) void {
        return wgpuShaderModuleSetLabel(self, String.from(label));
    }

    extern fn wgpuShaderModuleAddRef(self: *@This()) void;
    pub const addRef = wgpuShaderModuleAddRef;

    extern fn wgpuShaderModuleRelease(self: *@This()) void;
    pub const release = wgpuShaderModuleRelease;
};

/// An object used to continuously present image data to the user, see @ref Surfaces for more details.
pub const Surface = opaque {
    /// Configures parameters for rendering to `surface`.
    /// Produces a @ref DeviceError for all content-timeline errors defined by the WebGPU specification.
    /// 
    /// See @ref Surface-Configuration for more details.
    extern fn wgpuSurfaceConfigure(self: *Surface, config: *const SurfaceConfiguration) void;
    /// Configures parameters for rendering to `surface`.
    /// Produces a @ref DeviceError for all content-timeline errors defined by the WebGPU specification.
    /// 
    /// See @ref Surface-Configuration for more details.
    pub fn configure(self: *Surface, config: *const SurfaceConfiguration) void {
        return wgpuSurfaceConfigure(self, config);
    }

    /// Provides information on how `adapter` is able to use `surface`.
    /// See @ref Surface-Capabilities for more details.
    extern fn wgpuSurfaceGetCapabilities(self: *Surface, adapter: *Adapter, capabilities: *SurfaceCapabilities) Status;
    /// Provides information on how `adapter` is able to use `surface`.
    /// See @ref Surface-Capabilities for more details.
    pub fn getCapabilities(self: *Surface, adapter: *Adapter, capabilities: *SurfaceCapabilities) Status {
        return wgpuSurfaceGetCapabilities(self, adapter, capabilities);
    }

    /// Returns the @ref WGPUTexture to render to `surface` this frame along with metadata on the frame.
    /// Returns `NULL` and @ref WGPUSurfaceGetCurrentTextureStatus_Error if the surface is not configured.
    /// 
    /// See @ref Surface-Presenting for more details.
    extern fn wgpuSurfaceGetCurrentTexture(self: *Surface, surface_texture: *SurfaceTexture) void;
    /// Returns the @ref WGPUTexture to render to `surface` this frame along with metadata on the frame.
    /// Returns `NULL` and @ref WGPUSurfaceGetCurrentTextureStatus_Error if the surface is not configured.
    /// 
    /// See @ref Surface-Presenting for more details.
    pub fn getCurrentTexture(self: *Surface, surface_texture: *SurfaceTexture) void {
        return wgpuSurfaceGetCurrentTexture(self, surface_texture);
    }

    /// Shows `surface`'s current texture to the user.
    /// See @ref Surface-Presenting for more details.
    extern fn wgpuSurfacePresent(self: *Surface) Status;
    /// Shows `surface`'s current texture to the user.
    /// See @ref Surface-Presenting for more details.
    pub fn present(self: *Surface) Status {
        return wgpuSurfacePresent(self);
    }

    /// Removes the configuration for `surface`.
    /// See @ref Surface-Configuration for more details.
    extern fn wgpuSurfaceUnconfigure(self: *Surface) void;
    /// Removes the configuration for `surface`.
    /// See @ref Surface-Configuration for more details.
    pub fn unconfigure(self: *Surface) void {
        return wgpuSurfaceUnconfigure(self);
    }

    /// Modifies the label used to refer to `surface`.
    extern fn wgpuSurfaceSetLabel(self: *Surface, label: String) void;
    /// Modifies the label used to refer to `surface`.
    pub fn setLabel(self: *Surface, label: []const u8) void {
        return wgpuSurfaceSetLabel(self, String.from(label));
    }

    extern fn wgpuSurfaceAddRef(self: *@This()) void;
    pub const addRef = wgpuSurfaceAddRef;

    extern fn wgpuSurfaceRelease(self: *@This()) void;
    pub const release = wgpuSurfaceRelease;
};

pub const Texture = opaque {
    extern fn wgpuTextureCreateView(self: *Texture, descriptor: ?*const TextureViewDescriptor) *TextureView;
    pub fn createView(self: *Texture, descriptor: ?*const TextureViewDescriptor) *TextureView {
        return wgpuTextureCreateView(self, descriptor);
    }

    extern fn wgpuTextureSetLabel(self: *Texture, label: String) void;
    pub fn setLabel(self: *Texture, label: []const u8) void {
        return wgpuTextureSetLabel(self, String.from(label));
    }

    extern fn wgpuTextureGetWidth(self: *Texture) u32;
    pub fn getWidth(self: *Texture) u32 {
        return wgpuTextureGetWidth(self);
    }

    extern fn wgpuTextureGetHeight(self: *Texture) u32;
    pub fn getHeight(self: *Texture) u32 {
        return wgpuTextureGetHeight(self);
    }

    extern fn wgpuTextureGetDepthOrArrayLayers(self: *Texture) u32;
    pub fn getDepthOrArrayLayers(self: *Texture) u32 {
        return wgpuTextureGetDepthOrArrayLayers(self);
    }

    extern fn wgpuTextureGetMipLevelCount(self: *Texture) u32;
    pub fn getMipLevelCount(self: *Texture) u32 {
        return wgpuTextureGetMipLevelCount(self);
    }

    extern fn wgpuTextureGetSampleCount(self: *Texture) u32;
    pub fn getSampleCount(self: *Texture) u32 {
        return wgpuTextureGetSampleCount(self);
    }

    extern fn wgpuTextureGetDimension(self: *Texture) TextureDimension;
    pub fn getDimension(self: *Texture) TextureDimension {
        return wgpuTextureGetDimension(self);
    }

    extern fn wgpuTextureGetTextureBindingViewDimension(self: *Texture) TextureViewDimension;
    pub fn getTextureBindingViewDimension(self: *Texture) TextureViewDimension {
        return wgpuTextureGetTextureBindingViewDimension(self);
    }

    extern fn wgpuTextureGetFormat(self: *Texture) TextureFormat;
    pub fn getFormat(self: *Texture) TextureFormat {
        return wgpuTextureGetFormat(self);
    }

    extern fn wgpuTextureGetUsage(self: *Texture) TextureUsage;
    pub fn getUsage(self: *Texture) TextureUsage {
        return wgpuTextureGetUsage(self);
    }

    extern fn wgpuTextureDestroy(self: *Texture) void;
    pub fn destroy(self: *Texture) void {
        return wgpuTextureDestroy(self);
    }

    extern fn wgpuTextureAddRef(self: *@This()) void;
    pub const addRef = wgpuTextureAddRef;

    extern fn wgpuTextureRelease(self: *@This()) void;
    pub const release = wgpuTextureRelease;
};

pub const TextureView = opaque {
    extern fn wgpuTextureViewSetLabel(self: *TextureView, label: String) void;
    pub fn setLabel(self: *TextureView, label: []const u8) void {
        return wgpuTextureViewSetLabel(self, String.from(label));
    }

    extern fn wgpuTextureViewAddRef(self: *@This()) void;
    pub const addRef = wgpuTextureViewAddRef;

    extern fn wgpuTextureViewRelease(self: *@This()) void;
    pub const release = wgpuTextureViewRelease;
};

/// Create a WGPUInstance
extern fn wgpuCreateInstance(descriptor: ?*const InstanceDescriptor) *Instance;
/// Create a WGPUInstance
pub fn createInstance(descriptor: ?*const InstanceDescriptor) *Instance {
    return wgpuCreateInstance(descriptor);
}

/// Get the list of @ref WGPUInstanceFeatureName values supported by the instance.
extern fn wgpuGetInstanceFeatures(features: *SupportedInstanceFeatures) void;
/// Get the list of @ref WGPUInstanceFeatureName values supported by the instance.
pub fn getInstanceFeatures(features: *SupportedInstanceFeatures) void {
    return wgpuGetInstanceFeatures(features);
}

/// Get the limits supported by the instance.
extern fn wgpuGetInstanceLimits(limits: *InstanceLimits) Status;
/// Get the limits supported by the instance.
pub fn getInstanceLimits(limits: *InstanceLimits) Status {
    return wgpuGetInstanceLimits(limits);
}

/// Check whether a particular @ref WGPUInstanceFeatureName is supported by the instance.
extern fn wgpuHasInstanceFeature(feature: InstanceFeatureName) Bool;
/// Check whether a particular @ref WGPUInstanceFeatureName is supported by the instance.
pub fn hasInstanceFeature(feature: InstanceFeatureName) bool {
    return (wgpuHasInstanceFeature(feature)).into();
}

