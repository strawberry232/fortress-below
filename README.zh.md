# 《堡垒之下》

[下载 Windows 试玩版](https://github.com/strawberry232/fortress-below/releases/latest)

下载附件为此前已验证的 v1.8 Windows 试玩成品；仓库保存当前开发源码，包含后续调整，本次没有从当前源码重新构建该附件。详见 [构建来源说明](docs/release/build-provenance.md)。

个人制作的 2D 像素风地牢探索与塔防 Demo，使用 Godot 4.7.2、GDScript 和 GL Compatibility 渲染。

## 游戏玩法

探索地牢、获取金币与钥匙、返回地表建设防御，再沿两条固定路线守住堡垒。游戏包含连续三轮冒险，成功完成一轮后保留已有建设成果。

- 六个塔位支持点击建造与升级，并可通过集火和“加大火力”技能应对进攻。
- 地牢包含普通与封印宝箱、木门、墙梯和尖刺陷阱；封印宝箱提供额外收益，也会增加守城压力。
- 敌人包含兽人、骷髅、重甲骷髅、分裂史莱姆、远程魔颅和拥有两条生命的精英吸血鬼。
- 失败可重试当前轮，保留此前成功轮次的建设成果。

## 试玩画面

以下为稳定试玩版视觉的既有流程验证截图。

![地牢探索](docs/screenshots/dungeon.png)

![堡垒防守](docs/screenshots/defense.png)

## 我的工作与 AI 使用

我负责玩法规划、需求拆解、素材筛选与整合、试玩问题反馈，以及迭代验收和交付。使用 Codex 进行 AI 辅助代码实现、调试和重构，通过 Godot MCP 连接编辑器开展开发。

角色、场景、UI、特效和音频来自网络第三方免费资源。详细来源与区别见 [素材说明](docs/assets-and-attribution.md)。

## 源码范围与运行

本仓库包含游戏代码、场景、地图与数值数据、测试、中文文案，以及保留许可的开发依赖。原始美术、字体、音频和编译后的引擎模板未随源码再分发。

**缺少素材时，这份源码不能直接运行完整游戏；依赖素材的测试也需要先补齐对应文件。** 素材路径与校验记录见 `docs/asset-files.csv`，运行时必要文件另见 `config/runtime_assets.json`。取得素材并按路径配置后，可在 Godot 中打开 `project.godot`，按 F5 运行。

| 操作 | 按键 |
| --- | --- |
| 移动 | WASD |
| 剑击 | J / 鼠标左键 |
| 射箭 | K / 鼠标右键 |
| 交互 | E |
| 暂停 | Esc |
| 加大火力 | 空格 / 技能按钮 |

完整开发工程的 v1.8 优化记录为：323 项单元测试通过，完成三轮自动流程验证；Windows 试玩 ZIP 从 43.7 MiB 降至 13.1 MiB，减少约 70%。这些是完整工程的历史结果，本次不将它们作为缺少素材的源码快照已通过运行验证的声明。

Windows 试玩成品单独放在 GitHub Releases，试玩无需 Godot 编辑器。

开发依赖沿用各自许可证；尚未为项目自身代码选定统一开源许可证。第三方素材版权归原作者，不能将依赖许可证视为对全部素材的授权。

## 代码与验证

游戏逻辑位于 `game/scripts/`，关卡与数值配置位于 `game/data/`，测试位于 `test/`，中文文案位于 `docs/localization/`。`tools/` 保留资源优化、定制模板编译与发布脚本；`addons/` 为保留独立许可的 Godot MCP Native 和 GUT。

补齐对应素材后，在 PowerShell 中指定 `GODOT_EXE`，可执行：

```powershell
& $env:GODOT_EXE --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://test/unit/ -ginclude_subdirs -gexit
```

精简版导出还需要自行编译匹配的引擎模板，仓库不提交模板 EXE；历史过程见 [优化记录](docs/v18-optimization.md)。

导出时可向 `tools/export_release.ps1` 传入 `-GodotPath`，或设置 `GODOT_EXE`，覆盖原开发机的引擎路径。
