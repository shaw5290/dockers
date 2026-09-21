下面是更新后的完整目录规则文档，已把 **自动扫描生成 include**、**存在确认（默认否）**、**菜单式管理** 等新逻辑纳入。可直接保存为 `docker/README.md`。

# Docker 目录规范

## 一、总览

本目录集中管理所有 Docker Compose 脚本。每个服务独立成目录，可单独启停；
根目录提供总控 `compose.yaml`，通过 `include` 统一编排全部服务。

设计原则：
- **单个可用**：每个服务目录能独立 `docker compose up -d`，不依赖总控。
- **总控统一**：根目录一键启停全部服务。
- **路径自洽**：所有相对路径以自身 `compose.yaml` 所在目录为基准。
- **配置隔离**：公共变量放根目录 `.env`，服务私有变量放各自 `.env`。
- **不覆盖已有**：脚本遇到已存在文件时询问，默认否，保护敏感配置。


## 二、目录结构

```text
docker/
├── compose.yaml              # 总控编排（include 各子服务）
├── .env                      # 公共变量（总控变量替换用）
├── README.md                 # 本文档
├── docker-manager.bat        # 管理脚本（初始化/新增/生成总控）
│
├── plaindoc/
│   ├── compose.yaml          # 单服务编排
│   ├── .env                  # 服务私有变量（含 JWT_SECRET 等）
│   ├── data/                 # 持久化数据
│   └── uploads/
│
├── nginx/
│   ├── compose.yaml
│   ├── .env
│   └── conf/
│
├── mysql/
│   ├── compose.yaml
│   ├── .env
│   └── data/
│
└── redis/
    ├── compose.yaml
    └── data/
```


## 三、命名规则

| 类型 | 规则 | 示例 |
|---|---|---|
| 服务目录 | 全小写，短横线分隔 | `plaindoc`、`web-stack` |
| 编排文件 | 统一 `compose.yaml` | `compose.yaml` |
| 环境变量 | 统一 `.env` | `.env` |
| 数据目录 | `data/` 固定名 | `plaindoc/data/` |
| 配置目录 | 按用途命名 | `conf/`、`nginx/` |
| 服务名 | 与目录名一致 | `plaindoc` |
| 容器名 | 服务名，全局唯一 | `plaindoc` |

**文件命名说明**：
- `compose.yaml` 是当前官方推荐的标准名称，优先级高于 `compose.yml`、`docker-compose.yaml`、`docker-compose.yml`。
- 只要目录存在 `compose.yaml`，Compose 就会自动使用，无需 `-f` 指定。

**禁止**：
- 禁止在根目录堆放零散的 `xxx.compose.yaml`。
- 禁止服务名、容器名重复。
- 禁止跨目录用 `../.env` 引用环境变量。


## 四、单个服务目录规范

每个服务目录必须包含：

1. `compose.yaml`：服务定义
2. `.env`：该服务的全部环境变量（敏感配置也放这里）
3. 数据/配置子目录（按需）

**compose.yaml 模板**：

```yaml
services:
  plaindoc:
    image: lifei6671/plaindoc:latest
    container_name: plaindoc
    ports:
      - "8080:8080"
    env_file:
      - .env
    volumes:
      - ./data:/app/data
      - ./uploads:/app/uploads
    restart: unless-stopped
```

要点：
- `env_file` 写相对路径 `.env`，与 `compose.yaml` 同目录。
- `volumes` 用 `./data`，数据落在服务目录内。
- 不写 `version:` 字段（Compose v2 已废弃）。


## 五、总控编排规范

根目录 `compose.yaml` 使用 `include`（需 Compose v2.20+）引入各子服务：

```yaml
name: mydocker

include:
  - plaindoc/compose.yaml
  - nginx/compose.yaml
  - mysql/compose.yaml
  - redis/compose.yaml
```

要点：
- 顶部显式写 `name:`，避免项目名随目录变化导致容器重复。
- `include` 是 **YAML 列表**，每个元素单独一行，各自独立，**不能把多个目录塞进一个引号里**。
- `include` 保持子文件路径基准，子服务 `./data` 仍指向各自目录。
- 总控文件**只做引入**，不重复定义服务。
- 总控 `include` 由脚本**自动扫描**所有含 `compose.yaml` 的子目录生成，与实际目录保持一致。

**错误写法示例**：

```yaml
# ❌ 错误：引号把多个目录包成一个字符串，路径无效
include:
  - " mysql nginx plaindoc redis"/compose.yaml
```

**版本检查**：

```bash
docker compose version
```

低于 v2.20 时改用 `extends`，但需注意相对路径基准会变为总控目录，需手动调整。


## 六、环境变量规则

| 变量类型 | 存放位置 | 说明 |
|---|---|---|
| 公共变量 | 根目录 `.env` | 仅用于总控变量替换 |
| 服务私有 | 服务目录 `.env` | 通过 `env_file` 注入容器 |
| 敏感配置 | 服务目录 `.env` | 如 `JWT_SECRET`，禁止提交到仓库 |

**优先级**（从高到低）：
1. `docker compose run -e`
2. `environment` 中直接写的值
3. `env_file` 指定的文件
4. 镜像内置 `ENV`

建议敏感配置只走 `env_file`，不要在 `environment` 里引用 `${...}`，避免空值覆盖。


## 七、管理脚本使用

`docker-manager.bat` 提供菜单式管理：

```
1. 初始化 / 同步全部服务
2. 新增单个服务
3. 生成总控 compose.yaml (include)
4. 退出
```

### 各模式说明

| 模式 | 作用 | 是否覆盖已有文件 |
|---|---|---|
| 1 初始化/同步全部 | 扫描所有含 `compose.yaml` 的子目录，补建 `data/`、`uploads/`、缺失的 `.env` | 仅补缺失，不覆盖 |
| 2 新增单个服务 | 交互输入目录名、服务名、镜像、端口，建目录、写文件、追加总控 include | 存在则询问，默认否 |
| 3 生成总控 | 扫描所有子服务，重新生成根 `compose.yaml` 的 include 列表 | 存在则询问，默认否 |

### 可选预设列表

脚本顶部 `PRESET_SERVICES` 可填批量服务定义：

```bat
set "PRESET_SERVICES=plaindoc|plaindoc|lifei6671/plaindoc:latest|8080:8080"
set "PRESET_SERVICES=!PRESET_SERVICES!;nginx|nginx|nginx:alpine|80:80"
```

格式：`目录名|服务名|镜像|端口`，用 `;` 分隔。留空则纯自动扫描，不新建子服务。

### 存在确认规则

- 任何目标文件已存在时，提示 `[y/N]`。
- **直接回车 = 否**，保留原文件。
- 只有输入 `y` 或 `yes` 才覆盖。


## 八、启动与运维

**单个服务**：

```bash
cd docker/plaindoc
docker compose up -d
docker compose logs -f
docker compose down
```

**总控全部**：

```bash
cd docker
docker compose up -d
docker compose ps
docker compose restart plaindoc
docker compose down
```

**校验配置**：

```bash
cd docker && docker compose config
```

**禁止混用**：不要对同一服务同时用单启和总控操作，否则会创建两套容器（项目名不同），导致端口和卷冲突。


## 九、新增服务流程

### 方式一：用脚本（推荐）

1. 运行 `docker-manager.bat`，选 `2`。
2. 按提示输入目录名、服务名、镜像、端口。
3. 脚本自动建目录、写 `compose.yaml` 和 `.env`、追加总控 include。
4. 手动补全该服务 `.env` 里的真实配置。

### 方式二：手动

1. 在 `docker/` 下新建服务目录，如 `docker/foo/`。
2. 创建 `foo/compose.yaml`，服务名与目录名一致。
3. 创建 `foo/.env`，写入该服务全部环境变量。
4. 按需创建 `foo/data/` 等子目录。
5. 运行脚本选 `3`，或手动在根 `compose.yaml` 的 `include` 追加 `- foo/compose.yaml`。
6. 验证：
   ```bash
   cd docker/foo && docker compose config
   cd docker && docker compose config
   ```
7. 启动测试：
   ```bash
   cd docker && docker compose up -d foo
   ```


## 十、检查清单

新增或修改服务后，逐项确认：

- [ ] 目录名、服务名、容器名一致且全局唯一
- [ ] `env_file` 指向同目录 `.env`
- [ ] `volumes` 使用 `./` 相对路径
- [ ] 敏感变量已写入 `.env` 且未提交仓库
- [ ] 根 `compose.yaml` 的 `include` 已包含该服务
- [ ] `include` 每行一个路径，无多余引号、无前导空格
- [ ] `docker compose config` 两份均无报错
- [ ] 单启与总控不会同时操作同一服务

### 📌 本次更新要点

| 更新项 | 说明 |
|---|---|
| 新增「七、管理脚本使用」 | 说明三种模式、预设列表、存在确认规则 |
| 新增「九、新增服务流程」 | 区分脚本方式和手动方式 |
| 明确 `include` 格式 | 强调逐行列表，给出错误示例对比 |
| 明确文件名 `compose.yaml` | 说明优先级和官方推荐 |
| 检查清单补充 | 增加 `include` 格式、文件名校验项 |

保存后，团队按「第九节」走新增流程，按「第十节」做检查即可。#   d o c k e r s  
 