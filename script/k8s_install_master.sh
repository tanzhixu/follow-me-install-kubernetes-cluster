#!/bin/sh

# BASE CONFIG
#---------------------------------------
DEPLOYDIR="/data"
BINDIR="/root/local/bin"
SSLCONFDIR=$DEPLOYDIR/ssl
KUBESSLDIR="/etc/kubernetes/ssl"
ETCDSSLDIR="/etc/etcd/ssl"
FLANNELDDIR="/etc/flanneld/ssl"
HARBORDIR="/etc/harbor/ssl"
DOCKERDIR="/etc/docker"
YAML=$DEPLOYDIR/yaml

mkdir -p $DEPLOYDIR
mkdir -p $BINDIR
mkdir -p $SSLCONFDIR
mkdir -p $KUBESSLDIR
mkdir -p $ETCDSSLDIR
mkdir -p $FLANNELDDIR
mkdir -p $DOCKERDIR
mkdir -p $HARBORDIR
mkdir -p /root/.kube/
mkdir -p $YAML/dashboard
mkdir -p $YAML/dns
mkdir -p $YAML/heapster

cat > $BINDIR/environment.sh << EOF
#TLS Bootstrapping 使用的 Token，可以使用命令 head -c 16 /dev/urandom | od -An -t x | tr -d ' ' 生成
BOOTSTRAP_TOKEN="41f7e4ba8b7be874fcff18bf5cf41a7c"
NODE_NAME="etcd-host0"
NODE_IP="10.10.7.175"
NODE_IPS="10.10.7.175 10.10.7.176 10.10.7.177"
MASTER_IP="10.10.7.175"
KUBE_APISERVER="https://10.10.7.175:6443"
ETCD_NODES="etcd-host0=https://10.10.7.175:2380,etcd-host1=https://10.10.7.176:2380,etcd-host2=https://10.10.7.177:2380"
SERVICE_CIDR="10.254.0.0/16"
CLUSTER_CIDR="172.30.0.0/16"
NODE_PORT_RANGE="8400-9000"
ETCD_ENDPOINTS="https://10.10.7.175:2379,https://10.10.7.176:2379,https://10.10.7.177:2379"
FLANNEL_ETCD_PREFIX="/kubernetes/network"
CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"
CLUSTER_DNS_SVC_IP="10.254.0.2"
CLUSTER_DNS_DOMAIN="cluster.local."
REGISTRY_DOMAIN="harbor.gqichina.com"
BASE_PODS="harbor.gqichina.com/k8s/pod-infrastructure:rhel7"
EOF

source $BINDIR/environment.sh
echo "export PATH=$BINDIR:\$PATH" >> /etc/profile
source /etc/profile

service iptables stop >/dev/null 2>&1
yum -y install wget
echo "net.ipv4.ip_forward = 1" >> /usr/lib/sysctl.d/50-default.conf
sysctl -p

# BASE CONFIG SUCCESS
#---------------------------------------

# DOWDLOAD PACKAGE
echo "Downloading package:"
cd $DEPLOYDIR
if [ ! -f "$DEPLOYDIR/cfssl_linux-amd64" ]; then
  wget -c https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 --no-check-certificate -P $DEPLOYDIR
fi
if [ ! -f "$DEPLOYDIR/cfssljson_linux-amd64" ]; then
  wget -c https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 --no-check-certificate -P $DEPLOYDIR
fi
if [ ! -f "$DEPLOYDIR/cfssl-certinfo_linux-amd64" ]; then
  wget -c https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64 --no-check-certificate -P $DEPLOYDIR
fi
if [ ! -f "$DEPLOYDIR/etcd-v3.1.6-linux-amd64.tar.gz" ]; then
  wget -c https://github.com/coreos/etcd/releases/download/v3.1.6/etcd-v3.1.6-linux-amd64.tar.gz -P $DEPLOYDIR
fi
if [ ! -f "$DEPLOYDIR/kubernetes-client-linux-amd64.tar.gz" ]; then
  wget -c https://dl.k8s.io/v1.6.2/kubernetes-client-linux-amd64.tar.gz -P $DEPLOYDIR
fi
if [ ! -f "$DEPLOYDIR/kubernetes-server-linux-amd64.tar.gz" ]; then
  wget -c https://dl.k8s.io/v1.6.2/kubernetes-server-linux-amd64.tar.gz -P $DEPLOYDIR
fi
if [ ! -f "$DEPLOYDIR/flannel-v0.7.1-linux-amd64.tar.gz" ]; then
  wget -c https://github.com/coreos/flannel/releases/download/v0.7.1/flannel-v0.7.1-linux-amd64.tar.gz -P $DEPLOYDIR
fi
if [ ! -f "$DEPLOYDIR/docker-17.04.0-ce.tgz" ]; then
  wget -c https://get.docker.com/builds/Linux/x86_64/docker-17.04.0-ce.tgz -P $DEPLOYDIR
fi
# COPY PACKAGE TO CLUSTER
ssh -p 6123 root@10.10.7.176 "mkdir -p $DEPLOYDIR"
ssh -p 6123 root@10.10.7.177 "mkdir -p $DEPLOYDIR"
scp -P 6123 cfssl* root@10.10.7.176:$DEPLOYDIR/ >/dev/null 2>&1
scp -P 6123 etcd-v3.1.6-linux-amd64.tar.gz root@10.10.7.176:$DEPLOYDIR/ >/dev/null 2>&1
scp -P 6123 kubernetes* root@10.10.7.176:$DEPLOYDIR/ >/dev/null 2>&1
scp -P 6123 flannel-v0.7.1-linux-amd64.tar.gz root@10.10.7.176:$DEPLOYDIR/ >/dev/null 2>&1
scp -P 6123 docker-17.04.0-ce.tgz root@10.10.7.176:$DEPLOYDIR/ >/dev/null 2>&1

scp -P 6123 cfssl* root@10.10.7.177:$DEPLOYDIR/ >/dev/null 2>&1
scp -P 6123 etcd-v3.1.6-linux-amd64.tar.gz root@10.10.7.177:$DEPLOYDIR/ >/dev/null 2>&1
scp -P 6123 kubernetes* root@10.10.7.177:$DEPLOYDIR/ >/dev/null 2>&1
scp -P 6123 flannel-v0.7.1-linux-amd64.tar.gz root@10.10.7.177:$DEPLOYDIR/ >/dev/null 2>&1
scp -P 6123 docker-17.04.0-ce.tgz root@10.10.7.177:$DEPLOYDIR/ >/dev/null 2>&1
echo "Package copy success................................."
# DEPLOY CA
#---------------------------------------
cd $DEPLOYDIR
chmod +x cfssl_linux-amd64
sudo cp cfssl_linux-amd64 $BINDIR/cfssl
chmod +x cfssljson_linux-amd64
sudo cp cfssljson_linux-amd64 $BINDIR/cfssljson
chmod +x cfssl-certinfo_linux-amd64
sudo cp cfssl-certinfo_linux-amd64 $BINDIR/cfssl-certinfo

cd $SSLCONFDIR
cfssl print-defaults config > config.json
cfssl print-defaults csr > csr.json

cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "8760h"
      }
    }
  }
}
EOF

cat > ca-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

cfssl gencert -initca ca-csr.json 2>/dev/null | cfssljson -bare ca
sudo cp ca* $KUBESSLDIR
ssh -p 6123 root@10.10.7.176 "mkdir -p $KUBESSLDIR"
ssh -p 6123 root@10.10.7.177 "mkdir -p $KUBESSLDIR"
scp -P 6123 ca* root@10.10.7.176:$KUBESSLDIR/ >/dev/null 2>&1
scp -P 6123 ca* root@10.10.7.177:$KUBESSLDIR/ >/dev/null 2>&1

# echo "scp -P 6123 /etc/kubernetes/ssl/ca* root@cluster_node_ip:/etc/kubernetes/ssl/"
echo "Please check ca copy to cluster, us: ls /etc/kubernetes/ssl/"
read -p "If copy finished, input y or n:" input
if [ "$input" != "y" ]; then
  echo "CA DEPLOY FAILED........"
  exit
fi
echo "Ca copy success................................."
#------------------------------------------------------------------------------------

# ETCD CONFIG
# ------------------------------------------------------------------------------------
cd $DEPLOYDIR

tar -xf etcd-v3.1.6-linux-amd64.tar.gz
sudo cp -fr etcd-v3.1.6-linux-amd64/etcd* $BINDIR/

cat > etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "${NODE_IP}"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

cfssl gencert -ca=$KUBESSLDIR/ca.pem \
-ca-key=$KUBESSLDIR/ca-key.pem \
-config=$KUBESSLDIR/ca-config.json \
-profile=kubernetes etcd-csr.json 2>/dev/null | cfssljson -bare etcd
sudo mv etcd*.pem $ETCDSSLDIR/

sudo mkdir -p /var/lib/etcd
cat > etcd.service <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
ExecStart=/root/local/bin/etcd \\
  --name=${NODE_NAME} \\
  --cert-file=/etc/etcd/ssl/etcd.pem \\
  --key-file=/etc/etcd/ssl/etcd-key.pem \\
  --peer-cert-file=/etc/etcd/ssl/etcd.pem \\
  --peer-key-file=/etc/etcd/ssl/etcd-key.pem \\
  --trusted-ca-file=$KUBESSLDIR/ca.pem \\
  --peer-trusted-ca-file=$KUBESSLDIR/ca.pem \\
  --initial-advertise-peer-urls=https://${NODE_IP}:2380 \\
  --listen-peer-urls=https://${NODE_IP}:2380 \\
  --listen-client-urls=https://${NODE_IP}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://${NODE_IP}:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${ETCD_NODES} \\
  --initial-cluster-state=new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
echo "Please start deploy cluster node scripts.........................."
sudo mv etcd.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable etcd >/dev/null 2>&1
sudo systemctl start etcd

# CHECK ETCD CLUSTER
# ------------------------------------------------------------------------------------
read -p "Please deploy Etcd cluster, If deploy finished, input y or n:" input
if [ "$input" != "y" ]; then
  exit
fi
for ip in ${NODE_IPS}; do
  ETCDCTL_API=3 $BINDIR/etcdctl \
  --endpoints=https://${ip}:2379  \
  --cacert=$KUBESSLDIR/ca.pem \
  --cert=$ETCDSSLDIR/etcd.pem \
  --key=$ETCDSSLDIR/etcd-key.pem \
  endpoint health; done
echo "Etcd cluster checking..........................."
read -p "Continue:" input 
if [ "$input" != "y" ]; then
  exit
fi
echo "Etcd deploy success................................."
# ETCD DEPLOY SUCCESS
# ------------------------------------------------------------------------------------


# KUBECTL CONFIG
#------------------------------------------------------------------------------------
cd $DEPLOYDIR

tar -xf kubernetes-client-linux-amd64.tar.gz
sudo cp kubernetes/client/bin/kube* $BINDIR
chmod a+x $BINDIR/kube*
export PATH=$BINDIR:$PATH

cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF

cfssl gencert -ca=$KUBESSLDIR/ca.pem \
-ca-key=$KUBESSLDIR/ca-key.pem \
-config=$KUBESSLDIR/ca-config.json \
-profile=kubernetes admin-csr.json  2>/dev/null| cfssljson -bare admin
ls admin*
sudo mv admin*.pem $KUBESSLDIR/

kubectl config set-cluster kubernetes \
--certificate-authority=$KUBESSLDIR/ca.pem \
--embed-certs=true \
--server=${KUBE_APISERVER} >/dev/null 2>&1

kubectl config set-credentials admin \
--client-certificate=$KUBESSLDIR/admin.pem \
--embed-certs=true \
--client-key=$KUBESSLDIR/admin-key.pem >/dev/null 2>&1

kubectl config set-context kubernetes \
--cluster=kubernetes \
--user=admin >/dev/null 2>&1
kubectl config use-context kubernetes >/dev/null 2>&1

# ssh root@10.10.7.176 "mkdir -p /root/.kube"
# ssh root@10.10.7.177 "mkdir -p /root/.kube"
scp -P 6123 /root/.kube/config root@10.10.7.176:/root/.kube/
scp -P 6123 /root/.kube/config root@10.10.7.177:/root/.kube/
echo "Kubectl config success.................................."
# ------------------------------------------------------------------------------------


# FLANNEL CONFIG
# ------------------------------------------------------------------------------------
cd $DEPLOYDIR
rm -fr ${FLANNEL_ETCD_PREFIX}
cat > flanneld-csr.json <<EOF
{
  "CN": "flanneld",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

cfssl gencert -ca=$KUBESSLDIR/ca.pem \
-ca-key=$KUBESSLDIR/ca-key.pem \
-config=$KUBESSLDIR/ca-config.json \
-profile=kubernetes flanneld-csr.json  2>/dev/null| cfssljson -bare flanneld
sudo mv flanneld*.pem $FLANNELDDIR

$BINDIR/etcdctl \
--endpoints=${ETCD_ENDPOINTS} \
--ca-file=$KUBESSLDIR/ca.pem \
--cert-file=$FLANNELDDIR/flanneld.pem \
--key-file=$FLANNELDDIR/flanneld-key.pem \
set ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${CLUSTER_CIDR}'", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}'

mkdir flannel
tar -xf flannel-v0.7.1-linux-amd64.tar.gz -C flannel
sudo cp flannel/{flanneld,mk-docker-opts.sh} $BINDIR/

cat > flanneld.service <<EOF
[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service

[Service]
Type=notify
ExecStart=$BINDIR/flanneld \\
  -etcd-cafile=$KUBESSLDIR/ca.pem \\
  -etcd-certfile=$FLANNELDDIR/flanneld.pem \\
  -etcd-keyfile=$FLANNELDDIR/flanneld-key.pem \\
  -etcd-endpoints=${ETCD_ENDPOINTS} \\
  -etcd-prefix=${FLANNEL_ETCD_PREFIX}
ExecStartPost=$BINDIR/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=on-failure

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF

sudo cp flanneld.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable flanneld >/dev/null 2>&1
sudo systemctl start flanneld

$BINDIR/etcdctl \
--endpoints=${ETCD_ENDPOINTS} \
--ca-file=$KUBESSLDIR/ca.pem \
--cert-file=$FLANNELDDIR/flanneld.pem \
--key-file=$FLANNELDDIR/flanneld-key.pem \
ls ${FLANNEL_ETCD_PREFIX}/subnets
echo "Master flannel deploy success............................"
read -p "Please deploy flannel cluster, if deploy finished, input y or n:" input
if [ "$input" != "y" ]; then
  exit
fi

echo "Flannel deploy success................................"
#------------------------------------------------------------------------------------


# DEPLOY MASTER NODE
# ------------------------------------------------------------------------------------
cd $DEPLOYDIR

tar -xf kubernetes-server-linux-amd64.tar.gz
cd kubernetes
tar -xf  kubernetes-src.tar.gz
sudo cp -r server/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl,kube-proxy,kubelet} $BINDIR/
cd $DEPLOYDIR
cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "${MASTER_IP}",
    "${CLUSTER_KUBERNETES_SVC_IP}",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

cfssl gencert -ca=$KUBESSLDIR/ca.pem \
-ca-key=$KUBESSLDIR/ca-key.pem \
-config=$KUBESSLDIR/ca-config.json \
-profile=kubernetes kubernetes-csr.json  2>/dev/null | cfssljson -bare kubernetes
if [ ! -f "$DEPLOYDIR/kubernetes.pem" ]; then
  echo "Create Kubernetes CA Failed................................"
  exit
fi
sudo cp kubernetes*.pem $KUBESSLDIR/

cd $DEPLOYDIR
cat > token.csv <<EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF
cp token.csv /etc/kubernetes/
scp -P 6123 token.csv root@10.10.7.176:/etc/kubernetes/
scp -P 6123 token.csv root@10.10.7.177:/etc/kubernetes/


cat  > kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
ExecStart=/root/local/bin/kube-apiserver \\
  --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --advertise-address=${MASTER_IP} \\
  --bind-address=${MASTER_IP} \\
  --insecure-bind-address=${MASTER_IP} \\
  --authorization-mode=RBAC \\
  --runtime-config=rbac.authorization.k8s.io/v1alpha1 \\
  --kubelet-https=true \\
  --experimental-bootstrap-token-auth \\
  --token-auth-file=/etc/kubernetes/token.csv \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --service-node-port-range=${NODE_PORT_RANGE} \\
  --tls-cert-file=/etc/kubernetes/ssl/kubernetes.pem \\
  --tls-private-key-file=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --client-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --service-account-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --etcd-cafile=/etc/kubernetes/ssl/ca.pem \\
  --etcd-certfile=/etc/kubernetes/ssl/kubernetes.pem \\
  --etcd-keyfile=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --etcd-servers=${ETCD_ENDPOINTS} \\
  --enable-swagger-ui=true \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/lib/audit.log \\
  --event-ttl=1h \\
  --v=2
Restart=on-failure
RestartSec=5
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo cp kube-apiserver.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver >/dev/null 2>&1
sudo systemctl start kube-apiserver
echo "Kube apiserver deploy success................................"

cat > kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/root/local/bin/kube-controller-manager \\
  --address=127.0.0.1 \\
  --master=http://${MASTER_IP}:8080 \\
  --allocate-node-cidrs=true \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --cluster-cidr=${CLUSTER_CIDR} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \\
  --cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --service-account-private-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --root-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo cp kube-controller-manager.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kube-controller-manager >/dev/null 2>&1
sudo systemctl start kube-controller-manager
echo "Kube controller manager deploy success................................"

cat > kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/root/local/bin/kube-scheduler \\
  --address=127.0.0.1 \\
  --master=http://${MASTER_IP}:8080 \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo cp kube-scheduler.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kube-scheduler >/dev/null 2>&1
sudo systemctl start kube-scheduler
echo "Kube scheduler deploy success................................"
kubectl get componentstatuses
echo "Master node deploy success..............................."
# ------------------------------------------------------------------------------------


# DEPLOY CLUSTER NODE
cd $DEPLOYDIR

mkdir -p /etc/bash_completion.d/
tar -xf docker-17.04.0-ce.tgz
cp $DEPLOYDIR/docker/docker* $BINDIR/
cp $DEPLOYDIR/docker/completion/bash/docker /etc/bash_completion.d/

cat > docker.service <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io

[Service]
Environment="PATH=/root/local/bin:/bin:/sbin:/usr/bin:/usr/sbin"
EnvironmentFile=-/run/flannel/docker
ExecStart=/root/local/bin/dockerd --log-level=error \$DOCKER_NETWORK_OPTIONS --insecure-registry=${REGISTRY_DOMAIN}
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn", "registry.docker-cn.com"],
  "max-concurrent-downloads": 10
}
EOF

sudo cp docker.service /etc/systemd/system/docker.service
sudo systemctl daemon-reload
# sudo systemctl stop firewalld
# sudo systemctl disable firewalld
sudo iptables -F && sudo iptables -X && sudo iptables -F -t nat && sudo iptables -X -t nat
sudo systemctl enable docker >/dev/null 2>&1
sudo systemctl start docker
echo "Docker deploy success..............................."
# ------------------------------------------------------------------------------------

# DEPLOY KUBELET
# ------------------------------------------------------------------------------------
cd $DEPLOYDIR
rm -fr /etc/kubernetes/kubelet.kubeconfig
kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap >/dev/null 2>&1
kubectl config set-cluster kubernetes \
--certificate-authority=/etc/kubernetes/ssl/ca.pem \
--embed-certs=true \
--server=${KUBE_APISERVER} \
--kubeconfig=bootstrap.kubeconfig >/dev/null 2>&1

kubectl config set-credentials kubelet-bootstrap \
--token=${BOOTSTRAP_TOKEN} \
--kubeconfig=bootstrap.kubeconfig >/dev/null 2>&1

kubectl config set-context default \
--cluster=kubernetes \
--user=kubelet-bootstrap \
--kubeconfig=bootstrap.kubeconfig >/dev/null 2>&1

kubectl config use-context default --kubeconfig=bootstrap.kubeconfig >/dev/null 2>&1
cp bootstrap.kubeconfig /etc/kubernetes/
cd $DEPLOYDIR
sudo mkdir /var/lib/kubelet
cat > kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
ExecStart=/root/local/bin/kubelet \\
  --address=${NODE_IP} \\
  --hostname-override=${NODE_IP} \\
  --pod-infra-container-image=${BASE_PODS} \\
  --experimental-bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \\
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
  --require-kubeconfig \\
  --cert-dir=/etc/kubernetes/ssl \\
  --cluster-dns=${CLUSTER_DNS_SVC_IP} \\
  --cluster-domain=${CLUSTER_DNS_DOMAIN} \\
  --hairpin-mode promiscuous-bridge \\
  --allow-privileged=true \\
  --serialize-image-pulls=false \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo cp kubelet.service /etc/systemd/system/kubelet.service
sudo systemctl daemon-reload
sudo systemctl enable kubelet >/dev/null 2>&1
sudo systemctl restart kubelet
for i in `kubectl get csr |awk '{print $1}' | sed -n '2,$p'`;do kubectl certificate approve $i >/dev/null 2>&1 ;done
# if [ ! -f "/etc/kubernetes/kubelet.kubeconfig" ]; then
#   echo "Node Insert Cluster Failed..............................."
#   exit
# fi
echo "Kubelet deploy success..............................."

# DEPLOY KUBE PROXY
# ------------------------------------------------------------------------------------
cd $DEPLOYDIR
cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF
cfssl gencert -ca=$KUBESSLDIR/ca.pem \
-ca-key=$KUBESSLDIR/ca-key.pem \
-config=$KUBESSLDIR/ca-config.json \
-profile=kubernetes  kube-proxy-csr.json  2>/dev/null | cfssljson -bare kube-proxy
sudo cp kube-proxy*.pem $KUBESSLDIR/

kubectl config set-cluster kubernetes \
--certificate-authority=$KUBESSLDIR/ca.pem \
--embed-certs=true \
--server=${KUBE_APISERVER} \
--kubeconfig=kube-proxy.kubeconfig >/dev/null 2>&1

kubectl config set-credentials kube-proxy \
--client-certificate=$KUBESSLDIR/kube-proxy.pem \
--client-key=$KUBESSLDIR/kube-proxy-key.pem \
--embed-certs=true \
--kubeconfig=kube-proxy.kubeconfig >/dev/null 2>&1

kubectl config set-context default \
--cluster=kubernetes \
--user=kube-proxy \
--kubeconfig=kube-proxy.kubeconfig >/dev/null 2>&1

kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig >/dev/null 2>&1
cp kube-proxy.kubeconfig /etc/kubernetes/

sudo mkdir -p /var/lib/kube-proxy
cat > kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=/var/lib/kube-proxy
ExecStart=/root/local/bin/kube-proxy \\
  --bind-address=${NODE_IP} \\
  --hostname-override=${NODE_IP} \\
  --cluster-cidr=${SERVICE_CIDR} \\
  --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo cp kube-proxy.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kube-proxy >/dev/null 2>&1
sudo systemctl start kube-proxy
echo "Kube proxy deploy success..............................."
# ------------------------------------------------------------------------------------

echo "Master deploy success, please deploy cluster................................"
read -p "Cluster deploy success?:" input
if [ "$input" != "y" ]; then
  exit
fi

# Deploy Dns Plugin
# ------------------------------------------------------------------------------------
cd $YAML/dns
cat > kubedns-cm.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    addonmanager.kubernetes.io/mode: EnsureExists
EOF
cat > kubedns-controller.yaml <<EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  # replicas: not specified here:
  # 1. In order to make Addon Manager do not reconcile this replicas parameter.
  # 2. Default is 1.
  # 3. Will be tuned in real time if DNS horizontal auto-scaling is turned on.
  strategy:
    rollingUpdate:
      maxSurge: 10%
      maxUnavailable: 0
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ''
    spec:
      tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
      volumes:
      - name: kube-dns-config
        configMap:
          name: kube-dns
          optional: true
      containers:
      - name: kubedns
        image: harbor.gqichina.com/k8s/k8s-dns-kube-dns-amd64:1.14.1
        resources:
          # TODO: Set memory limits when we've profiled the container for large
          # clusters, then set request = limit to keep this container in
          # guaranteed class. Currently, this container falls into the
          # "burstable" category so the kubelet doesn't backoff from restarting it.
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        livenessProbe:
          httpGet:
            path: /healthcheck/kubedns
            port: 10054
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /readiness
            port: 8081
            scheme: HTTP
          # we poll on pod startup for the Kubernetes master service and
          # only setup the /readiness HTTP server once that's available.
          initialDelaySeconds: 3
          timeoutSeconds: 5
        args:
        - --domain=cluster.local.
        - --dns-port=10053
        - --config-dir=/kube-dns-config
        - --v=2
        #__PILLAR__FEDERATIONS__DOMAIN__MAP__
        env:
        - name: PROMETHEUS_PORT
          value: "10055"
        ports:
        - containerPort: 10053
          name: dns-local
          protocol: UDP
        - containerPort: 10053
          name: dns-tcp-local
          protocol: TCP
        - containerPort: 10055
          name: metrics
          protocol: TCP
        volumeMounts:
        - name: kube-dns-config
          mountPath: /kube-dns-config
      - name: dnsmasq
        image: harbor.gqichina.com/k8s/k8s-dns-dnsmasq-nanny-amd64:1.14.1
        livenessProbe:
          httpGet:
            path: /healthcheck/dnsmasq
            port: 10054
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        args:
        - -v=2
        - -logtostderr
        - -configDir=/etc/k8s/dns/dnsmasq-nanny
        - -restartDnsmasq=true
        - --
        - -k
        - --cache-size=1000
        - --log-facility=-
        - --server=/cluster.local./127.0.0.1#10053
        - --server=/in-addr.arpa/127.0.0.1#10053
        - --server=/ip6.arpa/127.0.0.1#10053
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        # see: https://github.com/kubernetes/kubernetes/issues/29055 for details
        resources:
          requests:
            cpu: 150m
            memory: 20Mi
        volumeMounts:
        - name: kube-dns-config
          mountPath: /etc/k8s/dns/dnsmasq-nanny
      - name: sidecar
        image: harbor.gqichina.com/k8s/k8s-dns-sidecar-amd64:1.14.1
        livenessProbe:
          httpGet:
            path: /metrics
            port: 10054
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        args:
        - --v=2
        - --logtostderr
        - --probe=kubedns,127.0.0.1:10053,kubernetes.default.svc.cluster.local.,5,A
        - --probe=dnsmasq,127.0.0.1:53,kubernetes.default.svc.cluster.local.,5,A
        ports:
        - containerPort: 10054
          name: metrics
          protocol: TCP
        resources:
          requests:
            memory: 20Mi
            cpu: 10m
      dnsPolicy: Default  # Don't use cluster DNS.
      serviceAccountName: kube-dns
EOF

cat > kubedns-sa.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
EOF

cat > kubedns-svc.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/name: "KubeDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: 10.254.0.2
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
EOF
kubectl create -f . >/dev/null 2>&1
echo "Kube dns deploy success..............................."
# ------------------------------------------------------------------------------------


# DEPLOY DASHBOARD
# ------------------------------------------------------------------------------------

cd $YAML/dashboard
cat > dashboard-controller.yaml <<EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: kubernetes-dashboard
  namespace: kube-system
  labels:
    k8s-app: kubernetes-dashboard
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  selector:
    matchLabels:
      k8s-app: kubernetes-dashboard
  template:
    metadata:
      labels:
        k8s-app: kubernetes-dashboard
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ''
    spec:
      serviceAccountName: dashboard
      containers:
      - name: kubernetes-dashboard
        image: harbor.gqichina.com/k8s/kubernetes-dashboard-amd64:v1.6.0
        resources:
          # keep request = limit to keep this container in guaranteed class
          limits:
            cpu: 100m
            memory: 50Mi
          requests:
            cpu: 100m
            memory: 50Mi
        ports:
        - containerPort: 9090
        livenessProbe:
          httpGet:
            path: /
            port: 9090
          initialDelaySeconds: 30
          timeoutSeconds: 30
      tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
EOF
cat > dashboard-rbac.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dashboard
  namespace: kube-system

---

kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1alpha1
metadata:
  name: dashboard
subjects:
  - kind: ServiceAccount
    name: dashboard
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF
cat > dashboard-service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-dashboard
  namespace: kube-system
  labels:
    k8s-app: kubernetes-dashboard
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  type: NodePort 
  selector:
    k8s-app: kubernetes-dashboard
  ports:
  - port: 80
    targetPort: 9090
EOF
kubectl create -f  . >/dev/null 2>&1
echo "Kube dashboard deploy success................................"
# ------------------------------------------------------------------------------------


# Deploy Dashboard Heapster
# ------------------------------------------------------------------------------------
cd $YAML/heapster
cat > grafana-deployment.yaml <<EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: monitoring-grafana
  namespace: kube-system
spec:
  replicas: 1
  template:
    metadata:
      labels:
        task: monitoring
        k8s-app: grafana
    spec:
      containers:
      - name: grafana
        image: lvanneo/heapster-grafana-amd64:v4.0.2
        ports:
          - containerPort: 3000
            protocol: TCP
        volumeMounts:
        - mountPath: /var
          name: grafana-storage
        env:
        - name: INFLUXDB_HOST
          value: monitoring-influxdb
        - name: GRAFANA_PORT
          value: "3000"
          # The following env variables are required to make Grafana accessible via
          # the kubernetes api-server proxy. On production clusters, we recommend
          # removing these env variables, setup auth for grafana, and expose the grafana
          # service using a LoadBalancer or a public IP.
        - name: GF_AUTH_BASIC_ENABLED
          value: "false"
        - name: GF_AUTH_ANONYMOUS_ENABLED
          value: "true"
        - name: GF_AUTH_ANONYMOUS_ORG_ROLE
          value: Admin
        - name: GF_SERVER_ROOT_URL
          # If you're only using the API Server proxy, set this value instead:
          value: /api/v1/proxy/namespaces/kube-system/services/monitoring-grafana/
          #value: /
      volumes:
      - name: grafana-storage
        emptyDir: {}
EOF
cat > grafana-service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  labels:
    # For use as a Cluster add-on (https://github.com/kubernetes/kubernetes/tree/master/cluster/addons)
    # If you are NOT using this as an addon, you should comment out this line.
    kubernetes.io/cluster-service: 'true'
    kubernetes.io/name: monitoring-grafana
  name: monitoring-grafana
  namespace: kube-system
spec:
  # In a production setup, we recommend accessing Grafana through an external Loadbalancer
  # or through a public IP.
  # type: LoadBalancer
  # You could also use NodePort to expose the service at a randomly-generated port
  ports:
  - port : 80
    targetPort: 3000
  selector:
    k8s-app: grafana
EOF
cat > heapster-deployment.yaml <<EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: heapster
  namespace: kube-system
spec:
  replicas: 1
  template:
    metadata:
      labels:
        task: monitoring
        k8s-app: heapster
    spec:
      serviceAccountName: heapster
      containers:
      - name: heapster
        image: lvanneo/heapster-amd64:v1.3.0-beta.1
        imagePullPolicy: IfNotPresent
        command:
        - /heapster
        - --source=kubernetes:https://kubernetes.default
        - --sink=influxdb:http://monitoring-influxdb:8086
EOF
cat > heapster-rbac.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: heapster
  namespace: kube-system

---

kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1alpha1
metadata:
  name: heapster
subjects:
  - kind: ServiceAccount
    name: heapster
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: system:heapster
  apiGroup: rbac.authorization.k8s.io
EOF
cat > heapster-service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  labels:
    task: monitoring
    # For use as a Cluster add-on (https://github.com/kubernetes/kubernetes/tree/master/cluster/addons)
    # If you are NOT using this as an addon, you should comment out this line.
    kubernetes.io/cluster-service: 'true'
    kubernetes.io/name: Heapster
  name: heapster
  namespace: kube-system
spec:
  ports:
  - port: 80
    targetPort: 8082
  selector:
    k8s-app: heapster
EOF
cat > influxdb-cm.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: influxdb-config
  namespace: kube-system
data:
  config.toml: |
    reporting-disabled = true
    bind-address = ":8088"
    [meta]
      dir = "/data/meta"
      retention-autocreate = true
      logging-enabled = true
    [data]
      dir = "/data/data"
      wal-dir = "/data/wal"
      query-log-enabled = true
      cache-max-memory-size = 1073741824
      cache-snapshot-memory-size = 26214400
      cache-snapshot-write-cold-duration = "10m0s"
      compact-full-write-cold-duration = "4h0m0s"
      max-series-per-database = 1000000
      max-values-per-tag = 100000
      trace-logging-enabled = false
    [coordinator]
      write-timeout = "10s"
      max-concurrent-queries = 0
      query-timeout = "0s"
      log-queries-after = "0s"
      max-select-point = 0
      max-select-series = 0
      max-select-buckets = 0
    [retention]
      enabled = true
      check-interval = "30m0s"
    [admin]
      enabled = true
      bind-address = ":8083"
      https-enabled = false
      https-certificate = "/etc/ssl/influxdb.pem"
    [shard-precreation]
      enabled = true
      check-interval = "10m0s"
      advance-period = "30m0s"
    [monitor]
      store-enabled = true
      store-database = "_internal"
      store-interval = "10s"
    [subscriber]
      enabled = true
      http-timeout = "30s"
      insecure-skip-verify = false
      ca-certs = ""
      write-concurrency = 40
      write-buffer-size = 1000
    [http]
      enabled = true
      bind-address = ":8086"
      auth-enabled = false
      log-enabled = true
      write-tracing = false
      pprof-enabled = false
      https-enabled = false
      https-certificate = "/etc/ssl/influxdb.pem"
      https-private-key = ""
      max-row-limit = 10000
      max-connection-limit = 0
      shared-secret = ""
      realm = "InfluxDB"
      unix-socket-enabled = false
      bind-socket = "/var/run/influxdb.sock"
    [[graphite]]
      enabled = false
      bind-address = ":2003"
      database = "graphite"
      retention-policy = ""
      protocol = "tcp"
      batch-size = 5000
      batch-pending = 10
      batch-timeout = "1s"
      consistency-level = "one"
      separator = "."
      udp-read-buffer = 0
    [[collectd]]
      enabled = false
      bind-address = ":25826"
      database = "collectd"
      retention-policy = ""
      batch-size = 5000
      batch-pending = 10
      batch-timeout = "10s"
      read-buffer = 0
      typesdb = "/usr/share/collectd/types.db"
    [[opentsdb]]
      enabled = false
      bind-address = ":4242"
      database = "opentsdb"
      retention-policy = ""
      consistency-level = "one"
      tls-enabled = false
      certificate = "/etc/ssl/influxdb.pem"
      batch-size = 1000
      batch-pending = 5
      batch-timeout = "1s"
      log-point-errors = true
    [[udp]]
      enabled = false
      bind-address = ":8089"
      database = "udp"
      retention-policy = ""
      batch-size = 5000
      batch-pending = 10
      read-buffer = 0
      batch-timeout = "1s"
      precision = ""
    [continuous_queries]
      log-enabled = true
      enabled = true
      run-interval = "1s"
EOF
cat > influxdb-deployment.yaml <<EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: monitoring-influxdb
  namespace: kube-system
spec:
  replicas: 1
  template:
    metadata:
      labels:
        task: monitoring
        k8s-app: influxdb
    spec:
      containers:
      - name: influxdb
        image: lvanneo/heapster-influxdb-amd64:v1.1.1
        volumeMounts:
        - mountPath: /data
          name: influxdb-storage
        - mountPath: /etc/
          name: influxdb-config
      volumes:
      - name: influxdb-storage
        emptyDir: {}
      - name: influxdb-config
        configMap:
          name: influxdb-config
EOF
cat > influxdb-service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  labels:
    task: monitoring
    # For use as a Cluster add-on (https://github.com/kubernetes/kubernetes/tree/master/cluster/addons)
    # If you are NOT using this as an addon, you should comment out this line.
    kubernetes.io/cluster-service: 'true'
    kubernetes.io/name: monitoring-influxdb
  name: monitoring-influxdb
  namespace: kube-system
spec:
  type: NodePort
  ports:
  - port: 8086
    targetPort: 8086
    name: http
  - port: 8083
    targetPort: 8083
    name: admin
  selector:
    k8s-app: influxdb
EOF
kubectl create -f  . >/dev/null 2>&1
echo "Kube Dashboard Heapster Deploy Sucess......................"
# ------------------------------------------------------------------------------------

# # DEPLOY HARBOR
# # ------------------------------------------------------------------------------------
# cd $DEPLOYDIR
# if [ ! -f "$DEPLOYDIR/docker-compose-Linux-x86_64" ]; then
#   wget -c https://github.com/docker/compose/releases/download/1.12.0/docker-compose-Linux-x86_64 --no-check-certificate -P $DEPLOYDIR
# fi
# cp docker-compose-Linux-x86_64 $BINDIR/docker-compose
# chmod a+x $BINDIR/docker-compose
# export PATH=$BINDIR:$PATH

# if [ ! -f "$DEPLOYDIR/harbor-offline-installer-v1.1.2.tgz" ]; then
#   wget -c https://github.com/vmware/harbor/releases/download/v1.1.2/harbor-offline-installer-v1.1.2.tgz --no-check-certificate -P $DEPLOYDIR
# fi
# tar -xf harbor-offline-installer-v1.1.2.tgz
# cd $DEPLOYDIR/harbor
# docker load -i harbor.v1.1.2.tar.gz
# cd $DEPLOYDIR
# cat > harbor-csr.json <<EOF
# {
#   "CN": "harbor",
#   "hosts": [
#     "127.0.0.1",
#     "$NODE_IP"
#   ],
#   "key": {
#     "algo": "rsa",
#     "size": 2048
#   },
#   "names": [
#     {
#       "C": "CN",
#       "ST": "BeiJing",
#       "L": "BeiJing",
#       "O": "k8s",
#       "OU": "System"
#     }
#   ]
# }
# EOF
# cfssl gencert -ca=$KUBESSLDIR/ca.pem \
# -ca-key=$KUBESSLDIR/ca-key.pem \
# -config=$KUBESSLDIR/ca-config.json \
# -profile=kubernetes harbor-csr.json | cfssljson -bare harbor
# sudo cp harbor*.pem $HARBORDIR/

# sed -i "s@hostname = reg.mydomain.com@hostname = ${NODE_IP}@g" $DEPLOYDIR/harbor/harbor.cfg
# sed -i "s@ui_url_protocol = http@ui_url_protocol = https@g" $DEPLOYDIR/harbor/harbor.cfg
# sed -i "s@ssl_cert = /data/cert/server.crt@ssl_cert = ${HARBORDIR}/harbor.pem@g" $DEPLOYDIR/harbor/harbor.cfg
# sed -i "s@ssl_cert_key = /data/cert/server.key@ssl_cert_key = ${HARBORDIR}/harbor-key.pem@g" $DEPLOYDIR/harbor/harbor.cfg
# sh $DEPLOYDIR/harbor/install.sh
# echo "Harbor Web: https://${NODE_IP}"
# echo "User/Password: admin/Harbor12345"
# echo "Log Dir: /var/log/harbor"

# sudo mkdir -p /etc/docker/certs.d/${NODE_IP}
# sudo cp ${KUBESSLDIR}/ca.pem /etc/docker/certs.d/${NODE_IP}/ca.crt

# echo "Access to harbor..........................."
# docker login 127.0.0.1
# echo "Harbor Deploy Success.........................."
# # ------------------------------------------------------------------------------------
echo "DEPLOY INFO:"
docker version
kubectl cluster-info
echo "Grafana URL: http://10.10.7.175:8080/api/v1/proxy/namespaces/kube-system/services/monitoring-grafana"
