#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 16, local_size_y = 16 ) in;

#include "common.h"

layout ( set = 0, binding = 1 ) uniform sampler2D lenticularLUT;
layout ( rgba32f, set = 0, binding = 2 ) uniform image2D accumulator;

float tMin, tMax; // global state tracking
bool Intersect ( const vec3 rO, vec3 rD ) {
	// Intersect() code adapted from:
	//    Amy Williams, Steve Barrus, R. Keith Morley, and Peter Shirley
	//    "An Efficient and Robust Ray-Box Intersection Algorithm"
	//    Journal of graphics tools, 10(1):49-54, 2005
	const float minDistance = -100.0;
	const float maxDistance =  100.0;
	int s[ 3 ]; // sign toggle
	// inverse of ray direction
	const vec3 iD = vec3( 1.0 ) / rD;
	s[ 0 ] = ( iD[ 0 ] < 0 ) ? 1 : 0;
	s[ 1 ] = ( iD[ 1 ] < 0 ) ? 1 : 0;
	s[ 2 ] = ( iD[ 2 ] < 0 ) ? 1 : 0;
	const vec3 min = vec3( -1.0, -1.0, -1.0 );
	const vec3 max = vec3(  1.0,  1.0,  1.0 );
	const vec3 b[ 2 ] = { min, max }; // bounds
	tMin = ( b[ s[ 0 ] ][ 0 ] - rO[ 0 ] ) * iD[ 0 ];
	tMax = ( b[ 1 - s[ 0 ] ][ 0 ] - rO[ 0 ] ) * iD[ 0 ];
	const float tYMin = ( b[ s[ 1 ] ][ 1 ] - rO[ 1 ] ) * iD[ 1 ];
	const float tYMax = ( b[ 1 - s[ 1 ] ][ 1 ] - rO[ 1 ] ) * iD[ 1 ];
	if ( ( tMin > tYMax ) || ( tYMin > tMax ) ) return false;
	if ( tYMin > tMin ) tMin = tYMin;
	if ( tYMax < tMax ) tMax = tYMax;
	const float tZMin = ( b[ s[ 2 ] ][ 2 ] - rO[ 2 ] ) * iD[ 2 ];
	const float tZMax = ( b[ 1 - s[ 2 ] ][ 2 ] - rO[ 2 ] ) * iD[ 2 ];
	if ( ( tMin > tZMax ) || ( tZMin > tMax ) ) return false;
	if ( tZMin > tMin ) tMin = tZMin;
	if ( tZMax < tMax ) tMax = tZMax;
	return ( ( tMin < maxDistance ) && ( tMax > minDistance ) );
}

vec3 boxNormal ( vec3 p ) {
	// sort of an approximation... take the normal of the nearest face
	const float ome = 1.0f - 0.00001f; // one minus epsilon
	if ( abs( p.x ) > ome ) {
		return vec3( 1.0f, 0.0f, 0.0f ) * sign( p.x );
	} else if ( abs( p.y ) > ome ) {
		return vec3( 0.0f, 1.0f, 0.0f ) * sign( p.y );
	} else if ( abs( p.z ) > ome ) {
		return vec3( 0.0f, 0.0f, 1.0f ) * sign( p.z );
	} else {
		// shouldn't hit this
		return vec3( 1.0f );
	}
}

float rayPlaneIntersect ( in vec3 rayOrigin, in vec3 rayDirection ) {
	const vec3 normal = GlobalData.planeBasisY;
	const vec3 planePt = vec3( 0.0f, 0.0f, 0.0f );
	return -( dot( rayOrigin - planePt, normal ) ) / dot( rayDirection, normal );
}

vec3 colorSampleSingle ( in ivec2 subSample, in ivec2 planePointPixelSpace ) {
	ivec2 sampleBaseLoc = GlobalData.gridDivisions * planePointPixelSpace;
	vec3 LUTread = vec3( 0.0f );
	if ( clamp( subSample, vec2( 0.0f ), vec2( GlobalData.gridDivisions - 1.0f ) ) == subSample ) { // out-of-angle is black
		LUTread = texture( lenticularLUT, vec2( sampleBaseLoc + subSample.yx ) / ( GlobalData.gridBaseDim * GlobalData.gridDivisions ) ).xyz;
	}
	return LUTread;
}

vec3 colorSampleFilter ( in vec3 rayDirection, in ivec2 planePointPixelSpace ) {
	vec2 subSample = vec2(
		remapClamp( dot( -GlobalData.planeBasisZ, rayDirection ), -GlobalData.angleScale, GlobalData.angleScale, 0.0f, GlobalData.gridDivisions - 1.0f ),
		remapClamp( dot( GlobalData.planeBasisX, rayDirection ), -GlobalData.angleScale, GlobalData.angleScale, 0.0f, GlobalData.gridDivisions - 1.0f )
	); // consider doing some linear interpolation over the nearest subpixel samples
	vec2 floorCoord = floor( subSample );
	vec2 fractCoord = fract( subSample );
	vec3 samples[] = vec3[ 4 ] (
		colorSampleSingle( ivec2( floorCoord.x, floorCoord.y ), planePointPixelSpace ),
		colorSampleSingle( ivec2( floorCoord.x + 1, floorCoord.y ), planePointPixelSpace ),
		colorSampleSingle( ivec2( floorCoord.x, floorCoord.y + 1 ), planePointPixelSpace ),
		colorSampleSingle( ivec2( floorCoord.x + 1, floorCoord.y + 1 ), planePointPixelSpace )
	);
	vec3 value1 = mix( samples[ 0 ], samples[ 1 ], fractCoord.x );
	vec3 value2 = mix( samples[ 2 ], samples[ 3 ], fractCoord.x );
	return mix( value1, value2, fractCoord.yyy );
}

vec3 colorSample ( in vec3 rayDirection, in vec2 planePoint ) {
	vec2 planePointPixelSpace = vec2(
		remapWrap( planePoint.x, -GlobalData.panelMaskSize, GlobalData.panelMaskSize, 0, GlobalData.gridBaseDim - 1 ),
		remapWrap( planePoint.y, -GlobalData.panelMaskSize, GlobalData.panelMaskSize, 0, GlobalData.gridBaseDim - 1 )
	);
	if ( GlobalData.linearFilter != 0 ) {
		// need to do the linear interpolation math
		// figure out the fractional pixel location
		const vec2 floorCoord = clamp( floor( planePointPixelSpace - 0.5f ), ivec2( 0 ), ivec2( GlobalData.gridBaseDim - 1 ) );
		const vec2 fractCoord = fract( planePointPixelSpace - 0.5f );

		// figure out the four nearest samples
		vec3 samples[] = vec3[ 4 ] (
			colorSampleFilter( rayDirection, ivec2( floorCoord.x, floorCoord.y ) ),
			colorSampleFilter( rayDirection, ivec2( floorCoord.x + 1, floorCoord.y ) ),
			colorSampleFilter( rayDirection, ivec2( floorCoord.x, floorCoord.y + 1 ) ),
			colorSampleFilter( rayDirection, ivec2( floorCoord.x + 1, floorCoord.y + 1 ) )
		);

		// figure out the output, based on mixing them
			// horizontal interpolation first
		vec3 value1 = mix( samples[ 0 ], samples[ 1 ], fractCoord.x );
		vec3 value2 = mix( samples[ 2 ], samples[ 3 ], fractCoord.x );

		// then the vertical interpolation between those samples
		return mix( value1, value2, fractCoord.yyy );
	} else {
		ivec2 subSample = ivec2(
			remapClamp( dot( -GlobalData.planeBasisZ, rayDirection ), -GlobalData.angleScale, GlobalData.angleScale, 0.0f, GlobalData.gridDivisions - 1.0f ),
			remapClamp( dot( GlobalData.planeBasisX, rayDirection ), -GlobalData.angleScale, GlobalData.angleScale, 0.0f, GlobalData.gridDivisions - 1.0f )
		);
		return colorSampleSingle( subSample, ivec2( planePointPixelSpace ) );
	}
}

#define MIRRORBOX 0
#define PLANEFRONT 1
#define PLANEBACK 2
struct sceneIntersection {
	float t;		// distance to hit
	vec3 normal;	// normal vector for the hit surface
	int matID;		// identifying which surface is hit
	vec3 LUTread;	// if the matID is PLANEFRONT, this is the lenticular color data
};

sceneIntersection getSceneIntersection ( in vec3 rayOrigin, in vec3 rayDirection ) {
	sceneIntersection si;

	// Hit one of three things first:
		// the inside of the mirror box			-> you need to continue
		// the lenticular panel (light side)	-> you have a color
		// the lenticular panel (dark side)		-> ray dies


	bool mirrorBoxHit = Intersect( rayOrigin, rayDirection );
	float planeHit = rayPlaneIntersect( rayOrigin, rayDirection );
	vec3 pPlaneHit = rayOrigin + planeHit * rayDirection;

	vec2 projPt = ( 1.0f / GlobalData.numRepeats ) * vec2(
		dot( pPlaneHit, GlobalData.planeBasisX ),
		dot( pPlaneHit, GlobalData.planeBasisZ )
	);

	bool planeMask = ( planeHit > 0.0f  // positive distance
		&& projPt.x < GlobalData.panelMaskSize && projPt.x >= -GlobalData.panelMaskSize && projPt.y < GlobalData.panelMaskSize && projPt.y >= -GlobalData.panelMaskSize ); // image mask

	projPt *= GlobalData.numRepeats;

	if ( planeHit < tMax && planeMask ) {
		// we hit the plane before the box -> normal unimportant, as the ray dies now
		if ( dot( rayDirection, GlobalData.planeBasisY ) > 0.0f ) {
			// dark side
			si.matID = PLANEBACK;
			si.LUTread = vec3( 0.0f );
		} else {
			// front side of plane -> need to find the color from the LUT
			si.matID = PLANEFRONT;

			// need to sample the LUT -> based on ray direction
			si.LUTread = colorSample( rayDirection, projPt );
		}
	} else {
		// box hit
		si.t = tMax;
		si.matID = MIRRORBOX;
		si.normal = -boxNormal( rayOrigin + rayDirection * tMax );
	}

	return si;
}


void main () {
	ivec2 idx = ivec2( gl_GlobalInvocationID.xy );

	vec2 uv = ( 2.0f * ( vec2( idx ) + vec2( 0.5f ) ) / vec2( imageSize( accumulator ).xy ) ) - vec2( 1.0f );
	uv.x *= float( imageSize( accumulator ).x ) / float( imageSize( accumulator ).y );

	// create a view ray
	vec3 rayOrigin = GlobalData.zoomFactor * (uv.x * GlobalData.viewBasisX + uv.y * GlobalData.viewBasisY) - 10.0f * GlobalData.viewBasisZ;
	vec3 rayDirection = GlobalData.viewBasisZ;

	vec4 color = vec4( 0.0f );
	if ( Intersect( rayOrigin, rayDirection ) ) {
		// if the ray hits, we're pathtracing

		vec3 pInitial = rayOrigin + rayDirection * tMin;
		rayOrigin = pInitial + rayDirection * 0.0001f;

		// has to be done without the epsilon bump included
		vec3 normal = boxNormal( pInitial );
		rayDirection = refract( rayDirection, normal, 1.0f / 1.2f );

		float transmission = 1.0f;
		for ( int i = 0; i < 8; i++ ) {
			// scene intersection - in the box, rays can't escape...
			sceneIntersection si = getSceneIntersection( rayOrigin, rayDirection );

			// need to keep bouncing till you hit the panel
			if ( si.matID == MIRRORBOX ) {
				// reflect, attenuate transmission by wall albedo
				color.xyz += 0.01f * transmission;
				transmission *= 0.9f;
				rayOrigin = rayOrigin + si.t * rayDirection + 0.001f * si.normal;
				rayDirection = reflect(rayDirection, si.normal);
			} else {
				color.xyz += si.LUTread * transmission;
				break;
			}
		}
	} else {
		color.xyz = vec3( 0.1f );
	}

	imageStore( accumulator, idx, color );
}