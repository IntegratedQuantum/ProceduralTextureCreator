#version 330 

layout (location=0) out vec4 frag_color;

in vec3 worldPos;
in vec3 outNormal;
in float outNormalVariation;
uniform sampler2DArray patterns;

uniform vec4 color[16];

uvec3 pcg3d(uvec3 v) {
	v *= uvec3(7, 13, 23);
	v = v*1664525u + 1013904223u;
	v += v.yzx*v.zxy;
	v ^= v >> 16;
	v += v.yzx*v.zxy;
	return v;
}

float snoise(vec3 v){
	const vec2 C = vec2(1.0/6.0, 1.0/3.0) ;
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

// First corner
	vec3 i = floor(v + dot(v, C.yyy) );
	vec3 x0 = v - i + dot(i, C.xxx) ;

// Other corners
	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min( g.xyz, l.zxy );
	vec3 i2 = max( g.xyz, l.zxy );

	// x0 = x0 - 0. + 0.0 * C 
	vec3 x1 = x0 - i1 + 1.0 * C.xxx;
	vec3 x2 = x0 - i2 + 2.0 * C.xxx;
	vec3 x3 = x0 - 1. + 3.0 * C.xxx;

// Get gradients:
	uvec3 rand = pcg3d(uvec3(ivec3(i)));
	vec3 p0 = vec3(rand & 65535u)/65536.0*2 - 1;
	
	rand = pcg3d(uvec3(ivec3(i + i1)));
	vec3 p1 = vec3(rand & 65535u)/65536.0*2 - 1;
	
	rand = pcg3d(uvec3(ivec3(i + i2)));
	vec3 p2 = vec3(rand & 65535u)/65536.0*2 - 1;
	
	rand = pcg3d(uvec3(ivec3(i + 1)));
	vec3 p3 = vec3(rand & 65535u)/65536.0*2 - 1;

// Mix final noise value
	vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
	m = m * m;
	return 42.0 * dot( m*m, vec4( dot(p0,x0), dot(p1,x1), 
					              dot(p2,x2), dot(p3,x3) ) );
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
    //paletteID += snoise(vec3(pixelPosition*paletteID));
	paletteID = paletteID*3 + 4;
	//paletteID += 8*(1 - patternStrength);
	int paletteIndex = int(paletteID);
	frag_color = color[paletteIndex];
	frag_color.rgb *= outNormalVariation;
}
