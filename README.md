# Asterisk EC20

Asterisk 22.11.0 + `biaide/asterisk-chan-quectel`，用于 Linux / 群晖的 EC20 AT 控制与 ALSA UAC 音频。GitHub Actions 构建 `linux/amd64` 和 `linux/arm64` 并推送到 GHCR。

## 构建与版本

- 推送 `main` 或在 Actions 中选择 **Build Asterisk EC20 Image → Run workflow** 触发构建。
- 使用仓库自动提供的 `GITHUB_TOKEN`，工作流声明 `contents: read`、`packages: write`，无需保存个人访问令牌用于构建。
- 首先推送 `ghcr.io/lhkuan/asterisk-ec20:sha-<完整提交 SHA>`。
- 检查远端 manifest 包含两种架构，并分别启动容器验证 `chan_quectel.so` 能加载；通过后，main 分支才更新 `latest` 和 `22.11.0`。
- `v*` 标签触发构建及检查，保留对应 SHA 镜像，不覆盖 main 的发布标签。
- 驱动固定为提交 `005f74f11a8bac5102e17a6d092136f20336f4db`；Asterisk 源码包固定 SHA256，避免源码漂移。

从官方 Asterisk 22.11.0 源码构建，校验 SHA256；驱动使用同一次构建安装的头文件。编译阶段与运行阶段均为 Debian Trixie，运行镜像不包含编译工具。禁用 BUILD_NATIVE，避免镜像依赖构建机器的 CPU 特性。amd64 与 arm64 使用各自原生 GitHub runner 编译并验证。

CI 不连接 EC20 硬件，也不会拨打电话。镜像构建与模块加载通过不等于蜂窝网络、SIP 注册或双向语音已经验收。

## GHCR 拉取权限

首次发布的包可能是私有的。私有包需先在 NAS 执行 `docker login ghcr.io -u lhkuan`，密码位置输入具有 `read:packages` 权限的个人访问令牌。不要把令牌写入 Compose 或仓库。

如果希望匿名拉取，可在 GitHub 的包设置中将该镜像包设为 Public。仓库公开不代表镜像包自动公开。

## 群晖准备

1. DSM 宿主机必须识别 EC20 的 AT 口及 UAC 声卡；容器不能代替缺失的宿主机 USB/声音驱动。
2. 确认 `/dev/ttyUSB2` 是 AT 口，并检查 `/dev/snd`。需要改 AT 口时，在 `.env` 设置 `EC20_AT_DEVICE`；容器内始终映射为 `/dev/ttyUSB2`。
3. 在项目目录创建 `.env`。将下面命令输出的组 ID 填入，声卡编号以实际设备为准：

```sh
stat -c '%g' /dev/ttyUSB2
stat -c '%g' /dev/snd/controlC0
```

```dotenv
SERIAL_GID=填入串口设备组ID
AUDIO_GID=填入声音设备组ID
EC20_AT_DEVICE=/dev/ttyUSB2
IMAGE_TAG=22.11.0
```

Compose 默认以镜像中的 Asterisk 用户 UID/GID 1000:1000 运行，并添加宿主机设备组。如果有既有数据卷，确保其所有者与运行 UID/GID 一致。不要仅修改 UID 而不修正数据卷权限。

## Asterisk 配置

在 `config/` 放置自己的四个配置文件：`pjsip.conf`、`extensions.conf`、`quectel.conf`、`rtp.conf`。Compose 对每个文件单独挂载，并在文件不存在时直接报错；不会把空目录挂载到配置文件位置。

`quectel.conf` 的 UAC 示例：

```ini
[general]
interval=15

[defaults]
context=from-ec20
group=0
disablesms=yes
autodeletesms=no
initstate=start

[quectel0]
data=/dev/ttyUSB2
quec_uac=1
alsadev=hw:CARD=Android,DEV=0
```

`alsadev` 必须替换成实际 ALSA 卡名称。此驱动读取的是 `quec_uac=1`，不能写成 `uac=yes`。UAC 模式不需要映射串口音频端口。`from-ec20` 应与拨号计划上下文一致。示例关闭短信接收；需要短信时再按上游限制配置。

SIP 密码、手机号及拨号规则由本地配置提供，`config/` 和 `.env` 已被 Git 忽略，且 Docker 构建上下文仅包含 Dockerfile。按需限制 SIP/RTP 为可信局域网访问；不要把可拨打外线的分机直接暴露到公网。

## 启动与检查

```sh
docker compose pull
docker compose up -d
docker compose logs --tail=100
docker compose exec asterisk-ec20 asterisk -rx 'module show like chan_quectel.so'
docker compose exec asterisk-ec20 asterisk -rx 'quectel show devices'
docker compose exec asterisk-ec20 aplay -l
docker compose exec asterisk-ec20 arecord -l
```

升级仍使用 `docker compose pull && docker compose up -d`。需要保留特定构建时，将 `.env` 的 `IMAGE_TAG` 设置为已验证的 `sha-<完整提交 SHA>`。

EC20 的 UAC 配置、SIM/运营商语音能力、USB 供电与实际通话质量仍需在设备端测试。启动 Asterisk 后不要同时让其他程序占用 AT 串口。

## 上游

- [Asterisk Docker 基础镜像](https://github.com/andrius/asterisk)
- [EC20 / chan_quectel 源码](https://github.com/biaide/asterisk-chan-quectel/tree/005f74f11a8bac5102e17a6d092136f20336f4db)
- [Docker 多架构 GitHub Actions 文档](https://docs.docker.com/build/ci/github-actions/multi-platform/)

基础镜像及驱动各自的许可证仍适用。
