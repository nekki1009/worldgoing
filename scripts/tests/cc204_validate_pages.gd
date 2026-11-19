extends SceneTree
var failures: Array[String]=[]
var source_cache: Dictionary={}
var results: Array=[]
func _initialize() -> void:_run.call_deferred()
func need(ok: bool,label: String) -> bool:
 if not ok:failures.append(label);push_error(label)
 return ok
func digest(bytes: PackedByteArray) -> String:
 var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func sources(record: Dictionary,label: String) -> bool:
 var ok:=need(not record.get("source_fingerprints",{}).is_empty(),label+" source bundle")
 for p: String in record.get("source_fingerprints",{}):
  if not source_cache.has(p):source_cache[p]=FileAccess.get_md5(p)
  ok=need(str(source_cache[p]).length()==32 and source_cache[p]==record.source_fingerprints[p],label+" source "+p) and ok
 if record.has("source_manifest_md5"):ok=need(record.source_manifest_md5==FileAccess.get_md5(record.source_manifest),label+" parent hash") and ok
 return ok
func color_page(page: Dictionary,label: String) -> Dictionary:
 var png:=Image.load_from_file(str(page.path))
 var texture:=ResourceLoader.load(str(page.resource_path),"Texture2D",ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
 if not need(png!=null and texture!=null,label+" decode"):return {}
 var restored:=texture.get_image()
 if not need(restored!=null,label+" resource image"):return {}
 png.convert(Image.FORMAT_RGBA8);restored.convert(Image.FORMAT_RGBA8)
 need(png.get_width()==int(page.width) and png.get_height()==int(page.height) and restored.get_size()==png.get_size(),label+" dimensions")
 need(png.get_data()==restored.get_data(),label+" complete RGBA PNG/resource equality")
 if page.has("png_md5"):need(page.png_md5==FileAccess.get_md5(page.path),label+" PNG hash")
 if page.has("resource_md5"):need(page.resource_md5==FileAccess.get_md5(page.resource_path),label+" resource hash")
 var f:=FileAccess.open(page.path,FileAccess.READ)
 var png_bytes:=f.get_length();f.close();f=FileAccess.open(page.resource_path,FileAccess.READ)
 var resource_bytes:=f.get_length();f.close()
 return {"path":page.path,"resource_path":page.resource_path,"width":png.get_width(),"height":png.get_height(),"png_bytes":png_bytes,"resource_bytes":resource_bytes,"decoded_rgba_bytes":png.get_data().size(),"rgba_sha256":digest(png.get_data())}
func _run() -> void:
 var args:=OS.get_cmdline_user_args()
 if args.size()!=2:quit(1);return
 var paths: Array=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
 for p: String in paths:
  var record: Variant=JSON.parse_string(FileAccess.get_file_as_string(p))
  if not need(record is Dictionary,p+" JSON"):continue
  var start_errors:=failures.size()
  sources(record,p)
  var metrics: Array=[]
  if record.has("mask_path"):
   need(record.get("complete")==true,p+" complete dye")
   need(FileAccess.get_md5(record.mask_path)==record.mask_md5,p+" mask hash")
   var mask:=Image.load_from_file(record.mask_path)
   if need(mask!=null,p+" mask decode"):
    need(mask.get_width()==int(record.width) and mask.get_height()==int(record.height),p+" mask dimensions")
    mask.convert(Image.FORMAT_RGB8)
    var parent: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(record.source_manifest))
    var page: Dictionary=parent.atlas if parent.has("atlas") else parent.pages[0]
    need(int(page.width)==mask.get_width() and int(page.height)==mask.get_height(),p+" matching color size")
    need(int(record.frame_count)==parent.frames.size(),p+" matching color frame count")
    metrics.append({"mask_path":record.mask_path,"decoded_rgb_bytes":mask.get_data().size(),"rgb_sha256":digest(mask.get_data())})
  elif record.get("kind") in ["mounted_soldier_atlas","logistics_rider_atlas","cloth_wagon_rider_atlas"] or record.has("asset_md5"):
   var folder:=p.get_base_dir()+"/"
   for name: String in record.get("asset_md5",{}):
    need(FileAccess.get_md5(folder+name)==record.asset_md5[name],p+" asset "+name)
    if name.ends_with(".res"):
     var resource:=ResourceLoader.load(folder+name,"",ResourceLoader.CACHE_MODE_IGNORE)
     # The original mounted baker saves Image resources; other bakers save Texture2D.
     var image: Image=resource if resource is Image else resource.get_image() if resource is Texture2D else null
     if need(image!=null,p+" resource image "+name):metrics.append({"resource_path":folder+name,"resource_type":resource.get_class(),"width":image.get_width(),"height":image.get_height(),"decoded_bytes":image.get_data().size(),"pixel_sha256":digest(image.get_data())})
  else:
   var pages: Array=[record.atlas] if record.has("atlas") else record.get("pages",[])
   need(not pages.is_empty(),p+" complete pages")
   var page_of: Dictionary={}
   for n in pages.size():
    var page: Dictionary=pages[n]
    var m:=color_page(page,p+" page "+str(n));metrics.append(m)
    page_of[int(page.get("page",n))]=page
    if record.get("metrics",{}).has("pixel_sha256"):need(m.get("rgba_sha256")==record.metrics.pixel_sha256,p+" baked pixel SHA256")
   for frame: Dictionary in record.get("frames",[]):
    var page: Dictionary=page_of.get(int(frame.get("page",0)),{})
    if not need(not page.is_empty(),p+" frame page"):continue
    var rect: Dictionary=frame.rect
    need(int(rect.x)>=0 and int(rect.y)>=0 and int(rect.w)>0 and int(rect.h)>0 and int(rect.x)+int(rect.w)<=int(page.width) and int(rect.y)+int(rect.h)<=int(page.height),p+" rect bounds")
    need(is_finite(float(frame.anchor_offset.x)) and is_finite(float(frame.anchor_offset.y)) and is_finite(float(frame.sample_time)) and float(frame.duration)>0.0,p+" anchor/time")
   if record.get("kind")=="terrain_army_recipe_batch":need(record.frames.size()<=128,p+" original batch cap")
  results.append({"path":p,"status":"PASS" if failures.size()==start_errors else "FAIL","frames":record.get("frames",[]).size(),"metrics":metrics})
  print("CC204_PAGE ",results.back().status," ",p)
 for p: String in source_cache:need(FileAccess.get_md5(p)==source_cache[p],"source stable at end "+p)
 var file:=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL","results":results,"failures":failures,"source_md5":source_cache},"  ",true));file.close()
 print("CC204_PAGES_", "PASS" if failures.is_empty() else "FAIL"," manifests=",results.size())
 quit(0 if failures.is_empty() else 1)
