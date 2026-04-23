#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 16, local_size_y = 16 ) in;

layout ( rgba8, set = 0, binding = 1 ) uniform image2D lenticularLUT;
layout ( r32i, set = 0, binding = 2 ) uniform iimage2D heightmap;

#include "common.h"
#include "hg_sdf.h"
#include "random.h"

// using this for normal vector estimation
vec2 RaySphereIntersect ( vec3 r0, vec3 rd, vec3 s0, float sr ) {
	// r0 is ray origin
	// rd is ray direction
	// s0 is sphere center
	// sr is sphere radius
	// return is the roots of the quadratic, includes negative hits
	float a = dot( rd, rd );
	vec3 s0_r0 = r0 - s0;
	float b = 2.0f * dot( rd, s0_r0 );
	float c = dot( s0_r0, s0_r0 ) - ( sr * sr );
	float disc = b * b - 4.0f * a * c;
	if ( disc < 0.0f ) {
		return vec2( -1.0f, -1.0f );
	} else {
		return vec2( -b - sqrt( disc ), -b + sqrt( disc ) ) / ( 2.0f * a );
	}
}

struct particle {
	vec2 position;
	vec2 speed;
	float volume;
	float sedimentFraction;
};

void main () {
	ivec2 idx = ivec2( gl_GlobalInvocationID.xy );
	seed = PushConstants.wangSeed + idx.x * 69420 + idx.y * 8675309;

	// basic initialization
	particle p;
	p.speed = vec2( 0.0f );
	p.volume = 1.0f;
	p.sedimentFraction = 0.0f;

	// generate an initial position on the surface
	p.position = vec2(
		remap( NormalizedRandomFloat(), 0.0f, 1.0f, 0.0f, imageSize( heightmap ).x - 1 ),
		remap( NormalizedRandomFloat(), 0.0f, 1.0f, 0.0f, imageSize( heightmap ).y - 1 )
	);

	// do the particle transport, for some number of steps

}