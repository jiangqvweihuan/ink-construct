extends Node

## 统一退出入口：安卓返回手势（滑动返回）/ 桌面关窗 / 主菜单与暂停菜单的「退出」
## 都先弹一次确认，避免误触直接秒退。确认框打开时再次返回等于取消。

const QuitDialog := preload("res://scripts/ui/quit_dialog.gd")

var _dialog: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 关掉引擎的「收到返回/关窗就直接退」，改由本节点派发确认框。
	# auto_accept_quit 管关窗，quit_on_go_back 管安卓返回手势——两个都得关，
	# 否则手机滑动返回仍会被引擎直接 quit。
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# 设置等模态面板开着时，返回只关面板，不弹退出确认。
			if get_tree().get_first_node_in_group("modal_ui") == null:
				request_quit()
		NOTIFICATION_WM_CLOSE_REQUEST:
			request_quit()


## 弹退出确认；已经在显示时，再次触发等于取消
func request_quit() -> void:
	if is_instance_valid(_dialog):
		_dialog.call("cancel")
		return
	_dialog = QuitDialog.new()
	_dialog.confirmed.connect(_on_confirmed)
	_dialog.cancelled.connect(_on_cancelled)
	get_tree().root.add_child(_dialog)


## 确认框是否正在显示：其它界面在响应 Esc / 返回时要先让位
func is_dialog_open() -> bool:
	return is_instance_valid(_dialog)


func _on_confirmed() -> void:
	_dialog = null
	get_tree().quit()


func _on_cancelled() -> void:
	_dialog = null
