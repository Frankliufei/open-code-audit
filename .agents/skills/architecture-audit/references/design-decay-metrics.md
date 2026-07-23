# 设计腐化量化指标

这些指标用于把 SRP、DIP、OCP、ISP 等设计原则转成可观察信号。指标只产生候选问题；写入审计报告前，必须用源码、代码图谱或工具输出核实。

## 使用方式

1. 先按模块、文件、函数、调用方计算指标。
2. 超过阈值时标记为候选腐化点。
3. 为每个候选点补充至少两类证据。
4. 报告里写具体信号和风险，不只写原则名称。

## 指标

### public_interface_ratio

衡量模块封装度。

```yaml
metric: public_interface_ratio
formula: public_api_count / max(private_api_count, 1)
thresholds:
  warning: "> 0.2"
  high: "> 0.35"
principles:
  - encapsulation
  - ISP
signal: "public 接口过多，模块暴露面过大，外部调用容易依赖内部细节。"
```

### responsibility_kinds_per_file

衡量单文件职责数量。

```yaml
metric: responsibility_kinds_per_file
count_kinds:
  - http_route
  - db_transaction
  - permission_check
  - file_io
  - external_api
  - state_machine
  - notification
  - migration_or_seed
thresholds:
  warning: ">= 3"
  high: ">= 4"
principles:
  - SRP
signal: "一个文件同时承担多类技术职责或业务职责。"
```

### concrete_infrastructure_imports

衡量高层模块是否直接依赖底层实现。

```yaml
metric: concrete_infrastructure_imports
count: high_level_to_infrastructure_import_edges
high_level_examples:
  - api
  - application
  - domain
infrastructure_examples:
  - db
  - storage
  - sdk
  - clients
  - external_gateway
thresholds:
  warning: ">= 1"
  high: ">= 3"
principles:
  - DIP
signal: "高层策略直接依赖数据库、SDK、存储或外部客户端。"
```

### variation_branch_density

衡量变化轴是否散落在多处。

```yaml
metric: variation_branch_density
variation_keys:
  - type
  - status
  - provider
  - channel
  - case_type
  - approval_type
thresholds:
  warning: "same variation key appears in >= 2 files"
  high: "same variation key appears in >= 4 files"
principles:
  - OCP
signal: "新增一种类型、状态、渠道或 provider 需要修改多个旧文件。"
```

### consumer_method_usage_ratio

衡量接口是否过胖。

```yaml
metric: consumer_method_usage_ratio
formula: caller_used_methods / provider_public_methods
thresholds:
  warning: "< 0.2"
  high: "< 0.1"
principles:
  - ISP
signal: "调用方只使用巨大 provider 的少数方法，却被迫依赖整个接口。"
```

### module_fanout

衡量模块出边过多。

```yaml
metric: module_fanout
formula: count(distinct directly_imported_modules)
thresholds:
  warning: ">= 5"
  high: ">= 8"
principles:
  - SRP
  - DIP
signal: "模块直接依赖过多 peer 或底层模块，可能成为流程中心或上帝服务。"
```

### module_fanin_without_stable_contract

衡量高入边模块是否具备稳定契约。

```yaml
metric: module_fanin_without_stable_contract
formula: fanin >= 8 and public_contract_missing
thresholds:
  warning: true
  high: "fanin >= 12 and public_contract_missing"
principles:
  - DIP
  - encapsulation
signal: "许多模块依赖同一模块，但该模块没有清晰 facade、protocol 或 public contract。"
```

### hotspot_score

衡量复杂度、职责、依赖是否叠加。

```yaml
metric: hotspot_score
formula: max_ccn + module_fanout * 2 + responsibility_kinds_per_file * 3
thresholds:
  warning: ">= 25"
  high: ">= 40"
principles:
  - SRP
  - DIP
  - maintainability
signal: "复杂度、依赖数量、职责数量同时偏高，是优先审计热点。"
```

## 报告格式

```yaml
principle_findings:
  - principle: SRP
    metric: responsibility_kinds_per_file
    threshold: "< 3"
    actual: 5
    verdict: high
    evidence:
      - "file contains route handlers, db commits, permission checks, file export, approval transitions"
      - "lizard: high CCN handlers in the same file"
    risk: "一个业务变化会同时牵动 HTTP、事务、权限和文件导出逻辑。"
    confidence: high
```
