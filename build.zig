const std = @import("std");

pub fn build(b: *std.Build) void {
	// Standard target options allows the person running `zig build` to choose
	// what target to build for. Here we do not override the defaults, which
	// means any target is allowed, and the default is native. Other options
	// for restricting supported target set are available.
	const target = b.standardTargetOptions(.{});
	const t = target.result;

	// Standard release options allow the person running `zig build` to select
	// between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
	const optimize = b.standardOptimizeOption(.{});

	const exe = b.addExecutable(.{
		.name = "ProceduralTextureCreator",
		.root_source_file = b.path("src/main.zig"),
		.target = target,
		.optimize = optimize,
		.single_threaded = true,
	});
	exe.addIncludePath(b.path("include"));
	exe.linkLibC();
	{ // compile glfw from source:
		if(t.os.tag == .windows) {
			exe.addCSourceFiles(.{.files = &[_][]const u8 {
				"lib/glfw/src/win32_init.c", "lib/glfw/src/win32_joystick.c", "lib/glfw/src/win32_monitor.c", "lib/glfw/src/win32_time.c", "lib/glfw/src/win32_thread.c", "lib/glfw/src/win32_window.c", "lib/glfw/src/wgl_context.c", "lib/glfw/src/egl_context.c", "lib/glfw/src/osmesa_context.c", "lib/glfw/src/context.c", "lib/glfw/src/init.c", "lib/glfw/src/input.c", "lib/glfw/src/monitor.c", "lib/glfw/src/vulkan.c", "lib/glfw/src/window.c"
			}, .flags = &[_][]const u8{"-gdwarf-4", "-std=c99", "-D_GLFW_WIN32"}});
			exe.linkSystemLibrary("gdi32");
			exe.linkSystemLibrary("opengl32");
		} else if(t.os.tag == .linux) {
			// TODO: if(isWayland) {
			//	exe.addCSourceFiles(&[_][]const u8 {
			//		"lib/glfw/src/linux_joystick.c", "lib/glfw/src/wl_init.c", "lib/glfw/src/wl_monitor.c", "lib/glfw/src/wl_window.c", "lib/glfw/src/posix_time.c", "lib/glfw/src/posix_thread.c", "lib/glfw/src/xkb_unicode.c", "lib/glfw/src/egl_context.c", "lib/glfw/src/osmesa_context.c", "lib/glfw/src/context.c", "lib/glfw/src/init.c", "lib/glfw/src/input.c", "lib/glfw/src/monitor.c", "lib/glfw/src/vulkan.c", "lib/glfw/src/window.c"
			//	}, &[_][]const u8{"-g",});
			//} else {
				exe.addCSourceFiles(.{.files = &[_][]const u8 {
					"lib/glfw/src/linux_joystick.c", "lib/glfw/src/x11_init.c", "lib/glfw/src/x11_monitor.c", "lib/glfw/src/x11_window.c", "lib/glfw/src/xkb_unicode.c", "lib/glfw/src/posix_time.c", "lib/glfw/src/posix_thread.c", "lib/glfw/src/glx_context.c", "lib/glfw/src/egl_context.c", "lib/glfw/src/osmesa_context.c", "lib/glfw/src/context.c", "lib/glfw/src/init.c", "lib/glfw/src/input.c", "lib/glfw/src/monitor.c", "lib/glfw/src/vulkan.c", "lib/glfw/src/window.c"
				}, .flags = &[_][]const u8{"-g", "-std=c99", "-D_GLFW_X11"}});
				exe.linkSystemLibrary("x11");
			//}
			exe.linkSystemLibrary("GL");
		} else {
			std.log.err("Unsupported target: {}\n", .{ t.os.tag });
		}
	}
	exe.addCSourceFiles(.{.files = &[_][]const u8{"lib/glad.c", "lib/stb_image.c"}, .flags = &[_][]const u8{"-g"}});
	b.installArtifact(exe);

	const run_cmd = b.addRunArtifact(exe);
	run_cmd.step.dependOn(b.getInstallStep());
	if (b.args) |args| {
		run_cmd.addArgs(args);
	}

	const run_step = b.step("run", "Run the app");
	run_step.dependOn(&run_cmd.step);
}