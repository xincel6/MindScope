---
name: harmony-device-loop
description: Build, install, launch, screenshot and drive the MindScope HarmonyOS app (harmony/ · ArkTS · DevEco 6.1) on the running emulator through hvigor + hdc without opening DevEco Studio. Use for any change under harmony/ that must be seen on screen, or when a build/install/screenshot command fails.
whenToUse: The task touches E:\MindScope\harmony (ets/, resources/, module.json5, build-profile.json5) and needs verification on the emulator, or a previous hvigor/hdc command failed with ENOENT/EPERM/signature problems.
user-invocable: true
---

# MindScope · HarmonyOS 设备闭环（构建 → 安装 → 拉起 → 截图 → 驱动）

本机装着 DevEco Studio 6.1 与一个**已在运行**的 HarmonyOS 模拟器。整个过程不需要打开 IDE：
命令行 hvigor 出 HAP，`hdc` 装进模拟器、拉起、截图、点按。这套流程已在本仓库验证过（tab 栏图标改版即用它验收）。

## 0 · 环境事实（换机器只需改这几处）

| 项 | 值 |
|---|---|
| DevEco 安装目录 | `E:\HarmonyOS\DevEco Studio`（`%DEVECO_HOME%`） |
| SDK | `<DevEco>\sdk`（`DEVECO_SDK_HOME`） |
| hvigor 入口 | `<DevEco>\tools\hvigor\hvigor\bin\hvigor.js`（**本工程没有 hvigorw 包装器**） |
| 自带 Node | `<DevEco>\tools\node\node.exe`（系统 `node` 也能用） |
| 自带 JDK | `<DevEco>\jbr\bin`（打包时要 `java` 在 PATH 上） |
| hvigor 用户目录 | `E:\hvigor-home-mindscope`（`HVIGOR_USER_HOME`，**不是** `HVIGOR_HOME`） |
| hdc | `<DevEco>\sdk\default\openharmony\toolchains\hdc.exe` |
| 设备 | `127.0.0.1:5555`（模拟器，`hdc list targets` 可查；多设备时所有命令加 `-t 127.0.0.1:5555`） |
| 屏幕 | 物理 1316×2832 px = **658×1416 vp**，密度 2.0（vp × 2 = px） |
| 包名 / Ability | `com.example.heartweather` / `EntryAbility` |
| 工程 | 构建目录 = `E:\MindScope\harmony`（不是仓库根） |

## 1 · 黄金路径

```powershell
# 1) 构建（bash 跑仓库脚本最省事；脚本里有完整注释）
bash harmony/scripts/build.sh                      # 日志 → harmony/_build.log
#    产物 harmony/entry/build/default/outputs/default/entry-default-unsigned.hap

# 2) 安装（未签名 HAP 在模拟器上可直接装；真机会被签名策略拒）
$hdc = "E:\HarmonyOS\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
& $hdc -t 127.0.0.1:5555 install -r "E:\MindScope\harmony\entry\build\default\outputs\default\entry-default-unsigned.hap"

# 3) 重新拉起（覆盖安装后旧进程可能还在，先停再起）
& $hdc -t 127.0.0.1:5555 shell "aa force-stop com.example.heartweather"
& $hdc -t 127.0.0.1:5555 shell "aa start -a EntryAbility -b com.example.heartweather"

# 4) 截图（等首帧画完，一般 2~3 s 足够）
bash -c 'true'   # 或者直接用脚本：
pwsh -File harmony/scripts/capture.ps1 -Name tab_icons_1 -SleepMs 2500
```

`pwsh` 里用纯 hdc 等价写法（`capture.ps1` 内部就是这样）：

```powershell
& $hdc -t 127.0.0.1:5555 shell "snapshot_display -f /data/local/tmp/shot.jpeg"
Push-Location "E:\MindScope\_materials\_verify"
& $hdc -t 127.0.0.1:5555 file recv /data/local/tmp/shot.jpeg "shot.jpeg"
Pop-Location
```

截图存 `E:\MindScope\_materials\_verify\`（既有历史验收图也在这里），再用 `read_image` 看。

## 2 · 仓库里的现成脚本（都要用 `pwsh -File` 调）

| 脚本 | 作用 | 典型用法 |
|---|---|---|
| `harmony/scripts/build.sh` | hvigor `assembleHap`，只回显 ERROR/结果行，全量日志进 `_build.log` | `bash harmony/scripts/build.sh` · `clean` 只清产物 |
| `harmony/scripts/capture.ps1` | 截图 + 拉回本地 | `-Name foo -SleepMs 2500 [-OutDir ...]` |
| `harmony/scripts/tap.ps1` | 点击 / 输入 / 滑动 | `-X 658 -Y 1208`、`-Swipe "658 2200 658 900 400"`、`-Fling "0 1 900"` |
| `harmony/scripts/uidump.ps1` | 导 UI 树，按文字打印真实 bounds | `-Filter "统计"`、`-All` |

**驱动 UI 的正确顺序：`uidump.ps1` 读真实坐标 → `tap.ps1` 点击 → `capture.ps1` 验收。**
别照着截图猜坐标：模拟器画面有缩放/letterbox，截图上的 px 与 `uiInput click` 期望值并不总是 1:1。

纯 hdc 等价命令：`shell "uitest uiInput click 658 1208"`、`"uitest uiInput swipe ..."`、
`"uitest uiInput inputText <x> <y> <text>"`、`"uitest dumpLayout -p /data/local/tmp/layout.json"`。
另有一套更原始的手势通道：`shell "uinput -T -c <x> <y>"`（本机实测可用，坐标是 px）。

## 3 · 踩过的坑（都是实测，不要再试一遍）

| 症状 | 原因 / 修法 |
|---|---|
| `ERROR 00308018 ... spawn java ENOENT` | `PackageHap` 要 JDK：把 `<DevEco>\jbr\bin` 加到 PATH 再构建（`CompileArkTS` 通过、卡在打包就是它）。 |
| `ERROR 00308003 ENOENT ... workspace/node_modules/@ohos/hvigor/bin/hvigor.js` | `HVIGOR_USER_HOME` 下的 workspace 坏了（IDE 占着软链接）。删掉该 workspace 目录让它重建。 |
| `es2abc ... spawn EPERM` | 受限沙箱拦了子进程管道，不是代码错。改用 `sandbox_permissions: danger-full-access` 或在工作区外跑。 |
| `hdc file recv` 落到了别的目录 | `recv` 的相对路径**不按调用者 cwd 解析**：先 `Set-Location` 到目标目录再 recv（脚本已处理）。 |
| 安装成功但界面没变 | 覆盖安装后旧进程还在：`aa force-stop` 再 `aa start`；首帧慢时可多等 1~2 s 再截。 |
| `aa start` 报错找不到 ability | 参数是 `-a EntryAbility -b com.example.heartweather`（`-a` 是 ability 名、不是类路径）。 |
| 截图为空/全黑 | 刚开机或锁屏；`hdc shell power-shell wakeup` 后重试。 |
| 写 `harmony/` 子目录被拒 | 此环境的 workspace-write 沙箱只放行工作区根目录；正式构建/截图走 danger-full-access。 |

## 4 · 改 UI 时的项目约定（避免踩到既有设计约束）

- **唯一视觉令牌源**：`harmony/entry/src/main/ets/common/UiTheme.ets`。颜色/间距/字号一律加令牌，别在页面里写魔法数；改完回头查谁在用它（`grep` 令牌名）。
- **底部 tab 栏**在 `harmony/entry/src/main/ets/pages/MainPage.ets` 的 `@Builder tabBar()`，元数据在 `pages/PageRoutes.ets` 的 `MAIN_TABS`（`MainTabMeta`：`tab/label/glyph/icon/iconActive`）。
  结构是 Material 3 写法：**图标胶囊（`tabIconPillWidth`×`tabIconPillHeight`，选中 `cardPressTint`）+ 下方 14fp 标签**（选中 `primary`+Medium）。
  栏高 `UiTheme.tabBarHeight = 64`（56 已不够：28 + 4 + 20 ≈ 52，只剩 2vp 余量会顶边）。
- **tab 图标是双份 SVG**：`resources/base/media/tab_<tab>.svg`（未选中 `#4E5969`）与 `tab_<tab>_on.svg`（选中 `#0D9488`），24 网格、描边 2。
  **不要改用 `Image.fillColor()` 换色**：官方定义是"叠加填充色"，只改 fill、不改 stroke，审计清单那种纯描边图标会出现"选中了还是灰的"。颜色烤进文件、按状态选资源才是稳的。
- ArkTS 里 `$r('app.media.xxx')` 引用**必须**有对应 `resources/base/media/xxx.svg|png`，拼错是编译期报错而不是运行时空白。
- 状态管理是 `@ComponentV2` / `@Local` / `@Param`（不是 V1 的 `@State`）；`ForEach` 第三个参数是 key 生成器，必须给。
- 改完一定要 `grep` 一遍旧引用（例如删常量、改构造签名后），再构建——ArkTS 的类型检查会兜住大部分，但 `@Builder` 里的属性链不会。

## 5 · 验收标准（本仓库习惯）

1. `bash harmony/scripts/build.sh` 输出 `BUILD SUCCESSFUL`；
2. 安装 + 拉起后截图，肉眼确认目标区域（颜色/间距/裁切/暗色对比）；
3. 至少截**两态**（例如默认态与操作后态、选中与未选中页签），并把图放 `_materials/_verify/`；
4. 汇报时给文件路径 + 截图路径，说明改了哪些令牌/常量、为什么这样改。
