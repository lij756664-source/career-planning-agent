# 职业规划智能体（GradQuest）

面向大学生的一站式职业规划系统。学生端完成能力画像、职业测评、人岗匹配与职业路径规划，HR 端基于同一套画像体系做候选人评估。

项目由三个服务组成：

| 服务 | 技术栈 | 端口 | 职责 |
|---|---|---|---|
| `frontend/` | 原生 HTML / CSS / JS | 8080 | 学生端与 HR 端页面 |
| `backend/` | Spring Boot 3.3.4 + MyBatis-Plus + MySQL 8 | 5000（`/api/v1`） | 用户、鉴权、业务数据、文件存储 |
| `ai/` | Flask 3.1 + LangChain / LangGraph + ChromaDB | 5002（`/api/v1`） | 画像生成、匹配、测评、报告、问答、模拟面试 |

## 一、整体架构

```
                 ┌──────────────────────────────┐
                 │  浏览器（静态页面，8080）      │
                 │  学生端 / HR 端               │
                 └───────────┬──────────────────┘
                             │ HTTP
                 ┌───────────▼──────────────────┐
                 │  Java 后端（5000, /api/v1）    │
                 │  JWT 鉴权 · 业务数据 · 文件    │
                 └───────┬──────────────┬───────┘
                         │ JDBC         │ HTTP 转发
                 ┌───────▼──────┐  ┌────▼─────────────────┐
                 │  MySQL 8     │  │ Python AI 服务（5002）│
                 │  gradquest   │  │ 画像 / 匹配 / 测评    │
                 └──────────────┘  │ 报告 / Agent / 面试   │
                                   └────┬──────────┬──────┘
                                        │          │
                              ┌─────────▼──┐  ┌────▼─────────┐
                              │ ChromaDB   │  │ LLM DeepSeek │
                              │ 本地BGE向量 │  │ BGE 向量化    │
                              └────────────┘  └──────────────┘
```

## 二、目录结构

```
.
├── ai/                    Python AI 服务
│   ├── api/               13 个 Blueprint，按业务域划分路由
│   ├── agent/             ReAct Agent 与工具集
│   ├── matching/          人岗匹配（混合检索 + 重排）
│   ├── job_profile/       岗位画像生成
│   ├── assessment/        职业测评（问卷、计分、报告）
│   ├── career_report/     职业规划报告
│   ├── student_ability/   学生能力画像
│   ├── graph/             岗位关联图谱与晋升路径
│   ├── rag/               检索增强问答
│   ├── config/            YAML 配置
│   ├── data/              数据集与运行时数据
│   └── app.py             服务入口
├── backend/               Spring Boot 后端（16 个 Controller / 14 个 Service）
├── frontend/              静态页面（学生端、HR 端、报告模板）
├── docs/                  API 文档、启动脚本、验证工具
├── database.sql           建表与初始化数据
└── start.bat              本地一键启动
```

## 三、核心模块与实现要点

### 1. 岗位画像生成
策略是「数据集优先」：先从岗位 JD 采样数据中取出该岗位的真实描述，交给模型提炼结构化画像（职责、技能要求、证书、晋升方向等）；数据集里没有匹配记录时，退化为模型基于行业知识生成。整条链路在没有 API Key 的情况下还有一层本地规则兜底，保证服务不会因为模型不可用而直接挂掉。

### 2. 人岗匹配
`matching/hybrid_retriever.py` 是一条完整的检索链：

```
BM25 / 关键词召回  ┐
                   ├→ 融合 → Cross-Encoder 精排 → MMR 多样性重排 → Top-N
双塔向量召回        ┘
```

召回阶段追求覆盖率，精排阶段追求准确率，MMR 用来抑制「推十个几乎一样的岗位」这种同质化结果。依赖缺省时会自动降级为纯关键词匹配，不影响接口可用性。

### 3. 职业测评
动态生成问卷，按霍兰德代码、MBTI、能力倾向、职业价值观四个维度分别计分，再汇总成综合报告。问卷入库时做了向量化，用于去重与相似题目检测。

### 4. 职业规划报告
按「自我认知 → 岗位匹配 → 目标与路径 → 行动计划 → 复盘机制」分节生成，每节独立约束输出结构，避免一次性生成导致后半段质量塌陷。

### 5. ReAct Agent
基于 LangGraph 的 `create_agent`，挂载 6 个工具：岗位列表、岗位详情、关联图谱、触发画像生成、迁移路径摘要、CSV 匹配预览。模型自行决定调用顺序，工具层做了统一监控与模型调用前日志。

### 6. 模拟面试
按岗位生成题目与追问，支持语音输入（ASR）与语音播报（TTS），会话状态落盘，可中断续答。

## 四、技术栈

- **后端**：Spring Boot 3.3.4、Java 17、MyBatis-Plus 3.5.15、MySQL 8、JWT（jjwt 0.12）、PDFBox 3.0
- **AI**：Flask 3.1、LangChain 1.2、LangGraph 1.0、ChromaDB、sentence-transformers、rank-bm25、pandas
- **前端**：原生 JS（无框架）、ECharts 风格图谱模板
- **模型**：对话走 DeepSeek `deepseek-chat`（OpenAI 兼容端点）；向量化走本地 `BAAI/bge-small-zh-v1.5`（DeepSeek 不提供 embedding 接口）

## 五、本地启动

环境要求：JDK 17、Maven 3.8+、Python 3.10、MySQL 8。

最省事的方式是双击根目录 `run.bat`：它会检查数据库、按需创建 venv 并装依赖、询问 DeepSeek Key、检测端口占用，然后把三个服务分别开到独立窗口并打开浏览器。下面是等价的手动步骤。

数据库只在首次初始化时需要 MySQL root 密码，脚本不会把它写到任何文件里：没有现成凭据时由 `mysql` 自行提示输入。

如果希望以后重建库也免输入，用 MySQL 自带的加密登录路径（凭据存在用户目录的 `.mylogin.cnf`，项目里没有明文）：

```
"D:\MySQL\MySQL installation\bin\mysql_config_editor.exe" set --login-path=gradquest-root --host=127.0.0.1 --user=root --password
```

下次 `run.bat` 会优先使用 `gradquest-root` 这条登录路径。

**1. 初始化数据库**

```sql
CREATE DATABASE gradquest DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
```

```bash
mysql -u root -p gradquest < database.sql
```

**2. 启动 AI 服务**

```bash
cd ai
python -m venv venv
venv\Scripts\activate          # Windows
pip install -r requirements.txt

# 密钥：推荐用 DPAPI 加密保存（只绑定当前 Windows 账号，项目内不留明文）
python scripts/set_api_key.py       # 交互输入，不回显；可加 --check / --delete

# 或者仅在当前进程临时注入（优先级更高）
set DEEPSEEK_API_KEY=sk-xxx       # Windows；Linux/macOS 用 export
set HF_ENDPOINT=https://hf-mirror.com   # 访问不了 huggingface.co 时使用（首次会下载约 95MB 向量模型）
python app.py                  # 默认 5002，可用 AI_SERVICE_PORT 覆盖
```

**3. 启动后端**

```bash
cd backend
mvn spring-boot:run
```

数据库连接、端口等在 `backend/src/main/resources/application.yml` 中配置，本地覆盖可参考 `application-local.yml.example`。

**4. 启动前端**

```bash
cd frontend
python -m http.server 8080
```

浏览器打开 `http://127.0.0.1:8080`。

也可以用根目录 `start.bat` 一键拉起三个服务（需先建好 `ai/venv`）。

## 六、数据说明

- `ai/data/a13基于AI的大学生职业规划智能体-JD采样数据.csv`：岗位 JD 采样数据，匹配与画像生成的数据源，**删掉会导致岗位相关接口不可用**。
- `ai/data/job_profiles/profiles.json`：画像生成结果的缓存，可由 `ai/init_job_profiles.py` 重建。
- `ai/data/profiles/`：用户上传的简历与解析结果，属于运行时数据。
- `docs/API文档.md`：接口清单与请求响应示例。

## 七、设计取舍与已知问题

- **三层降级**：模型 → 规则兜底 → 空结果提示。测评、画像、匹配三条链路都做了降级，任何一层失败都不会让前端白屏。
- **检索与生成分离**：匹配只负责算分与排序，解释文案由模型单独生成，两者可独立替换与评测。
- **配置管理**：模型密钥不落明文——用 Windows DPAPI 加密后存在用户目录（`%LOCALAPPDATA%\GradQuest\`），项目里既无密钥文件也无密钥副本，换机器/换账号无法解密；环境变量 `DEEPSEEK_API_KEY` 可临时覆盖。后端连库口令支持 `DB_PASSWORD` 覆盖，YAML 里只保留与建库脚本一致的默认值。
- **语音链路**：模拟面试的实时 ASR/TTS 依赖第三方语音服务，切到 DeepSeek 后语音入口会提示未配置，当前仅保留文字问答；语音与对话模型解耦，接回任意 ASR/TTS 服务即可。
- **评测缺失**：匹配准确率目前没有稳定的标注集，只有人工抽样检查，这是后续最需要补的一块。
- **并发**：当前按单机单进程设计，未做压测与限流。
