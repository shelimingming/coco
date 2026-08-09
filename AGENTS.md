# Coco 开发协作指南

开始实现前先读：

1. `doc/需求.md` — 产品边界与 MVP 范围
2. `doc/架构.md` — 目录、分层、表结构
3. `doc/DESIGN.md` — 视觉与可访问性

冲突时优先级：用户当前要求 > 需求.md > 架构.md > DESIGN.md > 本文件。

## 项目目标

Coco 是面向老人与子女的 AI 家庭陪伴助手。同一 App，父母端与子女端两种角色。

MVP 核心：语音陪伴、日常提醒、关怀摘要同步、子女今日状态、子女报平安、基础记忆。

不是医疗、诊断、急救或监控工具。

## 工作方式

- 始终使用中文沟通；代码命名用英文；关键业务规则加简洁中文注释。
- 注释解释「为什么」和约束，不复述代码。
- 不修改与当前任务无关的文件；不顺手大范围重构。
- `back/` 只读参考，不要复制其过度分层与上帝类。
- 未完成的能力用显式命名的 fake/mock，可替换。
- 禁止在仓库、日志、测试中写入真实密钥、手机号、验证码、私密对话。

## 技术基线

- 客户端：Flutter，Riverpod，go_router，Dio；首发 iOS 26。
- 后端：FastAPI，SQLAlchemy 2 async，Alembic，uv；库 `coco`，schema `coco`。
- 鉴权：手机号验证码；JWT access + opaque refresh。
- AI / ASR / TTS：必须经服务端适配层，客户端不存供应商密钥。

## 目录约束

后端：`modules/<feature>/{router,service,schemas}`，公共横切在 `src/coco/`。

前端：`features/<name>/{data,domain,application,presentation}`，公共能力在 `core/`。

禁止：

- 一个 Repository 实现全部业务接口
- AppView / AppActions 双层门面
- domain / application / api 三层无意义 DTO 转换
- 软删除 + 乐观锁 + outbox 等 MVP 不需要的基础设施

## 双角色

- 父母端：一屏一事、语音优先、大字号、大点击区、暖色。
- 子女端：结论优先、现代克制、青绿主色、四栏导航（后续）。
- 切换 UI 角色不等于扩大数据权限；服务端鉴权是最终判断。

## 视觉与 UI（必须统一）

前端界面风格一律以 `doc/DESIGN.md` 为准，后续新增或改版页面都必须对齐，不得各自发挥。

- 做 UI 前先读 DESIGN：色板、字号、圆角、间距、双角色气质、可访问性与危险操作样式。
- 颜色 / 间距 / 圆角只用 `frontend/lib/core/theme/tokens.dart`（`CocoColors` / `CocoSpace` / `CocoRadius`）及主题，**禁止页面内写裸色值**。
- 父母端只用老人端 token 与暖色气质；子女端只用子女端 token 与青绿主色；**禁止跨角色混用色板**。
- 优先复用 `CocoTheme`、`CocoScaffold`、`CocoPrimaryButton` / `CocoSecondaryButton` / `ParentChipButton` 等现有组件，新样式先落到 DESIGN 与 token，再进代码。
- 与 DESIGN 冲突时：用户当前明确要求 > DESIGN.md；若用户要求偏离 DESIGN，在实现说明里点明偏差。

## 不可破坏的规则

- 创建提醒、保存记忆、分享给家人等动作，必须经用户明确确认后由业务 API 执行。
- 默认最小共享；未经父母同意不得同步私人聊天。
- 不提供诊断、药量建议、虚假救援承诺。
- 用户错误文案包含：发生了什么、现在能做什么、数据是否受影响。

## 完成前检查

1. 格式化变更代码。
2. 后端相关：迁移可 upgrade；关键接口可 curl 通。
3. 前端相关：`flutter analyze` 通过；iOS 模拟器能跑通当前流程。
4. 说明已完成内容、未验证风险、后续必要工作。
