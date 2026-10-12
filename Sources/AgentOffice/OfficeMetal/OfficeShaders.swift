/// Ofisin tek shader kaynağı (spec v4 §2), çalışma anında derlenir. Köşe yapısı Core'daki `OfficeVertex` ile,
/// `Uniforms` / `RingData` / `CharDraw` `OfficeMetalRenderer`'daki Swift yapılarıyla aynı sıradadır.
enum OfficeShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VIn {
        float3 pos [[attribute(0)]];
        float3 nrm [[attribute(1)]];
        float2 uv [[attribute(2)]];
        float4 color [[attribute(3)]];
        ushort layer [[attribute(4)]];
        uchar bone [[attribute(5)]];
        uchar part [[attribute(6)]];
    };

    struct Uniforms {
        float4x4 viewProj;
        float4x4 lightViewProj;
        float4 lightDir;      // xyz: ışığın gidiş yönü
        float4 sun;           // rgb: güneş (doğrusal, şiddetiyle)
        float4 sky;           // rgb: yukarı bakan yüzlerin ortam ışığı
        float4 ground;        // rgb: aşağı bakan yüzlerin ortam ışığı
        float4 params;        // x: zaman, y: köylü gölgesi var mı, z: gölge haritası texel'i (statik), w: (köylü)
        float4 bend;          // x: bükülmenin başladığı z, y: katsayı (OfficeViewport.bend)
        float4 skyTop;        // rgb: gökyüzünün tepesi (doğrusal)
        float4 skyHorizon;    // rgb: ufka yakın gökyüzü (doğrusal)
        float4 light;         // x: emissive çarpanı (gece parlak), y: yıldızlar (0…1), z: oda içi ışık (0…1)
    };

    /// Zemin bükülmesi (v5 spec §2): başlangıcın arkasındaki noktalar ufka doğru alçalır. Işık bükülmez.
    static float4 bent(float4 w, constant Uniforms &u) {
        float behind = max(u.bend.x - w.z, 0.0);
        w.y -= u.bend.y * behind * behind;
        return w;
    }

    struct RingData { float4 posScale; };

    struct VOut {
        float4 pos [[position]];
        float3 nrm;
        float2 uv;
        float4 color;         // rgb doğrusal, a: emissive
        float4 lpos;
        ushort layer [[flat]];
        float interior;       // 1: oda içi (gece sıcak oda ışığı)
    };

    static float3 linear(float3 c) {
        return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
    }

    // MARK: Dünya

    vertex VOut worldVS(VIn v [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
        VOut o;
        float4 w = float4(v.pos, 1);
        o.pos = u.viewProj * bent(w, u);
        o.nrm = v.nrm;
        o.uv = v.uv;
        o.color = float4(linear(v.color.rgb), v.color.a);
        o.lpos = u.lightViewProj * w;
        o.layer = v.layer;
        o.interior = v.part == 5 ? 1.0 : 0.0;
        return o;
    }

    vertex float4 worldShadowVS(VIn v [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
        return u.lightViewProj * float4(v.pos, 1);
    }

    // MARK: Işık

    static float shadowAt(depth2d<float> map, sampler s, float3 p, float texel, float bias) {
        float2 uv = p.xy * float2(0.5, -0.5) + 0.5;
        if (any(uv < 0) || any(uv > 1) || p.z > 1) return 1;
        float lit = 0;
        for (int x = -1; x <= 1; x++)
            for (int y = -1; y <= 1; y++)
                lit += map.sample_compare(s, uv + float2(x, y) * texel, p.z - bias);
        return lit / 9;
    }

    /// Ortak aydınlatma (dünya, köylü ve karakterler): gölgeler, sarmalı Lambert, ortam, gece oda ışığı.
    static float4 lit(float3 albedo, float3 nIn, float4 lpos, float emissive, float interior, constant Uniforms &u,
                      depth2d<float> staticShadow, depth2d<float> villagerShadow, sampler shadowSampler) {
        float3 n = normalize(nIn);
        float3 p = lpos.xyz / lpos.w;
        float shade = shadowAt(staticShadow, shadowSampler, p, u.params.z, 0.0015);
        if (u.params.y > 0.5) shade = min(shade, shadowAt(villagerShadow, shadowSampler, p, u.params.w, 0.003));
        // Hafif sarmalı Lambert: gölgeli taraf tamamen kararmasın.
        float ndl = saturate((dot(n, -u.lightDir.xyz) + 0.15) / 1.15);
        float3 ambient = mix(u.ground.rgb, u.sky.rgb, n.y * 0.5 + 0.5);
        // Gece odaların içi sıcak sarı ışıkla aydınlanır (AC'deki gibi); yukarı bakan yüzler biraz daha fazla.
        ambient += float3(1.0, 0.70, 0.40) * (0.55 + 0.25 * saturate(n.y)) * interior * u.light.z;
        float3 c = albedo * (ambient + u.sun.rgb * ndl * shade) + albedo * emissive * 1.5 * u.light.x;
        // v3'teki (RealityKit) yumuşak tona yakın: biraz az doygun.
        c = mix(float3(dot(c, float3(0.2126, 0.7152, 0.0722))), c, 0.82);
        return float4(c, 1);
    }

    fragment float4 shadeFS(VOut i [[stage_in]], constant Uniforms &u [[buffer(1)]],
                            texture2d_array<float> patterns [[texture(0)]],
                            depth2d<float> staticShadow [[texture(1)]], depth2d<float> villagerShadow [[texture(2)]],
                            sampler patternSampler [[sampler(0)]], sampler shadowSampler [[sampler(1)]]) {
        float3 albedo = i.color.rgb;
        if (i.layer > 0) albedo *= patterns.sample(patternSampler, i.uv, i.layer).rgb;
        return lit(albedo, i.nrm, i.lpos, i.color.a, i.interior, u, staticShadow, villagerShadow, shadowSampler);
    }

    // MARK: Karakterler (modüler, dokulu, 4 kemik etkili skinning)

    struct CharIn {
        float3 pos [[attribute(0)]];
        float3 nrm [[attribute(1)]];
        float2 uv [[attribute(2)]];
        uchar4 joints [[attribute(3)]];
        float4 weights [[attribute(4)]];
    };

    struct CharDraw {
        float4x4 model;
        float4 tint;          // rgb (sRGB), w: mod (0 düz, 1 doku, 2 doku × ton, 3 çıkartma, 4 kesik, 5 tasarım)
        float4 tint2;         // tasarımın ikinci rengi (sRGB)
        uint boneBase;
        uint pad0, pad1, pad2;
    };

    struct CharOut {
        float4 pos [[position]];
        float3 nrm;
        float2 uv;
        float4 color;
        float3 color2;
        float4 lpos;
        ushort layer [[flat]];
    };

    static float4x4 charSkin(CharIn v, constant CharDraw &d, constant float4x4 *bones) {
        uint b = d.boneBase;
        return d.model * (bones[b + v.joints.x] * v.weights.x + bones[b + v.joints.y] * v.weights.y
                          + bones[b + v.joints.z] * v.weights.z + bones[b + v.joints.w] * v.weights.w);
    }

    vertex CharOut charVS(CharIn v [[stage_in]], constant Uniforms &u [[buffer(1)]], constant CharDraw &d [[buffer(2)]],
                     constant float4x4 *bones [[buffer(3)]]) {
        float4x4 m = charSkin(v, d, bones);
        float4 w = m * float4(v.pos, 1);
        CharOut o;
        o.pos = u.viewProj * bent(w, u);
        o.nrm = (m * float4(v.nrm, 0)).xyz;
        o.uv = float2(v.uv.x, 1.0 - v.uv.y);   // dokular üstten başlar
        o.color = float4(linear(d.tint.rgb), 0);
        o.color2 = linear(d.tint2.rgb);
        o.lpos = u.lightViewProj * w;
        o.layer = ushort(d.tint.w);
        return o;
    }

    vertex float4 charShadowVS(CharIn v [[stage_in]], constant Uniforms &u [[buffer(1)]], constant CharDraw &d [[buffer(2)]],
                             constant float4x4 *bones [[buffer(3)]]) {
        return u.lightViewProj * (charSkin(v, d, bones) * float4(v.pos, 1));
    }

    fragment float4 charFS(CharOut i [[stage_in]], constant Uniforms &u [[buffer(1)]], texture2d<float> tex [[texture(3)]],
                         texture2d<float> detail [[texture(4)]],
                         depth2d<float> staticShadow [[texture(1)]], depth2d<float> villagerShadow [[texture(2)]],
                         sampler texSampler [[sampler(0)]], sampler shadowSampler [[sampler(1)]]) {
        float3 tint = i.color.rgb;
        float3 albedo = tint;
        uint mode = i.layer;
        if (mode > 0) {
            float4 t = tex.sample(texSampler, i.uv);
            if (mode == 1) albedo = t.rgb;
            else if (mode == 2) albedo = t.rgb * tint;
            else if (mode == 3) albedo = tint * (1.0 - t.a) + t.rgb;   // önceden çarpılmış alfa
            else if (mode == 5) {
                // Tasarım: R ikinci renk maskesi, G gölge; ayrıntı dokusu (önceden çarpılmış) üstüne.
                float3 base = mix(tint, i.color2, t.r) * t.g;
                float4 d = detail.sample(texSampler, i.uv);
                albedo = base * (1.0 - d.a) + d.rgb;
            }
            else {
                if (t.a < 0.5) discard_fragment();
                albedo = t.rgb / max(t.a, 0.001);
            }
        }
        return lit(albedo, i.nrm, i.lpos, 0, 1.0, u, staticShadow, villagerShadow, shadowSampler);
    }

    // MARK: Gökyüzü

    struct SkyOut { float4 pos [[position]]; float2 uv; };

    /// Tam ekran üçgen (köşe tamponu yok); en arkada çizilir.
    vertex SkyOut skyVS(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        SkyOut o;
        o.pos = float4(p * 2 - 1, 1, 1);
        o.uv = float2(p.x, 1 - p.y);
        return o;
    }

    static float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    /// Ufukta açık, yukarıda koyu gökyüzü; gece yukarı kısımda hafifçe parlayıp sönen yıldızlar.
    fragment float4 skyFS(SkyOut i [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
        float t = smoothstep(0.0, 0.85, 1.0 - i.uv.y);
        float3 c = mix(u.skyHorizon.rgb, u.skyTop.rgb, t);
        if (u.light.y > 0.01) {
            float2 cell = floor(i.pos.xy / 3.0);
            float h = hash21(cell);
            if (h > 0.9965) {
                float twinkle = 0.6 + 0.4 * sin(u.params.x * 1.7 + h * 120.0);
                c += float3(0.9, 0.92, 1.0) * twinkle * u.light.y * smoothstep(0.15, 0.6, t);
            }
        }
        return float4(c, 1);
    }

    // MARK: Baş üstü efektleri

    struct EffectSprite { float4 center; float4 params; };   // center.w: boy (m); params: x ekranda kayma (m), y katman, z alfa
    struct EffectOut { float4 pos [[position]]; float2 uv; float alpha; ushort layer [[flat]]; };

    /// Kameraya dönük kare: boy, merkezin üstündeki `boy` metrelik dikey çizginin ekrandaki uzunluğundan.
    vertex EffectOut effectVS(uint vid [[vertex_id]], uint iid [[instance_id]], constant Uniforms &u [[buffer(1)]],
                              constant EffectSprite *sprites [[buffer(2)]], constant float &aspect [[buffer(3)]]) {
        const float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(1, 1), float2(-1, -1), float2(1, 1), float2(-1, 1) };
        EffectSprite sp = sprites[iid];
        float2 c = corners[vid];
        float4 base = u.viewProj * bent(float4(sp.center.xyz, 1), u);
        float4 top = u.viewProj * bent(float4(sp.center.xyz + float3(0, sp.center.w, 0), 1), u);
        float h = length(top.xy / top.w - base.xy / base.w);
        float2 ndc = base.xy / base.w + float2((c.x * 0.5 + sp.params.x / sp.center.w) * h / aspect, c.y * 0.5 * h);
        EffectOut o;
        o.pos = float4(ndc * base.w, base.z, base.w);
        o.uv = float2(c.x * 0.5 + 0.5, 0.5 - c.y * 0.5);
        o.alpha = sp.params.z;
        o.layer = ushort(sp.params.y);
        return o;
    }

    fragment float4 effectFS(EffectOut i [[stage_in]], texture2d_array<float> atlas [[texture(4)]],
                             sampler s [[sampler(0)]]) {
        return atlas.sample(s, i.uv, i.layer) * i.alpha;   // önceden çarpılmış alfa
    }

    // MARK: Bekleme halkası

    struct RingOut { float4 pos [[position]]; };

    vertex RingOut ringVS(VIn v [[stage_in]], constant Uniforms &u [[buffer(1)]], constant RingData *rings [[buffer(2)]],
                          uint iid [[instance_id]]) {
        float4 r = rings[iid].posScale;
        RingOut o;
        o.pos = u.viewProj * bent(float4(r.xyz + float3(v.pos.x * r.w, v.pos.y, v.pos.z * r.w), 1), u);
        return o;
    }

    fragment float4 ringFS(RingOut i [[stage_in]]) {
        return float4(linear(float3(1.0, 0.6, 0.15)), 0.85);
    }
    """
}
