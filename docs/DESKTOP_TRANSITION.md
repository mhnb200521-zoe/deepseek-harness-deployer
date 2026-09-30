# 官方桌面端部署迁移：架构与验收草案

状态：2026-09-30，桌面迁移 G1 架构复审 PASS；该结论只批准进入实现，不代表桌面端已交付或任何平台端到端验收通过。Windows 初版与 macOS 脚本已实现；冷安装和 Mac 真机仍待验收。

## 事实基线

- 官方仓库 `deepseek-ai/deepseek-harness` 已包含 Electron 桌面端。它自带 dsh、Node.js 和 pnpm，不依赖系统 Node/npm；桌面 Host 默认使用 19387 端口，不能用旧 Web 的 3080/token URL 判定安装成功。
- 官方 CDN 提供 Windows x64、macOS arm64、macOS x64 的安装文件。发布端为 `https://download.deepseek.com`，版本元数据位于 `dsh-desk/feeds/<target>/`，稳定通道是 `latest.yml` / `latest-mac.yml`，候选版通道是 `nightly.yml` / `nightly-mac.yml`。元数据包含版本、版本化下载 URL、大小和 SHA-512。固定的 `desktop/dsh-latest-*` 链接不携带可直接使用的校验值，不应作为自动安装的首选源。
- 2026-09-30 实测三个 `latest*` feed 均返回 404；三个 `nightly*` feed 均指向 `0.2.0-rc.2`。官方 GitHub Releases 标注该版本为 `Pre-release`，官网仍称产品处于 developer preview。用户已同意安装候选版，但部署器必须先显著提示预发布风险并取得本机确认。
- 官方发布目标只有 Windows x64、macOS arm64、macOS x64。Windows ARM64 不得把 x64 包伪装成原生支持；后续若验证仿真兼容，再单独增加支持。
- 本机只读样本证据：win-x64 `0.2.0-rc.2` EXE 长度 `289313640`，SHA-512 与官方 nightly feed 一致，Authenticode 为 `Valid`，签署者 `CN=O=Hangzhou DeepSeek Artificial Intelligence Co., Ltd., C=CN`；本机已安装的同版本应用亦具有相同有效签署者。mac-arm64 `0.2.0-rc.2` ZIP 长度 `374053565`，SHA-512 与官方 feed 一致；其 App `Info.plist` 为 `CFBundleIdentifier=com.deepseek.dsh`、`CFBundleShortVersionString=0.2.0-rc.2`，主程序 Mach-O CodeDirectory 内的 `TeamIdentifier=NAN929V4UM`。后者是对已校验字节的静态解析，**不能替代 Mac 上的 `codesign` / `spctl` 实测**。

来源：

- https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/desktop/README.md
- https://github.com/deepseek-ai/deepseek-harness/releases
- https://www.deepseek.com/harness/

## 变更边界

旧 `windows/install-windows.ps1`、`macos/install-macos.sh` 的 NodeResolver、NodeProvision、Get-DshUrl、Token URL 和 Web 启动/验证行为保持原样，作为原 Web 部署通道。唯一旧 Web 实现改动是快捷方式归属隔离：Web 安装器使用 `DeepSeek Harness Web.lnk`，Web 卸载器只删除目标精确属于本安装 launcher 的快捷方式。新增桌面端安装、修复和卸载入口；在桌面端经过相应平台验收前，不宣称原 Web 测试证明了桌面端可用。桌面端错误使用独立 `DSH-D*` 命名空间，原有 `DSH-E*` 编号及含义不变。

桌面功能先以新入口 `windows/install-desktop-windows.cmd`、`macos/install-desktop-macos.command` 独立交付和验收；当前同名 `install-windows.cmd`、`install-macos.command` 暂时继续指向 Web。只有桌面链、Web 共存和相关文档通过测试后，另一次受控变更才可把原同名入口切至桌面，并同时提供 `install-web-windows.cmd`、`install-web-macos.command`。在那之前 README 第一屏必须明确“Web 入口”和“桌面预览入口”，不得模糊称一键安装已转成桌面。

旧 Web Windows 快捷方式可能占用桌面 `DeepSeek Harness.lnk`。桌面部署器发现它指向由旧 Web 配置记录的本项目 launcher 时，先把它复制为未占用的 `DeepSeek Harness Web.lnk`（不删除原件），告知用户官方安装器可能接管原快捷方式；复制失败即停止安装。遇到同名但目标不属于本项目的快捷方式时停止并要求用户决定，绝不覆盖未知用户快捷方式。

共存需要一次可证明的**双向**最小修复：旧 Web 安装器此后只创建/更新 `DeepSeek Harness Web.lnk`；旧 Web 卸载器只在快捷方式目标精确指向本次卸载根目录 `launcher/start-dsh.cmd` 时删除 `DeepSeek Harness Web.lnk`，并对历史同名 `DeepSeek Harness.lnk` 做相同归属检查，不删除任何指向原生 App 或其他路径的快捷方式。此变更仅限 S6 快捷方式与卸载器快捷方式分支，不触及 Node、npm、Get-DshUrl、端口或其余 Web 行为。必须覆盖“Web→Desktop→Web 重跑”和“Desktop→Web→Web 卸载”两种顺序的回归，之后才可启用桌面公共入口。

## 当前实现切片（2026-09-30）

- Windows：`install-desktop-windows.cmd` 是薄入口；`install-desktop-windows.ps1` 支持 x64、官方 feed 选版、预发布确认、大小/SHA-512/Authenticode 校验、现有安装探测、原生安装器调用、用户 UI 确认和桌面快捷方式。`repair-desktop-windows.ps1` 只对已验证同版本重跑官方安装器；`uninstall-desktop-windows.ps1` 只打开 Windows 已安装应用设置，不自行删程序/数据。
- macOS：新增 `.command` 入口、官方 feed/架构检测、SHA-512 与 App Bundle/Team ID/codesign/spctl 验证、`~/Applications` 同卷暂存/备份/journal 恢复、用户 UI 确认、桌面启动器、修复及带二次确认的卸载。
- 旧 Web 的 Node/npm/Token URL 主路径未变。快捷方式隔离为必要的最小实现变更；Windows Web regression 仍 PASS。
- 当前宿主证据：Windows PowerShell 5.1 自测 PASS；本机官方签名桌面 App 的只读探测 PASS（未下载、安装、升级或启动）；macOS Git Bash 静态检查与 feed/版本自测 PASS。以上不是冷安装或 Mac 真机证据。
- 缺口：Windows 新用户冷安装/原生安装器完整交互/桌面 UI 未测试；Apple Silicon 和 Intel Mac 上 `codesign`、`spctl`、事务恢复、安装、启动、卸载及 UI 都 NOT TESTED。桌面公共入口仍保持独立，未切换原 Web 入口。

## 桌面端状态机

`平台/架构检测 → 现有桌面安装探测 → 选稳定/候选版本 → 下载官方安装物 → SHA-512 与签名验证 → 交给原生安装/复制 → 启动原生 App → 检查应用进程及用户可见窗口 → 记录结果`

各阶段输出 PASS/WARN/FAIL、阶段名、错误原因和本产品日志路径；失败不得自动切回 Web 并假报成功。

1. 版本选择只管**本次首次安装**，不承诺把官方 App 永久留在稳定通道；官方 App 自己使用 Nightly 更新通道，后续可能提示候选版更新。先读取稳定 feed；只有收到精确 404 才尝试候选 feed，网络超时、TLS 失败、5xx、200 但格式非法均立即失败，不能作为回退理由。候选版须显示版本与“预发布”并在本机得到明确确认；取消为安全退出，不能算安装 PASS。锁定同一次安装所用的 feed `version + URL + size + SHA-512`；安装途中不可改选浮动的固定 `latest` 下载链接。
2. URL 验证：只允许 HTTPS 且主机精确为 `download.deepseek.com`，路径限定对应 target 的 `dsh-desk/bin/` 下的版本化文件。拒绝跨架构、任意重定向到非官方主机、空哈希、格式错误的大小/版本、URL 与 feed 版本不一致。
3. 下载：临时文件位于本部署器用户级 cache，不入 Git；下载失败可安全重试，完成后核对字节数及 SHA-512。校验失败时停止，绝不执行。日志不写密钥、账户、会话、聊天或下载 URL 中可能出现的 query。
4. Windows：只运行 SHA-512 合格且 Authenticode 状态 `Valid`、证书 Subject 的 CN/O/C 精确匹配上方 DeepSeek 官方身份的 x64 NSIS 安装器；不把易轮换的叶证书 thumbprint 当永久身份。安装目标由官方原生界面管理，不强制写入旧 `D:\DeepSeekHarness`。安装前以当前用户注册表、版本、安装路径和签名检查现有应用；**仅完全同版本复用**。旧版升级交给官方 NSIS，并向用户说明；目标版本低于已安装版、版本不可比较、安装位置不可信时停止，不静默降级/覆盖。原生安装器退出后还必须再次核对版本、签名与路径；用户取消、非零退出或登记未更新均不得判 PASS。官方 NSIS 自身负责应用目录替换与回滚，本脚本不清理旧应用数据。
5. macOS：采用官方 feed 中有 SHA-512 的 ZIP，**不是**哈希未知的固定 DMG。官方 ZIP 内是已 stapled 的 App；固定 DMG 的公证票据附在容器上，两者不可按同一流程验收。下载校验后用 `ditto -xk` 解包到私有 staging；先检查包内目标 App 为真实目录（非符号链接），Bundle ID 为 `com.deepseek.dsh`，版本与 feed 完全一致，再执行 `codesign --verify --deep --strict`，核对 `TeamIdentifier=NAN929V4UM`，以及 `spctl -a -t exec` 验证 Gatekeeper 许可。任何一项失败即停，不清除 quarantine、不关闭 Gatekeeper。
6. macOS 默认安装到当前用户 `~/Applications/DeepSeek Harness.app`，不要求 Homebrew/Node。安装前拒绝 symlink/reparse 目标、错误 Bundle ID/Team ID、版本降级、未知 App 归属；现有同版本且签名与许可均通过则复用。所谓“本部署器拥有”必须同时满足：部署器私有 `receipts/desktop-macos.json` 记录了规范化的目标绝对路径、Bundle ID `com.deepseek.dsh` 和 Team ID `NAN929V4UM`，且目标当前的 Bundle ID、Team ID、`codesign` 与 `spctl` 均匹配；凭空同名的 App 不能靠名称认领。官方应用在该路径自行更新版本后仍可复用，但自动替换前须检查当前版本不高于目标并再次取得本机确认。无 receipt 的同名官方 App 可以核验后启动，但不自动覆盖；用户要升级时应使用应用自身更新流程。

   允许升级时，将新 App 先复制到同一目录的唯一 staging 路径并复核，先写入私有 transaction journal（目标、staging、备份的规范化路径和阶段），再把旧 App 移到同卷唯一备份路径，随后将新 App 原子改名为目标。若改名/验收失败，恢复旧 App 并保留日志。成功后保留旧版本备份供用户人工回滚，绝不自动删除用户数据。已有未解决的备份或空间不足则拒绝操作并给出明确提示。

   **中断恢复**：每次开始先读 journal，仅接受三个路径都位于当前用户 `~/Applications` 下、与固定命名模式一致且不是 symlink。若目标缺失而备份有效，优先恢复备份；若目标已是签名有效的新版本，保留备份并把 transaction 标为完成；若没有旧版本且 staging 有效，仅在 journal 明确记录原目标不存在时可完成首次安装。目标/备份/staging 任一身份不明、同时出现多个候选或恢复失败都 fail closed，列出路径供人工处理，不继续下载或启动。journal 在安装中以临时文件同目录原子替换写入；receipt 只在目标安装验证后写入，不以 UI 确认代替安装所有权凭据。
7. 验收分三层：`Installed` = 平台登记/Bundle 元数据、版本、路径与签名匹配；`Launched` = 从该**绝对安装路径**启动并观察该路径的进程；`UI ready` = 原生窗口存在且由用户在本机确认欢迎页或工作区可操作。Windows 仅凭标题/进程，macOS 仅凭 `open -a` 的返回值，均不满足 `UI ready`；不能自动取得可靠 UI 证据时显示 WARN 并请求用户确认，未确认不能标记全链 PASS。macOS 使用 `open <绝对 App 路径>`，不通过名称搜索其他同名 App。
8. 桌面产品的后续自动升级、插件和用户数据由官方应用管理。本部署器不自动迁移或删除旧 Web 的 `~/.dsh`、workspace、config、日志；桌面卸载以官方原生卸载方式为准，旧 Web 卸载器不得删除桌面数据。用户须在 App 内自行选择具体项目目录、登录或设置模型。

失败处理：下载/解析/哈希/签名失败只留下本产品日志和可安全删除的缓存，不执行安装物；Windows 原生安装取消或失败时不自行删改官方应用，仅记录安装前后登记差异并给 Repair 说明；macOS staged promotion 失败回滚到原 App，回滚失败需显式报告备份路径并停机，禁止继续启动。任何失败不自动回退到 Web，不把已有 Web 会话当作桌面安装成功。

## 验收门槛与风险

- Windows：新用户、已有 Web、已有桌面端、候选版提示取消、网络失败、哈希不符、签名无效、重复安装、安装取消、启动失败、非 D 盘、Repair/Uninstall 边界。须有真实 x64 桌面安装与窗口证据。
- macOS：Apple Silicon 与 Intel 分别验证下载安装、哈希、Gatekeeper/签名/公证、权限、替换保护、App 启动、重复运行、卸载/保留用户数据。Windows 上的 Bash 静态检查不能替代两类真机证据。
- 若官方 feed 格式、签名身份、发行渠道变动，安装器应 fail closed 并提示用户查看官方发布页，不能猜测 URL 或绕过系统安全检查。
- 桌面测试须与既有 `tests/windows-check.ps1`、`tests/macos-check.sh` 分离；后两者只证明 Web 路径。新增桌面 feed 解析/跨域 URL/大小/哈希/签名负例、注册表或 Bundle 已装探测、升级/降级与取消、窗口确认、旧 Web 快捷方式共存的单元/集成检查。Windows 本机先验证“已安装同版本”路径，再用隔离 VM 验证真正新用户安装。Mac 两架构真机验收前，不得宣称跨平台桌面一键部署 PASS。
- 当前 `G3/M5` 仍描述旧 Web 产品的验证进度。桌面方向属于新增变更，须完成 G1 架构评审、按平台新增实现与验收记录；不得把旧 Web 的 PASS 直接复制为 Desktop PASS。公开仓库暂不推送未验证变更。
