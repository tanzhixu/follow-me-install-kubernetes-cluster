#!/bin/sh

# BASE CONFIG
#---------------------------------------
DEPLOYDIR="/k8sdeploydir"
BINDIR="/root/local/bin"
SSLCONFDIR=$DEPLOYDIR/ssl
KUBESSLDIR="/etc/kubernetes/ssl"
ETCDSSLDIR="/etc/etcd/ssl"
FLANNELDDIR="/etc/flanneld/ssl"
YAML=$DEPLOYDIR/yaml

mkdir -p $DEPLOYDIR
mkdir -p $BINDIR
mkdir -p $SSLCONFDIR
mkdir -p $KUBESSLDIR
mkdir -p $ETCDSSLDIR
mkdir -p $FLANNELDDIR
mkdir -p $YAML
mkdir -p /root/.kube/

service iptables stop

function CheckFileExist()
{
  if [ ! -f $1 ]; then
    echo "Download File Failed: "$1
    exit
  fi
}

cat > $BINDIR/environment.sh <<EOF
BOOTSTRAP_TOKEN="41f7e4ba8b7be874fcff18bf5cf41a7c"
MASTER_IP="10.10.7.175"
NODE_NAME="etcd-host2"
NODE_IP="10.10.7.177"
KUBE_APISERVER="https://10.10.7.175:6443"
NODE_IPS="10.10.7.175 10.10.7.176 10.10.7.177"
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
# BASE CONFIG SUCCESS
#---------------------------------------

#DEPLOY CA
#---------------------------------------
cd $DEPLOYDIRC
if [ ! -f "$DEPLOYDIR/cfssl_linux-amd64" ]; then
  wget -c https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 --no-check-certificate -P $DEPLOYDIR
fi
chmod +x cfssl_linux-amd64
sudo cp cfssl_linux-amd64 $BINDIR/cfssl

if [ ! -f "$DEPLOYDIR/cfssljson_linux-amd64" ]; then
  wget -c https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 --no-check-certificate -P $DEPLOYDIR
fi
chmod +x cfssljson_linux-amd64
sudo cp cfssljson_linux-amd64 $BINDIR/cfssljson

if [ ! -f "$DEPLOYDIR/cfssl-certinfo_linux-amd64" ]; then
  wget -c https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64 --no-check-certificate -P $DEPLOYDIR
fi
chmod +x cfssl-certinfo_linux-amd64
sudo cp cfssl-certinfo_linux-amd64 $BINDIR/cfssl-certinfo
#DEPLOY CA SUCCESS
# ------------------------------------------------------------------------------------

echo "export PATH=$BINDIR:\$PATH" >> /etc/profile
source /etc/profile

# ETCD CONFIG
# ------------------------------------------------------------------------------------
cd $DEPLOYDIR
if [ ! -f "$DEPLOYDIR/etcd-v3.1.6-linux-amd64.tar.gz" ]; then
  wget -c https://github.com/coreos/etcd/releases/download/v3.1.6/etcd-v3.1.6-linux-amd64.tar.gz -P $DEPLOYDIR
fi
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

CheckFileExist /etc/kubernetes/ssl/ca.pem

cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
-ca-key=/etc/kubernetes/ssl/ca-key.pem \
-config=/etc/kubernetes/ssl/ca-config.json \
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
  --trusted-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --peer-trusted-ca-file=/etc/kubernetes/ssl/ca.pem \\
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

sudo mv etcd.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable etcd >/dev/null 2>&1
sudo systemctl start etcd
# ------------------------------------------------------------------------------------

# CHECK ETCD CLUSTER
# ------------------------------------------------------------------------------------
echo "NODE_IPS: " $NODE_IPS
for ip in ${NODE_IPS}; do
  ETCDCTL_API=3 $BINDIR/etcdctl \
  --endpoints=https://${ip}:2379  \
  --cacert=$KUBESSLDIR/ca.pem \
  --cert=$ETCDSSLDIR/etcd.pem \
  --key=$ETCDSSLDIR/etcd-key.pem \
  endpoint health; done

read -p "Cluster ETCD Deploy Success?:" input
if [ "$input" != "y" ]; then
  exit
fi
# ------------------------------------------------------------------------------------
# ETCD DEPLOY SUCCESS
# ------------------------------------------------------------------------------------
echo "ETCD DEPLOY SUCCESS................................"

# KUBECTL CONFIG
#------------------------------------------------------------------------------------
cd $DEPLOYDIR
if [ ! -f "$DEPLOYDIR/kubernetes-client-linux-amd64.tar.gz" ]; then
  wget -c https://dl.k8s.io/v1.6.2/kubernetes-client-linux-amd64.tar.gz -P $DEPLOYDIR
fi
tar -xf kubernetes-client-linux-amd64.tar.gz
sudo cp kubernetes/client/bin/kube* $BINDIR
chmod a+x $BINDIR/kube*
export PATH=$BINDIR:$PATH
echo "KUBECTL DEPLOY SUCCESS................................"
# ------------------------------------------------------------------------------------

# FLANNEL CONFIG
# ------------------------------------------------------------------------------------
echo "WAITING MASTER DEPLOY FLANNEL..............................."
read -p "MASTER FLANNEL DEPLOY SUCCESS?:" input
if [ "$input" != "y" ]; then
  exit
fi
cd $DEPLOYDIR
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
-profile=kubernetes flanneld-csr.json 2>/dev/null | cfssljson -bare flanneld
sudo mv flanneld*.pem $FLANNELDDIR

if [ ! -f "$DEPLOYDIR/flannel-v0.7.1-linux-amd64.tar.gz" ]; then
  wget -c https://github.com/coreos/flannel/releases/download/v0.7.1/flannel-v0.7.1-linux-amd64.tar.gz -P $DEPLOYDIR
fi
CheckFileExist flannel-v0.7.1-linux-amd64.tar.gz
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
sudo systemctl enable flanneld
sudo systemctl start flanneld
# journalctl  -u flanneld |grep 'Lease acquired'
# ifconfig flannel.1

$BINDIR/etcdctl \
--endpoints=${ETCD_ENDPOINTS} \
--ca-file=$KUBESSLDIR/ca.pem \
--cert-file=$FLANNELDDIR/flanneld.pem \
--key-file=$FLANNELDDIR/flanneld-key.pem \
ls ${FLANNEL_ETCD_PREFIX}/subnets
echo "CLUSTER FLANNEL DEPLOY SUCCESS......................"
read -p "CLUSTER FLANNEL DEPLOY SUCCESS:" input
if [ "$input" != "y" ]; then
  exit
fi
echo "FLANNEL DEPLOY SUCCESS................................"
# FLANNEL CONFIG SUCCESS
# ------------------------------------------------------------------------------------

# DEPLOY CLUSTER NODE
cd $DEPLOYDIR
if [ ! -f "$DEPLOYDIR/docker-17.04.0-ce.tgz" ]; then
  wget -c https://get.docker.com/builds/Linux/x86_64/docker-17.04.0-ce.tgz -P $DEPLOYDIR
fi
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
ExecReload=/bin/kill -s HUP \$MAINPID
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
  "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn", "hub-mirror.c.163.com"],
  "max-concurrent-downloads": 10
}
EOF

sudo cp docker.service /etc/systemd/system/docker.service
sudo systemctl daemon-reload
# sudo systemctl stop firewalld
# sudo systemctl disable firewalld
sudo iptables -F && sudo iptables -X && sudo iptables -F -t nat && sudo iptables -X -t nat
sudo systemctl stop iptables
sudo systemctl disable iptables
sudo systemctl enable docker >/dev/null 2>&1
sudo systemctl start docker
echo "DOCKER DEPLOY SUCCESS................................"
# ------------------------------------------------------------------------------------

# DEPLOY KUBELET
# ------------------------------------------------------------------------------------
cd $DEPLOYDIR
rm -fr /etc/kubernetes/kubelet.kubeconfig
if [ ! -f "$DEPLOYDIR/kubernetes-server-linux-amd64.tar.gz" ]; then
  wget -c https://dl.k8s.io/v1.6.2/kubernetes-server-linux-amd64.tar.gz -P $DEPLOYDIR
fi
tar -xf kubernetes-server-linux-amd64.tar.gz
cd $DEPLOYDIR/kubernetes
tar -xf  kubernetes-src.tar.gz
sudo cp -r $DEPLOYDIR/kubernetes/server/bin/{kube-proxy,kubelet} $BINDIR/
cd $DEPLOYDIR
kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap
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
mv bootstrap.kubeconfig /etc/kubernetes/
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
sudo systemctl enable kubelet
sudo systemctl start kubelet
echo "WAITING MASTER DEPLOY................................"
read -p "MASTER DEPLOY SUCCESS?:" input
if [ "$input" != "y" ]; then
  exit
fi
for i in `kubectl get csr |awk '{print $1}' | sed -n '2,$p'`;do kubectl certificate approve $i >/dev/null 2>&1;done
if [ ! -f "/etc/kubernetes/kubelet.kubeconfig" ]; then
  echo "Node Insert Cluster Failed..............................."
  exit
fi
echo "KUBELET DEPLOY SUCCESS..............................."
# ------------------------------------------------------------------------------------

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
-profile=kubernetes  kube-proxy-csr.json 2>/dev/null | cfssljson -bare kube-proxy
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
echo "KUBE PROXY DEPLOY SUCCESS..............................."
# ------------------------------------------------------------------------------------

echo "DEPLOY INFO:"
docker version