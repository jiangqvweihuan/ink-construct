# 墨构 InkConstruct

一款水墨武侠风的横版动作 Roguelite。执卷留白穿行残卷山谷，与七名行卷人物轮换显形，在三关残页与封线关核之间拆封轴、夺回下一笔。

**当前版本：1.0.0 正式版**

## 主要内容

- 七名可解锁化身：绯刃、镇岳、梅剑、剑仙、银夜、绛弦、烬生
- 五名正史首领：墨霆、焚鼎、武车、碎岳、鸣钟；另有番外首领「剑冢」可随机遭遇
- 冒险、无尽与五档难度；高难度「无归」为双首领连战
- 局内三选一强化、局外墨锭商栈、永久修炼、化身皮肤
- 敌人 / 化身 / 状态 / 故事四类图鉴，功名录与隐藏卷外手记
- 斗蛐蛐自动观战小模式
- 单人、本机双人与局域网联机入口（以「开始游戏」内可选模式为准）

## 操作

| 按键 | 功能 |
| --- | --- |
| A / D | 左右移动 |
| Space | 跳跃 |
| Shift | 闪避 |
| J | 普攻 |
| K / L | 技能一 / 技能二 |
| U | 奥义 |
| I / O / P | 角色专属技能（因化身而异） |

按键可在游戏设置中重新绑定。

## 运行

1. 使用 **Godot 4.6.2 mono** 打开 `project.godot`。
2. 首次导入完成后按 F5 运行；主场景为 `intro/Intro.tscn`。
3. 测试场景位于 `scenes/tests/`，不会被打进正式包；剑冢专属实测场为 `scenes/tests/c019_arena.tscn`。

## 构建

已配置两份正式导出：

- **Windows x64**：`Windows x64` 预设，输出 `build/windows/InkConstruct-1.0.0.exe`（需与同目录的 `libspine_godot.windows.template_release.x86_64.dll` 一起分发）
- **Android arm64**：`Android` 预设，输出 `build/android/InkConstruct-1.0.0.apk`

命令行示例：

```powershell
godot --headless --path . --export-release "Windows x64" "build/windows/InkConstruct-1.0.0.exe"
godot --headless --path . --export-release "Android" "build/android/unsigned/InkConstruct-1.0.0-unsigned.apk"
```

Android 正式包需使用本地 `build/android/keystore/` 中的发布密钥签名；签名文件与密码不进入仓库。

## 目录

- `scripts/`：战斗、敌人、UI、系统与测试脚本
- `scenes/`：主菜单、战斗房间、UI 与测试场景
- `art/`、`audio/`：水墨美术、Spine 动画与音频素材
- `docs/`、`PROGRESS.md`：开发记录、审计与设计资料
- `build/`：导出产物（已被版本控制忽略）

## 测试与致谢

感谢以下玩家参与测试游戏并协助排查 Bug：

**life、xxxg、江莫枯、XSXZ、yuanyang**

完整制作、音频与素材署名见游戏内「致谢」页面。

## 素材与授权

本作为个人开发作品，禁止未经许可的二次传播与商业化使用。部分美术与音频素材来源于网络，仅供学习交流；如权利人认为相关内容侵权，请通过游戏内致谢页所列邮箱联系处理。
