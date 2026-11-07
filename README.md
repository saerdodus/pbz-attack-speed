# PBZ Attack Speed — Configurable (UE4SS)

《影之刃零》独立「攻击速度」模组源码 / Standalone attack-speed mod source for **Phantom Blade Zero**.

- **Nexus Mods**: <https://www.nexusmods.com/phantombladezero/mods/673>
- **游戏版本**: UE 5.7.4 / CL-302256（v1.0 更新后验证）
- **依赖**: [PBZ UE4SS](https://www.nexusmods.com/phantombladezero/mods/13)
- **许可证**: MIT

![cover](https://staticdelivery.nexusmods.com/mods/10614/images/673/673-1794017823-1720744004.jpg)

---

## 功能 / Features

- 加速 **6 个近战攻击**的整条出招时间轴：轻击、重击、空中轻击、空中重击、Simple 通用攻击、Simple 空中攻击；
- 出招动作和判定窗口一起加速（不是只改动画速度）；
- `config.txt` 实时调节：默认 `+30%`，范围 `0–500`，建议 `0–100`；
- 可单独关闭空中攻击的加速；
- 每次攻击单独记录原速率，攻击结束、角色死亡、切换角色后自动恢复；
- **不写存档**、不加物品、不改伤害数值、不触碰游戏 EXE。

## 安装 / Installation

### 从 Nexus 下载（推荐）

<https://www.nexusmods.com/phantombladezero/mods/673> → Files → 下载 `pbz-attack-speed-v1.0.zip`，
解压到：

```
<游戏目录>\platform\steam\ue4ss\Mods\pbz-attack-speed\
```

### 从源码安装 / From source

1. 把本仓库的 `main.lua` 放到 `<游戏目录>\platform\steam\ue4ss\Mods\pbz-attack-speed\Scripts\main.lua`
   （`Scripts` 目录不存在就自己建）；
2. 把 `config.txt` 放到 `<游戏目录>\platform\steam\ue4ss\Mods\pbz-attack-speed\config.txt`；
3. 新建一个空文件 `enabled.txt` 放在同目录下（用于让 UE4SS 自动启用）；
4. 启动游戏。日志：`Mods\pbz-attack-speed\attack_speed_log.txt`。

## 仓库结构 / Repo layout

```
main.lua      # 模组主体（Lua / UE4SS）
config.txt    # 默认配置
```

## 配置 / Configuration

编辑 `config.txt`，保存后游戏内按 **Ctrl+F9** 重新读取（无需重启游戏）：

| 配置项 | 默认 | 说明 |
| --- | --- | --- |
| `attack_speed_percent` | `30` | 攻速提升百分比。`30` = 播放速率 ×1.30；`0` = 不加速；`100` = ×2.00；建议 0–100，上限 500 |
| `apply_to_air_attacks` | `true` | 是否对空中轻击 / 空中重击生效 |
| `enabled` | `true` | 总开关（游戏内 Ctrl+F8 也可切换） |
| `log` | `true` | 是否写 `attack_speed_log.txt` |
| `debug` | `false` | 每次攻击写详细日志（排查用） |
| `property_offset` | `0xA8` | 高级项：时间轴速率属性偏移，游戏大版本更新后才可能需要改 |

## 热键 / Hotkeys

| 热键 | 功能 |
| --- | --- |
| **Ctrl+F9** | 重新读取 `config.txt`（当前攻击先恢复，下一刀按新数值生效） |
| **Ctrl+F8** | 临时开启 / 关闭加速（不改配置文件） |

## 实现原理 / How it works

1. 挂钩 6 个近战攻击技能的 `K2_ActivateAbility`；
2. 攻击激活后通过 `ability:GetPlayTimelineTask()` 拿到本次攻击的 `LGATask_PlayTimeline`（驱动出招动画和判定窗口的时间轴）；
3. 该对象上有一个未导出到 SDK 的 float 属性 `PBZTimelinePlayRate`（偏移 `0xA8`），用 `RegisterCustomProperty` 动态注册后读取；
4. 调用 `task:SetPlayRate(原速率 × (1 + 百分比/100))`，并回读校验；
5. 每个攻击任务单独记录原速率，任务结束 / 技能失效 / 玩家死亡 / 切角色时自动恢复；偏移不对时只会不生效并写日志，不会乱写内存。

## 兼容与注意 / Compatibility & Notes

- 只影响**近战出招速度**，不影响武器技能 / 法术、移动速度、伤害数值；
- 不要和另一个同样修改 `LGATask_PlayTimeline` 播放速率的 mod 同时使用，后写入者会覆盖前一个；
- 不写存档、不加物品，卸载直接删除 `pbz-attack-speed` 文件夹即可；
- 单人离线使用，联机请勿使用。

## 更新日志 / Changelog

- **v1.0** — 首个发布版：支持配置文件实时调节、空中攻击开关、游戏内热键与自动恢复。

## 许可证 / License

[MIT](LICENSE) © 2026 saerdodus

## 致谢 / Credits

- 本模组的代码、文档与封面在 **DeepSeek Harness (AI)** 辅助下完成；发布前已人工验证与测试。
- 《影之刃零》游戏及其资产归 **S-GAME** 所有；本仓库不包含任何游戏资源。
