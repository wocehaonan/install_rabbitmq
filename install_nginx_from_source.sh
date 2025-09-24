# nginx一键安装脚本
~~~bash
#!/bin/bash
# =========================================
# 脚本名称: install_nginx_from_source.sh
# 功能: 从源码安装 Nginx 到 /data/nginx
# 系统: CentOS / RHEL 系列
# =========================================

# ---------- 参数配置 ----------
NGINX_VERSION="1.18.0"
NGINX_PREFIX="/data/nginx"
NGINX_TARBALL="nginx-${NGINX_VERSION}.tar.gz"
NGINX_URL="https://nginx.org/download/${NGINX_TARBALL}"
SRC_DIR="/usr/local/src/nginx-${NGINX_VERSION}"   # 源码临时目录
CONF_DIR="${NGINX_PREFIX}/conf/conf.d"
TRASH_DIR="/data/trash"

# ---------- 步骤 0：准备目录 ----------
echo "[1/7] 创建目录..."
mkdir -p "${NGINX_PREFIX}" "${TRASH_DIR}" "/usr/local/src"
cd "/usr/local/src" || exit 1

# ---------- 步骤 1：安装依赖 ----------
echo "[2/7] 安装编译依赖..."
yum groupinstall -y "Development Tools"
yum install -y pcre pcre-devel zlib zlib-devel openssl openssl-devel wget

# ---------- 步骤 2：下载源码 ----------
echo "[3/7] 下载 Nginx 源码..."
if [ ! -f "${NGINX_TARBALL}" ]; then
    wget "${NGINX_URL}"
fi

# ---------- 步骤 3：解压 & 编译 ----------
echo "[4/7] 解压并编译安装 Nginx..."
tar -xzf "${NGINX_TARBALL}"
cd "nginx-${NGINX_VERSION}" || exit 1

./configure --prefix="${NGINX_PREFIX}" \
  --pid-path="${NGINX_PREFIX}/nginx.pid" \
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-stream

make && make install

# ---------- 步骤 4：配置 conf.d ----------
echo "[5/7] 配置 conf.d 目录..."
mkdir -p "${CONF_DIR}"

# 在 nginx.conf 尾部添加 include（如果没有添加过）
CONF_MAIN="${NGINX_PREFIX}/conf/nginx.conf"
if ! grep -q "include conf.d/\*.conf;" "${CONF_MAIN}"; then
    echo -e "\n    include conf.d/*.conf;" >> "${CONF_MAIN}"
    echo "✅ 已在 nginx.conf 中添加 include conf.d/*.conf;"
else
    echo "⚠️ nginx.conf 中已存在 include conf.d/*.conf; 跳过"
fi

# ---------- 步骤 5：移动源码和安装包到 /data/trash ----------
echo "[6/7] 清理源码文件..."
mv "/usr/local/src/${NGINX_TARBALL}" "${TRASH_DIR}/" 2>/dev/null || true
mv "/usr/local/src/nginx-${NGINX_VERSION}" "${TRASH_DIR}/" 2>/dev/null || true
echo "✅ 已将源码和安装包移动到 ${TRASH_DIR}"

# ---------- 步骤 6：添加 systemd 服务 ----------
echo "[7/7] 创建 systemd 服务文件..."
cat >/etc/systemd/system/nginx.service <<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=network.target

[Service]
Type=forking
PIDFile=${NGINX_PREFIX}/nginx.pid
ExecStartPre=${NGINX_PREFIX}/sbin/nginx -t
ExecStart=${NGINX_PREFIX}/sbin/nginx
ExecReload=${NGINX_PREFIX}/sbin/nginx -s reload
ExecStop=${NGINX_PREFIX}/sbin/nginx -s stop
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload

# ---------- 结果提示 ----------
echo "✅ Nginx 源码安装完成！"
echo "📁 安装路径: ${NGINX_PREFIX}"
echo "📁 配置目录: ${NGINX_PREFIX}/conf"
echo "📁 虚拟主机配置目录: ${CONF_DIR}"
echo "🗑️ 源码和安装包已移动到: ${TRASH_DIR}"
echo
echo "✅ 启动:   ${NGINX_PREFIX}/sbin/nginx"
echo "✅ 停止:   ${NGINX_PREFIX}/sbin/nginx -s stop"
echo "✅ 重载:   ${NGINX_PREFIX}/sbin/nginx -s reload"
echo "✅ 或使用 systemd:"
echo "   systemctl start nginx"
echo "   systemctl enable nginx"
~~~