# การใช้งาน Pod Disruption Budget (PDB) บน MicroK8s

## MicroK8s รองรับ PodDisruptionBudget หรือไม่

MicroK8s รองรับ `PodDisruptionBudget` หรือ **PDB** เนื่องจากเป็น Kubernetes resource มาตรฐานใน API กลุ่ม `policy/v1` จึงใช้งานได้โดยตรงโดยไม่ต้องเปิด Add-on เพิ่มเติม

PDB ใช้กำหนดจำนวน Pod ขั้นต่ำที่ต้องพร้อมให้บริการ หรือจำนวน Pod สูงสุดที่ยอมให้หยุดพร้อมกันระหว่าง **Voluntary Disruption** เช่น การใช้ `kubectl drain` หรือการบำรุงรักษา Node

> ตัวอย่างทั้งหมดใช้คำสั่ง `microk8s kubectl` หากตั้ง alias แล้วสามารถเปลี่ยนเป็น `kubectl` ได้

---

## 1. ตรวจสอบว่า Cluster รองรับ PDB

```bash
microk8s kubectl api-resources | grep -i disruption
```

ผลลัพธ์ควรคล้าย:

```text
poddisruptionbudgets   pdb   policy/v1   true   PodDisruptionBudget
```

ตรวจสอบ Kubernetes version:

```bash
microk8s kubectl version
```

PDB แบบ `policy/v1` เป็นฟีเจอร์ Stable ตั้งแต่ Kubernetes 1.21 เป็นต้นมา

---

## 2. ตัวอย่าง Deployment 3 Replicas และยอมให้หยุดได้ครั้งละ 1 Pod

สร้างไฟล์ `web-app.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - name: http
              containerPort: 80
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-app-pdb
  namespace: default
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: web-app
```

ติดตั้ง:

```bash
microk8s kubectl apply -f web-app.yaml
```

ตรวจสอบ:

```bash
microk8s kubectl get deployment
microk8s kubectl get pods -o wide
microk8s kubectl get pdb
```

ตัวอย่างผลลัพธ์:

```text
NAME          MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
web-app-pdb   N/A             1                 1                     1m
```

ความหมาย:

- Deployment มีทั้งหมด 3 Pod
- ระหว่างการ Evict ต้องเหลือ Pod ที่ Healthy อย่างน้อย 2 Pod
- Kubernetes อนุญาตให้หยุดพร้อมกันได้สูงสุด 1 Pod

`maxUnavailable: 1` เหมาะกับ Stateless application เช่น Web API ที่มีอย่างน้อย 2-3 Replicas

---

## 3. ตัวอย่างกำหนดให้ต้องเหลืออย่างน้อย 2 Pod

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-app-pdb
  namespace: default
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: web-app
```

Apply:

```bash
microk8s kubectl apply -f web-app-pdb.yaml
```

สำหรับ Deployment ที่มี 3 Replicas:

- ต้องมี Pod ที่ Healthy อย่างน้อย 2 Pod
- หยุดได้ครั้งละไม่เกิน 1 Pod

ควรเลือกใช้ `minAvailable` หรือ `maxUnavailable` อย่างใดอย่างหนึ่งตามพฤติกรรมของระบบ และ selector ของ PDB ต้องตรงกับ label ของ Pod ที่ต้องการปกป้อง

---

## 4. ตัวอย่างใช้เปอร์เซ็นต์สำหรับระบบที่มี HPA

ถ้า Deployment มี HPA และจำนวน Replica เปลี่ยนแปลงตลอด ควรพิจารณาใช้เปอร์เซ็นต์:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
  namespace: production
spec:
  maxUnavailable: 25%
  selector:
    matchLabels:
      app: api
```

ตัวอย่าง:

| จำนวน Replica | `maxUnavailable: 25%` | ผลโดยประมาณ |
|---:|---:|---|
| 4 | 1 | หยุดได้ครั้งละ 1 |
| 8 | 2 | หยุดได้ครั้งละ 2 |
| 10 | 3 | เปอร์เซ็นต์จะมีการปัดขึ้น |

สำหรับ workload ที่ใช้ HPA การใช้ `maxUnavailable` แบบเปอร์เซ็นต์มักยืดหยุ่นกว่าการกำหนด `minAvailable` เป็นเลขตายตัว

---

## 5. ตัวอย่าง StatefulSet แบบ Quorum

สมมติระบบฐานข้อมูลหรือระบบ distributed มี 5 Replicas และต้องเหลืออย่างน้อย 3 Replicas เพื่อรักษา quorum:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: database-pdb
  namespace: database
spec:
  minAvailable: 3
  selector:
    matchLabels:
      app: distributed-database
```

อีกแนวทางหนึ่งคือ:

```yaml
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: distributed-database
```

สำหรับระบบประเภท Consul, ZooKeeper หรือ etcd สามารถกำหนด `maxUnavailable: 1` หรือกำหนด `minAvailable` ตามจำนวน quorum เช่น 3 จากทั้งหมด 5 instances

---

## 6. ทดสอบ PDB ด้วยการ Drain Node

ดูชื่อ Node:

```bash
microk8s kubectl get nodes
```

ตรวจสอบว่า Pod กระจายอยู่ Node ใด:

```bash
microk8s kubectl get pods -o wide
```

Drain ตัวอย่าง:

```bash
microk8s kubectl drain microk8s-node-02 \
  --ignore-daemonsets \
  --delete-emptydir-data
```

PDB จะควบคุมการ Evict Pod ไม่ให้เกินงบที่กำหนด หากการ Evict ทำให้จำนวน Pod ต่ำกว่า `minAvailable` หรือเกิน `maxUnavailable` คำสั่ง drain อาจรอหรือแสดงข้อความ:

```text
Cannot evict pod as it would violate the pod's disruption budget
```

หลังบำรุงรักษา Node เสร็จ:

```bash
microk8s kubectl uncordon microk8s-node-02
```

ตรวจสอบสถานะ:

```bash
microk8s kubectl get nodes
microk8s kubectl get pods -o wide
microk8s kubectl get pdb
```

---

## 7. คำสั่งบริหารจัดการ PDB

### ดู PDB ทุก Namespace

```bash
microk8s kubectl get pdb -A
```

### ดูรายละเอียด

```bash
microk8s kubectl describe pdb web-app-pdb -n default
```

ให้สังเกตค่า:

```text
Current
Desired
Total
Disruptions allowed
```

### ดู YAML ปัจจุบัน

```bash
microk8s kubectl get pdb web-app-pdb -n default -o yaml
```

### ตรวจสอบว่า selector เลือก Pod ถูกต้องหรือไม่

```bash
microk8s kubectl get pods \
  -n default \
  -l app=web-app \
  --show-labels
```

### ลบ PDB

```bash
microk8s kubectl delete pdb web-app-pdb -n default
```

---

## 8. ข้อจำกัดสำคัญ

PDB ป้องกันเฉพาะ **Voluntary Disruption** ที่ใช้ Kubernetes Eviction API เช่น:

- `kubectl drain`
- การบำรุงรักษา Node
- การ Scale down ของระบบ Node autoscaling บางประเภท
- เครื่องมือบริหาร Node ที่เรียก Eviction API

PDB ไม่สามารถรับประกันการป้องกันกรณีต่อไปนี้:

- Node เสียหรือดับกะทันหัน
- Hardware failure
- Network ขาด
- Pod ถูก `OOMKilled`
- Container crash
- Liveness probe restart
- ผู้ดูแลใช้ `kubectl delete pod` โดยตรง
- Deployment rolling update ซึ่งควบคุมด้วย `strategy.rollingUpdate`

PDB เป็นการจำกัด concurrent voluntary disruptions ไม่ใช่กลไกรับประกันว่า Pod จะไม่ล่ม

---

## 9. จุดที่ต้องระวังใน MicroK8s 3 Nodes

### 9.1 อย่าตั้ง PDB เข้มเกินจำนวน Replica

ตัวอย่างที่เสี่ยง:

```yaml
spec:
  minAvailable: 3
```

แต่ Deployment มีเพียง:

```yaml
replicas: 3
```

กรณีนี้ค่า `ALLOWED DISRUPTIONS` จะเป็น `0` และอาจทำให้ Drain Node ไม่ได้ เพราะระบบไม่ยอมให้หยุดแม้แต่ Pod เดียว

สำหรับ 3 Replicas ค่าที่แนะนำทั่วไปคือ:

```yaml
maxUnavailable: 1
```

หรือ:

```yaml
minAvailable: 2
```

### 9.2 PDB ไม่ได้ทำให้ Pod กระจายข้าม Node อัตโนมัติ

ควรใช้ `topologySpreadConstraints` หรือ `podAntiAffinity` ร่วมด้วย มิฉะนั้น Pod ทั้ง 3 ตัวอาจอยู่ Node เดียวกัน แม้จะมี PDB ก็ตาม

ตัวอย่างการกระจาย Pod:

```yaml
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app: web-app
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: web-app
      containers:
        - name: nginx
          image: nginx:1.27
```

สำหรับ MicroK8s 3 Nodes รูปแบบที่เหมาะสมคือ:

- Deployment มี `replicas: 3`
- กระจาย Node ละ 1 Pod ด้วย `topologySpreadConstraints`
- PDB ใช้ `maxUnavailable: 1`
- กำหนด `readinessProbe` ให้ถูกต้อง เพราะ PDB ใช้สถานะความพร้อมของ Pod ในการคำนวณ

### 9.3 อย่าใช้ `--disable-eviction` โดยไม่จำเป็น

คำสั่งนี้จะข้าม PDB:

```bash
microk8s kubectl drain microk8s-node-02 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --disable-eviction
```

ควรใช้เฉพาะกรณีฉุกเฉินที่ยอมรับ downtime ได้ เพราะอาจทำให้จำนวน Pod ที่ให้บริการต่ำกว่าที่ PDB กำหนด

---

## 10. ค่าที่แนะนำตาม Workload

| Workload | Replicas | PDB ที่แนะนำ |
|---|---:|---|
| Stateless Web/API | 3 | `maxUnavailable: 1` |
| Stateless Web/API + HPA | 3-20 | `maxUnavailable: 25%` |
| Critical API | 3 | `minAvailable: 2` |
| Stateful quorum | 5 | `minAvailable: 3` หรือ `maxUnavailable: 1` |
| Single replica | 1 | เพิ่ม Replicas ก่อนใช้ PDB |
| Background worker ที่หยุดได้ | หลาย Pod | อาจไม่จำเป็นต้องมี PDB |

## สรุป

การตั้งค่าที่เหมาะสำหรับ MicroK8s 3 Nodes โดยทั่วไป:

1. ใช้ Deployment จำนวน 3 Replicas
2. กระจาย Pod ให้ Node ละ 1 Pod ด้วย `topologySpreadConstraints`
3. กำหนด PDB เป็น `maxUnavailable: 1`
4. กำหนด `readinessProbe` ให้ถูกต้อง
5. Drain Node ครั้งละหนึ่ง Node และตรวจสอบ `ALLOWED DISRUPTIONS` ก่อนดำเนินการ

แนวทางนี้ช่วยให้สามารถบำรุงรักษาหรือ Drain ได้ครั้งละหนึ่ง Node โดยยังเหลือ Pod ให้บริการอีกสองตัว

---

## แหล่งอ้างอิง

- Kubernetes API Reference: https://kubernetes.io/docs/reference/kubernetes-api/policy-resources/pod-disruption-budget-v1/
- Kubernetes Documentation - Specifying a Disruption Budget: https://kubernetes.io/docs/tasks/run-application/configure-pdb/
