Includes = {
	"cw/pdxterrain.fxh"
	"cw/heightmap.fxh"
	"cw/shadow.fxh"
	"cw/utility.fxh"
	"cw/camera.fxh"
	"cw/lighting_util.fxh"
	"cw/lighting.fxh"
	"jomini/jomini_fog.fxh"
	"jomini/map_lighting.fxh"
	"jomini/jomini_fog_of_war.fxh"
	"jomini/jomini_water.fxh"
	"standardfuncsgfx.fxh"
	"bordercolor.fxh"
	"lowspec.fxh"
	"legend.fxh"
	"dynamic_masks.fxh"
	"disease.fxh"
	"shadow_tint.fxh"
	"clouds.fxh"
	"province_effects.fxh"
	"paper_transition.fxh"
	"utility_game.fxh"
}

VertexStruct VS_OUTPUT_PDX_TERRAIN
{
	float4 Position			: PDX_POSITION;
	float3 WorldSpacePos	: TEXCOORD1;
	float4 ShadowProj		: TEXCOORD2;
};

VertexStruct VS_OUTPUT_PDX_TERRAIN_LOW_SPEC
{
	float4 Position			: PDX_POSITION;
	float3 WorldSpacePos	: TEXCOORD1;
	float4 ShadowProj		: TEXCOORD2;
	float3 DetailDiffuse	: TEXCOORD3;
	float4 DetailMaterial	: TEXCOORD4;
	float3 ColorMap			: TEXCOORD5;
	float3 FlatMap			: TEXCOORD6;
	float3 Normal			: TEXCOORD7;
};

# Limited JominiEnvironment data to get nicer transitions between the Flatmap lighting and Terrain lighting
# Only used in terrain shader while lerping between flatmap and terrain.
ConstantBuffer( FlatMapLerpEnvironment )
{
	float	FlatMapLerpCubemapIntensity;
	float3	FlatMapLerpSunDiffuse;
	float	FlatMapLerpSunIntensity;
	float4x4 FlatMapLerpCubemapYRotation;
};

VertexShader =
{
	TextureSampler DetailTextures
	{
		Ref = PdxTerrainTextures0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		type = "2darray"
	}
	TextureSampler NormalTextures
	{
		Ref = PdxTerrainTextures1
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		type = "2darray"
	}
	TextureSampler MaterialTextures
	{
		Ref = PdxTerrainTextures2
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		type = "2darray"
	}
	TextureSampler DetailIndexTexture
	{
		Ref = PdxTerrainTextures3
		MagFilter = "Point"
		MinFilter = "Point"
		MipFilter = "Point"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	TextureSampler DetailMaskTexture
	{
		Ref = PdxTerrainTextures4
		MagFilter = "Point"
		MinFilter = "Point"
		MipFilter = "Point"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	TextureSampler ColorTexture
	{
		Ref = PdxTerrainColorMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	TextureSampler FlatMapTexture
	{
		Ref = TerrainFlatMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}

	Code
	[[
		VS_OUTPUT_PDX_TERRAIN TerrainVertex( float2 WithinNodePos, float2 NodeOffset, float NodeScale, float2 LodDirection, float LodLerpFactor )
		{
			STerrainVertex Vertex = CalcTerrainVertex( WithinNodePos, NodeOffset, NodeScale, LodDirection, LodLerpFactor );

			#ifdef TERRAIN_FLAT_MAP_LERP
				Vertex.WorldSpacePos.y = lerp( Vertex.WorldSpacePos.y, FlatMapHeight, FlatMapLerp );
			#endif
			#ifdef TERRAIN_FLAT_MAP
				Vertex.WorldSpacePos.y = FlatMapHeight;
			#endif

			VS_OUTPUT_PDX_TERRAIN Out;
			Out.WorldSpacePos = Vertex.WorldSpacePos;

			Out.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( Vertex.WorldSpacePos, 1.0 ) );
			Out.ShadowProj = mul( ShadowMapTextureMatrix, float4( Vertex.WorldSpacePos, 1.0 ) );

			return Out;
		}

		// Copies of the pixels shader CalcHeightBlendFactors and CalcDetailUV functions
		float4 CalcHeightBlendFactors( float4 MaterialHeights, float4 MaterialFactors, float BlendRange )
		{
			float4 Mat = MaterialHeights + MaterialFactors;
			float BlendStart = max( max( Mat.x, Mat.y ), max( Mat.z, Mat.w ) ) - BlendRange;

			float4 MatBlend = max( Mat - vec4( BlendStart ), vec4( 0.0 ) );

			float Epsilon = 0.00001;
			return float4( MatBlend ) / ( dot( MatBlend, vec4( 1.0 ) ) + Epsilon );
		}

		float2 CalcDetailUV( float2 WorldSpacePosXZ )
		{
			return (WorldSpacePosXZ + DetailTileOffset) * DetailTileFactor;
		}

		// A low spec vertex buffer version of CalculateDetails
		void CalculateDetailsLowSpec( float2 WorldSpacePosXZ, out float3 DetailDiffuse, out float4 DetailMaterial )
		{
			float2 DetailCoordinates = WorldSpacePosXZ * WorldSpaceToDetail;
			float2 DetailCoordinatesScaled = DetailCoordinates * DetailTextureSize;
			float2 DetailCoordinatesScaledFloored = floor( DetailCoordinatesScaled );
			float2 DetailCoordinatesFrac = DetailCoordinatesScaled - DetailCoordinatesScaledFloored;
			DetailCoordinates = DetailCoordinatesScaledFloored * DetailTexelSize + DetailTexelSize * 0.5;

			float4 Factors = float4(
				(1.0 - DetailCoordinatesFrac.x) * (1.0 - DetailCoordinatesFrac.y),
				DetailCoordinatesFrac.x * (1.0 - DetailCoordinatesFrac.y),
				(1.0 - DetailCoordinatesFrac.x) * DetailCoordinatesFrac.y,
				DetailCoordinatesFrac.x * DetailCoordinatesFrac.y
			);

			float4 DetailIndex = PdxTex2DLod0( DetailIndexTexture, DetailCoordinates ) * 255.0;
			float4 DetailMask = PdxTex2DLod0( DetailMaskTexture, DetailCoordinates ) * Factors[0];

			float2 Offsets[3];
			Offsets[0] = float2( DetailTexelSize.x, 0.0 );
			Offsets[1] = float2( 0.0, DetailTexelSize.y );
			Offsets[2] = float2( DetailTexelSize.x, DetailTexelSize.y );

			for ( int k = 0; k < 3; ++k )
			{
				float2 DetailCoordinates2 = DetailCoordinates + Offsets[k];

				float4 DetailIndices = PdxTex2DLod0( DetailIndexTexture, DetailCoordinates2 ) * 255.0;
				float4 DetailMasks = PdxTex2DLod0( DetailMaskTexture, DetailCoordinates2 ) * Factors[k+1];

				for ( int i = 0; i < 4; ++i )
				{
					for ( int j = 0; j < 4; ++j )
					{
						if ( DetailIndex[j] == DetailIndices[i] )
						{
							DetailMask[j] += DetailMasks[i];
						}
					}
				}
			}

			// We don't use different detail UVs per material like in the normal pdxterrain shader
			float2 DetailUV = CalcDetailUV( WorldSpacePosXZ );

			float4 DiffuseTexture0 = PdxTex2DLod0( DetailTextures, float3( DetailUV, DetailIndex[0] ) ) * smoothstep( 0.0, 0.1, DetailMask[0] );
			float4 DiffuseTexture1 = PdxTex2DLod0( DetailTextures, float3( DetailUV, DetailIndex[1] ) ) * smoothstep( 0.0, 0.1, DetailMask[1] );
			float4 DiffuseTexture2 = PdxTex2DLod0( DetailTextures, float3( DetailUV, DetailIndex[2] ) ) * smoothstep( 0.0, 0.1, DetailMask[2] );
			float4 DiffuseTexture3 = PdxTex2DLod0( DetailTextures, float3( DetailUV, DetailIndex[3] ) ) * smoothstep( 0.0, 0.1, DetailMask[3] );

			float4 BlendFactors = CalcHeightBlendFactors( float4( DiffuseTexture0.a, DiffuseTexture1.a, DiffuseTexture2.a, DiffuseTexture3.a ), DetailMask, DetailBlendRange );

			DetailDiffuse = DiffuseTexture0.rgb * BlendFactors[0] +
							DiffuseTexture1.rgb * BlendFactors[1] +
							DiffuseTexture2.rgb * BlendFactors[2] +
							DiffuseTexture3.rgb * BlendFactors[3];

			DetailMaterial = vec4( 0.0 );

			for ( int i = 0; i < 4; ++i )
			{
				float BlendFactor = BlendFactors[i];
				if ( BlendFactor > 0.0 )
				{
					float3 ArrayUV = float3( DetailUV, DetailIndex[i] );
					float4 NormalTexture = PdxTex2DLod0( NormalTextures, ArrayUV );
					float4 MaterialTexture = PdxTex2DLod0( MaterialTextures, ArrayUV );

					DetailMaterial += MaterialTexture * BlendFactor;
				}
			}
		}

		VS_OUTPUT_PDX_TERRAIN_LOW_SPEC TerrainVertexLowSpec( float2 WithinNodePos, float2 NodeOffset, float NodeScale, float2 LodDirection, float LodLerpFactor )
		{
			STerrainVertex Vertex = CalcTerrainVertex( WithinNodePos, NodeOffset, NodeScale, LodDirection, LodLerpFactor );

			#ifdef TERRAIN_FLAT_MAP_LERP
				Vertex.WorldSpacePos.y = lerp( Vertex.WorldSpacePos.y, FlatMapHeight, FlatMapLerp );
			#endif
			#ifdef TERRAIN_FLAT_MAP
				Vertex.WorldSpacePos.y = FlatMapHeight;
			#endif

			VS_OUTPUT_PDX_TERRAIN_LOW_SPEC Out;
			Out.WorldSpacePos = Vertex.WorldSpacePos;

			Out.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( Vertex.WorldSpacePos, 1.0 ) );
			Out.ShadowProj = mul( ShadowMapTextureMatrix, float4( Vertex.WorldSpacePos, 1.0 ) );

			CalculateDetailsLowSpec( Vertex.WorldSpacePos.xz, Out.DetailDiffuse, Out.DetailMaterial );

			float2 ColorMapCoords = Vertex.WorldSpacePos.xz * WorldSpaceToTerrain0To1;

#if defined( PDX_OSX ) && defined( PDX_OPENGL )
			// We're limited to the amount of samplers we can bind at any given time on Mac, so instead
			// we disable the usage of ColorTexture (since its effects are very subtle) and assign a
			// default value here instead.
			Out.ColorMap = float3( vec3( 0.5 ) );
#else
			Out.ColorMap = ToLinear( PdxTex2DLod0( ColorTexture, float2( ColorMapCoords.x, 1.0 - ColorMapCoords.y ) ).rgb );
#endif

			Out.FlatMap = float3( vec3( 0.5f ) ); // neutral overlay
			#ifdef TERRAIN_FLAT_MAP_LERP
				Out.FlatMap = lerp( Out.FlatMap, PdxTex2DLod0( FlatMapTexture, float2( ColorMapCoords.x, 1.0 - ColorMapCoords.y ) ).rgb, FlatMapLerp );
			#endif

			Out.Normal = CalculateNormal( Vertex.WorldSpacePos.xz );

			return Out;
		}
	]]

	MainCode VertexShader
	{
		Input = "VS_INPUT_PDX_TERRAIN"
		Output = "VS_OUTPUT_PDX_TERRAIN"
		Code
		[[
			PDX_MAIN
			{
				return TerrainVertex( Input.UV, Input.NodeOffset_Scale_Lerp.xy, Input.NodeOffset_Scale_Lerp.z, Input.LodDirection, Input.NodeOffset_Scale_Lerp.w );
			}
		]]
	}

	MainCode VertexShaderSkirt
	{
		Input = "VS_INPUT_PDX_TERRAIN_SKIRT"
		Output = "VS_OUTPUT_PDX_TERRAIN"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT_PDX_TERRAIN Out = TerrainVertex( Input.UV, Input.NodeOffset_Scale_Lerp.xy, Input.NodeOffset_Scale_Lerp.z, Input.LodDirection, Input.NodeOffset_Scale_Lerp.w );

				float3 Position = FixPositionForSkirt( Out.WorldSpacePos, Input.VertexID );
				Out.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( Position, 1.0 ) );

				return Out;
			}
		]]
	}

	MainCode VertexShaderLowSpec
	{
		Input = "VS_INPUT_PDX_TERRAIN"
		Output = "VS_OUTPUT_PDX_TERRAIN_LOW_SPEC"
		Code
		[[
			PDX_MAIN
			{
				return TerrainVertexLowSpec( Input.UV, Input.NodeOffset_Scale_Lerp.xy, Input.NodeOffset_Scale_Lerp.z, Input.LodDirection, Input.NodeOffset_Scale_Lerp.w );
			}
		]]
	}

	MainCode VertexShaderLowSpecSkirt
	{
		Input = "VS_INPUT_PDX_TERRAIN_SKIRT"
		Output = "VS_OUTPUT_PDX_TERRAIN_LOW_SPEC"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT_PDX_TERRAIN_LOW_SPEC Out = TerrainVertexLowSpec( Input.UV, Input.NodeOffset_Scale_Lerp.xy, Input.NodeOffset_Scale_Lerp.z, Input.LodDirection, Input.NodeOffset_Scale_Lerp.w );

				float3 Position = FixPositionForSkirt( Out.WorldSpacePos, Input.VertexID );
				Out.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( Position, 1.0 ) );

				return Out;
			}
		]]
	}
}


PixelShader =
{
	# PdxTerrain uses texture index 0 - 6

	# Jomini specific
	TextureSampler ShadowMap
	{
		Ref = PdxShadowmap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		CompareFunction = less_equal
		SamplerType = "Compare"
	}

	# Game specific
	TextureSampler FogOfWarAlpha
	{
		Ref = JominiFogOfWar
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler FlatMapTexture
	{
		Ref = TerrainFlatMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	TextureSampler EnvironmentMap
	{
		Ref = JominiEnvironmentMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		Type = "Cube"
	}
	TextureSampler FlatMapEnvironmentMap
	{
		Ref = FlatMapEnvironmentMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		Type = "Cube"
	}
	TextureSampler SurroundFlatMapMask
	{
		Ref = SurroundFlatMapMask
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Border"
		SampleModeV = "Border"
		Border_Color = { 1 1 1 1 }
		File = "gfx/map/surround_map/surround_mask.dds"
	}

	Code
	[[
		static const float UNDERWATER_CLIP_OFFSET = 0.00001f;
		static const float TERRAIN_SKIRT_CLIP_OFFSET = 0.01f;

		// --- ELDEN RING, OH ELDEN RING! ---
		static const float MATERIAL_INDEX_GELMIR_LAVA = 52.0f;
		static const float MATERIAL_INDEX_GRAVESITE_PLAIN = 64.0f;
		static const float MATERIAL_INDEX_CERULEAN_COAST  = 124.0f;

		float Hash12(float2 p)
		{
			p = frac(p * 0.1031f);
			p += dot(p, p.yx + 33.33f);
			return frac((p.x + p.y) * p.x);
		}

		float ValueNoise(float2 p)
		{
			float2 i = floor(p);
			float2 f = frac(p);

			float a = Hash12( i );
			float b = Hash12( i + float2( 1.0f, 0.0f ) );
			float c = Hash12( i + float2( 0.0f, 1.0f ) );
			float d = Hash12( i + float2( 1.0f, 1.0f ) );

			float2 u = f * f * ( 3.0f - 2.0f * f );

			return lerp(lerp( a, b, u.x ), lerp( c, d, u.x ), u.y);
		}

		float FBM( float2 p )
		{
			float v = 0.0f;
			v += ValueNoise( p * 0.015f ) * 0.50f;
			v += ValueNoise( p * 0.040f ) * 0.25f;
			v += ValueNoise( p * 0.100f ) * 0.15f;
			v += ValueNoise( p * 0.250f ) * 0.10f;
			return v;
		}

		float SampleMaterialWeightBilinear(float TargetIndex, float2 DetailCoords, float2 IndexMapResolution)
		{
			float2 TexelSize = 1.0f / IndexMapResolution;
			float2 IndexUV = DetailCoords * IndexMapResolution - 0.5f;
			float2 IndexUV_Base = floor(IndexUV);
			float2 IndexUV_Frac = frac(IndexUV);

			float2 UV00 = (IndexUV_Base + float2(0.5f, 0.5f)) * TexelSize;
			float2 UV10 = UV00 + float2(TexelSize.x, 0.0f);
			float2 UV01 = UV00 + float2(0.0f, TexelSize.y);
			float2 UV11 = UV00 + TexelSize;

			float4 Samples[4];
			Samples[0] = PdxTex2DLod0( DetailIndexTexture, UV00 ) * 255.0f;
			Samples[1] = PdxTex2DLod0( DetailIndexTexture, UV10 ) * 255.0f;
			Samples[2] = PdxTex2DLod0( DetailIndexTexture, UV01 ) * 255.0f;
			Samples[3] = PdxTex2DLod0( DetailIndexTexture, UV11 ) * 255.0f;

			float4 Masks[4];
			Masks[0] = PdxTex2D( DetailMaskTexture, UV00 );
			Masks[1] = PdxTex2D( DetailMaskTexture, UV10 );
			Masks[2] = PdxTex2D( DetailMaskTexture, UV01 );
			Masks[3] = PdxTex2D( DetailMaskTexture, UV11 );

			float Weights[4] = { 0.0f, 0.0f, 0.0f, 0.0f };

			[unroll]
			for (int i = 0; i < 4; ++i)
			{
				if ( abs(Samples[i].r - TargetIndex) < 0.5f ) Weights[i] += Masks[i].r;
				if ( abs(Samples[i].g - TargetIndex) < 0.5f ) Weights[i] += Masks[i].g;
				if ( abs(Samples[i].b - TargetIndex) < 0.5f ) Weights[i] += Masks[i].b;
				if ( abs(Samples[i].a - TargetIndex) < 0.5f ) Weights[i] += Masks[i].a;
			}

			return lerp(lerp(Weights[0], Weights[1], IndexUV_Frac.x), lerp(Weights[2], Weights[3], IndexUV_Frac.x), IndexUV_Frac.y);
		}

		void ApplyEldenRingTerrainEffects(in float3 WorldSpacePos, in float3 DetailNormal, in float ShadowTerm, inout float3 DetailDiffuse, inout float4 DetailMaterial)
		{
			float2 UVOffset = float2(
				ValueNoise( WorldSpacePos.xz * 0.15f ),
				ValueNoise( WorldSpacePos.xz * 0.15f + float2( 17.3f, 9.1f ) )
			) * 0.003f;

			float2 DetailCoords = WorldSpacePos.xz * WorldSpaceToDetail;

			float4 MaterialIndices = PdxTex2DLod0( DetailIndexTexture, DetailCoords ) * 255.0;
			float4 MaterialMasks = PdxTex2D( DetailMaskTexture, DetailCoords );

			//float MaterialWeight_GELMIR_LAVA = 0.0;
			//float MaterialWeight_GRAVESITE_PLAIN = 0.0;
			//float MaterialWeight_CERULEAN_COAST = 0.0;

			//if ( abs(MaterialIndices.r - MATERIAL_INDEX_GELMIR_LAVA) < 0.5 ) MaterialWeight_GELMIR_LAVA += MaterialMasks.r;
			//if ( abs(MaterialIndices.g - MATERIAL_INDEX_GELMIR_LAVA) < 0.5 ) MaterialWeight_GELMIR_LAVA += MaterialMasks.g;
			//if ( abs(MaterialIndices.b - MATERIAL_INDEX_GELMIR_LAVA) < 0.5 ) MaterialWeight_GELMIR_LAVA += MaterialMasks.b;
			//if ( abs(MaterialIndices.a - MATERIAL_INDEX_GELMIR_LAVA) < 0.5 ) MaterialWeight_GELMIR_LAVA += MaterialMasks.a;

			//if ( abs(MaterialIndices.r - MATERIAL_INDEX_GRAVESITE_PLAIN) < 0.5 ) MaterialWeight_GRAVESITE_PLAIN += MaterialMasks.r;
			//if ( abs(MaterialIndices.g - MATERIAL_INDEX_GRAVESITE_PLAIN) < 0.5 ) MaterialWeight_GRAVESITE_PLAIN += MaterialMasks.g;
			//if ( abs(MaterialIndices.b - MATERIAL_INDEX_GRAVESITE_PLAIN) < 0.5 ) MaterialWeight_GRAVESITE_PLAIN += MaterialMasks.b;
			//if ( abs(MaterialIndices.a - MATERIAL_INDEX_GRAVESITE_PLAIN) < 0.5 ) MaterialWeight_GRAVESITE_PLAIN += MaterialMasks.a;

			//if ( abs(MaterialIndices.r - MATERIAL_INDEX_CERULEAN_COAST) < 0.5 ) MaterialWeight_CERULEAN_COAST += MaterialMasks.r;
			//if ( abs(MaterialIndices.g - MATERIAL_INDEX_CERULEAN_COAST) < 0.5 ) MaterialWeight_CERULEAN_COAST += MaterialMasks.g;
			//if ( abs(MaterialIndices.b - MATERIAL_INDEX_CERULEAN_COAST) < 0.5 ) MaterialWeight_CERULEAN_COAST += MaterialMasks.b;
			//if ( abs(MaterialIndices.a - MATERIAL_INDEX_CERULEAN_COAST) < 0.5 ) MaterialWeight_CERULEAN_COAST += MaterialMasks.a;

			// Use bilinear sampling to remove blockiness (probably not too performance heavy?)
			float MaterialWeight_GELMIR_LAVA = SampleMaterialWeightBilinear( MATERIAL_INDEX_GELMIR_LAVA, DetailCoords, float2( 1024.0f, 1024.0f ) );
			float MaterialWeight_GRAVESITE_PLAIN = SampleMaterialWeightBilinear( MATERIAL_INDEX_GRAVESITE_PLAIN, DetailCoords, float2( 1024.0f, 1024.0f ) );
			float MaterialWeight_CERULEAN_COAST = SampleMaterialWeightBilinear( MATERIAL_INDEX_CERULEAN_COAST, DetailCoords, float2( 1024.0f, 1024.0f ) );

			float MaskThreshold = 0.0f;

			if ( MaterialWeight_GELMIR_LAVA > MaskThreshold ||
				MaterialWeight_GRAVESITE_PLAIN > MaskThreshold ||
				MaterialWeight_CERULEAN_COAST > MaskThreshold )
			{
				float2 BasePos = WorldSpacePos.xz;
				// GELMIR LAVA - TEXTURE SCROLLING ONLY
				//if ( MaterialWeight_GELMIR_LAVA > MaskThreshold )
				//{
				//	float FlowSpeed = 0.8f;
				//	
				//	float2 FlowingWorldPos = WorldSpacePos.xz + float2( GlobalTime * FlowSpeed, 0.0f );
//
				//	float2 FlowingDetailUV = CalcDetailUV( FlowingWorldPos );
				//	float4 FlowingBaseTex = PdxTex2DLod0( DetailTextures, float3( FlowingDetailUV, MATERIAL_INDEX_GELMIR_LAVA ) );
//
				//	float MaskOpacity = saturate( MaterialWeight_GELMIR_LAVA );
				//	DetailDiffuse = lerp( DetailDiffuse, FlowingBaseTex.rgb, MaskOpacity );
				//}
				if ( MaterialWeight_GELMIR_LAVA > MaskThreshold )
				{
					float FlowSpeed  = 0.8f;
					float PulseSpeed = 5.0f;

					float2 FlowingWorldPos = WorldSpacePos.xz + float2( GlobalTime * FlowSpeed, 0.0f );
					float2 FlowingDetailUV  = CalcDetailUV( FlowingWorldPos );

					float4 FlowingBaseTex = PdxTex2DLod0( DetailTextures, float3( FlowingDetailUV, MATERIAL_INDEX_GELMIR_LAVA ) );

					float Brightness     = max( FlowingBaseTex.r, max( FlowingBaseTex.g, FlowingBaseTex.b ) );
					float HighlightMask  = smoothstep( 0.45f, 0.85f, Brightness );

					float PulseFactor = 0.5f + 0.5f * sin( GlobalTime * PulseSpeed );

					float GlowMultiplier = 1.0f + ( HighlightMask * PulseFactor * 1.8f );
					float3 PulsingLavaColor = FlowingBaseTex.rgb * GlowMultiplier;

					float MaskOpacity = saturate( MaterialWeight_GELMIR_LAVA );
					DetailDiffuse = lerp( DetailDiffuse, PulsingLavaColor, MaskOpacity );
				}

				float GrainA = Hash12( floor( BasePos * 90.0f ) );
				float GrainB = Hash12( floor( BasePos * 180.0f + float2( 19.1f, 37.3f ) ) );
				float PixelGrain = pow( GrainA * GrainB, 2.0f ) * 3.5f;

				float TerrainNoise = FBM( BasePos * 0.5f );
				TerrainNoise = smoothstep( 0.3f, 0.8f, TerrainNoise );

				float PulseA = 0.5f + 0.5f * sin( GlobalTime * 0.8f + TerrainNoise * 15.0f );
				float PulseB = 0.5f + 0.5f * sin( GlobalTime * 1.5f + TerrainNoise * 25.0f );
				float CombinedPulse = PulseA * PulseB;

				float Spark = pow( saturate( sin( GlobalTime * 0.25f + 0.75f * 100.0f ) ), 15.0f );
				float DynamicPulse = ( CombinedPulse * 0.35f + Spark * 0.25f ) * TerrainNoise;

				float3 ViewDir = normalize( CameraPosition - WorldSpacePos );
				float ViewGlint = pow( saturate( dot( ViewDir, DetailNormal ) ), 14.0f );

				if ( MaterialWeight_GRAVESITE_PLAIN > MaskThreshold )
				{
					float MaskOpacity_GRAVESITE_PLAIN = smoothstep( 0.0f, 1.0f, MaterialWeight_GRAVESITE_PLAIN );
					float MaskFactor_GRAVESITE_PLAIN = MaskOpacity_GRAVESITE_PLAIN * ( 0.2f + 0.8f * GrainA );
					float GleamStrength_GRAVESITE_PLAIN = DynamicPulse * MaskFactor_GRAVESITE_PLAIN * PixelGrain;

					DetailMaterial.a = lerp( DetailMaterial.a, 0.05f, GleamStrength_GRAVESITE_PLAIN ); 
					DetailDiffuse += float3( 0.22f, 0.15f, 0.04f ) * GleamStrength_GRAVESITE_PLAIN * ShadowTerm;
					DetailDiffuse += float3( 0.25f, 0.18f, 0.04f ) * ViewGlint * DynamicPulse * MaskFactor_GRAVESITE_PLAIN * PixelGrain * ShadowTerm;
				}

				if ( MaterialWeight_CERULEAN_COAST > MaskThreshold )
				{
					float MaskOpacity_CERULEAN_COAST = smoothstep( 0.0f, 1.0f, MaterialWeight_CERULEAN_COAST );
					float MaskFactor_CERULEAN_COAST = MaskOpacity_CERULEAN_COAST * ( 0.3f + 0.7f * GrainA );
					float GleamStrength_CERULEAN_COAST = DynamicPulse * MaskFactor_CERULEAN_COAST * PixelGrain;

					float3 DeepBlue = float3( 0.03f, 0.08f, 0.35f );
					float3 Cerulean = float3( 0.30f, 0.75f, 1.00f );
					float3 CeruleanColor = lerp( DeepBlue, Cerulean, CombinedPulse );

					DetailMaterial.a = lerp( DetailMaterial.a, 0.02f, GleamStrength_CERULEAN_COAST ); 
					DetailDiffuse += CeruleanColor * GleamStrength_CERULEAN_COAST * ShadowTerm;
					DetailDiffuse += Cerulean * ViewGlint * DynamicPulse * MaskFactor_CERULEAN_COAST * PixelGrain * ShadowTerm;
				}
			}
		}

		// --------------------------------------------

		SLightingProperties GetFlatMapLerpSunLightingProperties( float3 WorldSpacePos, float ShadowTerm )
		{
			SLightingProperties LightingProps;
			LightingProps._ToCameraDir = normalize( CameraPosition - WorldSpacePos );
			LightingProps._ToLightDir = ToSunDir;
			LightingProps._LightIntensity = FlatMapLerpSunDiffuse * 5;
			LightingProps._ShadowTerm = ShadowTerm;
			LightingProps._CubemapIntensity = FlatMapLerpCubemapIntensity;
			LightingProps._CubemapYRotation = FlatMapLerpCubemapYRotation;

			return LightingProps;
		}
		void CheckClipNeeded( float TerrainHeight, float2 MapCoords, float StartColorOverlayHeightBlend )
		{
			#ifdef TERRAIN_SKIRT
				clip( TerrainHeight - TERRAIN_SKIRT_CLIP_OFFSET );
			#endif

			#ifdef UNDERWATER
				// When doing the refraction pass and applying the Color Overlay, skip the parts above the ocean.
				if ( StartColorOverlayHeightBlend > 0.99f )
				{
					clip( _RefractionCullHeight - TerrainHeight );
				}
			#endif
			clip( vec2( 1.0f ) - MapCoords );
		}

	]]

	MainCode PixelShader
	{
		Input = "VS_OUTPUT_PDX_TERRAIN"
		Output = "PDX_COLOR"
		Code
		[[

			PDX_MAIN
			{
				float FullColorOverlayFactor = 0.0f;
				bool IsFullyColorOverlay = false;

				const float2 ColorMapCoords = Input.WorldSpacePos.xz * WorldSpaceToTerrain0To1;
				CheckClipNeeded( Input.WorldSpacePos.y, ColorMapCoords, _StartColorOverlayHeightBlend * _EnabledTerrainCulling );

			#ifndef UNDERWATER
				// Skip terrain rendering below the ocean surface.
				if ( Input.WorldSpacePos.y < UNDERWATER_CLIP_OFFSET && _EnabledTerrainCulling > 0.99f)
				{
					return float4( _UnderwaterTerrainColor.rgb, 0.0f );
				}
			#endif

				float3 FlatMap = float3( 0.5f, 0.5f, 0.5f ); // neutral overlay
				#ifdef TERRAIN_FLAT_MAP_LERP
					FlatMap = lerp( FlatMap, PdxTex2D( FlatMapTexture,
						float2( ColorMapCoords.x, 1.0f - ColorMapCoords.y ) ).rgb,
						FlatMapLerp );
				#endif

				#ifdef TERRAIN_COLOR_OVERLAY
					float3 BorderColor;
					float BorderPreLightingBlend;
					float BorderPostLightingBlend;
					GetBorderColorAndBlendGame( Input.WorldSpacePos.xz, FlatMap, BorderColor, BorderPreLightingBlend, BorderPostLightingBlend );

					FullColorOverlayFactor = BorderPreLightingBlend + BorderPostLightingBlend;
					FullColorOverlayFactor *= _FullyColorOverlayHeightBlend * _EnabledTerrainCulling;
				#endif
				if ( FullColorOverlayFactor > 0.99f )
				{
					IsFullyColorOverlay = true;
				}

				float4 DetailDiffuse = vec4( 0.0f );
				float3 DetailNormal = float3( 0.0f, 1.0f, 0.0f );
				float4 DetailMaterial = vec4( 0.0f );
				float ShadowTerm = 1.0f;
				if( !IsFullyColorOverlay )
				{
					CalculateDetails( Input.WorldSpacePos.xz, DetailDiffuse, DetailNormal, DetailMaterial );
					ShadowTerm = CalculateShadow( Input.ShadowProj, ShadowMap );
					
					// ELDEN RING, OH ELDEN RING!
					ApplyEldenRingTerrainEffects( Input.WorldSpacePos, DetailNormal, ShadowTerm, DetailDiffuse.rgb, DetailMaterial );
				}

				float FogOfWarAlphaValue = PdxTex2D( FogOfWarAlpha, ColorMapCoords).r;
#if defined( PDX_OSX ) && defined( PDX_OPENGL )
				// We're limited to the amount of samplers we can bind at any given time on Mac, so instead
				// we disable the usage of ColorTexture (since its effects are very subtle) and assign a
				// default value here instead.
				float3 ColorMap = float3( vec3( 0.5f ) );
				float ColorDarken = 1.0f;
#else
				float4 ColorMapSample = ToLinear( PdxTex2D( ColorTexture,
						float2( ColorMapCoords.x, 1.0f - ColorMapCoords.y ) ) );
				float ColorDarken = ColorMapSample.a;
				float3 ColorMap = ColorMapSample.rgb;
#endif

				float SnowHighlight = 0.0f;
				float3 Normal = CalculateNormal( Input.WorldSpacePos.xz );
				#ifndef UNDERWATER
					float3 ReorientedNormal = Normal;
					if( !IsFullyColorOverlay )
					{
						float WaterNormalLerp = 0.0f;
						EffectIntensities ConditionData;
						BilinearSampleProvinceEffectsMask( ColorMapCoords, ConditionData );
						ApplyProvinceEffectsTerrain( ConditionData, DetailDiffuse, DetailNormal, DetailMaterial, Input.WorldSpacePos, WaterNormalLerp );

						// Use the property that only water has lower roughness to adjust the terrain normals to face upward.
						float WaterNormalAdjustment = smoothstep( 0.6f, 1.0f, 1 - DetailMaterial.a);
						WaterNormalLerp = max( WaterNormalLerp, WaterNormalAdjustment);
						float3 ReorientedNormal = ReorientNormal(
							lerp( Normal, float3( 0.0f, 1.0f, 0.0f ), WaterNormalLerp ),
							DetailNormal );

						ApplySnowMaterialTerrain( DetailDiffuse, DetailNormal, DetailMaterial, Normal, Input.WorldSpacePos.xz, ColorMapCoords, SnowHighlight );

						if( ConditionData._Drought > 0.0f || SnowHighlight > 0.0f )
						{
							ShadowTerm = lerp( ShadowTerm + 0.4f , ShadowTerm , ShadowTerm );
						}
					}
				#else
					float3 ReorientedNormal = ReorientNormal( Normal, DetailNormal );
				#endif

				float3 Diffuse = SoftLight( DetailDiffuse.rgb, ColorMap,
					( 1 - DetailMaterial.r ) * COLORMAP_OVERLAY_STRENGTH );

				#ifdef TERRAIN_COLOR_OVERLAY
					LerpBorderColorWithFogOfWarAlphaValue( Diffuse, FogOfWarAlphaValue, BorderColor, BorderPreLightingBlend );
					#ifdef TERRAIN_FLAT_MAP_LERP
						float3 FlatColor;
						GetBorderColorAndBlendGameLerp( Input.WorldSpacePos.xz, FlatMap,
							FlatColor, BorderPreLightingBlend, BorderPostLightingBlend,
							FlatMapLerp );

						FlatMap = lerp( FlatMap, FlatColor,
							saturate( BorderPreLightingBlend + BorderPostLightingBlend ) );
					#endif
					float4 HighlightColor = GetHighlightColor( ColorMapCoords );
					ApplyHighlightColor( Diffuse, HighlightColor );
					CompensateWhiteHighlightColor( Diffuse, HighlightColor, SnowHighlight );
				#endif

				SMaterialProperties MaterialProps = GetMaterialProperties(
					Diffuse,
					ReorientedNormal,
					DetailMaterial.a,
					DetailMaterial.g,
					DetailMaterial.b
				);

				SLightingProperties LightingProps = GetMapLightingProperties( Input.WorldSpacePos, ShadowTerm );
				#ifdef TERRAIN_FLAT_MAP_LERP
					LightingProps._LightIntensity = lerp( TERRAIN_SUNNY_SUN_COLOR * TERRAIN_SUNNY_SUN_INTENSITY, FlatMapLerpSunIntensity * SunDiffuse, FlatMapLerp );
					LightingProps._CubemapIntensity =  lerp( DefaultEnvironmentCubemapIntensity * TERRAIN_SUNNY_IBL_SCALE, FlatMapLerpCubemapIntensity , FlatMapLerp );
					LightingProps._ToLightDir = lerp( ToTerrainSunnySunDir, ToSunDir , FlatMapLerp );
				#endif

				// Calculate combined shadow mask from clouds and shadow tint
				float CloudMask = 0.0f;
				float3 FinalColor = vec3( 0.0f );
				if( !IsFullyColorOverlay )
				{
					CloudMask = GetCloudShadowMask( Input.WorldSpacePos.xz, FogOfWarAlphaValue );
					FinalColor = CalculateTerrainDualScenarioLighting( LightingProps, MaterialProps, CloudMask, EnvironmentMap );
					// Apply shadow tint with cloud interaction for terrain
					FinalColor = ApplyTerrainShadowTintWithClouds( FinalColor, Input.WorldSpacePos.xz, CloudMask, ShadowTerm, ReorientedNormal, Normal );
					float BlendAmount = ( 1.0f - ColorDarken ) * CloudMask; // Combine color mask with cloud coverage
					FinalColor.rgb = ApplyOvercastContrast( FinalColor, BlendAmount );
				}

				#ifdef TERRAIN_COLOR_OVERLAY
				 	float NdotL = saturate( dot( MaterialProps._Normal, LightingProps._ToLightDir ) ) + 1e-5;
					BorderColor *= lerp( max( _WaterZoomedInZoomedOutFactor - 0.4f, 0.4f ), 1.0f, NdotL );
					FinalColor.rgb = lerp( FinalColor.rgb, BorderColor, BorderPostLightingBlend );
					ApplyHighlightColor( FinalColor.rgb, HighlightColor, 0.25f );
					ApplyDiseaseDiffuse( FinalColor, ColorMapCoords );
					ApplyLegendDiffuse( FinalColor, ColorMapCoords );
				#endif

				#ifndef UNDERWATER
					if( !IsFullyColorOverlay )
					{
						FinalColor = ApplyFogOfWar( FinalColor, Input.WorldSpacePos, FogOfWarAlpha );
						FinalColor = ApplyMapDistanceFogWithoutFoW( FinalColor, Input.WorldSpacePos );
					}	
				#endif

				#ifdef TERRAIN_FLAT_MAP_LERP
					float Blend = CalculatePaperTransitionBlend( ColorMapCoords, FlatMapLerp );
					FlatMap = ApplyFlatMapBrightnessAdjustment( FlatMap );
					FinalColor = lerp( FinalColor, FlatMap, Blend );
				#endif

				float Alpha = 1.0f;
				#ifdef UNDERWATER
					Alpha = CompressWorldSpace( Input.WorldSpacePos );
				#endif

				#ifdef TERRAIN_DEBUG
					TerrainDebug( FinalColor, Input.WorldSpacePos );
				#endif
				// DebugReturn( FinalColor, MaterialProps, LightingProps, EnvironmentMap );

				return float4( FinalColor, Alpha );
			}
		]]
	}

	MainCode PixelShaderLowSpec
	{
		Input = "VS_OUTPUT_PDX_TERRAIN_LOW_SPEC"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float FullColorOverlayFactor = 0.0f;
				bool IsFullyColorOverlay = false;

				const float2 ColorMapCoords = Input.WorldSpacePos.xz * WorldSpaceToTerrain0To1;
				CheckClipNeeded( Input.WorldSpacePos.y, ColorMapCoords, _StartColorOverlayHeightBlend);

				float3 DetailDiffuse = Input.DetailDiffuse;
				float4 DetailMaterial = Input.DetailMaterial;
				float3 ColorMap = Input.ColorMap;
				float3 FlatMap = Input.FlatMap;
				float3 Normal = Input.Normal;

				#ifdef TERRAIN_COLOR_OVERLAY
					float3 BorderColor;
					float BorderPreLightingBlend;
					float BorderPostLightingBlend;
					GetBorderColorAndBlendGame( Input.WorldSpacePos.xz, FlatMap, BorderColor, BorderPreLightingBlend, BorderPostLightingBlend );

					FullColorOverlayFactor = BorderPreLightingBlend + BorderPostLightingBlend;
					FullColorOverlayFactor *= _FullyColorOverlayHeightBlend * _EnabledTerrainCulling;
				#endif
				if ( FullColorOverlayFactor > 0.99f )
				{
					IsFullyColorOverlay = true;
				}

				float SnowHighlight = 0.0f;
				#ifndef UNDERWATER
					DetailDiffuse = ApplyDynamicMasksDiffuse( DetailDiffuse, Normal, ColorMapCoords );
				#endif

				float3 Diffuse = SoftLight( DetailDiffuse.rgb, ColorMap, ( 1 - DetailMaterial.r ) * COLORMAP_OVERLAY_STRENGTH );

				#ifdef TERRAIN_COLOR_OVERLAY
					float FogOfWarAlphaValue = PdxTex2D( FogOfWarAlpha, ColorMapCoords).r;
					LerpBorderColorWithFogOfWarAlphaValue( Diffuse, FogOfWarAlphaValue, BorderColor, BorderPreLightingBlend );

					#ifdef TERRAIN_FLAT_MAP_LERP
						float3 FlatColor;
						GetBorderColorAndBlendGameLerp( Input.WorldSpacePos.xz, FlatMap,
							FlatColor, BorderPreLightingBlend, BorderPostLightingBlend,
							FlatMapLerp );
						FlatMap = lerp( FlatMap, FlatColor,
							saturate( BorderPreLightingBlend + BorderPostLightingBlend ) );
					#endif
				#endif

				float3 FinalColor = vec3( 0.0f );
				SMaterialProperties MaterialProps = GetMaterialProperties(
					Diffuse,
					Normal,
					DetailMaterial.a,
					DetailMaterial.g,
					DetailMaterial.b
				);
				float ShadowTerm = 1.0f;
				SLightingProperties LightingProps = GetMapLightingProperties( Input.WorldSpacePos, ShadowTerm );
				if( !IsFullyColorOverlay )
				{
					FinalColor = CalculateTerrainSunLightingLowSpec( MaterialProps, LightingProps );
				}
				#ifndef UNDERWATER
					if( !IsFullyColorOverlay )
					{
						FinalColor = ApplyFogOfWar( FinalColor, Input.WorldSpacePos, FogOfWarAlpha );
						FinalColor = ApplyMapDistanceFog( FinalColor, Input.WorldSpacePos, FogOfWarAlpha );
					}
				#endif

				#ifdef TERRAIN_COLOR_OVERLAY
					FinalColor.rgb = lerp( FinalColor.rgb, BorderColor, BorderPostLightingBlend );
				#endif

				#ifdef TERRAIN_COLOR_OVERLAY
					float4 HighlightColor = GetHighlightColor( ColorMapCoords );
					ApplyHighlightColor( FinalColor.rgb, HighlightColor );
					CompensateWhiteHighlightColor( FinalColor.rgb, HighlightColor, SnowHighlight );
				#endif

				#ifdef TERRAIN_FLAT_MAP_LERP
					FinalColor = lerp( FinalColor, FlatMap, FlatMapLerp );
				#endif

				float Alpha = 1.0f;
				#ifdef UNDERWATER
					Alpha = CompressWorldSpace( Input.WorldSpacePos );
				#endif

				#ifdef TERRAIN_DEBUG
					TerrainDebug( FinalColor, Input.WorldSpacePos );
				#endif

				DebugReturn( FinalColor, MaterialProps, LightingProps, EnvironmentMap );
				return float4( FinalColor, Alpha );
			}
		]]
	}

	MainCode PixelShaderFlatMap
	{
		Input = "VS_OUTPUT_PDX_TERRAIN"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				#ifdef TERRAIN_SKIRT
					return float4( 0, 0, 0, 0 );
				#endif

				clip( vec2( 1.0f ) - Input.WorldSpacePos.xz * WorldSpaceToTerrain0To1 );

				float2 ColorMapCoords = Input.WorldSpacePos.xz * WorldSpaceToTerrain0To1;
				float3 FlatMap = PdxTex2D( FlatMapTexture, float2( ColorMapCoords.x, 1.0 - ColorMapCoords.y ) ).rgb;


				#ifdef TERRAIN_COLOR_OVERLAY
					float3 BorderColor;
					float BorderPreLightingBlend;
					float BorderPostLightingBlend;

					GetBorderColorAndBlendGameLerp( Input.WorldSpacePos.xz, FlatMap,
						BorderColor, BorderPreLightingBlend, BorderPostLightingBlend,
						1.0f );

					FlatMap = lerp( FlatMap, BorderColor,
						saturate( BorderPreLightingBlend + BorderPostLightingBlend ) );

				#endif

				float3 FinalColor = FlatMap;
				#ifdef TERRAIN_COLOR_OVERLAY
					float4 HighlightColor = GetHighlightColor( ColorMapCoords );
					ApplyHighlightColor( FinalColor, HighlightColor, 0.5f );
				#endif

				#ifdef TERRAIN_DEBUG
					TerrainDebug( FinalColor, Input.WorldSpacePos );
				#endif

				FinalColor = ApplyFlatMapBrightnessAdjustment( FinalColor );

				// Make flatmap transparent based on the SurroundFlatMapMask
				float SurroundMapAlpha = 1 - PdxTex2D( SurroundFlatMapMask, float2( ColorMapCoords.x, 1.0 - ColorMapCoords.y ) ).b;
				SurroundMapAlpha *= FlatMapLerp;

				return float4( FinalColor, SurroundMapAlpha );
			}
		]]
	}
}


Effect PdxTerrain
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"

	Defines = { "TERRAIN_FLAT_MAP_LERP" }
}

Effect PdxTerrainLowSpec
{
	VertexShader = "VertexShaderLowSpec"
	PixelShader = "PixelShaderLowSpec"
}

Effect PdxTerrainSkirt
{
	VertexShader = "VertexShaderSkirt"
	PixelShader = "PixelShader"
	Defines = { "TERRAIN_SKIRT" }
}

Effect PdxTerrainLowSpecSkirt
{
	VertexShader = "VertexShaderLowSpecSkirt"
	PixelShader = "PixelShaderLowSpec"
	Defines = { "TERRAIN_SKIRT" }
}

### FlatMap Effects

BlendState BlendStateAlpha
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "INV_SRC_ALPHA"
}

Effect PdxTerrainFlat
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderFlatMap"
	BlendState = BlendStateAlpha

	Defines = { "TERRAIN_FLAT_MAP" "TERRAIN_FLATMAP_LIGHTING" }
}

Effect PdxTerrainFlatSkirt
{
	VertexShader = "VertexShaderSkirt"
	PixelShader = "PixelShaderFlatMap"
	BlendState = BlendStateAlpha

	Defines = { "TERRAIN_FLAT_MAP" "TERRAIN_SKIRT" }
}

# Low Spec flat map the same as regular effect
Effect PdxTerrainFlatLowSpec
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderFlatMap"
	BlendState = BlendStateAlpha

	Defines = { "TERRAIN_FLAT_MAP" }
}

Effect PdxTerrainFlatLowSpecSkirt
{
	VertexShader = "VertexShaderSkirt"
	PixelShader = "PixelShaderFlatMap"
	BlendState = BlendStateAlpha

	Defines = { "TERRAIN_FLAT_MAP" "TERRAIN_SKIRT" }
}
