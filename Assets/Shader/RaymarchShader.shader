Shader "Raymarch/RaymarchShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}

        [Space]

        _NoiseRTex ("Noise(red canal)", 2D) = "white" {}
        _NoiseGTex ("Noise(green canal)", 2D) = "white" {}
        _NoiseBTex ("Noise(blue canal)", 2D) = "white" {}
        _NoiseATex ("Noise(alpha canal)", 2D) = "white" {}


        [Space]

        _gc("gC", Range(0, 1)) = 0.285
        _gd("gD", Range(0, 1)) = 0.06

        [Space]

        _FreqNoise ("Frequency Noise", Float) = 7.5
        _scatteringCoeff("scatteringCoeff", Range(0, 1)) = 0.668
        _absorbtionCoeff("absorbtionCoeff", Range(0, 1)) = 0.38
        _g("Anisiotropy", Range(-1, 1)) = -0.1

        [Space]

        _SampleCount0("Sample Count (min)", Float) = 30
        _SampleCount1("Sample Count (max)", Float) = 90
        _SampleCountL("Sample Count (light)", Int) = 16

        [Space]

        _Altitude0("Altitude (bottom)", Float) = 1500
        _Altitude1("Altitude (top)", Float) = 3500


        [Space]

        _lightColor ("Light Color", Color) = (1, 1, 1, 1)
            
    }
        SubShader
    {
        Cull Off ZWrite Off ZTest Always


        Pass
        {
            Tags {"LightMode" = "ForwardBase"}
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #define PI 3.1415  

            sampler2D _CameraDepthTexture;
            sampler2D _MainTex;
            sampler2D _NoiseRTex;
            sampler2D _NoiseGTex;
            sampler2D _NoiseBTex;
            sampler2D _NoiseATex;     

            float _gc;
            float _gd;
            float _g; 
            float _w0; 
            float _w1; 

               
            float4x4 _frustrumCorners; 

            float3 _cameraWsPos;
            float3 _lightDir;

            float4 _sphere;
            float4 _sphere2;


            float _SampleCount0;
            float _SampleCount1;
            float _SampleCountL;

            float _Altitude0;
            float _Altitude1;
            float _FarDist;

            float _absorbtionCoeff;
            float _scatteringCoeff;
            float _FreqNoise;

            fixed4 _lightColor;
                
            fixed4 _nr;
            fixed4 _ng;
            fixed4 _nb;
            fixed4 _na ;
            fixed4 _wmr;
            fixed4 _wmg;
            fixed4 _wmb;
            fixed4 _wma;

            fixed4 N;


                struct appdata
                {
                    float4 vertex : POSITION;
                    float2 uv : TEXCOORD0;
                };

                struct v2f
                {
                    float2 uv : TEXCOORD0;
                    float4 vertex : SV_POSITION;
                    float3 rayDirection : TEXCOORD1;
                };

                //SIGNED DISTANCE FUNCTIONS-----------------------------------------------------------------------------------------------------------


                float SDFSphere(float3 p, float radius)
                {
                    return length(p) - radius;
                }


                float map(float3 p, float4 sphere)
                {
                    return SDFSphere(p, sphere.w);
                }
                
                //CLOUD DENSITY FUNCTION-----------------------------------------------------------------------------------------------------------

                float remap (float value, float from1, float to1, float from2, float to2) {
                    return (value - from1) / (to1 - from1) * (to2 - from2) + from2;
                }

                float saturate(float val) {
                    return clamp(val, 0, 1);
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
                   // uv += t;
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
                    uv += curlNoise(uv * 2); 
                
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


                float noise(float r, float g, float b, float a) {
                    return remap(r, - (1 - (g * 0.625 + b * 0.25 + a * 0.125)), 1, 0, 1);
                }



                float heightAlteringFunc(float percentHeight) {
                    float srb = saturate(remap(percentHeight, 0, 0.07, 0, 1));
                    float srt = saturate(remap(percentHeight, 0.2, 0.3, 1, 0));
                    return pow(srb + srt , saturate(remap(percentHeight ,0.65,0.95,1.0,(1 -_gd * _gc))));
                }

                float densityAlteringFunc(float percentHeight) {
                    float drb = percentHeight * saturate(remap(percentHeight, 0, 0.15, 0, 1));
                    float drt = saturate(remap(percentHeight, 0.9, 1, 1, 0)) ;
                    return _gd * drb * drt *  2;
                }

                float getDensity(float percentHeight,float2 uv, float t){
                    N.r = perlinFbm(uv *  _FreqNoise, 2, t);
                    N.g = worleyNoise(uv * _FreqNoise, 2, t * 2);
                    N.b = perlinFbm(uv *  _FreqNoise, 2, t) * (1 - worleyNoise(uv * _FreqNoise, 4, t * 4));
                    N.a = perlinFbm(uv *  _FreqNoise, 2, t) * (1 - worleyNoise(uv * _FreqNoise, 8, t * 4));

                    return saturate(remap(noise (N.r,N.g ,N.b,N.a ) * heightAlteringFunc(percentHeight), 
                    saturate(1 - _gc) , 1, 0, 1)) * densityAlteringFunc(percentHeight);    
                }


                //LIGHTING FUNCTIONS-----------------------------------------------------------------------------------------------------------

                float BP(float d) {
                return exp(-_absorbtionCoeff * d) * (1 - exp(-_absorbtionCoeff * 2 * d));
                }


                float HG(float g, float theta){
                    float g2 = _g*_g;
                    return  (1.-g2) / pow((1. + g2 - 2.*_g*cos(theta)),1.5);
                }


                float raymarchTowardsSun(float3 origin, float3 ld,float3 rayDirection, float2 uv){ //absorption and scattering
                  
                    float stepLength = 0.5*(_Altitude1-_Altitude0) / _SampleCountL;
                    float t=stepLength;
                    float totalDensityTowardsSun = 0;
                    for(int i =0;i<_SampleCountL;i++){
                        if(totalDensityTowardsSun>=1)
                            break;
                        float3 position = origin + t* ld;
                        float currentHeight = position.y / _Altitude1;
                        float densityAtHeight = getDensity(currentHeight,uv,t);
                        totalDensityTowardsSun += densityAtHeight;
                        t+=stepLength;
                    }

                    return   BP(totalDensityTowardsSun) ;
                }

                //RAYMARCH FUNCTION-----------------------------------------------------------------------------------------------------------
          
                float2 getUV(float3 position){
                   float3 n = normalize(position);
                   float u = atan2(n.x, n.z) / (2*PI) + 0.5;
                   float v = n.y * 0.5 + 0.5;
                   return float2(u,v);
                }

                float4 raymarchClouds(float3 origin, v2f input)
                {
                    float3 raydir = input.rayDirection;
                    int samples = lerp(_SampleCount1,_SampleCount0,raydir.y);

                    float2 uv;

                    float3 position=_cameraWsPos.xyz;

                    float dist0 = map(position, _sphere);
                    float dist1 = map(position, _sphere2);

       
                    if (raydir.y < 0.01 || dist0 >= _FarDist) return fixed4(0,0,0, 0);


                    float origStep = (dist1 - dist0) / samples  + 0.5 * length(dist1- _cameraWsPos.y);
                    float cloudStep = 0.2*origStep;
                    float currentStep=origStep;

                    float t = 0;

                    float totalDensity=0;
                    float lightDensity=0;
                    float density =0;
                    float ph =0;

                    float3 ld = - _WorldSpaceLightPos0;
                    float hg = HG(_g,dot(ld,raydir));
                    UNITY_LOOP for (int i =0 ; i<samples ; i++){
                        if(totalDensity>=1)
                            break;

                        dist0 = map(position, _sphere); //distance à la première sphère
                        dist1 = map(position, _sphere2);  //distance à la seconde sphère
                        
                        position = origin + t * input.rayDirection;

                        if(dist0<=10e-4){ //if we're still in the first sphere
                            t-=dist0;
                            float3 p = origin + t*raydir;
                            uv = getUV(p)+_Time.x *0.01;
                        }
                        else{ // we're between the first and second sphere
                                
                            ph = position.y/_Altitude1; //percentage height of current sample

                            density = getDensity(ph,uv,t); //density at this height
                            if(density > 0){ // if we're in a cloud
                                if(currentStep == origStep){ // we take a step back and shorten the step length
                                    t-=currentStep;             
                                    currentStep = cloudStep;
                                }else{
                                    totalDensity += density; // we're in a cloud with correct step length so we add the density at the current height
                                    lightDensity +=  raymarchTowardsSun(position,ld,raydir, uv ) * hg * _scatteringCoeff;
                                }
                            }else{ //we are not in a cloud
                                if(currentStep == cloudStep){ // if we were in one and stepped out of it 
                                    t+=10*currentStep;          // we advance a bit with with the short-step length 
                                    currentStep=origStep;   // and set back the normal length step
                                }   
                            }
                            t+=currentStep; // we advance on the ray   
                        }
                    }
                     return fixed4(float3(lightDensity, lightDensity, lightDensity) *_lightColor.xyz, lightDensity);
                }   

    

                //VERTEX AND FRAGMENT FUNCTIONS-----------------------------------------------------------------------------------------------------------
          
                v2f vert (appdata v)
                {
                    v2f o;

                    half index = v.vertex.z;
                    v.vertex.z = 0;

                    o.vertex = UnityObjectToClipPos(v.vertex);
                    o.uv = v.uv.xy;
                    o.rayDirection = _frustrumCorners[(int) index].xyz;

                    o.rayDirection /= abs(o.rayDirection.z);
                    o.rayDirection = normalize(o.rayDirection);


                    return o;
           
                }

                fixed4 frag(v2f i) : SV_Target
                {
                    float2 rayDir = i.rayDirection.xy;
                       
                     _sphere.w = _Altitude0;
                     _sphere2.w = _Altitude1;

                    float3 ray = normalize(i.rayDirection);
                    fixed4 col = tex2D(_MainTex,i.uv);
                    
                    float4 add = raymarchClouds(_cameraWsPos.xyz,i);
                    return fixed4(add.w * add.xyz + (1-add.w) * col.xyz,1)  ;
                }
                ENDCG
            }
         }

    Fallback "Diffuse"
        
}
