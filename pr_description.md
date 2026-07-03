## Findings

### wgpu-native differences
Introduces `WGPUNativeSType` enum starting at `0x00030001` with STypes like `DeviceExtras`, `NativeLimits`, `ShaderSourceGLSL`, `InstanceExtras`, `BindGroupEntryExtras`, `BindGroupLayoutEntryExtras`, `QuerySetDescriptorExtras`, `SurfaceConfigurationExtras`, `SurfaceSourceSwapChainPanel`, `PrimitiveStateExtras`, and `SamplerDescriptorExtras`.

### WGVK differences (excluding RayTracing)
Introduces additional `WGPUSType` values like `EmscriptenSurfaceSourceCanvasHTMLSelector` (`0x00040000`), `InstanceLayerSelection` (`0x10000001`), `BufferAllocatorSelector` (`0x10000002`), `ShaderSourceGLSL` (`0x10000003`), `PrimitiveLineWidthInfo` (`0x10000004`), `SurfaceSourceDrmPlane` (`0x10000005`), and `ExtrasLimits` (`0x10000006`).
Adds corresponding structs like `WGPUEmscriptenSurfaceSourceCanvasHTMLSelector`, `WGPUInstanceLayerSelection`, `WGPUBufferAllocatorSelector`, `WGPUSurfaceSourceDrmPlane`, `WGPUExtrasLimits`, and `WGPUPrimitiveLineWidthInfo`.

## Plan for Seamless Integration

- Create JSON extension files (e.g., `wgpu_native_ext.json` and `wgvk_ext.json`) structured exactly like the upstream `webgpu.json` but containing only the backend-specific `enums`, `structs`, `functions`, and `objects`.
- Modify the `tools/gen/main.zig` script to accept an optional list of extension JSON files as command-line arguments.
- Update the generator logic in `tools/gen/main.zig` to merge the ASTs in memory. Specifically, concatenate the arrays for `structs`, `functions`, and `objects`. For `enums` that already exist (like `SType`), merge their `entries` arrays.
- Update `build.zig` to conditionally pass the appropriate extension JSON file to the `gen-bindings` step depending on the `backend` build option (e.g., if `backend == .wgpu_native`, pass `wgpu_native_ext.json`).
- This ensures the generated bindings (`src/bindings.zig`) perfectly reflect the capabilities of the chosen backend while keeping the generation code clean and maintainable.
