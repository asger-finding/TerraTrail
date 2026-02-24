// Shader til at lave post-processing outline med en Laplacian kantdetektion på dybdebufferen.
// Laplacian (andenordens afledt) er nul på glatte flader, selv i perspektiv,
// og reagerer kun hvor dybden springer (kanter mellem objekter).
//
// Referencer:
// https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html
// https://godotshaders.com/shader/depth-based-outline-shader/
// https://blogs.love2d.org/content/let-it-glow-dynamically-adding-outlines-characters
// https://godotshaders.com/shader/high-quality-post-process-outline/
// https://github.com/jocamar/Godot-Post-Process-Outlines

shader_type spatial;
render_mode unshaded, blend_mul, fog_disabled, depth_test_disabled, skip_vertex_transform, cull_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 outline_color : source_color = vec3(0.15, 0.1, 0.1);

const float EDGE_MIN = 0.003;
const float EDGE_MAX = 0.015;
const float MIN_DEPTH = 0.1;
const float OUTLINE_FADE_START = 400.0;
const float OUTLINE_FADE_END = 1200.0;
const float LAPLACIAN_CENTER = 4.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// Lineær view-space dybde. inv_proj sendes som parameter fordi Mobile rendereren
// ikke giver adgang til INV_PROJECTION_MATRIX i custom funktioner?? (kun i fragment).
float lin_depth(sampler2D dt, vec2 uv, mat4 inv_proj) {
	float d = texture(dt, uv).r;
	vec2 ndc_xy = uv * 2.0 - 1.0;
	vec4 view = inv_proj * vec4(ndc_xy, d, 1.0);
	return -view.z / view.w;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;

	// dc = depth center, du/dd/dl/dr = depth up/down/left/right
	float dc = lin_depth(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX);
	float du = lin_depth(depth_tex, SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float dd = lin_depth(depth_tex, SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float dl = lin_depth(depth_tex, SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float dr = lin_depth(depth_tex, SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);

	// Laplacian [0,-1,0; -1,4,-1; 0,-1,0] normaliseret med dybden
	float laplacian = abs(dc * LAPLACIAN_CENTER - du - dd - dl - dr);
	laplacian /= max(dc, MIN_DEPTH);

	float edge = smoothstep(EDGE_MIN, EDGE_MAX, laplacian);
	edge *= 1.0 - smoothstep(OUTLINE_FADE_START, OUTLINE_FADE_END, dc);

	ALBEDO = mix(vec3(1.0), outline_color, edge);
}
