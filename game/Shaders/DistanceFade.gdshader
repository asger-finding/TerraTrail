shader_type spatial;
render_mode unshaded, blend_mul, depth_test_disabled, skip_vertex_transform, cull_disabled;

uniform sampler2D depth_tex : hint_depth_texture;

// Vores dither amplitude for at undgå quantization
const float NOISE_FRACTION = 0.250;

// Juster start/slut afstand (beregnet som summen af afstanden fra spiller + kamera)
uniform float fade_start = 2000.0;
uniform float fade_end = 4800.0;

// Spillerens XZ-position i verden (skal opdateres i script)
uniform vec2 player_pos = vec2(0.0, 0.0);

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
	// Rekonstruer verdenspositionen fra depth buffer
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec2 ndc_xy = SCREEN_UV * 2.0 - 1.0;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc_xy, depth_raw, 1.0);
	view_pos.xyz /= view_pos.w;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0)).xyz;

	// Sum af afstande fra kamera og spiller
	float dist_cam = length(world_pos.xz - CAMERA_POSITION_WORLD.xz);
	float dist_player = length(world_pos.xz - player_pos);
	float dist_sum = dist_cam + dist_player;

	// Hash noise
	// skaleres med fade-bredden så dithering vokser med zoom
	float noise = fract(sin(dot(SCREEN_UV * NOISE_SEED_SCALE, HASH_K)) * HASH_M);
	float noise_amp = (fade_end - fade_start) * NOISE_FRACTION;
	float fade = smoothstep(fade_start, fade_end, dist_sum + (noise - 0.5) * noise_amp);

	// Sæt alpha efter fade
	ALPHA = 1.0 - fade;
}
