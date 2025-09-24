# rabbitmq一键安装脚本
~~~bash
#!/bin/bash

set -e

INSTALL_DIR="/data"
ERLANG_VERSION="OTP-25.3"
ERLANG_SRC_VERSION="25.3"
RABBITMQ_VERSION="3.12.2"
ERLANG_DIR="$INSTALL_DIR/erlang"
RABBITMQ_DIR="$INSTALL_DIR/rabbitmq"
OTP_REPO="$INSTALL_DIR/otp"
TRASH_DIR="$INSTALL_DIR/trash"
SERVICE_FILE="/etc/systemd/system/rabbitmq.service"

RABBITMQ_FILE="rabbitmq-server-generic-unix-${RABBITMQ_VERSION}.tar.xz"
RABBITMQ_URL="https://mirrors.huaweicloud.com/rabbitmq-server/v${RABBITMQ_VERSION}/$RABBITMQ_FILE"

ERLANG_TAR="otp_src_${ERLANG_SRC_VERSION}.tar.gz"
ERLANG_SRC_DIR="otp_src_${ERLANG_SRC_VERSION}"

# 0. 创建 trash 目录
mkdir -p "$TRASH_DIR"

echo "1. 安装依赖包"
yum install -y wget gcc gcc-c++ glibc-devel make ncurses-devel openssl-devel xmlto perl tar unzip git xz

echo "2. 克隆 Erlang 源码仓库"
if [ -d "$OTP_REPO" ]; then
  echo "Erlang 源码目录已存在，跳过克隆"
elif [ -d "$TRASH_DIR/otp" ]; then
  echo "Erlang 源码目录已在 trash 中，跳过克隆"
else
  git clone https://gitee.com/mirrors/otp.git "$OTP_REPO"
fi

if [ -d "$OTP_REPO" ]; then
  cd "$OTP_REPO"
  git fetch --all --tags

  echo "3. 切换到 Erlang 版本 $ERLANG_VERSION"
  if [ "$(git rev-parse --abbrev-ref HEAD)" != "$ERLANG_VERSION" ]; then
    git checkout $ERLANG_VERSION
  else
    echo "已处于 $ERLANG_VERSION 分支，跳过切换"
  fi
  cd -
else
  echo "跳过 Erlang 版本切换，因为源码目录在 trash 中"
fi

echo "4. 编译并安装 Erlang"
if [ -x "$ERLANG_DIR/bin/erl" ]; then
  echo "Erlang 已安装，跳过编译"
elif [ -d "$TRASH_DIR/$ERLANG_SRC_DIR" ]; then
  echo "$ERLANG_SRC_DIR 已在 trash 中，跳过编译"
else
  if [ ! -f "$ERLANG_TAR" ] && [ ! -f "$TRASH_DIR/$ERLANG_TAR" ]; then
    wget "https://erlang.org/download/$ERLANG_TAR"
  fi

  if [ -f "$ERLANG_TAR" ]; then
    tar -zxf "$ERLANG_TAR"
    cd "$ERLANG_SRC_DIR"
    ./configure --prefix=$ERLANG_DIR
    make -j$(nproc)
    make install
    cd ..
    mv "$ERLANG_TAR" "$TRASH_DIR/" || true
    mv "$ERLANG_SRC_DIR" "$TRASH_DIR/" || true
  else
    echo "跳过 Erlang 安装（源码包已在 trash 中）"
  fi
fi

echo "5. 配置环境变量"
if ! grep -q "$ERLANG_DIR/bin" /etc/profile; then
  echo "export PATH=$ERLANG_DIR/bin:\$PATH" >> /etc/profile
  echo "[Info] Erlang 路径已添加到 /etc/profile"
fi
export PATH=$ERLANG_DIR/bin:$PATH
source /etc/profile

echo "6. 下载并安装 RabbitMQ"
cd $INSTALL_DIR

if [ -d "$RABBITMQ_DIR" ]; then
  echo "RabbitMQ 已存在，跳过安装"
elif [ -d "$TRASH_DIR/rabbitmq_server-${RABBITMQ_VERSION}" ]; then
  echo "RabbitMQ 解压目录已在 trash 中，跳过安装"
else
  if [ ! -f "$RABBITMQ_FILE" ] && [ ! -f "$TRASH_DIR/$RABBITMQ_FILE" ]; then
    wget -c "$RABBITMQ_URL"
  fi

  if [ -f "$RABBITMQ_FILE" ]; then
    tar -xf "$RABBITMQ_FILE"
    extracted_dir=$(tar -tf "$RABBITMQ_FILE" | head -1 | cut -f1 -d"/")
    mv "$extracted_dir" "$RABBITMQ_DIR"
    mv "$RABBITMQ_FILE" "$TRASH_DIR/"
  else
    echo "跳过 RabbitMQ 解压（压缩包已在 trash 中）"
  fi
fi

export RABBITMQ_HOME=$RABBITMQ_DIR
export PATH=$RABBITMQ_HOME/sbin:$PATH

echo "7. 启用 rabbitmq_management 插件"
if ! rabbitmq-plugins list -e | grep -q rabbitmq_management; then
  rabbitmq-plugins enable rabbitmq_management
else
  echo "插件 rabbitmq_management 已启用"
fi

echo "8. 创建配置与数据目录"
mkdir -p $RABBITMQ_HOME/data
mkdir -p $RABBITMQ_HOME/log
mkdir -p $RABBITMQ_HOME/etc/rabbitmq

if [ ! -f "$RABBITMQ_HOME/etc/rabbitmq/rabbitmq-env.conf" ]; then
  cat > "$RABBITMQ_HOME/etc/rabbitmq/rabbitmq-env.conf" <<EOF
RABBITMQ_MNESIA_BASE=$RABBITMQ_HOME/data
RABBITMQ_LOG_BASE=$RABBITMQ_HOME/log
EOF
fi

echo "9. 启动 RabbitMQ（首次）"
if ! pgrep -f rabbitmq-server > /dev/null; then
  $RABBITMQ_HOME/sbin/rabbitmq-server -detached
else
  echo "RabbitMQ 正在运行"
fi

sleep 5

echo "10. 创建 RabbitMQ 用户 admin/admin123"
if ! rabbitmqctl list_users | grep -q admin; then
  rabbitmqctl add_user admin admin123
  rabbitmqctl set_user_tags admin administrator
  rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
else
  echo "用户 admin 已存在"
fi

echo "11. 配置防火墙"
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=5672/tcp || true
  firewall-cmd --permanent --add-port=15672/tcp || true
  firewall-cmd --reload || true
fi

echo "12. 清理中间文件"
mkdir -p "$TRASH_DIR"
[ -f "$INSTALL_DIR/$RABBITMQ_FILE" ] && mv "$INSTALL_DIR/$RABBITMQ_FILE" "$TRASH_DIR/"
[ -d "$OTP_REPO" ] && mv "$OTP_REPO" "$TRASH_DIR/"
[ -d "$INSTALL_DIR/rabbitmq_server-${RABBITMQ_VERSION}" ] && mv "$INSTALL_DIR/rabbitmq_server-${RABBITMQ_VERSION}" "$TRASH_DIR/"

echo "13. 配置 systemd 服务"
if [ ! -f "$SERVICE_FILE" ]; then
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=RabbitMQ service (custom)
After=network.target

[Service]
Type=simple
User=root
Environment=PATH=/data/erlang/bin:/data/rabbitmq/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=RABBITMQ_MNESIA_BASE=/data/rabbitmq/data
Environment=RABBITMQ_LOG_BASE=/data/rabbitmq/log
WorkingDirectory=/data/rabbitmq
ExecStart=/data/rabbitmq/sbin/rabbitmq-server
ExecStop=/data/rabbitmq/sbin/rabbitmqctl stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable rabbitmq
  systemctl restart rabbitmq
  systemctl status rabbitmq
  systemctl stop rabbitmq
echo -e "\e[1;32m"
echo "============================================================"
echo "✅ RabbitMQ systemd 服务测试正常！"
echo "⚠️  脚本执行结束后请执行：systemctl restart rabbitmq"
echo "============================================================"
echo -e "\e[0m"
else
  echo "RabbitMQ systemd 服务已存在，跳过创建"
fi

echo
echo "✅ RabbitMQ 安装并配置完成！"
echo "👉 Web 管理地址: http://<服务器IP>:15672"
echo "👉 用户名：admin"
echo "👉 密码：admin123"
echo "👉 启动管理: systemctl status|start|stop rabbitmq"


~~~