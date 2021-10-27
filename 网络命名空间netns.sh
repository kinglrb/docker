# -------------------------------------------手动创建命名空间，并配置互通--------
# add the namespaces
ip netns add ns1
ip netns add ns2
# create the veth pair
ip link add tap1 type veth peer name tap2
# move the interfaces to the namespaces
ip link set tap1 netns ns1
ip link set tap2 netns ns2
# bring up the links
ip netns exec ns1 ip link set dev tap1 up
ip netns exec ns2 ip link set dev tap2 up

# 多个network namespace通信，则需借助bridge
# add the namespaces
ip netns add ns1
ip netns add ns2
# create the switch
BRIDGE=br-test
brctl addbr $BRIDGE
brctl stp   $BRIDGE off
ip link set dev $BRIDGE up
#### PORT 1
# create a port pair
ip link add tap1 type veth peer name br-tap1
# attach one side to linuxbridge
brctl addif br-test br-tap1
# attach the other side to namespace
ip link set tap1 netns ns1
# set the ports to up
ip netns exec ns1 ip link set dev tap1 up
ip link set dev br-tap1 up
# 解释：
ip link set tap1 netns ns1
	----<ip link add  tap1 type veth peer name br-tap1>   
		----brctl addif br-test br-tap1
#### PORT 2
# create a port pair
ip link add tap2 type veth peer name br-tap2
# attach one side to linuxbridge
brctl addif br-test br-tap2  ###把所有 br-tap2i连到桥br-test
# attach the other side to namespace
ip link set tap2 netns ns2###把所有 br-tap2i的对端连到namespace
# set the ports to up
ip netns exec ns2 ip link set dev tap2 up
ip link set dev br-tap2 up
# 内核实现
veth的实现与loopback interface类似

# docker(container)虚拟网络
host创建一个虚拟bridge，
	每个container对应一个虚拟网络设备(TAP设备)，与bridge一起构成一个虚拟网络，
		host内部container内部互访，通过虚拟bridge相互通信。
	Host的物理网络设备eth0，作为内部虚拟网络的NAT网关，container通过eth0访问外部网络。
ifconfig
brctl show
# container通过NAT访问外部网络
-t nat -A POSTROUTING -s 127.0.0.0/8 ! -d 127.0.0.0/8 -j MASQUERADE
	127.0.0.0/8是内部container网络，
		如果目标地址非内部虚拟网络，则进行NAT转换
# 外部网络访问container，通过DNAT实现
-t nat -A DOCKER ! -i docker0 -p tcp -m tcp --dport 49153 -j DNAT --to-destination 127.0.0.3:22
	127.0.0.3: 22是内部container的ip和sshd端口，在host上映射为49153端口
docker port test_sshd 22

# docker网络结构，是VMWare/KVM的NAT模式
	# container内网不暴露给外部，采用NAT方式
与host在同一网络，采用桥接模型
