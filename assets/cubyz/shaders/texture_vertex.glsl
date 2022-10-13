#version 430

out vec3 worldPos;
out vec3 outNormal;
out float outNormalVariation;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;

struct FaceData {
	int encodedPosition;
	int texCoordAndNormals;
};
layout(std430, binding = 3) buffer _faceData
{
	FaceData faceData[];
};

const float[6] outNormalVariations = float[6](
	1.0, //vec3(0, 1, 0),
	0.8, //vec3(0, -1, 0),
	0.9, //vec3(1, 0, 0),
	0.9, //vec3(-1, 0, 0),
	0.95, //vec3(0, 0, 1),
	0.8 //vec3(0, 0, -1)
);
const vec3[6] normals = vec3[6](
	vec3(0, 1, 0),
	vec3(0, -1, 0),
	vec3(1, 0, 0),
	vec3(-1, 0, 0),
	vec3(0, 0, 1),
	vec3(0, 0, -1)
);
const ivec3[6] positionOffset = ivec3[6](
	ivec3(0, 0, 0),
	ivec3(0, 1, 0),
	ivec3(0, 0, 0),
	ivec3(1, 0, 0),
	ivec3(0, 0, 0),
	ivec3(0, 0, 1)
);
const ivec3[6] textureX = ivec3[6](
	ivec3(1, 0, 0),
	ivec3(-1, 0, 0),
	ivec3(0, 0, -1),
	ivec3(0, 0, 1),
	ivec3(1, 0, 0),
	ivec3(-1, 0, 0)
);
const ivec3[6] textureY = ivec3[6](
	ivec3(0, 0, 1),
	ivec3(0, 0, 1),
	ivec3(0, -1, 0),
	ivec3(0, -1, 0),
	ivec3(0, -1, 0),
	ivec3(0, -1, 0)
);

void main() {
	int faceID = gl_VertexID/4;
	int vertexID = gl_VertexID%4;
	int encodedPosition = faceData[faceID].encodedPosition;
	int texCoordAndNormals = faceData[faceID].texCoordAndNormals;
	int normal = (texCoordAndNormals >> 24) & 7;
	outNormal = normals[normal];

	ivec3 position = ivec3(
		encodedPosition & 31,
		encodedPosition >> 5 & 31,
		encodedPosition >> 10 & 31
	);
	
	position += positionOffset[normal];
	position += ivec3(equal(textureX[normal], ivec3(-1, -1, -1))) + (vertexID>>1 & 1)*textureX[normal];
	position += ivec3(equal(textureY[normal], ivec3(-1, -1, -1))) + (vertexID & 1)*textureY[normal];
	worldPos = position - outNormal*0.5/16;

	gl_Position = projectionMatrix*viewMatrix*vec4(position - ivec3(8, 8, 8), 1);
	outNormalVariation = outNormalVariations[normal];
}