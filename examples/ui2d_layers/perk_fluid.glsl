extern number time;
extern number seed;
extern number cursed;
extern number brightness;
extern vec2 rect_origin;
extern number hex_radius;

number hash21(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

vec2 mod289(vec2 x) {
    return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec3 mod289(vec3 x) {
    return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec3 permute(vec3 x) {
    return mod289(((x * 34.0) + 10.0) * x);
}

number simplex_noise(vec2 v) {
    const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
    vec2 i = floor(v + dot(v, C.yy));
    vec2 x0 = v - i + dot(i, C.xx);
    vec2 i1 = x0.x > x0.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289(i);
    vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
    vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;
    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    vec3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

number noise(vec2 p) {
    return clamp(simplex_noise(p) * 0.5 + 0.5, 0.0, 1.0);
}

vec3 palette(number v) {
    vec3 dark = cursed > 0.5 ? vec3(0.13, 0.01, 0.015) : vec3(0.08, 0.03, 0.17);
    vec3 deep = cursed > 0.5 ? vec3(0.28, 0.025, 0.035) : vec3(0.23, 0.05, 0.36);
    vec3 mid = cursed > 0.5 ? vec3(0.52, 0.055, 0.045) : vec3(0.48, 0.13, 0.62);
    vec3 hot = cursed > 0.5 ? vec3(0.84, 0.10, 0.055) : vec3(0.92, 0.18, 0.86);
    vec3 light = cursed > 0.5 ? vec3(1.00, 0.38, 0.18) : vec3(1.00, 0.67, 1.00);
    if (v < 0.34) return mix(dark, deep, v / 0.34);
    if (v < 0.68) return mix(deep, mid, (v - 0.34) / 0.34);
    if (v < 0.90) return mix(mid, hot, (v - 0.68) / 0.22);
    return mix(hot, light, (v - 0.90) / 0.10);
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec4 sample_color = Texel(tex, texture_coords);
    number radius = max(1.0, hex_radius);
    vec2 local_pos = screen_coords - rect_origin;

    number axial_q = (0.57735026919 * local_pos.x - 0.33333333333 * local_pos.y) / radius;
    number axial_r = (0.66666666667 * local_pos.y) / radius;
    number cube_x = axial_q;
    number cube_z = axial_r;
    number cube_y = -cube_x - cube_z;
    number rx = floor(cube_x + 0.5);
    number ry = floor(cube_y + 0.5);
    number rz = floor(cube_z + 0.5);
    number x_diff = abs(rx - cube_x);
    number y_diff = abs(ry - cube_y);
    number z_diff = abs(rz - cube_z);
    if (x_diff > y_diff && x_diff > z_diff) rx = -ry - rz;
    else if (y_diff > z_diff) ry = -rx - rz;
    else rz = -rx - ry;

    vec2 cell = vec2(rx, rz);
    vec2 center = vec2(radius * 1.7320508 * (rx + rz * 0.5), radius * 1.5 * rz);
    vec2 local_hex = local_pos - center;
    vec2 world_center = rect_origin + center;
    vec2 p = vec2((world_center.x + seed * 19.7) * 0.0092, (world_center.y - seed * 13.1) * 0.0092);
    number t = time * 0.045;
    number warp_a = noise(p * 0.62 + vec2(t * 0.75, -t * 0.34 + seed * 0.071));
    number warp_b = noise(p * 0.62 + vec2(-t * 0.47 + seed * 0.113, t * 0.58));
    number wx = (warp_a - 0.5) * 4.4;
    number wy = (warp_b - 0.5) * 4.4;
    number broad = noise(p + vec2(wx + t * 0.92 + seed * 0.127, wy - t * 0.48 + seed * 0.083));
    number detail = noise(p * 2.2 + vec2(wx * 0.55 - t * 0.36, wy * 0.55 + t * 0.42));
    number haze = noise(p * 4.4 + vec2(seed * 0.29 + t * 0.18, -seed * 0.17 - t * 0.14));
    number grain = hash21(vec2((cell.x + seed * 17.0) * 12.9898, (cell.y - seed * 9.0) * 78.233));
    number fleck = hash21(vec2((cell.x - seed * 5.0) * 41.113, (cell.y + seed * 3.0) * 17.371));
    number fluid = clamp(broad * 0.62 + detail * 0.26 + haze * 0.12
        + (grain - 0.5) * 0.16 + (fleck - 0.5) * 0.08, 0.0, 1.0);
    fluid = smoothstep(0.04, 0.98, fluid);
    fluid = clamp(floor(fluid * 15.0 + 0.5) / 15.0, 0.0, 1.0);
    number highlight = smoothstep(0.74, 1.0, fluid);
    vec3 rgb = palette(fluid) + vec3(highlight * 0.06);

    number qx = abs(local_hex.x) / max(0.001, radius * 0.866);
    number qy = abs(local_hex.y) / max(0.001, radius);
    number hex_edge = max(qx * 0.866 + qy * 0.5, qy);
    number edge = smoothstep(0.78, 0.99, hex_edge);
    rgb *= 0.82 + edge * 0.18;
    rgb = mix(rgb, vec3(1.0), clamp(brightness, 0.0, 1.0));

    return vec4(rgb * color.rgb, sample_color.a * color.a * (0.76 + highlight * 0.18));
}
