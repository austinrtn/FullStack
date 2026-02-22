#version 330

in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform float time;

out vec4 finalColor;

void main() {
	vec2 uv = fragTexCoord;
	uv.x += sin(uv.y * 10.0 + time) * 0.02;
	uv.y += sin(uv.x * 10.0 + time) * 0.02;

	finalColor = texture(texture0, uv);
}
