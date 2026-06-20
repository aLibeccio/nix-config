# nix-config — 我的 Nix / home-manager 配置

一份配置管理多设备的 CLI 环境(包 + shell + git/helix/zellij 设置),用 **Determinate Nix + 独立 home-manager(flake)** 实现,公开同步在本仓库。

## 用法速查

| 操作 | 命令 |
|---|---|
| 应用配置(本机) | `hms`(= `home-manager switch --flake ~/nix-config#generic --impure`) |
| 上传改动 | `cd ~/nix-config && git add -A && git commit -m '...' && git push` |
| 别的机器拉更新 | `git -C ~/nix-config pull && hms` |
| 升级所有工具版本 | `cd ~/nix-config && nix flake update && hms`,再 push |
| **新设备一条命令接入** | `curl -fsSL https://raw.githubusercontent.com/aLibeccio/nix-config/main/bootstrap.sh \| sh` |

> ⚠️ 新增 `.nix` 文件记得先 `git add`(flake 只认 git 跟踪的文件)。
> ⚠️ 配置文件(`~/.config/git/config`、`~/.config/helix/config.toml` 等)现在是指向 Nix 的只读软链 —— **改设置 = 改 `~/nix-config` 里的 `.nix` 再 `hms`**,别手编辑。

## 文件结构

- `flake.nix` —— 入口:依赖(nixpkgs / home-manager)+ `generic` 自动探测配置
- `packages.nix` —— CLI 工具清单(下面详解)
- `shell.nix` —— zsh + oh-my-zsh + starship/zoxide/atuin/fzf/direnv 的 shell 集成
- `programs.nix` —— 声明式管理 git / gh / helix / zellij 的设置
- `home.nix` —— 主配置(import 上面几个)
- `bootstrap.sh` —— 新机一条命令脚本

---

# CLI 工具清单（作用 · 常见用法 · 场景）

## 核心工具 / 数据处理

- **`curl`** —— 传输数据/下载 · `curl -fL -o f URL` · 下载文件、手撸 HTTP 请求
- **`xh`** —— 现代 HTTP 客户端(httpie 风格) · `xh GET httpbin.org/get`、`xh POST api.x name=foo` · 测试/调试 REST API,输出比 curl 可读
- **`jq`** —— JSON 处理器 · `curl … | jq '.items[].name'` · 从 API 响应/JSON 里提取、过滤、改写
- **`yq`** —— 像 jq 但处理 YAML · `yq '.services.web.image' compose.yml` · 读/改 k8s、docker-compose、CI 的 YAML
- **`dasel`** —— 一个工具查 JSON/YAML/TOML/XML/CSV · `dasel -f c.toml '.server.port'` · 懒得为每种格式记不同工具时
- **`duckdb`** —— 进程内分析型数据库,直接 SQL 查文件 · `duckdb -c "SELECT * FROM 'd.csv' LIMIT 5"` · 对 CSV/Parquet 快速跑 SQL 分析
- **`psql`** (postgresql) —— Postgres 客户端 · `psql -h host -U user db` · 连库跑 SQL、导入导出
- **`mlr`** (miller) —— CSV/TSV/JSON 处理 · `mlr --csv cut -f name,age d.csv` · 命令行做表格数据过滤/聚合/转格式
- **`shfmt`** —— shell 脚本格式化 · `shfmt -w s.sh` · 统一 `.sh` 风格
- **`eza`** —— 现代 `ls` · `eza -la --git --icons`、`eza --tree` · 日常列目录(带 git 状态/图标/树)
- **`bat`** —— 现代 `cat` · `bat file.rs` · 看代码/文件,语法高亮 + 行号
- **`rg`** (ripgrep) —— 超快全文搜索 · `rg "TODO" -t py` · 代码库里搜字符串/正则(比 grep 快很多)
- **`fd`** —— 现代 `find` · `fd '\.nix$'`、`fd -e png` · 按名字/扩展找文件,语法简单
- **`sd`** —— 查找替换(现代 sed) · `sd 'foo' 'bar' f.txt` · 批量替换文本
- **`dust`** —— 现代 `du` · `dust -d 2` · 看哪个目录占磁盘最多
- **`tailspin`** (tspin) —— 日志高亮 · `tailspin app.log`、`tail -f log | tspin` · 看日志时自动高亮 IP/时间/级别
- **`hexyl`** —— 彩色十六进制查看 · `hexyl f.bin | head` · 看二进制文件内容
- **`doggo`** —— 现代 `dig`(DNS) · `doggo example.com`、`doggo MX gmail.com` · 查 DNS 记录,输出清晰
- **`trip`** (trippy) —— 现代 traceroute/mtr · `sudo trip example.com` · 诊断网络路径/丢包在哪一跳
- **`bandwhich`** —— 按进程看带宽 · `sudo bandwhich` · 查"谁在占网速"
- **`glow`** —— 终端渲染 Markdown · `glow README.md` · 在终端漂亮地读 md
- **`jless`** —— TUI 浏览 JSON/YAML · `jless data.json`、`curl … | jless` · 交互式折叠/展开大 JSON

## Nix 与系统

- **`nh`** —— home-manager/nixos 操作助手 · `nh home switch ~/nix-config`、`nh clean all` · 更顺手地 switch / 清理旧代
- **`nom`** (nix-output-monitor) —— 构建进度美化 · `nom build …` · 看 nix 构建进度更直观
- **`nixd`** —— Nix 语言服务器(LSP) · 编辑器自动用(helix 已接) · 写 `.nix` 时补全/跳转/诊断
- **`nixfmt`** —— 官方 Nix 格式化 · `nixfmt f.nix` · 格式化 `.nix`(helix 保存时自动跑)
- **`statix`** —— Nix 静态检查 · `statix check ~/nix-config`、`statix fix` · 发现/修 Nix 反模式
- **`deadnix`** —— 找未使用的 Nix 代码 · `deadnix ~/nix-config` · 清理没用的绑定/参数
- **`nix-tree`** —— 浏览依赖闭包 · `nix-tree` · 看包依赖了啥、谁让闭包变大
- **`btop`** —— 系统监视器(top↑) · `btop` · 看 CPU/内存/进程/网络
- **`procs`** —— 现代 `ps` · `procs firefox`、`procs --tree` · 查进程(带树/端口/搜索)
- **`fastfetch`** —— 系统信息展示 · `fastfetch` · 秀配置/截图
- **`hyperfine`** —— 命令基准测试 · `hyperfine 'rg foo' 'grep -r foo .'` · 精确对比两条命令谁快
- **`oha`** —— HTTP 压测 · `oha -n 1000 http://localhost:8080` · 给 web 服务做负载测试

## 代码统计 / 工具

- **`tokei`** —— 统计代码行数 · `tokei` · 看项目各语言代码量
- **`grex`** —— 从示例生成正则 · `grex 1.2.3 4.5.6` · 懒得手写正则时给例子让它生成

## 开发 / 版本控制

- **`git-lfs`** —— Git 大文件存储 · `git lfs install && git lfs track "*.psd"` · 仓库里放大二进制文件
- **`sops`** —— 加密管理 secrets · `sops secrets.yaml` · 把密钥加密后安全提交(公开仓库尤其需要)
- **`age`** —— 现代加密工具 · `age -r <pubkey> -o f.age f` · 给文件加密(sops 的后端之一)
- **`watchexec`** —— 文件变化触发命令 · `watchexec -e rs cargo test` · 改代码自动跑测试/构建
- **`usage`** —— CLI 规格/补全生成器 · 给 CLI 写 spec、生成补全 · 偏工具作者用
- **`shellcheck`** —— shell 脚本静态检查 · `shellcheck s.sh` · 发现 shell 脚本里的坑
- **`yamlfmt`** —— YAML 格式化 · `yamlfmt .` · 统一 YAML 风格
- **`pre-commit`** —— git 提交钩子框架 · `pre-commit install`、`pre-commit run -a` · 提交前自动跑 lint/format
- **`gh`** —— GitHub CLI · `gh pr create`、`gh repo clone`、`gh auth login` · 命令行操作 GitHub(PR/issue/仓库)
- **`lazygit`** —— git 终端 UI · `lazygit` · 可视化 暂存/提交/分支/rebase(日常 git 神器)
- **`delta`** —— git diff 高亮(已设为 git pager) · `git diff`、`git show` 自动用 · 看 diff 更清楚
- **`difft`** (difftastic) —— 结构化(语法感知)diff · `difft a.js b.js` · 看"逻辑变了什么"而非纯文本行
- **`gitleaks`** —— 扫描密钥泄露 · `gitleaks detect` · 提交/推送前查有没有写进密钥(公开仓库必备)
- **`just`** —— 命令运行器(现代 make) · `just`、`just build` · 在 `justfile` 里写项目常用任务
- **`mise`** —— 多语言运行时/版本管理(asdf↑) · `mise use node@22`、`mise install` · 按项目管 node/python/go 等版本

## 基础设施 / 云

- **`k9s`** —— Kubernetes 终端 UI · `k9s` · 可视化浏览/操作 k8s 资源
- **`kubectl`** —— Kubernetes 命令行 · `kubectl get pods`、`kubectl logs …` · 操作 k8s 的基本工具
- **`kubectx` / `kubens`** —— 切上下文/命名空间 · `kubectx prod`、`kubens kube-system` · 多集群/多命名空间快速切换
- **`helm`** (kubernetes-helm) —— k8s 包管理 · `helm install …`、`helm repo add …` · 用 chart 部署应用到 k8s
- **`minikube`** —— 本地单机 k8s · `minikube start` · 本地起集群练手/开发
- **`stern`** —— 多 pod 日志聚合 · `stern my-app` · 按标签同时跟多个 pod 的日志
- **`dive`** —— 检查容器镜像层 · `dive my-image:tag` · 分析镜像每层加了啥、怎么瘦身
- **`lazydocker`** —— docker 终端 UI · `lazydocker` · 可视化管理容器/镜像/日志(配 colima)
- **`aws`** (awscli2) —— AWS 命令行 · `aws s3 ls`、`aws ec2 …` · 操作 AWS 资源
- **`rclone`** —— 云存储同步(rsync for cloud) · `rclone copy ./ remote:bucket` · 本地 ↔ S3/GDrive 等之间同步

## 文件 / 媒体

- **`yt-dlp`** —— 视频下载 · `yt-dlp URL`、`yt-dlp -x --audio-format mp3 URL` · 下视频/抽音频
- **`ffmpeg`** —— 音视频处理 · `ffmpeg -i in.mov out.mp4` · 转码/剪辑/抽帧/压缩
- **`unar`** —— 解压各种格式 · `unar x.rar`、`unar x.7z` · 解 rar/7z/zip(比系统强)
- **`ouch`** —— 通用压缩/解压 · `ouch decompress x.tar.gz`、`ouch compress f/ out.zip` · 不记各种 tar 参数,统一命令
- **`typst`** —— 现代排版(LaTeX↑) · `typst compile doc.typ`、`typst watch doc.typ` · 写论文/简历/PDF,语法比 LaTeX 简单

## Shell / 导航（含已接 shell 集成的）

> 快捷键:**Ctrl-R** atuin 历史 · **Ctrl-T** fzf 选文件 · **Alt-C** fzf 进目录 · **`z 关键词`** zoxide 跳转 · **Tab** 参数补全(carapace)· **→** 接受灰字建议

- **`fzf`** —— 模糊查找器 · `Ctrl-T` 选文件、`Alt-C` 进目录、`命令 | fzf` · 任何"从一个列表里挑一个"
- **`zoxide`** —— 智能 `cd` · `z proj`、`zi` · 按访问频率记忆目录,几个字母跳过去
- **`atuin`** —— 升级版 shell 历史 · `Ctrl-R` 搜索;`atuin register` 可端到端加密同步 · 翻找/重用历史命令(可按目录/退出码过滤)
- **`starship`** —— 跨 shell 提示符 · 自动显示 · 提示符里看 git 分支/语言版本/状态
- **`direnv`** —— 进目录自动加载环境 · 写 `.envrc`(内容 `use flake`) · 进项目自动进 devShell / 设环境变量
- **`zellij`** —— 终端复用/分屏(现代 tmux) · `zellij` · 一个终端里多面板/标签、会话保持
- **`yazi`** —— 极快 TUI 文件管理器 · `yazi` · 终端里浏览/预览/操作文件(带图片预览)
- **`tldr`** (tealdeer) —— 命令精简示例 · `tldr tar`、`tldr ffmpeg` · 忘了某命令怎么用,看几个实用例子(比 man 快)
- **`navi`** —— 交互式命令速查表 · `navi` · 忘了参数时交互式查/填
- **`rtk`** —— 减少 LLM token 的 CLI 代理 · 包裹常见 dev 命令 · 配合 AI 编码工具省 token
- **`carapace`** —— 给 1000+ 个 CLI 提供 子命令/参数/flag 的 Tab 补全 · 装好直接按 Tab · 任何命令都想要参数补全时

> zsh 还开了 **autosuggestions**(灰字历史建议,`→` 接受)和 **syntax-highlighting**(命令边打边高亮),配置在 `shell.nix`。Nix 装的工具大多自带补全,carapace 再统一补强。

## 编辑器

- **`hx`** (helix) —— 模态编辑器 · `hx file` · Vim 风格但开箱即用;已接 `nixd` LSP + 保存自动 `nixfmt`

## 容器(平台相关)

- **macOS**:**`colima`**(跑容器的轻量 VM)+ **`docker`**(docker-client,CLI 连 colima) · `colima start` 后照常 `docker …`
- **Linux**:**`podman`**(无守护进程容器,docker 替代)、**`buildah`**(建 OCI 镜像)、**`skopeo`**(查/拷镜像)

---

# 声明式管理的程序设置(`programs.nix`)

- **git** —— name/email、`delta` 做 diff 高亮、别名 `st/co/br/lg`、`pull.rebase`、`push.autoSetupRemote`;凭据助手用 `gh`
- **gh** —— 保留 git 凭据助手(HTTPS push 免密)、默认协议 https
- **helix** —— 主题、相对行号等;`.nix` 文件接 `nixd` + 保存自动 `nixfmt`
- **zellij** —— 基础 `config.kdl`(`default_shell=zsh`;未开自动进 zellij)

> 这些的设置都在 `programs.nix`,改完 `hms` 即生效并可同步到其它设备。
