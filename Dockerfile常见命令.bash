# Dockerfile常见命令
FROM image_name:tag
MAINTAINER user_name                    #声明镜像的作者
ENV key value                           #设置环境变量 (可写多条)
RUN command                             #编译镜像时,运行的脚本(可写多条)
CMD                                     #设置容器的启动命令
ENTRYPOINT                              #设置容器的入口程序
ADD source_dir/file dest_dir/file       #将宿主机文件复制到容器内，复制后,自动解压压缩文件
COPY source_dir/file dest_dir/file      #和ADD相似，不解压压缩文件
WORKDIR path_dir                        #设置工作目录
ARG                                     #设置编译镜像时,加入的参数
VOLUMN                                  #设置容器的挂载卷

镜像从基础镜像一层一层叠加生成
# 每安装一个软件，就在现有镜像基础上增加一层
基础：
kernel(bootfs)、baseImage、image

# RUN、CMD、ENTRYPOINT区别
RUN： 
#指定 docker build 过程中运行的命令，即创建 Docker 镜像（image）的步骤
CMD： 
#设置容器的启动命令， Dockerfile 中，只能有一条 CMD 命令，如果写了多条则最后一条生效，CMD不接收docker run的参数
ENTRYPOINT： 
#入口程序，容器启动时执行的程序， docker run后跟的命令，将作为参数传递给入口程序，ENTRYPOINY类似 CMD 指令，但可以接收docker run参数

# ---------------------------mysql官方镜像Dockerfile：
FROM oraclelinux:7-slim
ARG MYSQL_SERVER_PACKAGE=mysql-community-server-minimal-5.7.28
ARG MYSQL_SHELL_PACKAGE=mysql-shell-8.0.18
# Install server
RUN yum install -y https://repo.mysql.com/mysql-community-minimal-releaseel7.rpm https://repo.mysql.com/mysql-community-release-el7.rpm \
&& yum-config-manager --enable mysql57-server-minimal \
&& yum install -y $MYSQL_SERVER_PACKAGE $MYSQL_SHELL_PACKAGE libpwquality \
&& yum clean all \
&& mkdir /docker-entrypoint-initdb.d
VOLUME /var/lib/mysql
COPY docker-entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /healthcheck.sh
ENTRYPOINT ["/entrypoint.sh"]
#健康检查
HEALTHCHECK CMD /healthcheck.sh
#端口映射
EXPOSE 3306 33060       
CMD ["mysqld"]

# ------------------------------制作微服务镜像
# 利用Dockerfile制作Eureka注册中心镜像
1）上传Eureka微服务jar包到linux
# 2）编写Dockerfile
FROM openjdk:8-jdk-alpine
#定义参数，构建时传入参数值
ARG JAR_FILE
#引用参数
COPY ${JAR_FILE} app.jar
#仅指定容器开放端口
EXPOSE 10086
ENTRYPOINT ["java","-jar","/app.jar"]
# 3）构建镜像，传参
docker build --build-arg JAR_FILE=tensquare_eureka_server-1.0-SNAPSHOT.jar -t eureka:v1 .
# 4）查看镜像
docker images
# 5）创建容器
docker run -i --name=eureka -p 10086:10086 eureka:v1
# 6）访问容器
http://192.168.66.101:10086
