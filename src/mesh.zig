const std = @import("std");
const Allocator = std.mem.Allocator;

const graphics = @import("graphics.zig");
const c = graphics.c;
const Shader = graphics.Shader;
const SSBO = graphics.SSBO;
const main = @import("main.zig");
const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Mat4f = vec.Mat4f;

pub const chunkShift: u5 = 5;
pub const chunkShift2: u5 = chunkShift*2;
pub const chunkSize: i32 = 1 << chunkShift;
pub const chunkSizeIterator: [chunkSize]u0 = undefined;
pub const chunkVolume: u31 = 1 << 3*chunkShift;
pub const chunkMask: i32 = chunkSize - 1;

const Block = u1;

/// Contains a bunch of constants used to describe neighboring blocks.
pub const Neighbors = struct {
	/// How many neighbors there are.
	pub const neighbors: u32 = 6;
	/// Directions → Index
	pub const dirUp: u32 = 0;
	/// Directions → Index
	pub const dirDown: u32 = 1;
	/// Directions → Index
	pub const dirPosX: u32 = 2;
	/// Directions → Index
	pub const dirNegX: u32 = 3;
	/// Directions → Index
	pub const dirPosZ: u32 = 4;
	/// Directions → Index
	pub const dirNegZ: u32 = 5;
	/// Index to relative position
	pub const relX = [_]i32 {0, 0, 1, -1, 0, 0};
	/// Index to relative position
	pub const relY = [_]i32 {1, -1, 0, 0, 0, 0};
	/// Index to relative position
	pub const relZ = [_]i32 {0, 0, 0, 0, 1, -1};
	/// Index to bitMask for bitmap direction data
	pub const bitMask = [_]u6 {0x01, 0x02, 0x04, 0x08, 0x10, 0x20};
	/// To iterate over all neighbors easily
	pub const iterable = [_]u3 {0, 1, 2, 3, 4, 5};
};

/// Gets the index of a given position inside this chunk.
fn getIndex(x: i32, y: i32, z: i32) u32 {
	std.debug.assert((x & chunkMask) == x and (y & chunkMask) == y and (z & chunkMask) == z);
	return (@as(u32, @intCast(x)) << chunkShift) | (@as(u32, @intCast(y)) << chunkShift2) | @as(u32, @intCast(z));
}

pub const Chunk = struct {
	blocks: [chunkVolume]Block = undefined,

	wasChanged: bool = false,
	/// When a chunk is cleaned, it won't be saved by the ChunkManager anymore, so following changes need to be saved directly.
	wasCleaned: bool = false,
	generated: bool = false,

	pub fn init(self: *Chunk) void {
		self.* = Chunk {
			.blocks = [_]Block{0} ** chunkVolume,
		};
	}

	pub fn addBlock(self: *Chunk, x: i32, y: i32, z: i32) void {
		self.blocks[getIndex(x, y, z)] = 1;
	}

	pub fn getNeighbors(self: *const Chunk, x: i32, y: i32, z: i32, neighborsArray: *[6]Block) void {
		std.debug.assert(neighborsArray.length == 6);
		x &= chunkMask;
		y &= chunkMask;
		z &= chunkMask;
		for(Neighbors.relX, 0..) |_, i| {
			const xi = x + Neighbors.relX[i];
			const yi = y + Neighbors.relY[i];
			const zi = z + Neighbors.relZ[i];
			if (xi == (xi & chunkMask) and yi == (yi & chunkMask) and zi == (zi & chunkMask)) { // Simple double-bound test for coordinates.
				neighborsArray[i] = self.getBlock(xi, yi, zi);
			} else {
				// TODO: What about other chunks?
//				NormalChunk ch = world.getChunk(xi + wx, yi + wy, zi + wz);
//				if (ch != null) {
//					neighborsArray[i] = ch.getBlock(xi & chunkMask, yi & chunkMask, zi & chunkMask);
//				} else {
//					neighborsArray[i] = 1; // Some solid replacement, in case the chunk isn't loaded. TODO: Properly choose a solid block.
//				}
			}
		}
	}
};


pub const meshing = struct {
	var shader: Shader = undefined;
	pub var uniforms: struct {
		projectionMatrix: c_int,
		patterns: c_int,
		viewMatrix: c_int,
		color: c_int,
	} = undefined;
	var vao: c_uint = undefined;
	var vbo: c_uint = undefined;
	var faces: std.ArrayList(u32) = undefined;

	pub fn init() !void {
		shader = try Shader.create("assets/cubyz/shaders/texture_vertex.glsl", "assets/cubyz/shaders/texture_fragment.glsl");
		uniforms = shader.bulkGetUniformLocation(@TypeOf(uniforms));

		var rawData: [6*3 << (3*chunkShift)]u32 = undefined; // 6 vertices per face, maximum 3 faces/block
		const lut = [_]u32{0, 1, 2, 2, 1, 3};
		for(rawData, 0..) |_, i| {
			rawData[i] = @as(u32, @intCast(i))/6*4 + lut[i%6];
		}

		c.glGenVertexArrays(1, &vao);
		c.glBindVertexArray(vao);
		c.glGenBuffers(1, &vbo);
		c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, vbo);
		c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, rawData.len*@sizeOf(f32), &rawData, c.GL_STATIC_DRAW);
		c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 2*@sizeOf(f32), null);
		c.glBindVertexArray(0);

		faces = try std.ArrayList(u32).initCapacity(std.heap.page_allocator, 65536);
	}

	pub fn deinit() void {
		shader.delete();
		c.glDeleteVertexArrays(1, &vao);
		c.glDeleteBuffers(1, &vbo);
		faces.deinit();
	}

	pub fn bindShaderAndUniforms(projMatrix: Mat4f) void {
		shader.bind();

		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_FALSE, @ptrCast(&projMatrix));

		c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_FALSE, @ptrCast(&main.camera.viewMatrix));

		c.glBindVertexArray(vao);
	}

	pub const ChunkMesh = struct {
		chunk: ?*Chunk,
		faces: std.ArrayList(u32),
		faceData: SSBO,
		coreCount: u31 = 0,
		neighborStart: [7]u31 = [_]u31{0} ** 7,
		vertexCount: u31 = 0,
		generated: bool = false,
		allocator: Allocator,

		pub fn init(allocator: Allocator) ChunkMesh {
			return ChunkMesh{
				.faces = std.ArrayList(u32).init(allocator),
				.chunk = null,
				.faceData = SSBO.init(),
				.allocator = allocator,
			};
		}

		pub fn deinit(self: *ChunkMesh) void {
			self.faceData.deinit();
			self.faces.deinit();
			if(self.chunk) |ch| {
				self.allocator.destroy(ch);
			}
		}

		fn canBeSeenThroughOtherBlock(block: Block, other: Block, neighbor: u3) bool {
			_ = block;
			_ = neighbor; // TODO:    ↓← Blocks.mode(other).checkTransparency(other, neighbor)
			return other == 0;
		}

		pub fn regenerateMainMesh(self: *ChunkMesh, chunk: *Chunk) !void {
			self.faces.clearRetainingCapacity();
			var n: u32 = 0;
			var x: u8 = 0;
			while(x < chunkSize): (x += 1) {
				var y: u8 = 0;
				while(y < chunkSize): (y += 1) {
					var z: u8 = 0;
					while(z < chunkSize): (z += 1) {
						const block = (&chunk.blocks)[getIndex(x, y, z)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
						if(block == 0) continue;
						// Check all neighbors:
						for(Neighbors.iterable) |i| {
							n += 1;
							const x2 = x + Neighbors.relX[i];
							const y2 = y + Neighbors.relY[i];
							const z2 = z + Neighbors.relZ[i];
							if(x2&chunkMask != x2 or y2&chunkMask != y2 or z2&chunkMask != z2) continue; // Neighbor is outside the chunk.
							const neighborBlock = (&chunk.blocks)[getIndex(x2, y2, z2)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
							if(canBeSeenThroughOtherBlock(block, neighborBlock, i)) {
								const normal: u32 = i;
								const position: u32 = @as(u32, @intCast(x2)) | @as(u32, @intCast(y2))<<5 | @as(u32, @intCast(z2))<<10;
								const textureNormal = normal<<24;
								try self.faces.append(position);
								try self.faces.append(textureNormal);
							}
						}
					}
				}
			}

			if(self.chunk) |oldChunk| {
				self.allocator.destroy(oldChunk);
			}
			self.chunk = chunk;
			self.coreCount = @intCast(self.faces.items.len);
			self.neighborStart = [_]u31{self.coreCount} ** 7;
		}

		pub fn uploadDataAndFinishNeighbors(self: *ChunkMesh) !void {
			if(self.chunk == null) return; // In the mean-time the mesh was discarded and recreated and all the data was lost.
			self.faces.shrinkRetainingCapacity(self.coreCount);
			self.neighborStart[6] = @intCast(self.faces.items.len);
			self.vertexCount = @intCast(6*(self.faces.items.len)/2);
			self.faceData.bufferData(u32, self.faces.items);
			self.generated = true;
		}

		pub fn render(self: *ChunkMesh) void {
			if(!self.generated) {
				return;
			}
			if(self.vertexCount == 0) return;
			self.faceData.bind(3);
			c.glDrawElements(c.GL_TRIANGLES, self.vertexCount, c.GL_UNSIGNED_INT, null);
		}
	};
};