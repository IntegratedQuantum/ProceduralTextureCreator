#version 330

layout (location=0) in vec2 in_vertex_pos;

out vec2 position;

void main() {
	position = in_vertex_pos;
	gl_Position = vec4(in_vertex_pos, 0, 1);
}