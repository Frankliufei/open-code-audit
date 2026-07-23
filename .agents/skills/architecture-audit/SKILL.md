---
name: architecture-audit
description: 用于全仓架构审计，发现模块边界、依赖方向、所有权、分层违规、耦合、复杂度和治理缺口等问题，并输出可核实的审计摘要。
---

# 架构审计

## 核心任务

审计真实代码，找出架构问题。agent 必须先建立代码事实，再判断问题；每条结论都要有证据，不能只写泛泛的设计原则。

## 必要条件

审计需要这些工具。缺失时先安装或补齐，再继续完整审计：

- `codebase-memory-mcp`
- `grimp`
- `import-linter`
- `semgrep`
- `ruff`
- `radon`
- `lizard`
- `vulture`
- `bandit`
- `pydeps`

工具分工：

- `codebase-memory-mcp`：主代码图谱，优先用于索引仓库、读取架构概览、搜索符号、追踪调用、读取关键源码片段。
- `grimp` / `pydeps`：验证模块 import 边、依赖方向和循环。
- `import-linter`：验证已经明确的依赖契约；没有配置时，输出建议契约。
- `semgrep`：查找架构模式，例如路由层提交事务、直接返回文件、文件系统写入、直接调用外部进程、疑似密钥暴露。
- `ruff`：提供正确性旁证，例如 undefined name、重复定义、异常 import。
- `radon` / `lizard`：确认高复杂度函数、超长函数、超大文件和职责集中。
- `vulture`：发现死代码、失效 owner、重复入口候选，写入报告前必须复核。
- `bandit`：发现安全相关架构旁证，例如危险 SQL 拼接、吞异常、运行时代码里的 assert、硬编码密钥。

## 审计流程

### 1. 建立代码事实

优先使用 `codebase-memory-mcp`：

1. 索引目标仓库。
2. 读取架构概览。
3. 搜索路由、服务、模型、仓储、启动入口、外部系统调用。
4. 对热点符号追踪 inbound / outbound 调用。
5. 对异常依赖、复杂流程、边界跨越读取源码片段。

同时排除明显非生产代码对结论的干扰，例如缓存、构建产物、虚拟环境、生成报告、审计证据目录。若这些内容污染代码图谱，本身可以作为治理问题报告。

### 2. 推断模块

从真实代码推断模块，不从已有治理配置起步。

依据：

- 目录结构和包名
- 路由归属
- service / domain / model / schema / db 的 import 关系
- DB/session、文件存储、外部 API、消息队列等资源访问位置
- 调用图热点和 fan-in / fan-out
- 同一文件或模块是否混合多个 bounded context

先输出 YAML：

```yaml
inferred_modules:
  - name: api
    paths:
      - backend/app/api/**
    responsibilities:
      - HTTP 路由
      - 请求响应适配
    evidence:
      - "codebase-memory: 路由定义集中在 backend/app/api"
```

### 3. 分析依赖关系

用 `grimp`、`pydeps` 和代码图谱输出模块依赖 YAML：

```yaml
dependency_edges:
  - from: api
    to: db
    kind: direct_persistence_dependency
    evidence:
      - "grimp: app.api.v1.routes.lvs -> app.db.session"
      - "semgrep: route handler contains await db.commit()"
    verdict: risk
    reason: "HTTP 路由层直接拥有事务边界。"
```

逐条检查：

- 是否存在反向依赖。
- 是否存在循环依赖。
- 上层是否直接依赖底层内部实现。
- API 层是否直接依赖 DB、ORM model、repository internals。
- domain 是否反向依赖 service、adapter、infrastructure。
- service 是否变成多个业务域的共同 owner。
- 启动入口是否承担 migration、seed、部署、业务初始化等多种职责。

### 4. 发现架构问题

重点寻找这些问题：

- 模块边界不清：一个文件或模块混合路由、权限、事务、文件、业务流程。
- 依赖方向错误：领域层依赖应用层/适配层，基础设施反向依赖业务流程。
- 事务 owner 错位：路由层直接 `commit`、`rollback` 或组织复杂数据库写流程。
- 状态 owner 分散：同一实体、权限、配置、附件、审批、财务等状态被多个模块直接写。
- 重复事实来源：同一能力存在多个 `get_*`、`sync_*`、权限判断或状态转换实现。
- 高复杂度聚集：大文件、大函数、高 CCN 与跨模块依赖同时出现。
- 公共契约缺失：跨模块直接 import 私有实现，没有 facade、service contract 或清晰 owner。
- 启动边界混乱：应用启动逻辑包含迁移、补数据、seed、外部同步等运行职责。
- 图谱污染：测试、生成物、治理输出被当成生产模块，影响审计判断。
- 安全与治理信号：硬编码密钥、危险 SQL 拼接、吞异常、运行时代码 assert。

### 5. 逐条核实

每个重要发现至少用两类证据确认：

- 代码图谱或 import 边
- 源码片段
- `semgrep` 模式匹配
- `radon` / `lizard` 复杂度
- `ruff` 正确性问题
- `bandit` / `vulture` 旁证

不要只报工具原始结果。工具结果必须被解释成架构风险。

发现格式：

```yaml
findings:
  - id: ARCH-001
    severity: high
    title: "路由层拥有业务流程和事务边界"
    files:
      - backend/app/api/v1/routes/lvs.py
    evidence:
      - "grimp: api -> db"
      - "semgrep: route handler contains await db.commit()"
      - "lizard: file contains multiple high-CCN handlers"
    risk: "HTTP 适配层与业务规则、权限、事务提交强耦合。"
    next_check: "选一个具体流程追踪调用链，确认应归属的 application service。"
    confidence: high
```

### 6. 输出审计摘要

报告保持简短，包含：

1. `Decision`：`PASS`、`PASS_WITH_WARNINGS`、`REQUIRES_ATTENTION`、`BLOCKED_TOOLING`
2. `Inferred Modules`：模块 YAML 摘要
3. `Dependency Direction Summary`：依赖 YAML 摘要
4. `Top Findings`：按严重度排序的问题
5. `Tool Coverage`：哪些工具参与了证据收集
6. `Next Investigation`：下一步最小核实动作

`import-linter` 配置说明：

```ini
[importlinter]
root_package = app

[importlinter:contract:api-does-not-import-db]
name = API must not import database layer directly
type = forbidden
source_modules =
    app.api
forbidden_modules =
    app.db
```

有契约配置时运行验证；没有配置时，根据审计发现输出建议契约。
