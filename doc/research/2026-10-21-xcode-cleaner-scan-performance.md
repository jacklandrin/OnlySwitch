# Xcode Cleaner 扫描提速研究

日期：2026-10-21。此报告是研究结果；本次没有把实验扫描器替换进生产代码，也没有扫描或清理真实开发数据。

建议先优化逐文件元数据读取，再拆开模拟器删除前的身份核验与体积统计。随后评估有限并发和渐进显示。暂不引入持久化文件索引。

## 当前耗时来源

代码检查确认以下调用顺序；这是结构分析，不是对用户磁盘各阶段耗时的测量：

- `CleanerCoordinator.scan()` 先等待文件缓存扫描，再等待模拟器扫描。
- 文件缓存各根目录串行扫描。每个普通文件先读取预取的 URL 资源值，再调用一次 `attributesOfItem` 获取磁盘及 inode 标识以去重。
- 模拟器扫描先执行 `simctl list --json`，逐台遍历设备数据目录，最后执行 `simctl runtime list --json`。
- 删除模拟器前调用完整 inventory 再核验，会重新统计所有设备大小；清理后又完整刷新一次。
- 界面直到完整快照返回才显示结果，小目录和运行时元数据也要等待大目录。

## 可复现实验

环境：本机 arm64 macOS，Xcode 27.1，Swift 6 语言模式，`swiftc -O`。数据全部位于独立 `/private/tmp` 目录。受当前环境限制，未获得具体 CPU 型号、内存容量及磁盘格式；不据此推断其他机器的耗时。

夹具包含 40 个类似项目的目录树，每个 250 个 128 字节文件，共 10,000 个普通文件，另有一个硬链接和一个目录符号链接。两种算法交替运行六轮，丢弃首轮，报告其余五轮的中位数。未清空系统磁盘缓存，因此属于热缓存实验。两种算法每轮得到完全相同的分配大小 `39,936,000` 字节，符号链接未被递归计入，硬链接只计一次。

| 算法 | 中位耗时 | 实验结论 |
| --- | ---: | --- |
| 当前生产 `measure` | 1,272.82 ms | 基线 |
| 同批预取 `fileIdentifierKey`、`volumeIdentifierKey` 及大小，以卷标识 + UInt64 inode 去重 | 48.16 ms | 本夹具约快 26.4 倍，耗时降低 96.2% |

这只证明该夹具的目录计量环节有较大的提速空间，**不代表整应用扫描能提速 26 倍**。真实目录大小、文件系统、缓存冷热、模拟器服务启动以及后台负载均会影响结果。未测量真实设备数据树、冷启动、权限失败、文件持续变动、挂载切换和大规模内存峰值。正式落地前还需补齐这些验证。

实验脚本：[xcode-cleaner-scan-benchmark.swift](xcode-cleaner-scan-benchmark.swift)。逐轮数据：[原始结果](2026-10-21-xcode-cleaner-scan-benchmark.txt)。从仓库根目录运行：

```sh
rtk proxy swiftc -O -swift-version 6 -parse-as-library \
  -module-cache-path /private/tmp/onlyswitch-cleaner-benchmark-module-cache \
  Modules/Sources/XcodeCleaner/XcodeCleanerModels.swift \
  Modules/Sources/XcodeCleaner/XcodeCleanerFileSystem.swift \
  doc/research/xcode-cleaner-scan-benchmark.swift \
  -o /private/tmp/onlyswitch-cleaner-scan-benchmark
rtk proxy /private/tmp/onlyswitch-cleaner-scan-benchmark
```

脚本只创建和移除自己的 UUID 临时夹具，不访问用户缓存。若卷不提供所需元数据，实验明确失败，不把缺失属性当作零大小。

另一组探索说明不能只看 API 名称：把不透明 `fileResourceIdentifier` 和卷标识作为 `NSObject` 组合键，使用合法对象相等与哈希语义时，本机实验中位耗时约 2,233 ms，较同轮基线 1,256 ms 更慢。尝试桥接为 Data 并回退属性查询则约 1,235 ms，没有明显改善。对象 `description` 的字符串曾产生较快结果，但该表示不是身份契约，不能用于生产正确性。最终候选使用系统明确提供的数值 inode 和卷身份，而非描述字符串。

## 方案与优先级

| 优先级 | 方案 | 预期收益及边界 |
| --- | --- | --- |
| 1 | 一次预取大小、文件 inode 和卷标识，移除每个文件的第二次属性读取 | 直接缩短目录遍历。上表有实测证据；生产实现需处理不支持属性的卷，并保证整次扫描的去重策略一致。保留分配大小口径、错误传播、取消和符号链接策略。 |
| 2 | 把模拟器 inventory 分为轻量身份/启动状态核验与可选体积统计 | 删除前只查询最新 UDID、运行状态、运行时关系和可删除标志，避免重扫所有设备数据。不得复用旧状态作为删除授权。此方案尚未量化。 |
| 3 | 文件缓存和模拟器元数据查询并发；设备/根目录统计限制在 2–4 个任务 | 缩短独立阶段的等待。需要实测并发度，避免磁盘争用、文件句柄膨胀及 actor 内串行工作导致“表面并发”。 |
| 4 | 先显示分类、设备和运行时，再逐项补齐体积；优先统计可见项目 | 改善首次可见结果的等待，未必缩短完整扫描。进行中的大小必须显示“计算中/未知”，不能显示为零或生成虚假的精确总量。 |
| 5 | 清理后优先刷新受影响项，并把其他体积标为先前结果 | 减少重复遍历。需要明确快照版本、授权失效规则与剩余项目的过期状态；不能简单拼接不同时间的已授权快照。 |
| 6 | 短期体积缓存，必要时配合 FSEvents 失效 | 重复访问可能更快，但正确性和维护成本高。深层文件修改不能靠根目录 mtime 判断；丢失事件、根目录变化或事件合并要求重新扫描。不建议第一阶段实现。 |

不建议直接用逻辑文件大小替代磁盘分配大小、以 `du` 输出充当可释放空间、无限并发、把大小缓存当删除授权，或为了提速去掉根目录身份及链接检查。低层 `getattrlistbulk` 可以后续评估，但在 Foundation 数值元数据候选已显示明显潜力时，暂不承担额外的记录解析和兼容成本。

## 官方依据与落地验证

Foundation 枚举器支持预取并缓存所需资源信息，减少重复访问；现有扫描已预取大小，候选进一步把文件身份纳入同一批。[Apple 文件与目录访问指南](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/AccessingFilesandDirectories/AccessingFilesandDirectories.html)

`fileIdentifierKey` 表示 inode，但并非对所有文件系统、挂载或重启保持稳定，因此候选只在当前扫描中配合卷标识去重，不持久化；缺失属性需要明确回退。[Apple fileIdentifierKey](https://developer.apple.com/documentation/foundation/urlresourcekey/fileidentifierkey)、[Apple URLResourceValues](https://developer.apple.com/documentation/foundation/urlresourcevalues)

继续使用 `totalFileAllocatedSizeKey`，而不是仅对逻辑字节求和；该属性包含文件元数据占用。[Apple 分配大小说明](https://developer.apple.com/documentation/foundation/urlresourcekey/totalfileallocatedsizekey)

FSEvents 适合维护变更索引，但事件合并、丢失和根目录移动都需要重扫，不能替代删除前的最新核验。[Apple FSEvents 使用指南](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html)

下一步实施范围建议限定为优先级 1 和 2：先补硬链接/跨卷身份、属性缺失、权限拒绝、扫描中删除或替换文件、取消及错误传播测试，再比较真实只读样本的分阶段耗时、峰值内存和首次结果时间。清理路径和确认流程保持原有安全语义。并发和渐进结果单独评估，避免同时改变太多变量。
