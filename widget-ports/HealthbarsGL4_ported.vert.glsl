#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shader_storage_buffer_object : require
#extension GL_ARB_shading_language_420pack: require

// BAR-on-mac: the original HealthbarsGL4 geometry shader is merged into this vertex
// shader because MoltenVK/Metal has no geometry-shader stage. Each unit is one instance;
// the bar is expanded here from a 28-vertex TRIANGLE_STRIP corner buffer (location 5).
// Three sub-strips (background, colored backing, foreground) are joined by degenerate
// bridge vertices. On-bar number glyphs (%, stockpile, timers) are intentionally omitted.
#line 5000

layout (location = 0) in vec4 height_timers;
layout (location = 1) in uvec4 bartype_index_ssboloc;
layout (location = 2) in vec4 mincolor;
layout (location = 3) in vec4 maxcolor;
layout (location = 4) in uvec4 instData;
layout (location = 5) in float v_vertIdx;   // 0..27 strip corner index (per-vertex)

//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__

struct SUniformsBuffer {
    uint composite;
    uint unused2;
    uint unused3;
    uint unused4;
    float maxHealth;
    float health;
    float unused5;
    float unused6;
    vec4 drawPos;
    vec4 speed;
    vec4[4] userDefined;
};

layout(std140, binding=1) readonly buffer UniformsBuffer {
    SUniformsBuffer uni[];
};

uniform float iconDistance;
uniform float cameraDistanceMult;
uniform float cameraDistanceMultGlyph;
uniform float skipGlyphsNumbers; // <0.5 all, <1.5 numbers only, >1.5 none

out DataGS {
	vec4 g_color;
	vec4 g_uv;
};

bool vertexClipped(vec4 clipspace, float tolerance) {
  return any(lessThan(clipspace.xyz, -clipspace.www * tolerance)) ||
         any(greaterThan(clipspace.xyz, clipspace.www * tolerance));
}

#define UNITUNIFORMS uni[instData.y]
#define UNIFORMLOC bartype_index_ssboloc.z
#define BARTYPE bartype_index_ssboloc.x

#define BITUSEOVERLAY 1u
#define BITSHOWGLYPH 2u
#define BITPERCENTAGE 4u
#define BITTIMELEFT 8u
#define BITINTEGERNUMBER 16u
#define BITGETPROGRESS 32u
#define BITFLASHBAR 64u
#define BITCOLORCORRECT 128u
#define HALFPIXEL 0.0019765625

void main()
{
	// ===================== per-unit setup (from original vertex shader) =====================
	vec4 drawPos = vec4(UNITUNIFORMS.drawPos.xyz, 1.0);
	vec4 clipPos = cameraViewProj * drawPos;

	vec4 v_centerpos = drawPos;
	uint v_numvertices = 4u;
	if (vertexClipped(clipPos, CLIPTOLERANCE)) v_numvertices = 0u;

	float cameraDistance = length((cameraViewInv[3]).xyz - v_centerpos.xyz);

	vec4 v_parameters;
	v_parameters.y = (clamp(cameraDistance * cameraDistanceMult, BARFADESTART, BARFADEEND) - BARFADESTART) / (BARFADEEND - BARFADESTART);
	v_parameters.y = 1.0 - clamp(v_parameters.y, 0.0, 1.0);
	v_parameters.z = (clamp(cameraDistance * cameraDistanceMult * cameraDistanceMultGlyph, BARFADESTART, BARFADEEND) - BARFADESTART) / (BARFADEEND - BARFADESTART);
	v_parameters.z = 1.0 - clamp(v_parameters.z, 0.0, 1.0);
	#ifdef DEBUGSHOW
		v_parameters.y = 1.0;
		v_parameters.z = 1.0;
	#endif
	v_parameters.w = height_timers.w;
	vec2 v_sizemodifiers = height_timers.yz;

	if (dot(v_centerpos.xyz, v_centerpos.xyz) < 1.0) v_numvertices = 0u;

	v_centerpos.y += HEIGHTOFFSET;
	v_centerpos.y += height_timers.x;

	uvec4 v_bartype_index_ssboloc = bartype_index_ssboloc;
	float relativehealth = UNITUNIFORMS.health / UNITUNIFORMS.maxHealth;
	v_parameters.x = relativehealth;
	if (UNIFORMLOC < 20u)
	{
		v_parameters.x = UNITUNIFORMS.userDefined[0].y;
	} else {
		float buildprogress = UNITUNIFORMS.userDefined[0].x;
		#ifndef DEBUGSHOW
			if (abs(buildprogress - relativehealth) < 0.03) v_numvertices = 0u;
		#endif
	}
	if (UNIFORMLOC < 4u) v_parameters.x = UNITUNIFORMS.userDefined[0][bartype_index_ssboloc.z];
	if (UNIFORMLOC == 1u) v_parameters.x = UNITUNIFORMS.userDefined[0].y;
	if (UNIFORMLOC == 2u) v_parameters.x = UNITUNIFORMS.userDefined[0].z;
	if (UNIFORMLOC == 4u) v_parameters.x = UNITUNIFORMS.userDefined[1].x;
	if (UNIFORMLOC == 5u) v_parameters.x = UNITUNIFORMS.userDefined[1].y;

	if ((BARTYPE & BITGETPROGRESS) > 0u) {
		v_parameters.x =
			((timeInfo.x + timeInfo.w) - UNITUNIFORMS.userDefined[0].z) /
			(UNITUNIFORMS.userDefined[0].w - UNITUNIFORMS.userDefined[0].z);
		v_parameters.x = clamp(v_parameters.x, 0.0, 1.0);
	}

	vec4 v_mincolor = mincolor;
	vec4 v_maxcolor = maxcolor;

	// ===================== merged geometry-shader main (bars + glyphs) =====================
	float zoffset = 1.15 * BARHEIGHT * float(v_bartype_index_ssboloc.y);
	vec4 centerpos = v_centerpos;
	mat3 rotY = mat3(cameraViewInv[0].xyz, cameraViewInv[2].xyz, cameraViewInv[1].xyz);
	float sizemultiplier = v_sizemodifiers.x;
	float oldhealth = v_parameters.x;       // pre-fract (for stockpile digit extraction)
	float health = v_parameters.x;
	float BARALPHA = v_parameters.y;
	float GLYPHALPHA = v_parameters.z;
	float UVOFFSET = v_parameters.w;

	bool draw = true;
	if (v_numvertices == 0u) draw = false;
	if (BARALPHA < MINALPHA) draw = false;
	#ifndef DEBUGSHOW
		if (health < 0.00001) draw = false;
		if ((BARTYPE & BITPERCENTAGE) > 0u) { if (health > 0.999) draw = false; }
		else if ((BARTYPE & BITGETPROGRESS) > 0u) { if (health > 0.999) draw = false; }
	#endif
	if ((BARTYPE & BITINTEGERNUMBER) > 0u) health = fract(health);

	vec4 truecolor = mix(v_mincolor, v_maxcolor, health);

	// Foreground fill extent (shared by the fg bar and the glyph anchor / bar-end vertex).
	float healthbasedpos = (2.0 * (BARWIDTH - BARCORNER) - 2.0 * SMALLERCORNER) * health;
	if ((BARTYPE & BITTIMELEFT) > 0u) healthbasedpos = (2.0 * (BARWIDTH - BARCORNER) - 2.0 * SMALLERCORNER);
	vec2 barFgLast = vec2(-BARWIDTH + BARCORNER + 2.0 * SMALLERCORNER + healthbasedpos, BARHEIGHT - BARCORNER - SMALLERCORNER);

	// ---- build the glyph table (unit icon + number digits), max 5 slots ----
	const int MAXGLYPHS = 5;
	vec2 gBL[MAXGLYPHS];
	vec2 gUVbl[MAXGLYPHS];
	bool gActive[MAXGLYPHS];
	for (int i = 0; i < MAXGLYPHS; i++) { gBL[i] = vec2(0.0); gUVbl[i] = vec2(0.0); gActive[i] = false; }
	int ng = 0;
	if (draw && (GLYPHALPHA >= MINALPHA) && (skipGlyphsNumbers <= 1.5)) {
		float currentglyphpos = 1.0;
		if (skipGlyphsNumbers < 0.5) {
			if ((BARTYPE & BITSHOWGLYPH) > 0u) {
				gBL[ng] = vec2(-BARWIDTH - currentglyphpos * BARHEIGHT, 0.0); gUVbl[ng] = vec2(ATLASSTEP, UVOFFSET); gActive[ng] = true; ng++;
			}
		} else {
			currentglyphpos = 0.0;
		}
		if ((BARTYPE & BITINTEGERNUMBER) > 0u) {
			float oh = floor(oldhealth);
			float numStockpiled = floor(mod(oh, 128.0));
			float numStockpileQueued = floor(oh / 128.0);
			vec4 numbers = vec4(numStockpiled, numStockpiled, numStockpileQueued, numStockpileQueued) * vec4(1.0, 0.1, 1.0, 0.1);
			numbers = floor(mod(numbers, 10.0)) * ATLASSTEP;
			if (ng < MAXGLYPHS) { gBL[ng] = vec2(-BARWIDTH - (currentglyphpos + 1.0) * BARHEIGHT, 0.0); gUVbl[ng] = vec2(0.0, numbers.x); gActive[ng] = true; ng++; }
			if (numbers.y > 0.0 && ng < MAXGLYPHS) { gBL[ng] = vec2(-BARWIDTH - (currentglyphpos + 2.0) * BARHEIGHT + BARHEIGHT * 0.4, 0.0); gUVbl[ng] = vec2(0.0, numbers.y); gActive[ng] = true; ng++; }
		}
		if ((BARTYPE & (BITTIMELEFT | BITPERCENTAGE)) > 0u) {
			float lsb; float msb; float glyphpctsecatlas;
			float h2 = health;
			if ((BARTYPE & BITTIMELEFT) > 0u) {
				h2 = (h2 - 1.0) / (1.0 / 40.0);
				lsb = abs(floor(mod(h2, 10.0)));
				msb = abs(floor(mod(h2 * 0.1, 10.0)));
				glyphpctsecatlas = 14.0;
			} else {
				lsb = floor(mod(h2 * 100.0, 10.0));
				msb = floor(mod(h2 * 10.0, 10.0));
				glyphpctsecatlas = 11.0;
			}
			if (ng < MAXGLYPHS) { gBL[ng] = vec2(-BARWIDTH - (currentglyphpos + 1.0) * BARHEIGHT, 0.0); gUVbl[ng] = vec2(0.0, glyphpctsecatlas * ATLASSTEP); gActive[ng] = true; ng++; }
			if (ng < MAXGLYPHS) { gBL[ng] = vec2(-BARWIDTH - (currentglyphpos + 2.0) * BARHEIGHT + BARHEIGHT * 0.2, 0.0); gUVbl[ng] = vec2(0.0, lsb * ATLASSTEP); gActive[ng] = true; ng++; }
			if (msb > 0.0 && ng < MAXGLYPHS) { gBL[ng] = vec2(-BARWIDTH - (currentglyphpos + 3.0) * BARHEIGHT + BARHEIGHT * 0.5, 0.0); gUVbl[ng] = vec2(0.0, msb * ATLASSTEP); gActive[ng] = true; ng++; }
		}
	}

	// ---- vertex expansion: vid 0..27 = bars (3 strips), vid 28..57 = glyph quads ----
	int vid = int(v_vertIdx + 0.5);
	vec2 pos;
	vec4 outcolor;
	float depthbuffermod = 0.0;
	float texBlend = 0.0;
	vec2 baruv = vec2(0.0);

	if (vid < 28) {
		int strip; int lv;
		if      (vid <= 8)  { strip = 0; lv = min(vid, 7); }
		else if (vid == 9)  { strip = 1; lv = 0; }
		else if (vid <= 18) { strip = 1; lv = min(vid - 10, 7); }
		else if (vid == 19) { strip = 2; lv = 0; }
		else                { strip = 2; lv = vid - 20; }

		if (strip == 0) {
			// BACKGROUND (was emitVertexBG)
			depthbuffermod = 0.001;
			if      (lv == 0) pos = vec2(-BARWIDTH,             BARCORNER);
			else if (lv == 1) pos = vec2(-BARWIDTH,             BARHEIGHT - BARCORNER);
			else if (lv == 2) pos = vec2(-BARWIDTH + BARCORNER, 0.0);
			else if (lv == 3) pos = vec2(-BARWIDTH + BARCORNER, BARHEIGHT);
			else if (lv == 4) pos = vec2( BARWIDTH - BARCORNER, 0.0);
			else if (lv == 5) pos = vec2( BARWIDTH - BARCORNER, BARHEIGHT);
			else if (lv == 6) pos = vec2( BARWIDTH,             BARCORNER);
			else              pos = vec2( BARWIDTH,             BARHEIGHT - BARCORNER);
			float extracolor = 0.0;
			if (((BARTYPE & BITFLASHBAR) > 0u) && (mod(timeInfo.x, 10.0) > 4.0)) extracolor = 0.5;
			outcolor = mix(BGBOTTOMCOLOR + extracolor, BGTOPCOLOR + extracolor, pos.y);
			outcolor.a *= v_parameters.y;
		} else {
			// BACKING (strip 1) / FOREGROUND (strip 2) (was emitVertexBarBG)
			vec4 col;
			float bartextureoffset = 0.0;
			if (strip == 1) {
				depthbuffermod = 0.0;
				vec4 tc = truecolor; tc.a = 0.2;
				vec4 topcolor = tc; topcolor.rgb *= BOTTOMDARKENFACTOR;
				if      (lv == 0) { pos = vec2(-BARWIDTH + BARCORNER,                 SMALLERCORNER + BARCORNER);             col = tc; }
				else if (lv == 1) { pos = vec2(-BARWIDTH + BARCORNER,                 BARHEIGHT - SMALLERCORNER - BARCORNER); col = topcolor; }
				else if (lv == 2) { pos = vec2(-BARWIDTH + SMALLERCORNER + BARCORNER, BARCORNER);                            col = tc; }
				else if (lv == 3) { pos = vec2(-BARWIDTH + SMALLERCORNER + BARCORNER, BARHEIGHT - BARCORNER);                 col = topcolor; }
				else if (lv == 4) { pos = vec2( BARWIDTH - SMALLERCORNER - BARCORNER, BARCORNER);                            col = tc; }
				else if (lv == 5) { pos = vec2( BARWIDTH - SMALLERCORNER - BARCORNER, BARHEIGHT - BARCORNER);                 col = topcolor; }
				else if (lv == 6) { pos = vec2( BARWIDTH - BARCORNER,                 SMALLERCORNER + BARCORNER);             col = tc; }
				else              { pos = vec2( BARWIDTH - BARCORNER,                 BARHEIGHT - SMALLERCORNER - BARCORNER); col = topcolor; }
			} else {
				depthbuffermod = -0.001;
				vec4 tc = truecolor;
				if ((BARTYPE & BITCOLORCORRECT) > 0u) tc.rgb = tc.rgb / max(tc.r, tc.g);
				tc.a = 1.0;
				vec4 botcolor = tc; botcolor.rgb *= BOTTOMDARKENFACTOR;
				if ((BARTYPE & BITUSEOVERLAY) > 0u) bartextureoffset = v_parameters.w;
				if      (lv == 0) { pos = vec2(-BARWIDTH + BARCORNER,                                 SMALLERCORNER + BARCORNER);             col = botcolor; }
				else if (lv == 1) { pos = vec2(-BARWIDTH + BARCORNER,                                 BARHEIGHT - BARCORNER - SMALLERCORNER); col = tc; }
				else if (lv == 2) { pos = vec2(-BARWIDTH + BARCORNER + SMALLERCORNER,                 BARCORNER);                            col = botcolor; }
				else if (lv == 3) { pos = vec2(-BARWIDTH + BARCORNER + SMALLERCORNER,                 BARHEIGHT - BARCORNER);                 col = tc; }
				else if (lv == 4) { pos = vec2(-BARWIDTH + BARCORNER + SMALLERCORNER + healthbasedpos, BARCORNER);                           col = botcolor; }
				else if (lv == 5) { pos = vec2(-BARWIDTH + BARCORNER + SMALLERCORNER + healthbasedpos, BARHEIGHT - BARCORNER);               col = tc; }
				else if (lv == 6) { pos = vec2(-BARWIDTH + BARCORNER + 2.0 * SMALLERCORNER + healthbasedpos, BARCORNER + SMALLERCORNER);     col = botcolor; }
				else              { pos = vec2(-BARWIDTH + BARCORNER + 2.0 * SMALLERCORNER + healthbasedpos, BARHEIGHT - BARCORNER - SMALLERCORNER); col = tc; }
			}
			float ux = pos.x * 1.0 / (2.0 * (BARWIDTH - BARCORNER));
			ux += 0.5;
			float uy = (pos.y - BARCORNER) / (BARHEIGHT - 2.0 * BARCORNER);
			baruv = vec2(ux, uy) * vec2(ATLASSTEP * 9.0, ATLASSTEP) + vec2(3.0 * ATLASSTEP, bartextureoffset);
			baruv.y = -baruv.y;
			texBlend = clamp(10000.0 * bartextureoffset, 0.0, 1.0);
			outcolor = col;
			outcolor.a *= v_parameters.y;
		}
	} else {
		// ---- GLYPHS: each slot is 6 strip verts [prevLast, gc0, gc0, gc1, gc2, gc3] ----
		depthbuffermod = 0.0;
		int gi = vid - 28;
		int g = gi / 6;
		int k = gi - g * 6;
		// prevLast (bar-local): position of the last real vertex emitted before this glyph
		vec2 prevLast = barFgLast;
		for (int j = 0; j < g; j++) { if (j < MAXGLYPHS && gActive[j]) prevLast = gBL[j] + vec2(BARHEIGHT, BARHEIGHT); }
		bool slotActive = (g < MAXGLYPHS) && gActive[g];
		if (!slotActive || k == 0) {
			pos = prevLast;            // bridge / collapsed -> degenerate (zero-area)
			outcolor = vec4(1.0, 1.0, 1.0, GLYPHALPHA);
			baruv = vec2(0.0);
			texBlend = 1.0;
		} else {
			int ci = (k <= 2) ? 0 : (k - 2);   // k:1->0 2->0 3->1 4->2 5->3
			vec2 off = (ci == 0) ? vec2(0.0, 0.0)
			         : (ci == 1) ? vec2(0.0, BARHEIGHT)
			         : (ci == 2) ? vec2(BARHEIGHT, 0.0)
			         :             vec2(BARHEIGHT, BARHEIGHT);
			vec2 uvoff = (ci == 0) ? vec2(HALFPIXEL, HALFPIXEL)
			           : (ci == 1) ? vec2(HALFPIXEL, ATLASSTEP - HALFPIXEL)
			           : (ci == 2) ? vec2(ATLASSTEP - HALFPIXEL, HALFPIXEL)
			           :             vec2(ATLASSTEP - HALFPIXEL, ATLASSTEP - HALFPIXEL);
			pos = gBL[g] + off;
			vec2 uvc = gUVbl[g] + uvoff;
			baruv = vec2(uvc.x, 1.0 - uvc.y);  // emitVertexGlyph: g_uv.xy = (uv.x, 1-uv.y)
			outcolor = vec4(1.0, 1.0, 1.0, GLYPHALPHA);
			texBlend = 1.0;                     // glyphs are textured
		}
	}

	vec3 primitiveCoords = vec3(pos.x, 0.0, pos.y - zoffset) * BARSCALE * sizemultiplier;
	vec4 worldPos = vec4(centerpos.xyz + rotY * primitiveCoords, 1.0);
	vec4 P = cameraViewProj * worldPos;
	P.z += depthbuffermod;

	g_color = outcolor;
	g_uv = vec4(baruv, texBlend, 0.0);

	if (!draw) {
		gl_Position = vec4(0.0, 0.0, 2.0, 1.0); // off-screen / clipped -> degenerate
		g_color.a = 0.0;
	} else {
		gl_Position = P;
	}
}
