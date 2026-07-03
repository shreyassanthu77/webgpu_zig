## Findings

### wgpu-native differences
Introduces `WGPUNativeSType` enum starting at `0x00030001` with STypes like `DeviceExtras`, `NativeLimits`, `ShaderSourceGLSL`, `InstanceExtras`, `BindGroupEntryExtras`, `BindGroupLayoutEntryExtras`, `QuerySetDescriptorExtras`, `SurfaceConfigurationExtras`, `SurfaceSourceSwapChainPanel`, `PrimitiveStateExtras`, and `SamplerDescriptorExtras`.

### WGVK differences (excluding RayTracing)
Introduces additional `WGPUSType` values like `EmscriptenSurfaceSourceCanvasHTMLSelector` (`0x00040000`), `InstanceLayerSelection` (`0x10000001`), `BufferAllocatorSelector` (`0x10000002`), `ShaderSourceGLSL` (`0x10000003`), `PrimitiveLineWidthInfo` (`0x10000004`), `SurfaceSourceDrmPlane` (`0x10000005`), and `ExtrasLimits` (`0x10000006`).
Adds corresponding structs like `WGPUEmscriptenSurfaceSourceCanvasHTMLSelector`, `WGPUInstanceLayerSelection`, `WGPUBufferAllocatorSelector`, `WGPUSurfaceSourceDrmPlane`, `WGPUExtrasLimits`, and `WGPUPrimitiveLineWidthInfo`.

## Plan for Seamless Integration

- Create JSON extension files (e.g., `wgpu_native_ext.json` and `wgvk_ext.json`) containing only the backend-specific `enums`, `structs`, `functions`, and `objects`.
- Generate a separate module (e.g., `wgpu_native_bindings.zig` or `wgvk_bindings.zig`) for backend-specific features instead of modifying the agnostic `bindings.zig`, keeping the agnostic bindings purely tracked in git.
- For `SType` extensions, generate an extended `SType` enum in the new module with an `into()` method that casts back to the original agnostic `webgpu.SType`.
- Modify the `tools/gen/main.zig` script (or add a new script) to generate these backend extension modules, allowing them to import and interoperate with the base agnostic bindings.
- Update `build.zig` to expose this new extension module to consumers when they select a specific backend, without affecting the base `webgpu` module.
