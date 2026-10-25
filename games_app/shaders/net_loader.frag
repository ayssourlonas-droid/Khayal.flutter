// منقول من net_loader.gdshader — مؤشر تحميل (أقواس وايفاي / أعمدة بيانات / سهمان).
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uModeBlend;   // 0 = وايفاي، 1 = بيانات
uniform float uAspect;      // عرض / ارتفاع
uniform vec4 uBase;
uniform vec4 uPulse;
uniform vec4 uBg;

out vec4 fragColor;

const float PI = 3.14159265359;

float sdf_arc(vec2 p, float radius, float thickness, float a0, float a1) {
  float a = atan(p.y, p.x);
  if (a < a0) a += 2.0 * PI;
  float ring_d = abs(length(p) - radius) - thickness;
  if (a >= a0 && a <= a1) return ring_d;
  float d0 = length(p - radius * vec2(cos(a0), sin(a0)));
  float d1 = length(p - radius * vec2(cos(a1), sin(a1)));
  return min(d0, d1) - thickness;
}

float sdf_box(vec2 p, vec2 hs) {
  vec2 d = abs(p) - hs;
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdf_triangle(vec2 p, float size, float up) {
  p.y *= (up > 0.5) ? 1.0 : -1.0;
  p.y += size * 0.4;
  vec2 a = vec2(0.0, -size);
  vec2 b = vec2(-size, size * 0.6);
  vec2 c = vec2(size, size * 0.6);
  vec2 e0 = b - a, e1 = c - b, e2 = a - c;
  vec2 v0 = p - a, v1 = p - b, v2 = p - c;
  vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
  vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
  vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
  float s = sign(e0.x * e2.y - e0.y * e2.x);
  vec2 d0 = vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x));
  vec2 d1 = vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x));
  vec2 d2 = vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x));
  vec2 d = min(min(d0, d1), d2);
  return -sqrt(d.x) * sign(d.y);
}

float shape_mask(float d, float aa) {
  return 1.0 - smoothstep(0.0, aa, d);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 p = uv - 0.5;
  p.x *= uAspect;

  float t = uTime;
  float aa = 0.012;
  vec4 col = uBg;

  float wifi_alpha = 1.0 - uModeBlend;
  float data_alpha = uModeBlend;

  if (wifi_alpha > 0.01) {
    vec2 wp = p - vec2(0.0, 0.02);
    for (int i = 0; i < 3; i++) {
      float radius = 0.09 + float(i) * 0.065;
      float wave = fract(t * 0.5 - float(i) * 0.33);
      float pulse = smoothstep(1.0, 0.55, wave);
      float d = sdf_arc(wp, radius, 0.01, radians(-140.0), radians(-40.0));
      float shape = shape_mask(d, aa);
      vec3 c = mix(uBase.rgb, uPulse.rgb, 0.3 + 0.4 * (1.0 - pulse));
      col.rgb = mix(col.rgb, c, shape * wifi_alpha);
      col.a = max(col.a, shape * wifi_alpha);
    }
    float dd = length(wp - vec2(0.0, 0.045)) - 0.018;
    float ds = shape_mask(dd, aa);
    col.rgb = mix(col.rgb, uBase.rgb, ds * wifi_alpha);
    col.a = max(col.a, ds * wifi_alpha);
  }

  if (data_alpha > 0.01) {
    float bar_w = 0.028;
    float spacing = 0.022;
    float total_w = 4.0 * bar_w + 3.0 * spacing;
    float start_x = -total_w / 2.0 + bar_w / 2.0;
    for (int i = 0; i < 4; i++) {
      float bar_h = 0.05 + float(i) * 0.045;
      float bar_x = start_x + float(i) * (bar_w + spacing);
      float wave = fract(t * 0.5 - float(i) * 0.25);
      float pulse = smoothstep(1.0, 0.55, wave);
      vec2 bp = p - vec2(bar_x, 0.06 - bar_h * 0.5);
      float d = sdf_box(bp, vec2(bar_w * 0.5, bar_h * 0.5));
      float shape = shape_mask(d, aa);
      vec3 c = mix(uBase.rgb, uPulse.rgb, 0.2 + 0.5 * (1.0 - pulse));
      col.rgb = mix(col.rgb, c, shape * data_alpha);
      col.a = max(col.a, shape * data_alpha);
    }
  }

  float total_alpha = max(wifi_alpha, data_alpha);
  if (total_alpha > 0.01) {
    bool toggle = mod(floor(t * 0.9), 2.0) < 1.0;
    vec2 ap = p - vec2(0.16, -0.02);
    float up_d = sdf_triangle(ap - vec2(0.0, -0.025), 0.02, 1.0);
    float down_d = sdf_triangle(ap - vec2(0.0, 0.02), 0.02, 0.0);
    float up_s = shape_mask(up_d, aa);
    float down_s = shape_mask(down_d, aa);
    vec3 up_c = toggle ? uBase.rgb : uPulse.rgb;
    vec3 down_c = toggle ? uPulse.rgb : uBase.rgb;
    col.rgb = mix(col.rgb, up_c, up_s * total_alpha);
    col.a = max(col.a, up_s * total_alpha);
    col.rgb = mix(col.rgb, down_c, down_s * total_alpha);
    col.a = max(col.a, down_s * total_alpha);
  }

  fragColor = vec4(col.rgb * col.a, col.a);
}
