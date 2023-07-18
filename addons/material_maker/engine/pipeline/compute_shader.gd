extends MMPipeline
class_name MMComputeShader


var shader : RID
var texture_type : int

var diff : int

var render_time : int = 0


const LOCAL_SIZE : int = 64


func _init():
	clear()

func clear():
	super.clear()

func set_shader(string : String, tex_type : int, replaces : Dictionary = {}):
	texture_type = tex_type
	replaces["@LOCAL_SIZE"] = str(LOCAL_SIZE)
	replaces["@OUT_TEXTURE_TYPE"] = TEXTURE_TYPE[tex_type].decl
	replaces["@DECLARATIONS"] = get_uniform_declarations()+"\n"+get_texture_declarations()
	
	var rd : RenderingDevice = await mm_renderer.request_rendering_device(self)
	shader = do_compile_shader(rd, { compute=string }, replaces)
	mm_renderer.release_rendering_device(self)

func set_parameters_from_shadercode(shader_code : MMGenBase.ShaderCode):
	for u in shader_code.uniforms:
		for c in [ "\n".join(shader_code.globals), shader_code.defs, shader_code.code, shader_code.output_values.rgba ]:
			if c.find(u.name) != -1:
				add_parameter_or_texture(u.name, u.type, u.value)
				break

func set_shader_from_shadercode(shader_code : MMGenBase.ShaderCode, is_32_bits : bool = false, compare_texture : MMTexture = null) -> void:
	var tex_type : int = 0 if shader_code.output_type == "f" else 1
	if is_32_bits:
		tex_type |= 2
	
	var replaces : Dictionary = {}
	
	clear()
	set_parameters_from_shadercode(shader_code)
	
	if compare_texture != null:
		add_parameter_or_texture("mm_compare", "sampler2D", compare_texture)
	
	var string : String = ""
	
	string = "#version 450\n"
	string += "\n"
	string += "layout(local_size_x = @LOCAL_SIZE, local_size_y = 1, local_size_z = 1) in;\n"
	string += "\n"
	string += "layout(set = 0, binding = 0, @OUT_TEXTURE_TYPE) uniform image2D OUTPUT_TEXTURE;\n" 
	string += "@DECLARATIONS"
	string += "layout(set = 3, binding = 0, std140) restrict buffer MM {\n"
	string += "\tint mm_chunk_y;\n"
	string += "};\n"
	if compare_texture != null:
		string += "layout(set = 4, binding = 0, std140) buffer MMout {\n"
		string += "\tint mm_compare[1];\n"
		string += "} mm_out;\n"
	string += preload("res://addons/material_maker/shader_functions.tres").text
	string += "\n"
	string += "const float seed_variation = 0.0;\n"
	string += "\n"
	string += "@GLOBALS\n"
	string += "@DEFINITIONS\n"
	string += "void main() {\n"
	string += "\tfloat _seed_variation_ = seed_variation;\n"
	string += "\tvec2 pixel = gl_GlobalInvocationID.xy+vec2(0.5, 0.5+mm_chunk_y);\n"
	string += "\tvec2 image_size = imageSize(OUTPUT_TEXTURE);\n"
	string += "\tvec2 uv = pixel/image_size;\n"
	string += "\t@CODE;\n"
	string += "\tvec4 outColor = @OUTPUT_VALUE;\n"
	string += "\timageStore(OUTPUT_TEXTURE, ivec2(pixel), outColor);\n"
	if compare_texture != null:
		string += "\tvec4 diff_vec = abs(outColor - texture(mm_compare, uv));\n"
		string += "\tfloat diff = max(max(diff_vec.r, diff_vec.g), max(diff_vec.b, diff_vec.a));\n"
		string += "\tatomicMax(mm_out.mm_compare[0], int(diff*65536.0));\n"
	string += "}\n"
	
	replaces["@GLOBALS"] = "\n".join(shader_code.globals)
	replaces["@DEFINITIONS"] = shader_code.defs
	replaces["@CODE"] = shader_code.code
	replaces["@OUTPUT_VALUE"] = shader_code.output_values.rgba

	await set_shader(string, tex_type, replaces)

func get_parameters() -> Dictionary:
	var rv : Dictionary = {}
	for p in parameters.keys():
		rv[p] = parameters[p].value
	for t in texture_indexes.keys():
		rv[t] = textures[texture_indexes[t]].texture
	return rv

func render_loop(rd : RenderingDevice, size : Vector2i, chunk_height : int, uniform_set_0 : RID, uniform_set_1 : RID, uniform_set_2 : RID, uniform_set_4 : RID):
	var y : int = 0
	while y < size.y:
		var h : int = min(chunk_height, size.y-y)
		
		var rids : RIDs = RIDs.new()
		
		# Create a compute pipeline
		var pipeline : RID = rd.compute_pipeline_create(shader)
		if !pipeline.is_valid():
			print("Cannot create pipeline")
		rids.add(pipeline)
		var compute_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set_0, 0)
		if uniform_set_1.is_valid():
			rd.compute_list_bind_uniform_set(compute_list, uniform_set_1, 1)
		if uniform_set_2.is_valid():
			rd.compute_list_bind_uniform_set(compute_list, uniform_set_2, 2)
		
		var loop_parameters_values : PackedByteArray = PackedByteArray()
		loop_parameters_values.resize(4)
		loop_parameters_values.encode_s32(0, y)
		var uniform_set_3 : RID = rd.uniform_set_create(create_buffers_uniform_list(rd, [loop_parameters_values], rids), shader, 3)
		rids.add(uniform_set_3)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set_3, 3)
		
		if uniform_set_4.is_valid():
			rd.compute_list_bind_uniform_set(compute_list, uniform_set_4, 4)
		
		#print("Dispatching compute list")
		rd.compute_list_dispatch(compute_list, (size.x+LOCAL_SIZE-1)/LOCAL_SIZE, h, 1)
		rd.compute_list_end()
		#print("Rendering "+str(self))
		rd.submit()
		#await mm_renderer.get_tree().process_frame
		rd.sync()
		
		rids.free_rids(rd)
		
		#print("End rendering %d-%d (%dms)" % [ y, y+h, render_time ])
		
		y += h

func render(texture : MMTexture, size : int) -> bool:
	var rd : RenderingDevice = await mm_renderer.request_rendering_device(self)
	var rids : RIDs = RIDs.new()
	var start_time = Time.get_ticks_msec()
	var status = await render_2(rd, texture, size, rids)
	rids.free_rids(rd)
	render_time = Time.get_ticks_msec() - start_time
	mm_renderer.release_rendering_device(self)
	return status

func render_2(rd : RenderingDevice, texture : MMTexture, size : int, rids : RIDs) -> bool:
	#print("Preparing render")
	var output_tex : RID = create_output_texture(rd, Vector2i(size, size), texture_type)
	if shader.is_valid():
		var status : bool = await do_render(rd, output_tex, Vector2i(size, size), rids)
		if ! status:
			return false
	else:
		print("Invalid shader, generating blank image")
		return false
	
	texture.set_texture_rid(output_tex, Vector2i(size, size), TEXTURE_TYPE[texture_type].data_format)
	
	return true

func do_render(rd : RenderingDevice, output_tex : RID, size : Vector2i, rids : RIDs) -> bool:
	var outputs : PackedByteArray
	
	diff = 65536
	
	var output_tex_uniform : RDUniform = RDUniform.new()
	output_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_tex_uniform.binding = 0
	output_tex_uniform.add_id(output_tex)
	var uniform_set_0 : RID = rd.uniform_set_create([output_tex_uniform], shader, 0)
	rids.add(uniform_set_0)
	
	var uniform_set_1 : RID = RID()
	if parameter_values.size() > 0:
		uniform_set_1 = get_parameter_uniforms(rd, shader, rids)
		if ! uniform_set_1.is_valid():
			print("Failed to create valid uniform for parameters")
			return false
	
	var uniform_set_2 = RID()
	if !textures.is_empty():
		uniform_set_2 = get_texture_uniforms(rd, shader, rids)
		if ! uniform_set_2.is_valid():
			print("Failed to create valid uniform for textures")
			return false
	
	var uniform_set_4 = RID()
	var outputs_buffer : RID
	if texture_indexes.has("mm_compare"):
		outputs = PackedInt32Array([0]).to_byte_array()
		outputs_buffer = rd.storage_buffer_create(outputs.size(), outputs)
		rids.add(outputs_buffer)
		var outputs_uniform : RDUniform = RDUniform.new()
		outputs_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		outputs_uniform.binding = 0
		outputs_uniform.add_id(outputs_buffer)
		uniform_set_4 = rd.uniform_set_create([outputs_uniform], shader, 4)
		rids.add(uniform_set_4)
	
	var max_viewport_size = mm_renderer.max_viewport_size
	var chunk_count : int = max(1, size.x*size.y/(max_viewport_size*max_viewport_size))
	var chunk_height : int = max(1, size.y/chunk_count)
	
	#await render_loop(rd, size, chunk_height, uniform_set_0, uniform_set_1, uniform_set_2, uniform_set_4)
	if true:
		# Use threads
		var thread : Thread = Thread.new()
		thread.start(render_loop.bind(rd, size, chunk_height, uniform_set_0, uniform_set_1, uniform_set_2, uniform_set_4))
		while thread.is_alive():
			await mm_renderer.get_tree().process_frame
		
		thread.wait_to_finish()
	else:
		render_loop(rd, size, chunk_height, uniform_set_0, uniform_set_1, uniform_set_2, uniform_set_4)
	
	if uniform_set_4.is_valid():
		outputs = rd.buffer_get_data(outputs_buffer)
		diff = outputs.to_int32_array()[0]
	
	return true

func get_difference() -> int:
	return diff