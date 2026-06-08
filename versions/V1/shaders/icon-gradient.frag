#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tintColor;
} ubuf;

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 src = texture(source, qt_TexCoord0);
    float gray = dot(src.rgb, vec3(0.299, 0.587, 0.114));
    // gradient: 1.0 at top (y=0), 0.0 at bottom (y=1)
    float t = pow(1.0 - qt_TexCoord0.y, 1.2);
    vec3 col = mix(vec3(gray), ubuf.tintColor.rgb, t * 0.6);
    fragColor = vec4(col * src.a, src.a) * ubuf.qt_Opacity;
}
