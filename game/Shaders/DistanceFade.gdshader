shader_type spatial;
render_mode unshaded, blend_mul, depth_test_disabled, skip_vertex_transform, cull_disabled;

uniform sampler2D depth_tex : hint_depth_texture;

// Vores dither amplitude - hvor stor er diteringen (skal tilpasses for at skjule quantization)
const float NOISE_AMPLITUDE = 300.0;

// Juster start/slut afstand
uniform float fade_start = 1000.0;
uniform float fade_end = 2400.0;

// Noise hash konstanter
// Se: https://stackoverflow.com/questions/4200224/random-noise-functions-for-glsl
const vec2 HASH_K = vec2(12.9898, 78.233);
const float HASH_M = 43758.5453;
// Wave func multiplier
const float NOISE_SEED_SCALE = 500.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	// Reconstruct world position from depth buffer
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec2 ndc_xy = SCREEN_UV * 2.0 - 1.0;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc_xy, depth_raw, 1.0);
	view_pos.xyz /= view_pos.w;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0)).xyz;

	// Distance from camera
	float dist = length(world_pos.xz - CAMERA_POSITION_WORLD.xz);

	// Animated hash noise for organic dither pattern
	float noise = fract(sin(dot(SCREEN_UV * NOISE_SEED_SCALE, HASH_K)) * HASH_M);
	float fade = smoothstep(fade_start, fade_end, dist + (noise - 0.5) * NOISE_AMPLITUDE);

	// blend_mul: ALPHA=1 preserves pixel, ALPHA=0 makes it transparent in the SubViewport
	ALPHA = 1.0 - fade;
}
