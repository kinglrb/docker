#!/bin/bash
libseccompPack=libseccomp-2.5.1-1.el8.x86_64.rpm
containerdPack=cri-containerd-cni-1.4.11-linux-amd64.tar.gz
sandbox_pause="registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.5"
endpoint="https://1nj0zren.mirror.aliyuncs.com"

echoVariable(){
	echo $libseccompPack
	echo $containerdPack
	echo $sandbox_pause
	echo $endpoint
	# return  echo $containerdPack|awk -F"-" '{print $4}'  #返回值，只能返回数值.可赋值
}

# ----------------------docker引擎切换为containerd
# 1,停止 docker 和 kubelet
stopDockerKuberlet(){
	systemctl stop kubelet
	systemctl stop docker
	systemctl stop containerd
	systemctl disable docker
}

# 2,清理docker
cleanDockerContainterd(){
	#--------------------------------清理
	rm -f /etc/crictl.yaml
	rm -f /etc/systemd/system/containerd.service
	rm -f /usr/lib/systemd/system/containerd.service
	# ---------------------------------
	for dir in /usr/local/sbin/ /usr/local/bin/ /usr/bin/
	do
		for script in runc containerd-shim-runc-v1 ctr containerd-shim-runc-v2 containerd-stress critest crictl containerd-shim containerd ctd-decoder docker dockerd docker-proxy docker-init
		do
			# echo "--------------开始清理程序文件-------------------"	
			rm -f $dir$script
			# echo "--------------查验下-------------------"
			if [ `ls $dir|grep $script|wc -l` == 0 ]
			then
				echo "--------------$dir$script已清理或不存在-------------------"
			else
				echo $dir$script"文件未能清理"
			fi
		done
	done
	for dir in /opt/docker /opt/cni /opt/containerd /etc/cni /opt/king/containerd
	do
		# echo "--------------开始清理，打印目录-------------------"
		# ls $dir
		# echo "--------------目录内容清单打印完毕，开始删除-------------------"
		rm -rf $dir
		echo "--------------docker目录清理完毕，对比结果-------------------"
		ls $dir
	done
	
	for dir in etc  opt  usr addAli.cfg
		do
			rm -rf /opt/king/$dir
	done
}

# 3,安装(2.5.1版)libseccomp依赖库
install_Libseccomp(){
	echo "--------------清理旧版libseccomp-------------------"
	if [ `rpm -qa|grep libseccomp|grep 2.5.1|wc -l` -ne 0 ]
	then
		echo  "libseccomp版本OK，跳过"
	else
		if [ `rpm -qa|grep libseccomp|wc -l` -gt 0 ]
		then
			rpm -e --nodeps libseccomp-devel-2.3.1-4.el7.x86_64
			rpm -e --nodeps libseccomp-2.3.1-4.el7.x86_64
			# rpm -qa|grep libseccomp
		fi
		# yum install -y libseccomp libseccomp-devel
		cd /opt/king
		if [ -z `rpm -qa|grep libseccomp` ]
		then
			echo "开始安装libseccomp"
			cd /opt/king
			yum install libseccomp-2.5.1-1.el8.x86_64.rpm
			yum install libseccomp-devel-2.5.1-1.el8.x86_64.rpm
			echo "依赖库已安装"
		fi
	fi
	echo "--------------libseccomp版本对比-------------------"
	rpm -qa|grep libseccomp
}

# 4,系统参数配置
sysParameterConf(){
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

	if [ `cat /etc/sysctl.d/99-kubernetes-cri.conf|grep net.ipv4.ip_forward|awk '{print $3}'`==1 ]
	then
		sudo sysctl --system
	else
		exit 1
		echo "参数配置失败"
	fi

# 配置先决条件
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
	sudo modprobe overlay
	sudo modprobe br_netfilter
}

# 5,安装前后文件比对检查
function checkFilePath(){
	echo "-------------------开始验证-----------------------"
	if [ -d /opt/containerd ]
	then
		echo "/opt/containerd目录存在"
		# y|cp /opt/containerd/* /usr/bin/
	else
		echo "/opt/containerd目录不存在"
	fi	
	ls /opt/cni/
	echo "检查执行程序"
	# cat /etc/systemd/system/containerd.service
	ls /usr/local/bin/|grep containerd
	echo "-------------------验证结束-----------------------"
}

# 6,安装containerd
installContainerd(){
	echo "###########################解压###################################"
	if [ -e /opt/src/$containerdPack ]
	then
		# tar -tf /opt/src/$containerdPack
		mkdir -p /opt/king/containerd
		tar -C /opt/king/containerd -xzf /opt/src/$containerdPack
		for dir in etc  opt  usr
		do
			if [ -e /opt/king/containerd/$dir ]
			then
				#部署安装文件
				y|cp -r /opt/king/containerd/$dir/* /$dir/
			else
				echo "$dir目录未生成退出，请检查"
				exit 1
			fi
		done
		source /etc/profile
	else
		echo "压缩文件未上传"
		exit 1
	fi
}

# 7、配置containerd的config.toml文件
containerdConf(){
	#生成配置
	mkdir -p /etc/containerd
	if [ -e /usr/local/bin/containerd ]
	then
		echo "生成containerd默认配置文件"
		containerd config default > /etc/containerd/config.toml
	else
		echo "文件不存在，请检查解压"
		exit 1
	fi

	# 修改config.toml配置
	# sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
	sed -i '/sandbox_image/s/=.*/= "registry.cn-hangzhou.aliyuncs.com\/google_containers\/pause:3.5"/g' /etc/containerd/config.toml

cat >/opt/king/containerd/addAli.cfg<<EOF
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."1nj0zren.mirror.aliyuncs.com"]
          endpoint = ["https://1nj0zren.mirror.aliyuncs.com"]
EOF
	if [ -z `cat -n /etc/containerd/config.toml |egrep "endpoint"` ]
	then
		echo "没有endpoint地址，添加"
		sed -i '/plugins."io.containerd.grpc.v1.cri".registry.mirrors/ r /opt/king/containerd/addAli.cfg' /etc/containerd/config.toml
	else
		# sed -i '/endpoint/s/https.*/https:\/\/1nj0zren.mirror.aliyuncs.com"\]/g' /etc/containerd/config.toml
		echo "可能存在多个endpoint，请确认文件，再替换"
	fi
	cat -n /etc/containerd/config.toml |egrep "sandbox_image|SystemdCgroup|endpoint"
}

#8,配置crictl工具
crictlConf_ctr(){
	# if [ -!e /etc/crictl.yaml]
	echo "------------------配置客户端------------------"
cat >/etc/crictl.yaml<<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

if [ -e /usr/local/bin/ctr ]
then
	if [ -x /usr/local/bin/ctr ]
	then
		ctr version
	fi
else
	echo "/usr/local/bin/ctr不存在或不可执行"
fi
}

# 9、配置kubelet启动参数，使用containerd容器运行时
kubeletConf(){
	# cat > /etc/sysconfig/kubelet<<EOF
	# KUBELET_EXTRA_ARGS="--container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock --cgroup-driver=systemd"
	# EOF
cat > /opt/kubernetes/cfg/kubelet.conf << EOF
KUBELET_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--hostname-override=$hostName \\
--network-plugin=cni \\
--kubeconfig=/opt/kubernetes/cfg/kubelet.kubeconfig \\
--bootstrap-kubeconfig=/opt/kubernetes/cfg/bootstrap.kubeconfig \\
--config=/opt/kubernetes/cfg/kubelet-config.yml \\
--cert-dir=/opt/kubernetes/ssl \\
--pod-infra-container-image=registry.aliyuncs.com/google_containers/pause:3.5 \\
--container-runtime=remote \\
--container-runtime-endpoint=unix:///run/containerd/containerd.sock \\
--cgroup-driver=systemd"
EOF
}

# 10,重启系统
restartContainerdKubelet(){
	# 重启containerd
	echo "----------------开始重启--------------"
	if [ -e /etc/containerd/config.toml ]
	then
		systemctl daemon-reload
		systemctl start containerd
		# systemctl enable containerd
		# systemctl restart containerd
		systemctl status containerd
	else
		echo "/etc/containerd/config.toml文件不存在"
		exit 1
	fi
	# 重启kubelet
	if [ $?==0 ]
	then
		systemctl restart kubelet
		systemctl status kubelet
	else
		echo "containerd启动故障，请排查"
	fi
}

# 11,查看容器引擎是否成功切换为containerd
checkContainerdInK8s(){
	ip=`hostname -i`
	if [ $ip = "192.168.1.35" -o $ip = "192.168.1.36" ]
	then
		kubectl get node -o wide
		kubectl get pod -n kube-system
		echo "本机IP为："$ip	
	fi
}

# ------------------------------------调用执行---------------------
# echoVariable
# echo "安装版本为"$?

stopDockerKuberlet
cleanDockerContainterd
# install_Libseccomp
# sysParameterConf

checkFilePath
installContainerd
checkFilePath

containerdConf
# kubeletConf
restartContainerdKubelet
crictlConf_ctr
checkContainerdInK8s