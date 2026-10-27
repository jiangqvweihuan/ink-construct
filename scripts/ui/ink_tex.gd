## 贴图统一入口：走 Godot 导入管线（导出后依然读得到，不再用 Image.load_from_file）
## 不用 class_name：全局类缓存要靠编辑器扫描刷新，命令行跑场景认不出。
## 用法：const InkTex = preload("res://scripts/ui/ink_tex.gd")


static func load(path: String) -> Texture2D:
	var tex := ResourceLoader.load(path, "Texture2D") as Texture2D
	if tex == null:
		push_error("贴图缺失: " + path)
	return tex
