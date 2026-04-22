#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 16, local_size_y = 16 ) in;

layout ( rgba8, set = 0, binding = 1 ) uniform image2D lenticularLUT;

#include "common.h"
#include "hg_sdf.h"
#include "random.h"

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

float de( vec3 p ){
	// spatial repeats
	pMod3( p, vec3( 5.0f ) );

	float s = 2.;
	float e = 0.;
	for(int j=0;++j<7;)
	p.xz=abs(p.xz)-2.3,
	p.z>p.x?p=p.zyx:p,
	p.z=1.5-abs(p.z-1.3+sin(p.z)*.2),
	p.y>p.x?p=p.yxz:p,
	p.x=3.-abs(p.x-5.+sin(p.x*3.)*.2),
	p.y>p.x?p=p.yxz:p,
	p.y=.9-abs(p.y-.4),
	e=12.*clamp(.3/min(dot(p,p),1.),.0,1.)+
	2.*clamp(.1/min(dot(p,p),1.),.0,1.),
	p=e*p-vec3(7,1,1),
	s*=e;
	return length(p)/s;
}

const float epsilon = 0.001f;
bool didHit = false;
float raymarch ( vec3 rayOrigin, vec3 rayDirection ) {
	float dQuery = 0.0f;
	float dTotal = 0.0f;
	vec3 pQuery = rayOrigin;
	for ( int steps = 0; steps < 200; steps++ ) {
		pQuery = rayOrigin + dTotal * rayDirection;
		dQuery = de( pQuery );
		dTotal += dQuery * 0.9f;
		didHit = ( abs( dQuery ) < epsilon );
		if ( dTotal > 20.0f || didHit ) {
			break;
		}
	}
	return dTotal;
}

vec3 SDFNormal ( in vec3 position ) {
	vec2 e = vec2( epsilon, 0.0f );
	return normalize( vec3( de( position ) ) - vec3( de( position - e.xyy ), de( position - e.yxy ), de( position - e.yyx ) ) );
}

void main () {
	ivec2 idx = ivec2( gl_GlobalInvocationID.xy );
	seed = PushConstants.wangSeed + idx.x * 69420 + idx.y * 8675309;

	ivec2 pixelIdx = idx / GlobalData.gridDivisions;
	vec3 color = vec3( 1.0f );

#if 1


	vec3 sphereCenter = vec3( 0.0f, 0.0f, -1.1025f );
	int numSamples = 256;
	vec3 c = vec3( 0.0f );
	for ( int i = 0; i < numSamples; i++ ) {
		vec3 rayOrigin = vec3(
			remap( float( pixelIdx.x + NormalizedRandomFloat() ), 0.0f, GlobalData.gridBaseDim - 1, -1.0f, 1.0f ),
			remap( float( pixelIdx.y + NormalizedRandomFloat() ), 0.0f, GlobalData.gridBaseDim - 1, -1.0f, 1.0f ),
			0.0f
		);

		ivec2 subpixelIdx = idx % GlobalData.gridDivisions;
		vec2 startAngle = vec2( // this is used to construct the vector, via rotations from a vector pointing downwards...
			remap( float( subpixelIdx.x + NormalizedRandomFloat() ), 0.0f, GlobalData.gridDivisions - 1, piHalf * GlobalData.angleScale, -piHalf * GlobalData.angleScale ),
			remap( float( subpixelIdx.y + NormalizedRandomFloat() ), 0.0f, GlobalData.gridDivisions - 1, piHalf * GlobalData.angleScale, -piHalf * GlobalData.angleScale )
		);
		vec3 rayDirection = Rotate3D( startAngle.x, vec3( 0.0f, 1.0f, 0.0f ) ) * Rotate3D( startAngle.y, vec3( 1.0f, 0.0f, 0.0f ) ) * vec3( 0.0f, 0.0f, -1.0f );

		vec2 roots = RaySphereIntersect( rayOrigin, rayDirection, sphereCenter, 1.0f );
		if ( roots != vec2( -1.0f ) ) {
			vec3 p = rayOrigin + rayDirection * roots.x;
			c += normalize( p - sphereCenter ) * step( mod( p.z, 0.2f ), 0.1f );
		} else {
//			c += 1.0f;
		}
	}
	color = c / float( numSamples );
#else
	// we need to figure out what pixel this invocation corresponds to -> informs ray origin
	vec3 rayOrigin = vec3(
		remap( float( pixelIdx.x + 0.5f ), 0.0f, GlobalData.gridBaseDim - 1, -1.0f, 1.0f ),
		remap( float( pixelIdx.y + 0.5f ), 0.0f, GlobalData.gridBaseDim - 1, -1.0f, 1.0f ),
		0.0f
	);

	// we need to figure out what angle this invocation corresponds to -> informs ray direction
	ivec2 subpixelIdx = idx % GlobalData.gridDivisions;
	vec2 startAngle = vec2( // this is used to construct the vector, via rotations from a vector pointing downwards...
		remap( float( subpixelIdx.x ), 0.0f, GlobalData.gridDivisions - 1, piHalf * GlobalData.angleScale, -piHalf * GlobalData.angleScale ),
		remap( float( subpixelIdx.y ), 0.0f, GlobalData.gridDivisions - 1, piHalf * GlobalData.angleScale, -piHalf * GlobalData.angleScale )
	);
	vec3 rayDirection = Rotate3D( startAngle.x, vec3( 0.0f, 1.0f, 0.0f ) ) * Rotate3D( startAngle.y, vec3( 1.0f, 0.0f, 0.0f ) ) * vec3( 0.0f, 0.0f, -1.0f );
	float dRaymarch = raymarch( rayOrigin + vec3( 0.0f, 0.0f, 0.75f ), rayDirection );
	if ( didHit ) {
		const vec3 normal = SDFNormal( rayOrigin + dRaymarch * rayDirection );
		const vec3 pHit = rayOrigin + dRaymarch * rayDirection + 3.0f * epsilon * normal;
		const vec3 pLight = vec3( 0.0f );
		const vec3 vLight = pLight - pHit;
		const vec3 vLightNorm = normalize( vLight );

		color = vec3( 0.75f, 0.5f, 0.3f );

		// shadow trace
		if ( raymarch( pHit, vLightNorm ) < length( vLight ) ) {
			// we hit something...
			color *= 0.1f;
		} else {
			color *= saturate( dot( vLightNorm, normal ) );
		}
	}
#endif

	// we need to store back the result, into the lenticular LUT
	imageStore( lenticularLUT, idx, vec4( color, 1.0f ) );
}