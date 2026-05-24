shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec3 base_color  : source_color = vec3(0.10, 0.10, 0.13);
uniform vec3 minor_color : source_color = vec3(0.28, 0.28, 0.33);
uniform vec3 major_color : source_color = vec3(0.62, 0.62, 0.68);
uniform float minor_spacing  = 1.0;
uniform float major_spacing  = 5.0;
uniform float line_thickness = 1.5;

float grid_factor(vec2 world_xz, float spacing) {
    vec2 coord = world_xz / spacing;
    vec2 grid  = abs(fract(coord - 0.5) - 0.5) / fwidth(coord);
    float line = min(grid.x, grid.y);
    return 1.0 - min(line / line_thickness, 1.0);
}

void fragment() {
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec2 xz = world_pos.xz;

    float minor = grid_factor(xz, minor_spacing);
    float major = grid_factor(xz, major_spacing);

    vec3 col = base_color;
    col = mix(col, minor_color, minor);
    col = mix(col, major_color, major);

    ALBEDO = col;
}
