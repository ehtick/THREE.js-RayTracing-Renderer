precision highp float;
precision highp int;
precision highp sampler2D;

#include <raytracing_uniforms_and_defines>

uniform sampler2D uUVGridTexture;
uniform float uRoughness;

#define N_BOXES 1
#define N_SPHERES 5
#define N_RECTANGLES 1

vec3 rayOrigin, rayDirection;
// recorded intersection data:
vec3 intersectionNormal;
vec2 intersectionUV;
int intersectionTextureID;

struct Material { int type; vec3 color; float roughness; float IoR; int textureID; vec2 uvScale; };
struct Rectangle { vec3 position; vec3 normal; vec3 vectorU; vec3 vectorV; float radiusU; float radiusV; Material material; };
struct Box { vec3 minCorner; vec3 maxCorner; Material material; };
struct Sphere { float radius; vec3 position; Material material; };

Material intersectionMaterial;
Rectangle rectangles[N_RECTANGLES];
Box boxes[N_BOXES];
Sphere spheres[N_SPHERES];


#include <raytracing_random_functions>

#include <raytracing_lighting_models>

#include <raytracing_calc_fresnel_reflectance>

#include <raytracing_rectangle_intersect>

#include <raytracing_box_intersect>

#include <raytracing_solve_quadratic>

#include <raytracing_sphere_intersect>


//---------------------------------------------------------------------------------------
float SceneIntersect( int isShadowRay )
//---------------------------------------------------------------------------------------
{
	
	vec3 rObjOrigin, rObjDirection; 
	vec3 normal;
        float d;
	float t = INFINITY;
	float u, v;
	int isRayExiting = FALSE;

	// When shadow rays are trying to intersect a small point light source, a tiny box makes a better shape to try and hit
	// than a tiny sphere (due to floating-point precision error, some rays will hit while others will miss the small sphere from far away).  
	// Viewers will still see a tiny sphere representing the point light, but shadow rays will instead "see" a tiny box in the same spot.
	if (isShadowRay == TRUE)
	{
		d = BoxIntersect( boxes[0].minCorner, boxes[0].maxCorner, rayOrigin, rayDirection, normal, isRayExiting );
		if (d < t)
		{
			t = d;
			//intersectionNormal = normal;
			intersectionMaterial = boxes[0].material;
		}
	}

	for (int i = 0; i < N_RECTANGLES; i++)
        {
		d = RectangleIntersect( rectangles[i].position, rectangles[i].normal, rectangles[i].vectorU, rectangles[i].vectorV, 
			rectangles[i].radiusU, rectangles[i].radiusV, rayOrigin, rayDirection, u, v );
		if (d < t)
		{
			t = d;
			intersectionNormal = rectangles[i].normal;
			intersectionMaterial = rectangles[i].material;
			intersectionUV = vec2(u, v) * intersectionMaterial.uvScale;
		}
	}
	
	for (int i = 0; i < N_SPHERES; i++)
        {
		d = SphereIntersect( spheres[i].radius, spheres[i].position, rayOrigin, rayDirection );
		if (d < t)
		{
			t = d;
			intersectionNormal = (rayOrigin + t * rayDirection) - spheres[i].position;
			intersectionMaterial = spheres[i].material;
		}
	}

	return t;
} // end float SceneIntersect( )


vec3 getSkyColor(vec3 rayDir)
{
	return mix(vec3(0), vec3(0.02, 0.0, 0.1), clamp(exp(rayDir.y * -15.0), 0.0, 1.0));
}


//-------------------------------------------------------------------------------------------
vec3 RayTrace()
//-------------------------------------------------------------------------------------------
{
        Material lightMaterial = spheres[0].material;

	vec3 accumulatedColor = vec3(0);
        vec3 rayColorMask = vec3(1);
	vec3 reflectionRayOrigin, reflectionRayDirection;
	vec3 reflectionRayColorMask;
        vec3 geometryNormal, shadingNormal;
	vec3 intersectionPoint;
	vec3 directionToLight;
	vec3 ambientContribution = vec3(0);
	vec3 diffuseContribution = vec3(0);
	vec3 specularContribution = vec3(0);
	vec3 textureColor;
	vec3 initialSkyColor = getSkyColor(rayDirection);
	vec3 skyColor;
	vec3 checkColor0 = vec3(0.3, 0.3, 0.3);
	vec3 checkColor1 = vec3(0.01, 0.01, 0.01);

	float t = INFINITY;
	float initial_t = INFINITY;
	float ambientIntensity = 0.02;
	float fogStart = 20.0;
	float reflectance, transmittance;
	float IoR_ratio;
	float transparentThickness;

	int isShadowRay = FALSE;
	int willNeedReflectionRay = FALSE;
	int previousIntersectionMaterialType;
	
	intersectionMaterial.type = -100;


	for (int bounces = 0; bounces < 5; bounces++)
	{
		previousIntersectionMaterialType = intersectionMaterial.type;

		t = SceneIntersect( isShadowRay );

		initial_t = bounces == 0 ? t : initial_t;

		if (t == INFINITY)
		{
			if (bounces == 0)
			{
				accumulatedColor = initialSkyColor;
				break;
			}
			
			skyColor = getSkyColor(rayDirection);

			accumulatedColor += rayColorMask * skyColor;
			//accumulatedColor += diffuseContribution;
			accumulatedColor += specularContribution;

			if (willNeedReflectionRay == TRUE)
			{
				rayColorMask = reflectionRayColorMask;
				rayOrigin = reflectionRayOrigin;
				rayDirection = reflectionRayDirection;
				willNeedReflectionRay = FALSE;
				isShadowRay = FALSE;
				continue;
			}

			break;
		}

		
		if (intersectionMaterial.type == POINT_LIGHT)
		{	
			if (bounces == 0)
				accumulatedColor = lightMaterial.color;
			else
			{
				accumulatedColor += specularContribution;
			}

			if (isShadowRay == TRUE)
			{
				accumulatedColor += diffuseContribution;
				//accumulatedColor += specularContribution;// already done above
			}
			
			if (willNeedReflectionRay == TRUE)
			{
				rayColorMask = reflectionRayColorMask;
				rayOrigin = reflectionRayOrigin;
				rayDirection = reflectionRayDirection;
				willNeedReflectionRay = FALSE;
				isShadowRay = FALSE;
				continue;
			}
			
			// reached a light source, so we can exit
			break;
		}

		// if we get here and isShadowRay == TRUE, that means the shadow ray failed to find
		// the light source. This surface will be rendered in shadow (ambient contribution only)
		if (isShadowRay == TRUE && intersectionMaterial.type != TRANSPARENT)
		{
			if (willNeedReflectionRay == TRUE)
			{
				rayColorMask = reflectionRayColorMask;
				rayOrigin = reflectionRayOrigin;
				rayDirection = reflectionRayDirection;
				willNeedReflectionRay = FALSE;
				isShadowRay = FALSE;
				continue;
			}

			// failed to find light source, so leave surface in shadow and exit
			break;
		}

		// useful data 
		geometryNormal = normalize(intersectionNormal);
                shadingNormal = dot(geometryNormal, rayDirection) < 0.0 ? geometryNormal : -geometryNormal;
		intersectionPoint = rayOrigin + t * rayDirection;
		directionToLight = normalize(spheres[0].position - intersectionPoint);

		
		if (intersectionMaterial.textureID > -1)
		{
			textureColor = texture(uUVGridTexture, intersectionUV).rgb;
			textureColor *= textureColor;
			intersectionMaterial.color *= textureColor;
		}
		
                if (intersectionMaterial.type == PHONG)
                {
			// Phong's original lighting model consists of 3 components - Ambient, Diffuse, and Specular contributions.
			// Ambient is an old 'hack' to cheaply simulate the effect of soft, diffuse bounce lighting (Global Illumination)
			ambientContribution = doAmbientLighting(rayColorMask, ambientIntensity, intersectionMaterial);
			accumulatedColor += ambientContribution; // ambient light is always present, so go ahead and add it now
			// Diffuse is the typical Lambertian lighting (NdotL) that arrives directly from the light source - this gives non-metallic surfaces their color & gradient shading
			diffuseContribution = doDiffuseDirectLighting(rayColorMask, shadingNormal, directionToLight, lightMaterial.color, intersectionMaterial);
			// Specular is the bright highlight on shiny surfaces, resulting from a direct reflection of the light source itself
			specularContribution = doBlinnPhongSpecularLighting(rayColorMask, rayDirection, shadingNormal, directionToLight, lightMaterial.color, intersectionMaterial);
			// when all 3 components (Ambient, Diffuse, and Specular) have been calculated, they are just simply added up to give the final lighting.
			// Since Ambient lighting (global) is always present no matter what, it was immediately added a couple lines above.
			// However, in order to add the Diffuse and Specular lighting contributions, we must be able to 'see' the light source from the surface's perspective.
			// Therefore, a shadow ray (i.e. a test ray) is created and sent out toward the light's position. If the shadow ray successfully hits the light source, 
			// the Diffuse and Specular lighting may be added. If it fails to find the light source (another object is in the way), the surface is left in shadow with Ambient light only.
			isShadowRay = TRUE;
			// first we must nudge shadow ray origin out from the surface (along the surface normal) just a little bit, in order to avoid self-intersection on the next bounces loop iteration
			rayOrigin = intersectionPoint + uEPS_intersect * shadingNormal;
			rayDirection = directionToLight; // all shadow rays go directly toward the light
			continue; // continue next with shadow ray towards the light source
                }
		
                if (intersectionMaterial.type == METAL)
		{
			// tint ray color with metal color
			rayColorMask *= intersectionMaterial.color;

			// Metals are purely specular with no diffuse component.
			// Therefore, the Ambient (global bounced diffuse) and Diffuse (direct diffuse from light source) contributions are skipped.
			// ambientContribution = NA
			// diffuseContribution = NA
			specularContribution = doBlinnPhongSpecularLighting(rayColorMask, rayDirection, shadingNormal, directionToLight, lightMaterial.color, intersectionMaterial);
			// we could technically do a shadow ray test (to see if the light is visible), but in the interest of speed, we go ahead and add the Specular contribution.
			accumulatedColor += specularContribution;

			// now spawn a reflection ray to see the parts of the scene that are visible in the mirror-like reflection
			rayColorMask *= clamp(1.0 - (intersectionMaterial.roughness * 1.2), 0.001, 1.0);
			rayOrigin = intersectionPoint + uEPS_intersect * shadingNormal; // nudge the new rayOrigin out from the surface to avoid self-intersection
			rayDirection = reflect(rayDirection, shadingNormal);
			continue; // continue ray tracing next with the mirror-reflection ray
		}

		if (intersectionMaterial.type == CHECKERED_CLEARCOAT)
		{
			if (mod(floor(intersectionUV.x) + floor(intersectionUV.y), 2.0) == 0.0)
				intersectionMaterial.color *= checkColor0;
			else intersectionMaterial.color *= checkColor1;

			// now that the checkered color has been determined for this surface, change the material type
			// to the usual ClearCoat, in order to handle lighting and reflections (avoids code duplication)
			intersectionMaterial.type = CLEARCOAT_DIFFUSE; // will be handled by the code directly below
		}

		if (intersectionMaterial.type == CLEARCOAT_DIFFUSE)
		{
			// the following will decrease the ClearCoat IoR(shininess) as the roughness increases 
			intersectionMaterial.IoR = mix(1.0, 1.5, clamp(1.0 - (intersectionMaterial.roughness * 1.2), 0.001, 1.0));
			// reflectance (range: 0-1), given by the Fresnel equations, will tell us what fraction of the light is reflected, vs. what fraction is refracted(transmittance)
			reflectance = calcFresnelReflectance(rayDirection, shadingNormal, 1.0, intersectionMaterial.IoR, IoR_ratio); // the fraction of light that is reflected,
			transmittance = 1.0 - reflectance; // vs. the fraction of light that is transmitted

			ambientContribution = doAmbientLighting(rayColorMask, ambientIntensity, intersectionMaterial);
			ambientContribution *= transmittance; // the ambient reflections from the surface are transmitted through the ClearCoat material, so we must weight them accordingly
			accumulatedColor += ambientContribution;

			diffuseContribution = doDiffuseDirectLighting(rayColorMask, shadingNormal, directionToLight, lightMaterial.color, intersectionMaterial);
			diffuseContribution *= transmittance; // the diffuse reflections from the surface are transmitted through the ClearCoat material, so we must weight them accordingly

			specularContribution = doBlinnPhongSpecularLighting(rayColorMask, rayDirection, shadingNormal, directionToLight, lightMaterial.color, intersectionMaterial);

			// If this ClearCoat type of material is the first thing that the camera ray encounters (bounces == 0), then setup and save a reflection ray for later use.
			// After we've done that, first we'll send out the usual shadow ray to see if the Diffuse and Specular contributions can be added. Then once the shadow ray 
			// is done testing for light visibility, we'll send out the saved reflection ray on its own trajectory, in order to capture reflections of the surrounding environment. 
			if (bounces == 0)
			{
				willNeedReflectionRay = TRUE;
				reflectionRayColorMask = rayColorMask * reflectance * clamp(1.0 - (intersectionMaterial.roughness * 1.2), 0.001, 1.0); // weight reflected ray with reflectance value we got
				reflectionRayOrigin = intersectionPoint + uEPS_intersect * shadingNormal; // nudge the reflection rayOrigin out from the surface to avoid self-intersection
				reflectionRayDirection = reflect(rayDirection, shadingNormal);
			}
			// First, send out the usual shadow ray for the diffuse part of this surface. When that's done with its job, the reflection ray will take over.  
			// The reflection ray above will start right back at this same spot on the surface, but will go off on its own mirror reflection trajectory.
			isShadowRay = TRUE;
			rayOrigin = intersectionPoint + uEPS_intersect * shadingNormal; // nudge the shadow rayOrigin out from the surface to avoid self-intersection
			rayDirection = directionToLight; // all shadow rays go directly toward the light
			continue; // continue next with shadow ray towards the light source
		}

		if (intersectionMaterial.type == TRANSPARENT)
		{
			reflectance = calcFresnelReflectance(rayDirection, geometryNormal, 1.0, intersectionMaterial.IoR, IoR_ratio);
			transmittance = 1.0 - reflectance;
			// Ideal Transparent materials (like glass, water, clear plastic, etc.) are purely specular with no diffuse component.
			// Therefore, the Ambient (global bounced diffuse) and Diffuse (direct diffuse from light source) contributions are skipped.
			// ambientContribution = NA
			// diffuseContribution = NA
			specularContribution = doBlinnPhongSpecularLighting(rayColorMask, rayDirection, shadingNormal, directionToLight, lightMaterial.color, intersectionMaterial);
			// shadow rays are only test rays and must not contribute any lighting of their own.
			// So if the current ray is a shadow ray (isShadowRay == TRUE), then we shut off the specular highlights.
			specularContribution = (isShadowRay == TRUE) ? vec3(0) : specularContribution;
			accumulatedColor += specularContribution;

			// If this Transparent type of material is the first thing that the camera ray encounters (bounces == 0), then setup and save a reflection ray for later use.
			// After we've done that, first we'll send out the refracted ray (transmitted ray) to find what parts of the scene we can see through the material. Then once the refraction
			// (transmitted) ray is done with its work, we'll send out the saved reflection ray on its own trajectory, in order to capture reflections of the surrounding environment. 
			// In the end, this will give us the photo-realistic double image (reflected portion & refracted portion) that we see on transparent materials like glass windows, water, plastic, etc.
			if (bounces == 0)
			{
				willNeedReflectionRay = TRUE;
				reflectionRayColorMask = rayColorMask * reflectance * clamp(1.0 - (intersectionMaterial.roughness * 1.2), 0.001, 1.0);
				reflectionRayOrigin = intersectionPoint + uEPS_intersect * shadingNormal; // nudge the reflection rayOrigin out from the surface to avoid self-intersection
				reflectionRayDirection = reflect(rayDirection, shadingNormal);
			}
			if (reflectance == 1.0) // total internal reflection has occured, so all light is mirror reflection only (refraction/transmittance is physically impossible)
			{
				rayColorMask = rayColorMask * reflectance * clamp(1.0 - (intersectionMaterial.roughness * 1.2), 0.001, 1.0); // weight reflected ray with reflectance value we got
				rayOrigin = intersectionPoint + uEPS_intersect * shadingNormal; // nudge the reflection rayOrigin out from the surface to avoid self-intersection
				rayDirection = reflect(rayDirection, shadingNormal);

				willNeedReflectionRay = FALSE;
				isShadowRay = FALSE;
				continue; // abandon transmitted ray(below) and go ahead and trace reflection ray now
			}

			// This part of the code handles the transmitted portion of the Transparent surface

			// is ray leaving a solid object from the inside? 
			// If so, attenuate ray color with object color by how far ray has travelled through the object's interior
			if (distance(geometryNormal, shadingNormal) > 0.1)
			{
				transparentThickness = 0.2;
				// the following uses Beer's Law to attenuate the light energy (brightness and color saturation) by how far it had to travel through the transparent material.
				// If the material is very thin, like thin glass or a shallow puddle of colored water, the transmitted light will still be bright, but will not pick up very much of the material's color.
				// As the material gets thicker, like thick glass or a deep pool of colored water, the transmitted light will lose more energy (darker) and will take on much more of the material's color.
				rayColorMask *= exp( log(clamp(intersectionMaterial.color, 0.01, 0.99)) * transparentThickness * t ); 
			}
			// the refraction through the surface only accounts for the portion of light that is transmitted, so we must weight it accordingly (Reflectance vs. Transmittance)
			rayColorMask *= transmittance;
			rayColorMask *= clamp(1.0 - (intersectionMaterial.roughness * 1.2), 0.001, 1.0);

			if (isShadowRay == FALSE) // do usual refraction - this happens most of the time
			{
				// note the minus(-) sign below, which nudges the rayOrigin below the surface along the normal, instead of above it (like for usual bounced reflections) 
				rayOrigin = intersectionPoint - uEPS_intersect * shadingNormal;
				rayDirection = refract(rayDirection, shadingNormal, IoR_ratio); // ray is now refracted according to Snell's Law
			}
			else // special case: shadow rays are allowed to penetrate un-refracted, in order to generate 'shadow' caustics (a clever technique found in the Hall Lighting Model)
			{
				diffuseContribution *= intersectionMaterial.color; // color future-generated caustics with the transparent material color
				diffuseContribution *= transmittance; // the light that generated the caustics only accounts for the transmitted portion, so weight accordingly
				diffuseContribution *= clamp(1.0 - (intersectionMaterial.roughness * 1.2), 0.001, 1.0);
				rayOrigin = intersectionPoint + uEPS_intersect * rayDirection; // nudge through surface along current rayDirection to avoid self-intersection
				rayDirection = rayDirection; // ray direction is unchanged and is allowed to pass through (un-refracted)
			}
			
			continue; // continue ray tracing next with the refracted(or transmitted) ray
		}
		
	} // end for (int bounces = 0; bounces < 5; bounces++)
	

	if (initial_t < INFINITY)
	{
		initial_t -= fogStart; // this makes the fog start a little farther away from the camera
		// the following is a standard fog/atmosphere blending into the distance (aerial perspective), using Beer's Law
		accumulatedColor = mix(initialSkyColor, accumulatedColor, clamp(exp(-initial_t * 0.001), 0.0, 1.0));
	}
		

	return max(vec3(0), accumulatedColor);

}  // end vec3 RayTrace()


//-----------------------------------------------------------------------
void SetupScene(void)
//-----------------------------------------------------------------------
{
	// rgb values for common metals
	// Gold: (1.000, 0.766, 0.336) / Aluminum: (0.913, 0.921, 0.925) / Copper: (0.955, 0.637, 0.538) / Silver: (0.972, 0.960, 0.915)
	float lightPower = 2.0;
	Material lightMaterial = Material(POINT_LIGHT, vec3(1.0, 1.0, 1.0) * lightPower, 0.0, 0.0, -1, vec2(1, 1));
	Material blueMaterial = Material(CLEARCOAT_DIFFUSE, vec3(0.01, 0.01, 1.0), uRoughness, 0.0, -1, vec2(1, 1));
	Material redMaterial = Material(PHONG, vec3(1.0, 0.01, 0.01), uRoughness, 0.0, -1, vec2(1, 1));
	Material groundUVGridMaterial = Material(CLEARCOAT_DIFFUSE, vec3(1.0), 0.0, 0.0, 0, vec2(100, 100));
	Material metalMaterial = Material(METAL, vec3(1.000, 0.766, 0.336), uRoughness, 0.0, -1, vec2(1, 1));
	Material glassMaterial = Material(TRANSPARENT, vec3(0.4, 1.0, 0.6), uRoughness, 1.5, -1, vec2(1, 1));
	Material grayBlackCheckerMaterial = Material(CHECKERED_CLEARCOAT, vec3(1.0), 0.0, 1.5, -1, vec2(300, 300));

	vec3 lightPosition = vec3(4, 10, 5);
	boxes[0] = Box(lightPosition - vec3(0.5), lightPosition + vec3(0.5), lightMaterial);

	rectangles[0] = Rectangle(vec3(0, 0, 0), normalize(vec3(0,1,0)), vec3(0), vec3(0), 1000.0, 1000.0, grayBlackCheckerMaterial);
	rectangles[0].vectorU = normalize(cross(abs(rectangles[0].normal.y) < 0.9 ? vec3(0,1,0) : vec3(0,0,-1), rectangles[0].normal));
	rectangles[0].vectorV = cross(rectangles[0].vectorU, rectangles[0].normal);

	spheres[0] = Sphere(0.2, lightPosition, lightMaterial);
	spheres[1] = Sphere(4.0, vec3(0, 4, 0), blueMaterial);
	spheres[2] = Sphere(4.0, vec3(-10, 4, 0), metalMaterial);
	spheres[3] = Sphere(3.0, vec3(10, 3, 0), redMaterial);
	spheres[4] = Sphere(4.0, vec3(-15, 4, 10), glassMaterial);
}


#include <raytracing_main>
