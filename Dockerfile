# 使用官方 Ubuntu 作为基础镜像
FROM ubuntu:22.04

# 更新系统并安装 Webmin 依赖
RUN apt-get update && \
    apt-get install -y wget perl sudo && \
    wget http://prdownloads.sourceforge.net/webadmin/webmin_2.230_all.deb && \
    dpkg --install webmin_2.230_all.deb || apt-get -f install -y && \
    rm webmin_2.230_all.deb

# 设置 root 密码为 root
RUN echo "root:root" | chpasswd

# 暴露 Webmin 默认端口
EXPOSE 10000

# 启动 Webmin
CMD ["/usr/share/webmin/miniserv.pl", "/etc/webmin/miniserv.conf"]
