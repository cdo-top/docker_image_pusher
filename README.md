# Docker Images Pusher

使用Github Action将国外的Docker镜像转存到阿里云私有仓库，供国内服务器使用，免费易用<br>
- 支持DockerHub, gcr.io, k8s.io, ghcr.io等任意仓库<br>
- 支持最大40GB的大型镜像<br>
- 使用阿里云的官方线路，速度快<br>
- 默认自动推送 linux/amd64 和 linux/arm64 双架构，并合并为多架构 manifest<br>

视频教程：https://www.bilibili.com/video/BV1Zn4y19743/

作者：**[技术爬爬虾](https://github.com/tech-shrimp/me)**<br>
B站，抖音，Youtube全网同名，转载请注明作者<br>

## 使用方式


### 配置阿里云
登录阿里云容器镜像服务<br>
https://cr.console.aliyun.com/<br>
启用个人实例，创建一个命名空间（**ALIYUN_NAME_SPACE**）
![](/doc/命名空间.png)

访问凭证–>获取环境变量<br>
用户名（**ALIYUN_REGISTRY_USER**)<br>
密码（**ALIYUN_REGISTRY_PASSWORD**)<br>
仓库地址（**ALIYUN_REGISTRY**）<br>

![](/doc/用户名密码.png)


### Fork本项目
Fork本项目<br>
#### 启动Action
进入您自己的项目，点击Action，启用Github Action功能<br>
#### 配置环境变量
进入Settings->Secret and variables->Actions->New Repository secret
![](doc/配置环境变量.png)
将上一步的**四个值**<br>
ALIYUN_NAME_SPACE,ALIYUN_REGISTRY_USER，ALIYUN_REGISTRY_PASSWORD，ALIYUN_REGISTRY<br>
配置成环境变量

### 添加镜像
打开images.txt文件，添加你想要的镜像 
可以加tag，也可以不用(默认latest)<br>
每个镜像默认自动拉取并推送 linux/amd64 和 linux/arm64 两种架构，并合并为多架构 manifest<br>
可使用 k8s.gcr.io/kube-state-metrics/kube-state-metrics 格式指定私库<br>
可使用 #开头作为注释<br>
![](doc/images.png)
文件提交后，自动进入Github Action构建

每次执行会先比较源仓库和阿里云目标仓库的镜像元数据，仅拉取、推送新增或内容发生变化的镜像。目标镜像内容相同则跳过，不重复下载镜像层；`latest` 等标签的上游更新也会被检测到。首次执行时，目标仓库已有且内容相同的镜像同样会跳过。检查失败（例如网络或认证错误）会终止任务，避免误判为无需更新。

比较脚本使用 Bash、Docker Buildx、`jq` 和 GNU `timeout`（GitHub Ubuntu runner 提供），不依赖 Python。按架构比较目标 `-linux-amd64`、`-linux-arm64` 标签的 config 和 layers，忽略索引 variant 元数据差异；未变化的架构不拉取推送。每次元数据请求默认最多等待 60 秒，可通过 `MANIFEST_TIMEOUT_SECONDS` 调整。日志会记录正在检查的镜像及比较结果。

### 使用镜像
回到阿里云，镜像仓库，点击任意镜像，可查看镜像状态。(可以改成公开，拉取镜像免登录)
![](doc/开始使用.png)

在国内服务器pull镜像, 例如：<br>
```
docker pull registry.cn-hangzhou.aliyuncs.com/shrimp-images/alpine
```
registry.cn-hangzhou.aliyuncs.com 即 ALIYUN_REGISTRY(阿里云仓库地址)<br>
shrimp-images 即 ALIYUN_NAME_SPACE(阿里云命名空间)<br>
alpine 即 阿里云中显示的镜像名<br>

### 多架构
默认自动支持 linux/amd64 和 linux/arm64 双架构，无需在 images.txt 中手动指定。

每个镜像推送后会自动创建多架构 manifest list，拉取时 Docker 客户端自动选择匹配本机架构的镜像：
```
nginx:1.25.3          ← manifest list（自动选择架构）
├── nginx:1.25.3-linux-amd64
└── nginx:1.25.3-linux-arm64
```

如需修改支持的架构，编辑 `.github/workflows/docker.yaml` 中的以下配置：
```bash
platforms=("linux/amd64" "linux/arm64")
```

### 镜像重名
程序自动判断是否存在名称相同, 但是属于不同命名空间的情况。
如果存在，会把命名空间作为前缀加在镜像名称前。
例如:
```
xhofe/alist
xiaoyaliu/alist
```
![](doc/镜像重名.png)

### 定时执行
当前 workflow 默认每 6 小时检查一次订阅镜像 `weishaw/sub2api:0.2.8`，也可通过 Actions 页面手动执行。代码 push 和手动执行仍处理 `images.txt` 中的完整列表。定时表达式使用 UTC 时区：
```yaml
schedule:
  - cron: '17 */6 * * *'
```
脚本只会拉取、推送新增或内容发生变化的镜像；即使标签名不变（例如 `latest` 或固定版本标签被重新发布），内容变化也会被检测到。修改 `.github/workflows/docker.yaml` 中的 `schedule` 可调整执行频率。
![](doc/定时执行.png)
