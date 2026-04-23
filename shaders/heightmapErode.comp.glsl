#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 16, local_size_y = 16 ) in;

layout ( rgba8, set = 0, binding = 1 ) uniform image2D lenticularLUT;
layout ( r32i, set = 0, binding = 2 ) uniform iimage2D heightmap;

#include "common.h"
#include "hg_sdf.h"
#include "random.h"

vec3 getNormal ( vec2 loc ) {
	// maybe do something with more local points?
	// get position within pixel..
		// do the same test as the point sprites, cheaper than ray-sphere

	// analytic solution via pythagoras
//	vec2 centered = fract( loc ) * 2.0f - vec2( 1.0f );
	vec2 centered = fract( loc );
	float radiusSquared = dot( centered, centered );
	if ( radiusSquared > 1.0f ) { // not on the sphere
		return normalize( vec3( normalize( centered ), 1.0f ) );
	}
	return vec3( centered, sqrt( 1.0f - radiusSquared ) );
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
	const vec2 iS = imageSize( heightmap ).xy;

	// basic initialization
	particle p;
	p.speed = vec2( 0.0f );
	p.volume = 1.0f;
	p.sedimentFraction = 0.0f;

	// generate an initial position on the surface
	p.position = vec2(
		remap( NormalizedRandomFloat(), 0.0f, 1.0f, 0.0f, iS.x - 1 ),
		remap( NormalizedRandomFloat(), 0.0f, 1.0f, 0.0f, iS.y - 1 )
	);

	// do the particle transport
		// break on:
			// max number of steps
			// particle goes out of bounds
			// simulation stop conditions:
				// p.volume is less than or equal GlobalData.minVolume

	int maxSteps = 500;
	while ( p.volume > GlobalData.minVolume && ( maxSteps-- != 0 ) ) {
		// cached position
		vec2 initialPosition = p.position;
		vec3 normal = getNormal( p.position );

		// newton's second law to calculate acceleration
		p.speed += GlobalData.timeStep * normal.xz / ( p.volume * GlobalData.density ); // F = MA, A = F/M
		p.position += GlobalData.timeStep * p.speed; // update position based on new speed
		p.speed *= ( 1.0f - GlobalData.timeStep * GlobalData.friction ); // friction factor to attenuate speed

		if ( !all( greaterThanEqual( p.position, vec2( 0.0f ) ) ) ||
			!all( lessThan( p.position, iS ) ) ) break;

		// sediment capacity
		ivec2 refPoint = ivec2( p.position );
		float maxSediment = p.volume * length( p.speed ) * ( ( imageLoad( heightmap, ivec2( initialPosition.xy ) ).r - imageLoad( heightmap, ivec2( p.position.xy ) ).r ) / float( GlobalData.maxHeight ) );
		maxSediment = max( maxSediment, 0.0f ); // don't want negative values here
		float sedimentDifference = maxSediment - p.sedimentFraction;

		// update sediment content, deposit on the heightmap
		p.sedimentFraction += GlobalData.timeStep * GlobalData.depositionRate * sedimentDifference;
		float oldValue = imageLoad( heightmap, ivec2( initialPosition.xy ) ).r / float( GlobalData.maxHeight );
		imageAtomicAdd( heightmap, ivec2( initialPosition.xy ), int( -0.1f * ( GlobalData.timeStep * p.volume * GlobalData.depositionRate * sedimentDifference ) * float( GlobalData.maxHeight ) ) );

		// evaporate the droplet
		p.volume *= ( 1.0f - GlobalData.timeStep * GlobalData.evaporationRate );
	}
}