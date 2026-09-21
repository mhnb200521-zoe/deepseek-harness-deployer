# 风险登记册 (Risk Register)

> 状态: M5 / G3 集成验证中 · 2026-09-21
> 每个风险: 描述 / 可能性 / 影响 / 缓解 / 触发条件。状态: OPEN / MITIGATED / ACCEPTED。

| ID | 描述 | 可能性 | 影响 | 缓解措施 | 触发条件 | 状态 |
|---|---|---|---|---|---|---|
| R01 | 官方 `@deepseek-ai/dsh` 包名/子命令/默认端口与假设不符,导致 S4/S7 全线失败 | **高** | 高 | S0 能力探测(ARCHITECTURE §4)实测子命令/端口/端口可配性并校正 §7 与 config;端口 config 可覆盖。已核验:包存在、latest=0.1.5-rc.2(RC),但 CLI 非 TTY 无 --help 输出,web/--no-open/3080 仍待 S0 实测 | 联网核验发现差异 | OPEN |
| R02 | Node 官方 `index.json` 结构或 LTS 标记变化,版本选择失效 | 低 | 中 | 解析容错 + 兜底“已知良好版本”并在日志标注;解析/获取失败映射 **DSH-E011**(非 E001),转人类可读 | 解析异常 | OPEN |
| R03 | 用户机无 D: 盘 | 中 | 中 | 交互三选一(AppData 回退/自定义路径/退出),严禁建虚拟盘或改分区 | S1 检测无 D: | MITIGATED(设计) |
| R04 | 现有 Node 版本不兼容却被误判复用 | 低 | 高 | 严格实现 §5.1 兼容集合(含 23.x 判否);单测覆盖 Case B/C/D | 版本解析错误 | OPEN |
| R05 | 覆盖/破坏用户已有 Node 或 PATH | 低 | 高 | 私有 Runtime 隔离 + 启动器局部注入 PATH,全程不写系统 PATH/不动用户 Node | — | MITIGATED(设计) |
| R06 | 端口 3080 被非 DSH 占用被盲杀 | 中 | 高 | ServiceProbe 先判定占用者,非 DSH 只报 E007 不杀进程 | S7 端口占用 | MITIGATED(设计) |
| R07 | API Key 泄漏(写日志/明文存储) | 低 | 严重 | 全程不采集 Key;Logger 脱敏;config 不含机密字段 | — | MITIGATED(设计) |
| R08 | PowerShell 执行策略/SmartScreen/Gatekeeper 阻止脚本运行 | 高 | 中 | 入口层用 `-ExecutionPolicy Bypass -File`(仅本进程);文档说明 mac `chmod +x`/右键打开;不建议关安全软件 | 首次运行被拦 | OPEN |
| R09 | 需要管理员/sudo 权限写目标目录 | 中 | 中 | 默认选无需提权路径(D: 用户可写区/AppData/~);确需提权时明确告知并允许拒绝 → E010 | 写入被拒 | OPEN |
| R10 | 网络受限(校园网/公司代理/DNS)导致下载或 registry 失败 | 高 | 中 | NetPreflight 分步探测,输出 E004/E005 人类可读模板;支持重试;详细写日志 | 预检失败 | MITIGATED(设计) |
| R11 | Windows ARM64 上 Node/DSH 支持不完善 | 中 | 中 | 检测到 ARM64 时优先尝试 win-arm64,不可靠则明确 WARN 并给 x64 兼容说明,不静默失败 | S1 识别 ARM64 | OPEN |
| R12 | 重复运行安装器造成重复下载/重复快捷方式/多进程 | 中 | 中 | 全 Stage 幂等:先探目标态再动作;快捷方式覆盖同名;启动前先探端口 | 二次运行 | MITIGATED(设计) |
| R13 | 无法在 M0/M1 真实验证 macOS(开发机为 Windows) | 高 | 中 | macOS 逻辑与 Windows 对等设计,先静态自检 + tests/macos-check.sh;真机验证列为 M5 前置门槛并如实标注未验证项 | — | ACCEPTED |
| R14 | npx 首次拉取缓慢导致健康检查超时误判 | 中 | 中 | S4 与 S7 分离:S4 允许较长准备超时;健康检查超时可配置且给“仍在下载”提示 | 慢网 | OPEN |
| R15 | dsh RC 版本快速演进(rc.2→rc.3→0.2.0)带破坏性变更,破坏“可重复” | 高 | 中 | 锁定 `config.dshVersion`,禁用无版本 latest;升级由 M2 显式路径触发并记 CHANGELOG | latest 变更 | MITIGATED(设计) |
| R16 | 并发安装/安装与启动同时进行踩踏 installDir | 低 | 中 | install 期在 installRoot 写 lock 文件,检测到活动锁则拒绝并提示 | 二实例并发 | OPEN |
| R17 | 日志无限增长,违背“可维护” | 低 | 低 | 日志轮转:仅保留最近 N 份 install-*/runtime-*;M2 已在安装器中启用并验证 | 长期累积 | MITIGATED |

## 待联网核验项(阻塞 M1 进入的前置)

- [ ] `@deepseek-ai/dsh` 是否真实存在、最新版本号
- [ ] `web` 子命令、`--no-open` 参数、默认端口 3080 是否属实
- [ ] Node 官方 dist index 与 SHASUMS 可达性
