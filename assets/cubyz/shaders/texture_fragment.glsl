#version 330 

layout (location=0) out vec4 frag_color;

in vec3 worldPos;
in vec3 outNormal;
in float outNormalVariation;
uniform sampler2DArray patterns;

uniform vec4 color[16];

ivec3 random3to3(ivec3 v) {
	int fac1 = 11248723;
	int fac2 = 105436839;
	int fac3 = 45399083;
	int seed = v.x*fac1 ^ v.y*fac2 ^ v.z*fac3;
	v.x = seed*fac3;
	v.y = seed*fac1;
	v.z = seed*fac2;
	return v;
}

ivec3 pcg3d(ivec3 v) {
	v *= ivec3(7, 13, 23);
	v = v.yzx*1664525 + 1013904223;
	v += v.yzx*v.zxy;
	v ^= v >> 16;
	v += v.yzx*v.zxy;
	return v;
}

float snoise(vec3 v){
	const vec2 C = vec2(1.0/6.0, 1.0/3.0);
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

	// First corner
	vec3 i = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);

	// Other corners
	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);

	// x0 = x0 - 0. + 0.0 * C 
	vec3 x1 = x0 - i1 + 1.0*C.xxx;
	vec3 x2 = x0 - i2 + 2.0*C.xxx;
	vec3 x3 = x0 - 1. + 3.0*C.xxx;

	// Get gradients:
	ivec3 rand = random3to3(ivec3(i));
	vec3 p0 = vec3(rand);
	
	rand = random3to3((ivec3(i + i1)));
	vec3 p1 = vec3(rand);
	
	rand = random3to3((ivec3(i + i2)));
	vec3 p2 = vec3(rand);
	
	rand = random3to3((ivec3(i + 1)));
	vec3 p3 = vec3(rand);

	// Mix final noise value
	vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
	m = m*m;
	return 42.0*dot(m*m, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)))/(1 << 31);
}

vec4 getPattern(ivec3 texturePosition, int textureIndex) {
	return texture(patterns, vec3(texturePosition.x/16.0, (texturePosition.y*16 + texturePosition.z)/256.0, textureIndex));
}

void main() {
	ivec3 pixelPosition = ivec3(floor(worldPos.xyz*16));
	float patternStrength = getPattern(pixelPosition & 15, 0).x;
	float paletteID = 0;//snoise(vec3(pixelPosition + 0.5)/40);
	for(int i = 0; i < 10; i++) {
		paletteID += snoise(vec3(pixelPosition*float(1 << i)/40))/float(1 << i);
	}
	ivec3 rand = random3to3(ivec3(pixelPosition));
	//paletteID = (vec3(rand)/(1 << 31)).x*1.0;
	//paletteID += snoise(vec3(pixelPosition*paletteID));
	paletteID = paletteID*3 + 4;
	//paletteID += 8*(1 - patternStrength);
	int paletteIndex = int(paletteID);
	frag_color = color[paletteIndex];
	frag_color.rgb *= outNormalVariation;
	//frag_color.rbg = vec3(rand)/(1 << 31)*0.5 + 0.5;
}
