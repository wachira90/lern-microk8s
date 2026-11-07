# คู่มือเปลี่ยน IP สำหรับ Kubernetes MicroK8s

ถ้าเปลี่ยน IP ของเครื่องที่ติดตั้ง **MicroK8s** ไปแล้ว มีค่าที่ควรตรวจสอบและอาจต้องแก้ โดยเฉพาะกรณีเป็น **Multi-node/HA cluster** ส่วน Single-node มักปรับตัวได้ง่ายกว่า แต่ควรกำหนด IP ให้ชัดเจนเพื่อป้องกัน Node InternalIP หรือ Calico ค้างเป็น IP เดิม

## สรุปตามกรณี

| รูปแบบ | สิ่งที่ต้องทำ |
|---|---|
| Single-node และใช้ DHCP/default interface | เปลี่ยน IP แล้ว restart MicroK8s จากนั้นตรวจสอบ Node IP และ certificate |
| Single-node กำหนด IP แบบตายตัวไว้ | แก้ `--node-ip`, `--advertise-address`, Calico และ kubeconfig ที่อ้าง IP เดิม |
| Multi-node/HA | ต้องระวัง dqlite, Calico, certificate และการติดต่อระหว่าง node แนะนำ remove/rejoin node ที่เปลี่ยน IP |
| มี MetalLB/Ingress/DNS ภายนอก | ต้องแก้ IP pool, DNS record, NAT, firewall และ load balancer เพิ่มเติม |

---

## 1. สำรองค่าก่อนเปลี่ยน IP

```bash
sudo microk8s stop

sudo cp -a /var/snap/microk8s/current \
  /var/snap/microk8s/current.backup.$(date +%Y%m%d-%H%M%S)
```

ถ้า workload สำคัญ ควรสำรอง manifests และ persistent data แยกต่างหากด้วย การ copy โฟลเดอร์ขณะระบบหยุดเป็นเพียง configuration backup ไม่ควรถือเป็น application-consistent backup ของฐานข้อมูลทั้งหมด

ค้นหาว่ามี IP เดิมถูกเขียนไว้ตรงไหน:

```bash
OLD_IP="192.168.1.10"

sudo grep -R --line-number --fixed-strings "$OLD_IP" \
  /var/snap/microk8s/current/args \
  /var/snap/microk8s/current/credentials \
  2>/dev/null
```

---

## 2. เปลี่ยน IP ที่ระดับ Ubuntu ก่อน

ตัวอย่างตรวจสอบ IP และ default interface:

```bash
ip -br addr
ip route
```

MicroK8s จะเลือก default interface ซึ่งหมายถึง interface ที่มี default gateway เป็นหลัก หากไม่ได้กำหนดค่า interface แบบเจาะจงไว้

สมมติ IP ใหม่คือ:

```text
192.168.1.20
```

หลังจากเปลี่ยน IP ของ Ubuntu แล้ว ให้ตรวจสอบว่า hostname resolve กลับมายัง IP ใหม่:

```bash
hostname
hostname -I
getent hosts "$(hostname)"
```

ถ้า `/etc/hosts` มี IP เดิม ให้แก้เป็น IP ใหม่ด้วย เช่น:

```text
192.168.1.20  microk8s-node1
```

---

## 3. กำหนด Node IP ของ kubelet

เปิดไฟล์:

```bash
sudo nano /var/snap/microk8s/current/args/kubelet
```

ตรวจสอบหรือเพิ่ม:

```text
--address=0.0.0.0
--node-ip=192.168.1.20
--healthz-bind-address=127.0.0.1
```

ค่า `--node-ip` จะถูกใช้เป็น `InternalIP` ของ Kubernetes node และ IP นี้ต้องสามารถเข้าถึงได้จาก node อื่นใน cluster

ตรวจสอบว่าไม่มี `--node-ip` ซ้ำ:

```bash
grep -nE 'node-ip|address|healthz-bind-address' \
  /var/snap/microk8s/current/args/kubelet
```

---

## 4. ตรวจสอบ kube-apiserver

เปิดไฟล์:

```bash
sudo nano /var/snap/microk8s/current/args/kube-apiserver
```

ถ้ามีค่าเดิม:

```text
--advertise-address=192.168.1.10
```

ให้เปลี่ยนเป็น:

```text
--advertise-address=192.168.1.20
```

แนะนำให้คง:

```text
--bind-address=0.0.0.0
--secure-port=16443
```

MicroK8s กำหนดค่า service arguments ไว้ใต้ `/var/snap/microk8s/current/args` และต้อง restart หลังแก้ไข ส่วน kube-apiserver สามารถกำหนด IP ที่ประกาศให้ component อื่นใช้ผ่าน `--advertise-address` ได้

> อย่าเปลี่ยน `--bind-address` เป็นเฉพาะ IP ใหม่โดยไม่จำเป็น เพราะ configuration ภายในบางส่วนของ MicroK8s อาศัยการเข้าถึง API ผ่าน `127.0.0.1`

---

## 5. ตรวจสอบ Calico

MicroK8s ใช้ **Calico** เป็น default CNI และ Calico อาจมีค่า `IP_AUTODETECTION_METHOD` ที่อ้างถึง network หรือ IP เดิม โดยเฉพาะ cluster ที่เคย join หลาย node

ตรวจสอบ:

```bash
grep -nA3 -B3 "IP_AUTODETECTION_METHOD" \
  /var/snap/microk8s/current/args/cni-network/cni.yaml
```

อาจพบค่า:

```yaml
- name: IP_AUTODETECTION_METHOD
  value: "can-reach=192.168.1.10"
```

ถ้า IP เดิมไม่สามารถเข้าถึงได้แล้ว ให้เปลี่ยนเป็น IP ที่เหมาะสม เช่น:

```yaml
- name: IP_AUTODETECTION_METHOD
  value: "can-reach=192.168.1.1"
```

โดยปกติควรใช้ IP ของ gateway หรือ IP ที่อยู่ใน network ปลายทางเดียวกับ node อื่น ไม่จำเป็นต้องใช้ IP ของ node เอง

อีกทางเลือกสำหรับเครื่องที่มี network interface เดียว:

```yaml
- name: IP_AUTODETECTION_METHOD
  value: "first-found"
```

จากนั้น apply:

```bash
sudo microk8s start

microk8s kubectl apply \
  -f /var/snap/microk8s/current/args/cni-network/cni.yaml
```

---

## 6. ตรวจสอบ certificate

ตรวจสอบว่า server certificate รองรับ IP ใหม่หรือไม่:

```bash
sudo openssl x509 \
  -in /var/snap/microk8s/current/certs/server.crt \
  -noout -text |
grep -A2 "Subject Alternative Name"
```

หรือ:

```bash
sudo microk8s refresh-certs -c
```

ถ้า IP ใหม่ไม่มีใน `Subject Alternative Name` และพบ error ประเภท:

```text
x509: certificate is valid for 192.168.1.10, not 192.168.1.20
```

ให้เพิ่ม IP ใหม่ใน template ก่อน:

```bash
sudo nano /var/snap/microk8s/current/certs/csr.conf.template
```

ใต้ `[ alt_names ]` เพิ่มรายการที่ไม่ซ้ำ เช่น:

```text
IP.50 = 192.168.1.20
```

แล้ว regenerate server certificate:

```bash
sudo microk8s refresh-certs -e server.crt
sudo snap restart microk8s
```

ตรวจสอบ SAN อีกครั้งหลังสร้าง certificate ใหม่

> ไม่ควร refresh `ca.crt` เพื่อแก้เพียงการเปลี่ยน IP เพราะการเปลี่ยน CA มีผลกระทบกว้างกว่า server certificate โดยเฉพาะ Multi-node cluster

---

## 7. ตรวจสอบ kubeconfig

สร้าง kubeconfig ใหม่:

```bash
microk8s config > ~/microk8s-config-new.yaml
```

ตรวจสอบ API endpoint:

```bash
grep "server:" ~/microk8s-config-new.yaml
```

ควรพบประมาณนี้:

```yaml
server: https://192.168.1.20:16443
```

หากใช้งานจากเครื่องอื่น ให้นำ kubeconfig ใหม่ไปแทนไฟล์เดิม:

```bash
export KUBECONFIG=~/microk8s-config-new.yaml
kubectl get nodes
```

ถ้า kubeconfig ภายใน `/var/snap/microk8s/current/credentials` ถูกกำหนดให้ใช้ IP เดิม อาจต้องแก้ endpoint แต่ถ้ายังใช้ `127.0.0.1:16443` สำหรับ component ภายใน ไม่จำเป็นต้องเปลี่ยน

---

## 8. กรณี Multi-node/HA

กรณีนี้ควรระวังมากกว่าปกติ เพราะ **dqlite** จะใช้ IP ที่ระบุตอน `microk8s join` เป็น address ของสมาชิก cluster

แนวทางที่ปลอดภัยกว่าการแก้ไฟล์ dqlite โดยตรงคือ:

1. ย้ายหรือ drain workload ออกจาก node ที่จะเปลี่ยน IP
2. Remove node ออกจาก cluster
3. เปลี่ยน IP
4. Join node กลับเข้ามาด้วย IP ใหม่

จาก control-plane node:

```bash
microk8s kubectl drain NODE_NAME \
  --ignore-daemonsets \
  --delete-emptydir-data

microk8s remove-node NODE_NAME
```

บน node ที่เปลี่ยน IP:

```bash
microk8s leave
```

หลังเปลี่ยน IP แล้ว บน control-plane node:

```bash
microk8s add-node
```

ระบบจะแสดงคำสั่งลักษณะนี้:

```bash
microk8s join 192.168.1.20:25000/TOKEN
```

นำคำสั่งที่ระบบสร้างให้ไปรันบน node ที่จะ join

ถ้าเป็น control-plane แบบ HA 3 nodes ควรเปลี่ยนทีละ node และตรวจสอบ quorum ทุกครั้ง:

```bash
microk8s status
microk8s kubectl get nodes -o wide
```

ไม่แนะนำให้เปลี่ยน IP ทุก control-plane node พร้อมกัน เพราะอาจทำให้ dqlite เสีย quorum และ API server ใช้งานไม่ได้

---

## 9. ตรวจสอบ MetalLB, Ingress และ DNS

ถ้าใช้ MetalLB ให้ดู IP pool:

```bash
microk8s kubectl get ipaddresspools.metallb.io \
  -n metallb-system -o yaml
```

ถ้าใช้ MicroK8s รุ่นเก่าที่เก็บ config อีกแบบ:

```bash
microk8s kubectl get configmap -n metallb-system -o yaml
```

ต้องแก้ pool เฉพาะกรณี subnet ใหม่ไม่ตรงกับ subnet เดิม ตัวอย่าง:

```yaml
addresses:
  - 192.168.2.200-192.168.2.220
```

ตรวจสอบเพิ่มเติม:

- DNS A record ที่ชี้มายัง IP เดิม
- `/etc/hosts` ของ client
- Firewall เช่น UFW
- NAT/Port forwarding
- Reverse proxy หรือ external load balancer
- Monitoring target ของ Prometheus
- Backup agent หรือระบบ inventory ที่ผูกกับ IP เดิม

---

## 10. Restart และตรวจสอบผล

```bash
sudo snap restart microk8s
microk8s status --wait-ready
```

ตรวจสอบ node:

```bash
microk8s kubectl get nodes -o wide
```

ค่า `INTERNAL-IP` ควรเป็น IP ใหม่

ตรวจสอบ Pod:

```bash
microk8s kubectl get pods -A -o wide
```

ตรวจสอบ system components:

```bash
microk8s kubectl get pods -A |
grep -vE 'Running|Completed'
```

ตรวจสอบ API:

```bash
curl -k https://192.168.1.20:16443/livez
curl -k https://192.168.1.20:16443/readyz
```

ตรวจสอบ log:

```bash
sudo journalctl -u snap.microk8s.daemon-kubelite \
  --since "15 minutes ago" --no-pager
```

## คำแนะนำสุดท้าย

- **Single-node:** แก้ `kubelet --node-ip`, ตรวจ `kube-apiserver`, Calico, certificate และสร้าง kubeconfig ใหม่
- **Multi-node/HA:** ใช้วิธี remove/leave แล้ว join ด้วย IP ใหม่ จะปลอดภัยกว่าการแก้ dqlite ด้วยมือ
- หากเป็น IP จาก DHCP ควรทำ **DHCP reservation** หรือใช้ static IP เพื่อไม่ให้ IP เปลี่ยนซ้ำ
- หากแค่เปลี่ยน public/NAT IP แต่ private IP ภายในเครื่องไม่เปลี่ยน MicroK8s มักไม่ต้องแก้ค่า node เพียงแก้ NAT, DNS และ firewall ภายนอกเท่านั้น

## แหล่งอ้างอิง

- Canonical: https://canonical.com/microk8s/docs/configuring-services
- Canonical: https://canonical.com/microk8s/docs/configure-host-interfaces
