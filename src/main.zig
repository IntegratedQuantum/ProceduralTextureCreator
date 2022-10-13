const std = @import("std");

const graphics = @import("graphics.zig");
const mesh = @import("mesh.zig");
const settings = @import("settings.zig");
const vec = @import("vec.zig");

const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Mat4f = vec.Mat4f;

pub const c = @cImport ({
	@cInclude("glad/glad.h");
	@cInclude("GLFW/glfw3.h");
});

pub threadlocal var threadAllocator: std.mem.Allocator = undefined;

const Key = struct {
	pressed: bool = false,
	key: c_int = c.GLFW_KEY_UNKNOWN,
	scancode: c_int = 0,
	releaseAction: ?*const fn() void = null,
};
pub var keyboard: struct {
	forward: Key = Key{.key = c.GLFW_KEY_W},
	left: Key = Key{.key = c.GLFW_KEY_A},
	backward: Key = Key{.key = c.GLFW_KEY_S},
	right: Key = Key{.key = c.GLFW_KEY_D},
	sprint: Key = Key{.key = c.GLFW_KEY_LEFT_CONTROL},
	jump: Key = Key{.key = c.GLFW_KEY_SPACE},
	fall: Key = Key{.key = c.GLFW_KEY_LEFT_SHIFT},
	fullscreen: Key = Key{.key = c.GLFW_KEY_F11, .releaseAction = &Window.toggleFullscreen},
} = .{};



pub const camera = struct {
	pub var pos: Vec3f = Vec3f{.x=0, .y=0, .z=0};
	pub var rotation: Vec3f = Vec3f{.x=0, .y=0, .z=0};
	pub var direction: Vec3f = Vec3f{.x=0, .y=0, .z=0};
	pub var viewMatrix: Mat4f = Mat4f.identity();
	pub fn moveRotation(mouseX: f32, mouseY: f32) void {
		// Mouse movement along the x-axis rotates the image along the y-axis.
		rotation.x += mouseY;
		if(rotation.x > std.math.pi/2.0) {
			rotation.x = std.math.pi/2.0;
		} else if(rotation.x < -std.math.pi/2.0) {
			rotation.x = -std.math.pi/2.0;
		}
		// Mouse movement along the y-axis rotates the image along the x-axis.
		rotation.y += mouseX;

		direction = Vec3f.rotateX(Vec3f{.x=0, .y=0, .z=-1}, rotation.x).rotateY(rotation.y);
	}

	pub fn updateViewMatrix() void {
		viewMatrix = Mat4f.rotationX(rotation.x).mul(Mat4f.rotationY(rotation.y)).mul(Mat4f.translation(.{.x=-pos.x, .y=-pos.y, .z=-pos.z}));
	}
	pub var projectionMatrix: Mat4f = Mat4f.identity();

	pub fn update(deltaTime: f32) !void {
		var movement = Vec3f{.x=0, .y=0, .z=0};
		var forward = Vec3f.rotateY(Vec3f{.x=0, .y=0, .z=-1}, -camera.rotation.y);
		var right = Vec3f{.x=forward.z, .y=0, .z=-forward.x};
		if(keyboard.forward.pressed) {
			if(keyboard.sprint.pressed) {
				movement.addEqual(forward.mulScalar(8));
			} else {
				movement.addEqual(forward.mulScalar(4));
			}
		}
		if(keyboard.backward.pressed) {
			movement.addEqual(forward.mulScalar(-4));
		}
		if(keyboard.left.pressed) {
			movement.addEqual(right.mulScalar(4));
		}
		if(keyboard.right.pressed) {
			movement.addEqual(right.mulScalar(-4));
		}
		if(keyboard.jump.pressed) {
			movement.y = 5.45;
		}
		if(keyboard.fall.pressed) {
			movement.y = -5.45;
		}

		camera.pos.addEqual(movement.mulScalar(deltaTime));
		updateViewMatrix();
	}
};

const fov: f32 = 90;
const zNear: f32 = 0.1;
const zFar: f32 = 1000;

pub const Window = struct {
	var isFullscreen: bool = false;
	pub var width: u31 = 1280;
	pub var height: u31 = 720;
	var window: *c.GLFWwindow = undefined;
	pub var grabbed: bool = false;
	const GLFWCallbacks = struct {
		fn errorCallback(errorCode: c_int, description: [*c]const u8) callconv(.C) void {
			std.log.err("GLFW Error({}): {s}", .{errorCode, description});
		}
		fn keyCallback(_: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
			if(action == c.GLFW_PRESS) {
				inline for(@typeInfo(@TypeOf(keyboard)).Struct.fields) |field| {
					if(key == @field(keyboard, field.name).key) {
						if(key != c.GLFW_KEY_UNKNOWN or scancode == @field(keyboard, field.name).scancode) {
							@field(keyboard, field.name).pressed = true;
						}
					}
				}
			} else if(action == c.GLFW_RELEASE) {
				inline for(@typeInfo(@TypeOf(keyboard)).Struct.fields) |field| {
					if(key == @field(keyboard, field.name).key) {
						if(key != c.GLFW_KEY_UNKNOWN or scancode == @field(keyboard, field.name).scancode) {
							@field(keyboard, field.name).pressed = false;
							if(@field(keyboard, field.name).releaseAction) |releaseAction| {
								releaseAction();
							}
						}
					}
				}
			}
			std.log.info("Key pressed: {}, {}, {}, {}", .{key, scancode, action, mods});
		}
		fn framebufferSize(_: ?*c.GLFWwindow, newWidth: c_int, newHeight: c_int) callconv(.C) void {
			std.log.info("Framebuffer: {}, {}", .{newWidth, newHeight});
			width = @intCast(u31, newWidth);
			height = @intCast(u31, newHeight);
			c.glViewport(0, 0, width, height);
			camera.projectionMatrix = Mat4f.perspective(std.math.degreesToRadians(f32, fov), @intToFloat(f32, width)/@intToFloat(f32, height), zNear, zFar);
		}
		// Mouse deltas are averaged over multiple frames using a circular buffer:
		const deltasLen: u2 = 3;
		var deltas: [deltasLen]Vec2f = [_]Vec2f{Vec2f{.x=0, .y=0}} ** 3;
		var deltaBufferPosition: u2 = 0;
		var currentPos: Vec2f = Vec2f{.x=0, .y=0};
		var ignoreDataAfterRecentGrab: bool = true;
		fn cursorPosition(_: ?*c.GLFWwindow, x: f64, y: f64) callconv(.C) void {
			const newPos = Vec2f {
				.x = @floatCast(f32, x),
				.y = @floatCast(f32, y),
			};
			if(grabbed and !ignoreDataAfterRecentGrab) {
				deltas[deltaBufferPosition].addEqual(newPos.sub(currentPos).mulScalar(settings.mouseSensitivity));
				var averagedDelta: Vec2f = Vec2f{.x=0, .y=0};
				for(deltas) |delta| {
					averagedDelta.addEqual(delta);
				}
				averagedDelta.divEqualScalar(deltasLen);
				camera.moveRotation(averagedDelta.x*0.0089, averagedDelta.y*0.0089);
				deltaBufferPosition = (deltaBufferPosition + 1)%deltasLen;
				deltas[deltaBufferPosition] = Vec2f{.x=0, .y=0};
			}
			ignoreDataAfterRecentGrab = false;
			currentPos = newPos;
		}
		fn glDebugOutput(_: c_uint, typ: c_uint, _: c_uint, severity: c_uint, length: c_int, message: [*c]const u8, _: ?*const anyopaque) callconv(.C) void {
			if(typ == c.GL_DEBUG_TYPE_ERROR or typ == c.GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR or typ == c.GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR or typ == c.GL_DEBUG_TYPE_PORTABILITY or typ == c.GL_DEBUG_TYPE_PERFORMANCE) {
				std.log.err("OpenGL {}:{s}", .{severity, message[0..@intCast(usize, length)]});
				@panic("OpenGL error");
			}
		}
	};

	pub fn setMouseGrabbed(grab: bool) void {
		if(grabbed != grab) {
			if(!grab) {
				c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
			} else {
				c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
				if (c.glfwRawMouseMotionSupported() != 0)
					c.glfwSetInputMode(window, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);
				GLFWCallbacks.ignoreDataAfterRecentGrab = true;
			}
			grabbed = grab;
		}
	}

	fn init() !void {
		_ = c.glfwSetErrorCallback(GLFWCallbacks.errorCallback);

		if(c.glfwInit() == 0) {
			return error.GLFWFailed;
		}

		if(@import("builtin").mode == .Debug) {
			c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, 1);
		}
		c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
		c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);

		window = c.glfwCreateWindow(width, height, "Procedural Texture Creator", null, null) orelse return error.GLFWFailed;

		_ = c.glfwSetKeyCallback(window, GLFWCallbacks.keyCallback);
		_ = c.glfwSetFramebufferSizeCallback(window, GLFWCallbacks.framebufferSize);
		_ = c.glfwSetCursorPosCallback(window, GLFWCallbacks.cursorPosition);

		c.glfwMakeContextCurrent(window);

		if(c.gladLoadGL() == 0) {
			return error.GLADFailed;
		}
		c.glfwSwapInterval(1);

		if(@import("builtin").mode == .Debug) {
			c.glEnable(c.GL_DEBUG_OUTPUT);
			c.glEnable(c.GL_DEBUG_OUTPUT_SYNCHRONOUS);
			c.glDebugMessageCallback(GLFWCallbacks.glDebugOutput, null);
			c.glDebugMessageControl(c.GL_DONT_CARE, c.GL_DONT_CARE, c.GL_DONT_CARE, 0, null, c.GL_TRUE);
		}
	}

	fn deinit() void {
		c.glfwDestroyWindow(window);
		c.glfwTerminate();
	}

	var oldX: c_int = 0;
	var oldY: c_int = 0;
	var oldWidth: c_int = 0;
	var oldHeight: c_int = 0;
	pub fn toggleFullscreen() void {
		isFullscreen = !isFullscreen;
		if (isFullscreen) {
			c.glfwGetWindowPos(window, &oldX, &oldY);
			c.glfwGetWindowSize(window, &oldWidth, &oldHeight);
			const monitor = c.glfwGetPrimaryMonitor();
			if(monitor == null) {
				isFullscreen = false;
				return;
			}
			const vidMode = c.glfwGetVideoMode(monitor).?;
			c.glfwSetWindowMonitor(window, monitor, 0, 0, vidMode[0].width, vidMode[0].height, c.GLFW_DONT_CARE);
		} else {
			c.glfwSetWindowMonitor(window, null, oldX, oldY, oldWidth, oldHeight, c.GLFW_DONT_CARE);
			c.glfwSetWindowAttrib(window, c.GLFW_DECORATED, c.GLFW_TRUE);
		}
	}
};

pub fn main() !void {
	var gpa = std.heap.GeneralPurposeAllocator(.{.thread_safe=false}){};
	threadAllocator = gpa.allocator();
	defer if(gpa.deinit()) {
		@panic("Memory leak");
	};

	try Window.init();
	defer Window.deinit();

	graphics.init();
	defer graphics.deinit();

	try mesh.meshing.init();
	defer mesh.meshing.deinit();

	Window.setMouseGrabbed(true);

	c.glCullFace(c.GL_BACK);
	c.glEnable(c.GL_BLEND);
	c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
	c.glEnable(c.GL_DEPTH_TEST);
	c.glEnable(c.GL_CULL_FACE);
	Window.GLFWCallbacks.framebufferSize(null, Window.width, Window.height);

	var chunk: mesh.Chunk = undefined;
	chunk.init();
	chunk.addBlock(1, 1, 1);
	chunk.addBlock(1, 1, 15);
	chunk.addBlock(1, 15, 1);
	chunk.addBlock(1, 15, 15);
	chunk.addBlock(15, 1, 1);
	chunk.addBlock(15, 1, 15);
	chunk.addBlock(15, 15, 1);
	chunk.addBlock(15, 15, 15);

	var _mesh: mesh.meshing.ChunkMesh = mesh.meshing.ChunkMesh.init(threadAllocator);
	defer _mesh.deinit();
	try _mesh.regenerateMainMesh(&chunk);
	try _mesh.uploadDataAndFinishNeighbors();

	while(c.glfwWindowShouldClose(Window.window) == 0) {
		{ // Check opengl errors:
			const err = c.glGetError();
			if(err != 0) {
				std.log.err("Got opengl error: {}", .{err});
			}
		}
		try camera.update(1.0/60.0);
		c.glfwSwapBuffers(Window.window);
		c.glfwPollEvents();

		c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

		mesh.meshing.bindShaderAndUniforms(camera.projectionMatrix);
		var colors: [16*4]f32 = [_]f32 {
			1, 1, 0, 1,
			0.8, 0.9, 0.1, 1,
			0.6, 0.8, 0.3, 1,
			0.45, 0.6, 0.35, 1,
			0.4, 0.5, 0.3, 1,
			0.3, 0.5, 0.2, 1,
			0.2, 0.4, 0.1, 1,
			0.05, 0.15, 0.05, 1,

			0, 1, 0.0, 1,
			0.1, 0.0, 0.8, 1,
			0.3, 0.0, 0.6, 1,
			0.35, 0.0, 0.45, 1,
			0.3, 0.0, 0.4, 1,
			0.2, 0.0, 0.3, 1,
			0.1, 0.0, 0.2, 1,
			0.05, 0.0, 0.05, 1,
		};
		c.glUniform4fv(mesh.meshing.uniforms.color, 16, &colors);
		_mesh.render();
	}
}
