// منقول من the_buttons_glow.gdshader — موجة توهج حلقية عند الضغط (تُرسم بدمج إضافي).
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uProgress;    // 0 → 1.4 ؛ 2.0 = خامد
uniform vec2 uMouse;        // UV
uniform float uThickness;
uniform float uSparkle;
uniform vec4 uColor;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float dist = distance(uv, uMouse);

  float inner_c = smoothstep(uProgress - uThickness, uProgress, dist);
  float outer_c = 1.0 - smoothstep(uProgress, uProgress + 0.03, dist);
  float ring = inner_c * outer_c;

  float noise = hash(uv * 500.0 + uTime * 0.05);
  float dust = ring * noise * uSparkle;

  float mask = (ring + dust) * 2.0;
  float fade = smoothstep(2.0, 0.0, uProgress);
  float a = clamp(uColor.a * mask * fade, 0.0, 1.0);
  fragColor = vec4(uColor.rgb * a, a);
}
