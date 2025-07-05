# k8s-cluster (Terraform + AWS + Kubespray)
>  Use Terraform to provision a secure Kubernetes cluster infrastructure on AWS. Only the Bastion node is assigned a public IP, while the Master and Worker nodes are deployed in private subnets.

## [1] Terraform으로 AWS에 프로비저닝

### 사전 준비 
- AWS 계정 및 IAM 키 준비 
    - 로컬 : aws cli 설치  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
        - `aws --version`
    - AWS Access Key 발급 및 aws configure로 등록
        - 사용자 이름 > 보안 자격 증명 클릭 > 새 액세스 키 만들기 
- 로컬에 SSH 키 (.pem) 생성되어 있어야 함 (예: ~/.ssh/vvue.pem)
- 로컬에 Terraform 설치되어 있어야 함 : `choco install terraform`
- 변수 파일 준비

### 생성 리소스 요약  

- VPC (10.250.0.0/16)
- Public Subnet (10.250.1.0/24)
- Private Subnet (10.250.2.0/24)
- Internet Gateway
- Bastion EC2 (`t3.micro`, 퍼블릭 IP O)
- Master EC2 (`t3.medium`, 퍼블릭 IP ❌) : 1대
- Worker EC2 (`t3.medium`, 퍼블릭 IP ❌) : 2대
- 보안 그룹 (SSH 및 내부 통신만 허용)


### 인프라 구조 

```
📦 VPC: 10.250.0.0/16
│
├── 🌐 Internet Gateway (IGW)
│
├── 📂 Public Subnet (10.250.1.0/24)
│   ├── 🔹 Bastion Host (t3.micro)
│   │     └─ Elastic IP 연결됨 (SSH 접근용 : 외부 -> Bastion)
│   │
│   └── 🔸 NAT Gateway
│         └─ NAT용 EIP 연결됨 (아웃바운드 통신 중계용 : Master/Worker -> 인터넷)
│
└── 🔒 Private Subnet (10.250.2.0/24)
    ├── ⚙️ Master Node (t3.medium)
    │     └─ 퍼블릭 IP 없음 (외부에서 직접 접속 불가)
    │
    ├── 🧱 Worker Node #1 (t3.medium)
    │     └─ 퍼블릭 IP 없음
    │
    └── 🧱 Worker Node #2 (t3.medium)
          └─ 퍼블릭 IP 없음
```

### 1️⃣ Terraform 구성 및 실행

#### 0) 현재 내 IP 확인 및 terraform.tfvars 필드 수정
```bash
ipconfig  # 내 IP 확인 
```

#### 1) 프로젝트 초기화

```bash
terraform init
```

#### 2) 계획 확인
```bash
terraform plan -out=tfplan
```

#### 3) 인프라 생성 (2기준으로 생성)
```bash
terraform apply tfplan
```

### 2️⃣ SSH 접속 및 네트워크 확인 
#### 1) Bastion 노드에 접속

```bash
ssh -i ~/.ssh/<your-key>.pem ubuntu@<bastion_public_ip>
```

#### 2) Bastion → Master/Worker 접속 (Bastion 내부에서)
> Bastion 서버의 .ssh 에 Master/Worker에 접속할 수 있는 SSH키가 있어야 한다. chmod 400 .pem

```bash
ssh -i <your-key-for-k8s> ubuntu@<master_private_ip>
ssh -i <your-key-for-k8s> ubuntu@<worker1_private_ip>
ssh -i <your-key-for-k8s> ubuntu@<worker2_private_ip>
```

#### 3) 인터넷 접속 가능 확인

```
curl https://google.com
```

#### 3️⃣ 리소스 삭제
```bash
terraform destroy -auto-approve
```

## [2] Kubespray로 Kubernetes 클러스터 구성 과정 
### 1️⃣ Kubespray 클러스터 구성 개요
> ingress(nginx), metrics server 도 on/off 할 수 있다 
- `CNI(Container Network Interface)` : `Calico(기본)`, Flannel, Canal, Cilium
  - Calico : 네트워크 정책, BGP 기반 고성능 (보안 정책 필요, 대규모)
  - Flannel : 단순, 설치 쉬움 
  - Cilium : eBPF 기반, 고성능 (성능 중요, observability)
  - Canal : Calico + Flannel 조합 (Calico 정책 + Flannel overlay)
- `CRI(Container Runtime Interface)` : `containerd(기본)`, CRI-O

#### 과정 설명
> Bastion 서버에서 진행 

- 운영체제 초기 설정
- Kubernetes 구성 요소 설치 
    - kubelet, kubeadm, kubectl 설치
    - container runtime(기본은 containerd) 설치
    - Control Plane(Master), Node 설정 자동화
- 클러스터 초기화
    -  `kubeadm init` 자동 실행 (Master, Worker 노드에서)
    - `kubeadm join` 자동 실행 (Worker 노드에서)
    - 인증서, 키 관리 자동 처리
- 네트워크 플러그인 설치
    - Calico, Flannel, Cilium 등 설치 가능
- 고가용성/로드밸런싱 지원
    - HA 구성
    - External LoadBalancer 설정

### 2️⃣ Inventory 및 설정 파일 준비
- Kubespray 설치 예시 다운로드

```bash
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
cp -rfp inventory/sample inventory/mycluster

```

- inventory/mycluster/inventory.ini 수정

```
[all]
bastion ansible_host=<bastion_public_ip> ip=<bastion_public_ip> access_ip=<bastion_public_ip>
master ansible_host=<master_private_ip> ip=<master_private_ip> access_ip=<master_private_ip>
worker1 ansible_host=<worker1_private_ip> ip=<worker1_private_ip> access_ip=<worker1_private_ip>
worker2 ansible_host=<worker2_private_ip> ip=<worker2_private_ip> access_ip=<worker2_private_ip>

[kube_control_plane]
master

[etcd]
master

[kube_node]
worker1
worker2

[bastion]
bastion

[k8s_cluster:children]
kube_control_plane
kube_node

[calico_rr]

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/vvue2.pem
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -W %h:%p -q -i ~/.ssh/vvue2.pem ubuntu@<bastion_public_ip>"'
```
### 3️⃣ 후처리 Ansible Role 설정 (admin.conf 복사)
- (필요하다면) Kubespray 후처리 작업으로  admin.conf를 사용자 홈으로 복사하고 권한 설정하는 Ansible Role 템플릿
```
kubespray/
├── inventory/mycluster/
│   └── hosts.ini
├── roles/
│   └── custom_postinstall/
│       └── tasks/
│           └── main.yml
└── extra_playbooks/
    └── postinstall.yml

```

1. postinstall.yml
```yaml
---
- name: Post-Install Setup
  hosts: kube_control_plane
  become: true
  roles:
    - custom_postinstall
```

2. roles/custom_postinstall/tasks/main.yml
```yaml
---
- name: Create .kube directory for ansible_user
  file:
    path: "/home/{{ ansible_user }}/.kube"
    state: directory
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
    mode: '0755'

- name: Copy admin.conf to user kube config
  copy:
    src: /etc/kubernetes/admin.conf
    dest: "/home/{{ ansible_user }}/.kube/config"
    remote_src: true
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
    mode: '0600'

- name: Set KUBECONFIG in .bashrc (optional)
  lineinfile:
    path: "/home/{{ ansible_user }}/.bashrc"
    line: "export KUBECONFIG=$HOME/.kube/config"
    insertafter: EOF
    state: present
```

### 4️⃣ Kubespray 실행
```bash
python3 -m venv .venv
source .venv/bin/activate

pip install --upgrade pip setuptools

pip install 'ansible>=2.17.3,<2.18.0'
pip install netaddr
pip install jmespath

cd ~/kubespray
ansible-playbook -i inventory/mycluster/inventory.ini --become --become-user=root cluster.yml
ansible-playbook -i inventory/mycluster/inventory.ini extra_playbooks/postinstall.yml
```


### 5️⃣ kubespray 콘솔 출력 

```text
bastion_public_ip = "<bastion_public_ip>"
master_private_ip = "<master_private_ip>"
worker_private_ips = [
  "<worker1_private_ip>",
  "<worker2_private_ip>",
]
```


## [3] 쿠버네티스 클러스터 확인 및 설정

### 1️⃣ 클러스터 상태 확인
> Bastion -내부SSH-> Master 에서 실행 (Bastion에 클러스터 제어 권한을 두는 것은 보안상 안좋음)
```bash
kubectl get nodes
kubectl get pods -A
```

### 2️⃣ CNI 플러그인 설정 확인 (Calico 등)
```bash
kubectl get pods -n kube-system | grep calico
kubectl get daemonset calico-node -n kube-system -o yaml | less
```

