Shader "Custom/CloudShader"
{
    Properties
    {
        _bgColor ("Background", Color) = (1, 1, 1, 1)
        [Space]
        [Space]
        [Space]
        _FreqNoise ("Frequency Noise", Float) = 3
        _NoiseRTex ("Noise(red canal)", 2D) = "white" {}
        _NoiseGTex ("Noise(green canal)", 2D) = "white" {}
        _NoiseBTex ("Noise(blue canal)", 2D) = "white" {}
        _NoiseATex ("Noise(alpha canal)", 2D) = "white" {}
        [Space]
        [Space]
        [Space]
        _AltMin ("Altitude Min", Float) = 1500
        _AltMax ("Altitude Max", Float) = 3000
        [Space]
        [Space]
        [Space]
        _gc("Global Coverage", Range(0, 1)) = 0.5
        _gd("Global Density", Range(0, 100)) = 0.8
        _g("Anisotropy", Range(-1, 1)) = 0.02
        [Space]
        [Space]
        [Space]
        _Scatter("Scattering Coeff", Range(0, 0.5)) = 0.375
        _Extinct("Extinction Coeff", Range(0, 0.5)) = 0.061
    }
    SubShader
    {
        // No culling or depth
        Tags {"Queue"="Transparent" "IgnoreProjector"="True" "RenderType"="Transparent"}
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Off 
        ZWrite Off 
        ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            const float PI = 3.14159265359;

            fixed4 _bgColor;
            sampler2D _NoiseRTex;
            sampler2D _NoiseGTex;
            sampler2D _NoiseBTex;
            sampler2D _NoiseATex;
            float _gc;
            float _gd;
            float _g;
            float _AltMin;
            float _AltMax;
            float _Scatter;
            float _Extinct;
            float _FreqNoise;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            // Hash functions by Dave_Hoskins
            float hash12(float2 p)
            {
                uint2 q = uint2(int2(p)) * uint2(1597334673, 3812015801);
                uint n = (q.x ^ q.y) * 1597334673;
                return float(n) * (1.0 / float(0xffffffff));
            }

            float2 hash22(float2 p)
            {
                uint2 q = uint2(int2(p))*uint2(1597334673, 3812015801);
                q = (q.x ^ q.y) * uint2(1597334673, 3812015801);
                return float2(q) * (1.0 / float(0xffffffff));
            }

            // Noise function by morgan3d
            float perlinNoise(float2 x) {
                float2 i = floor(x);
                float2 f = frac(x);

                float a = hash12(i);
                float b = hash12(i + float2(1.0, 0.0));
                float c = hash12(i + float2(0.0, 1.0));
                float d = hash12(i + float2(1.0, 1.0));

                float2 u = f * f * (3.0 - 2.0 * f);
                return lerp(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
            }

            float perlinFbm (float2 uv, float freq, float t)
            {
                uv *= freq;
                uv += t;
                float amp = .5;
                float noise = 0.;
                for (int i = 0; i < 8; ++i)
                {
                    noise += amp * perlinNoise(uv);
                    uv *= 2.;
                    amp *= .5;
                }
                return noise;
            }

            float2 curlNoise(float2 uv)
            {
                float2 eps = float2(0., 1.);
                
                float n1, n2, a, b;
                n1 = perlinNoise(uv + eps);
                n2 = perlinNoise(uv - eps);
                a = (n1 - n2) / (2. * eps.y);
                
                n1 = perlinNoise(uv + eps.yx);
                n2 = perlinNoise(uv - eps.yx);
                b = (n1 - n2)/(2. * eps.y);
                
                return float2(a, -b);
            }

            float worleyNoise(float2 uv, float freq, float t)
            {
                uv *= freq;
                uv += t + curlNoise(uv * 2); 
                
                float2 id = floor(uv);
                float2 gv = frac(uv);
                
                float minDist = 100.;
                for (float y = -1.; y <= 1.; ++y)
                {
                    for(float x = -1.; x <= 1.; ++x)
                    {
                        float2 offset = float2(x, y);
                        float2 h = hash22(id + offset) * .8 + .1; // .1 - .9
                        h += offset;
                        float2 d = gv - h;
                        minDist = min(minDist, dot(d, d));
                    }
                }
                
                return minDist;
            }

            float remap (float value, float from1, float to1, float from2, float to2) {
                return (value - from1) / (to1 - from1) * (to2 - from2) + from2;
            }

            float saturate(float val) {
                return clamp(val, 0, 1);
            }

            float noise(float r, float g, float b, float a) {
                return remap(r, - (1 - (g * 0.625 + b * 0.25 + a * 0.125)), 1, 0, 1);
            }

            float detailNoise(float r, float g, float b) {
                return r * 0.625 + g * 0.25 + b * 0.125;
            }

            float heightAlteringFunc(float percentHeight) {
                float srb = saturate(remap(percentHeight, 0, 0.07, 0, 1));
                float srt = saturate(remap(percentHeight, 0.2, 0.3, 1, 0));
                return pow(srb + srt , saturate(remap(percentHeight ,0.65,0.95,1.0,(1 -_gd * _gc))));
            }

            float densityAlteringFunc(float percentHeight, float wma) {
                float drb = percentHeight * saturate(remap(percentHeight, 0, 0.15, 0, 1));
                float drt = saturate(remap(percentHeight, 0.9, 1, 1, 0));
                return _gd * drb * drt * wma * 2;
            }

            float SN(float3 p, float t) {
                float time = ((_Time.x + _Time.y + _Time.z) / 3) * 0.001;
                float2 uv = p.xz + time;
                float ph = clamp(p.y, _AltMin,_AltMax) / _AltMax;

                float4 N;
                // N.r = tex2D(_NoiseRTex, uv).r * _FreqNoise;
                // N.g = tex2D(_NoiseGTex, uv).r * _FreqNoise;
                // N.b = tex2D(_NoiseBTex, uv).r * _FreqNoise;
                // N.a = tex2D(_NoiseATex, uv).r * _FreqNoise;
                N.r = perlinFbm(uv *  _FreqNoise, 2, t);
                N.g = worleyNoise(uv * _FreqNoise, 2, t * 2);
                N.b = perlinFbm(uv *  _FreqNoise, 2, t) * (1 - worleyNoise(uv * _FreqNoise, 4, t * 4));
                N.a = perlinFbm(uv *  _FreqNoise, 2, t) * (1 - worleyNoise(uv * _FreqNoise, 8, t * 4));

                float SN = saturate(remap(noise(N.r, N.g, N.b, N.a) * heightAlteringFunc(ph), saturate(1 - _gc), 1, 0, 1));
                float DN = 0.35 * exp(-_gc * 0.75) * lerp(detailNoise(N.g, N.b, N.a), 1 - detailNoise(N.g, N.b, N.a), saturate(ph * 5));
                float SNND = saturate(remap(SN, DN, 1, 0, 1)) * densityAlteringFunc(ph, 0.7);
                return SNND;
            }

            // ------------------ Lighting ---------------------

            float HG(float cos_angle) {
                float g2 = _g * _g;
                return 0.5 * (1 - g2) / pow(1 + g2 - 2 * _g * cos_angle, 1.5);
            }

            float BP(float d) {
                return exp(-_Extinct * d) * (1 - exp(-_Extinct * 2 * d));
            }

            float raymarchSun(float3 rd, float2 uv ,float t) {
                float sum = 0;
                float step = 1/64;
                float d = 0;
                for(int i = 0; i < 64; i++) {
                    float3 p = rd * i;
                    d = SN(float3(uv.x, p.y, uv.y), t);
                    sum += d;
                }

                return BP(sum);
            }

            float3 fog(float3 col, float t )
            {
                float3 fogCol = float3(0.4,0.6,1.15);
                return lerp( col, fogCol, 1.0-exp(-0.000001*t*t) );
            }

            fixed4 raymarch(float3 rpos, float3 rdir, float2 uv) {
                float t = 1;
                float accDensite = 0;
                float absorption = 0;
                float sum = 0;
                float step = 1 / 64;

                float3 ray = -rdir;
                float3 ld = normalize(_WorldSpaceLightPos0);
                float hg = HG(dot(rdir, ld));
                for(int i = 0; i < 64; i++) {
                    float3 p = rpos + t * rdir;
                    float d = SN(float3(uv.x, p.y, uv.y), t);
                    if(d > 0.001) {
                        float col = raymarchSun(ld, uv, t);
                        float s = d * _Scatter * hg * col ;
                        sum += s;
                        accDensite += d;
                    }
                    t += d * step * (_AltMin / _AltMax);
                }
                float3 color = lerp(float3(sum, sum, sum), _bgColor.xyz, 1 - saturate(accDensite));
                return fixed4(color, sum);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float3 ro = _WorldSpaceCameraPos.xyz;
                float3 rd = normalize(i.vertex.xyz - ro.xyz);

                return raymarch(ro, rd, i.uv);
            }
            ENDCG
        }
    }
}
